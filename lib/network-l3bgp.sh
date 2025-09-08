#!/bin/bash
# L3BGP network topology module
# Implements Layer 3 BGP-enabled network with custom node configurations
#
# This module provides BGP routing with automatic kernel route installation
# via FRR Zebra integration. Creates isolated network namespaces with unique
# subnets and hub-and-spoke BGP topology for realistic network testing.
#
# MAIN FUNCTIONS:
#   setup_l3bgp_network()       - Main orchestration function for L3BGP setup
#   cleanup_l3bgp_network()     - Complete cleanup of L3BGP infrastructure
#   check_l3bgp_prerequisites() - Verify GoBGP and FRR availability
#
# CONFIGURATION FUNCTIONS:
#   parse_l3bgp_config()        - Parse node-specific L3BGP configuration
#   create_gobgp_configs()      - Generate GoBGP config files for all nodes
#   create_node_gobgp_config()  - Create GoBGP config for specific node
#   create_manager_gobgp_config() - Create manager GoBGP config (route reflector)
#
# INFRASTRUCTURE FUNCTIONS:
#   create_frr_directories()    - Create FRR runtime directories in /var/run
#   create_l3bgp_hosts_files()  - Generate hosts files for all namespaces
#   create_l3bgp_veth_pairs()   - Create virtual ethernet pairs
#   create_l3bgp_namespaces()   - Create network namespaces with L3 routing
#   setup_l3bgp_bridges()       - Setup bridge network with gateway IPs
#   setup_manager_node()        - Setup manager node with multi-subnet addressing
#
# DAEMON MANAGEMENT:
#   start_zebra_daemons()       - Start FRR zebra in all namespaces
#   start_gobgp_daemons()       - Start GoBGP with zebra integration
#   stop_zebra_daemons()        - Stop zebra processes and cleanup directories
#   stop_gobgp_daemons()        - Stop all GoBGP processes
#
# UTILITY FUNCTIONS:
#   get_node_ip()              - Get IP address for specific node
#   get_node_hostname()        - Get hostname for specific node  
#   get_node_subnet()          - Get subnet for specific node
#   wait_for_zebra()           - Wait for zebra socket availability
#   wait_for_gobgp_zebra()     - Wait for GoBGP-Zebra connection
#
# TESTING AND VALIDATION:
#   validate_l3bgp_network()    - Validate network interface configuration
#   test_l3bgp_connectivity()   - Test cross-subnet connectivity
#   show_bgp_status()          - Display BGP and kernel routing status
#   add_test_routes()          - Add demonstration routes via BGP
#
# NSO INTEGRATION:
#   setup_l3bgp_nso_packages() - Setup NSO packages for L3BGP nodes
#
# ARCHITECTURE:
#   - Hub-and-spoke BGP topology with manager as route reflector
#   - Each node in separate subnet (192.168.x.0/24)
#   - Manager accessible via subnet-specific IPs (192.168.x.2)
#   - Automatic kernel route installation via FRR Zebra
#   - Cross-subnet communication through BGP routing

# Check L3BGP prerequisites
check_l3bgp_prerequisites() {
    log_info "Checking L3BGP prerequisites..."
    local missing_deps=()
    
    # Check for gobgpd
    if ! command_exists gobgpd; then
        log_error "❌ gobgpd not found in PATH"
        missing_deps+=("gobgp")
    else
        local gobgp_version=$(gobgpd --version 2>/dev/null | head -1)
        log_info "✅ Found gobgpd: $gobgp_version"
    fi
    
    # Check for zebra (FRR)
    if ! [[ -x "/usr/lib/frr/zebra" ]]; then
        log_error "❌ zebra (FRR) not found at /usr/lib/frr/zebra"
        missing_deps+=("frr")
    else
        local zebra_version=$(/usr/lib/frr/zebra --version 2>/dev/null | head -1)
        log_info "✅ Found zebra: $zebra_version"
    fi
    
    # Check for vtysh (FRR shell)
    if ! command_exists vtysh; then
        log_error "❌ vtysh (FRR shell) not found in PATH"
        missing_deps+=("frr")
    else
        log_info "✅ Found vtysh: $(vtysh --version 2>/dev/null | head -1)"
    fi
    
    # Check for git
    if ! command_exists git; then
        log_error "❌ git not found in PATH"
        missing_deps+=("git")
    else
        log_info "✅ Found git: $(git --version)"
    fi
    
    # Check if frr user exists
    if ! id frr >/dev/null 2>&1; then
        log_error "❌ frr user does not exist (required for FRR/Zebra)"
        missing_deps+=("frr")
    else
        log_info "✅ Found frr user"
    fi
    
    # Abort if dependencies missing
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies for L3BGP setup:"
        for dep in "${missing_deps[@]}"; do
            log_error "  - $dep"
        done
        log_error ""
        log_error "Installation commands:"
        log_error "  Ubuntu/Debian: sudo apt-get install gobgp frr"
        log_error "  CentOS/RHEL:   sudo yum install gobgp frr"
        log_error "  GoBGP source:  https://github.com/osrg/gobgp"
        log_error "  FRR source:    https://frrouting.org/"
        exit 1
    fi
    
    log_info "✅ All L3BGP prerequisites satisfied"
}

# Setup L3BGP network topology
setup_l3bgp_network() {
    log_info "Setting up L3BGP network topology..."
    
    # Parse L3BGP-specific configuration
    parse_l3bgp_config
    
    # Create L3BGP network components
    create_l3bgp_hosts_files
    create_frr_directories
    create_l3bgp_veth_pairs
    create_l3bgp_namespaces
    setup_l3bgp_bridges
    
    # Setup manager node if enabled
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        setup_manager_node
    fi
    
    # Validate L3BGP network
    validate_l3bgp_network
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        test_l3bgp_connectivity
    fi
    
    # Start Zebra daemons first
    start_zebra_daemons
    
    # Setup GoBGP configuration and daemons
    create_gobgp_configs
    start_gobgp_daemons
    
    log_info "L3BGP network setup completed"
}

# Parse L3BGP node configuration from loaded config
parse_l3bgp_config() {
    log_info "Parsing L3BGP configuration..."
    
    # Parse node-specific settings
    for ((i=1; i<=NODES; i++)); do
        local ip_var="node_${i}_ip"
        local hostname_var="node_${i}_hostname" 
        local subnet_var="node_${i}_subnet"
        local asn_var="node_${i}_asn"
        
        eval "NODE_${i}_IP=\${${ip_var}:-192.168.${i}.1}"
        eval "NODE_${i}_HOSTNAME=\${${hostname_var}:-${PREFIX}${i}.ha-cluster}"
        eval "NODE_${i}_SUBNET=\${${subnet_var}:-192.168.${i}.0/24}"
        eval "NODE_${i}_ASN=\${${asn_var}:-$((64500 + i))}"
        
        log_debug "Node $i: IP=$(eval echo \$NODE_${i}_IP), Hostname=$(eval echo \$NODE_${i}_HOSTNAME), ASN=$(eval echo \$NODE_${i}_ASN)"
    done
    
    # Parse manager configuration  
    MANAGER_IP="${MANAGER_IP:-172.17.0.2}"
    MANAGER_ENABLED="${MANAGER_ENABLED:-false}"
    MANAGER_ASN="${MANAGER_ASN:-64500}"
    
    log_debug "Manager: Enabled=$MANAGER_ENABLED, IP=$MANAGER_IP, ASN=$MANAGER_ASN"
}

# Setup L3BGP NSO packages
setup_l3bgp_nso_packages() {
    log_info "Setting up L3BGP NSO packages..."
    
    # Clone tailf-hcc package if not exists
    local hcc_dir="${WORK_DIR}/tailf-hcc"
    if [[ ! -d "$hcc_dir" ]]; then
        log_info "Cloning tailf-hcc package..."
        execute_cmd "git clone ssh://git@stash.tail-f.com/pkg/tailf-hcc.git $hcc_dir"
    fi
    
    # Create package links in each NSO node
    for ((i=1; i<=NODES; i++)); do
        local packages_dir="${WORK_DIR}/ncs-run${i}/packages"
        local hcc_link="${packages_dir}/tailf-hcc"
        
        if [[ ! -L "$hcc_link" ]]; then
            log_info "Creating tailf-hcc package link for node $i"
            execute_cmd "ln -sf $hcc_dir $hcc_link"
        fi
    done
}

# Get node IP address
get_node_ip() {
    local node_id="$1"
    eval echo "\$NODE_${node_id}_IP"
}

# Get node hostname
get_node_hostname() {
    local node_id="$1"
    eval echo "\$NODE_${node_id}_HOSTNAME"
}

# Get node subnet
get_node_subnet() {
    local node_id="$1"
    eval echo "\$NODE_${node_id}_SUBNET"
}

# Wait for Zebra socket to be ready
wait_for_zebra() {
    local ns="$1"
    local sock="$2"
    local retries=10
    local wait=0.5
    local i

    log_debug "Waiting for zebra socket $sock in namespace $ns..."
    
    for i in $(seq 1 $retries); do
        log_debug "Attempt $i: checking socket $sock in namespace $ns"
        if sudo ip netns exec "$ns" test -S "$sock"; then
            log_debug "Socket exists, checking writability..."
            # Optionally check writability too
            if sudo ip netns exec "$ns" test -w "$sock"; then
                log_debug "Socket is writable, zebra ready!"
                return 0
            else
                log_debug "Socket exists but not writable yet"
            fi
        else
            log_debug "Socket does not exist yet"
        fi
        sleep "$wait"
    done

    log_error "⚠ Zebra socket $sock in namespace $ns not ready after $retries attempts"
    return 1
}

# Wait for GoBGP to establish Zebra connection
wait_for_gobgp_zebra() {
    local ns="$1"
    local log_file="$2"
    local retries=30
    local wait=0.5
    local i
    
    log_debug "Waiting for GoBGP-Zebra connection in namespace $ns..."
    
    for i in $(seq 1 $retries); do
        if [[ -f "$log_file" ]] && grep -q "success to connect to Zebra" "$log_file"; then
            log_debug "✅ GoBGP connected to Zebra in namespace $ns"
            return 0
        fi
        sleep "$wait"
    done
    
    log_error "⚠ GoBGP failed to connect to Zebra in namespace $ns after ${retries} attempts"
    return 1
}

# Create L3BGP hosts file for a namespace
create_l3bgp_hosts_file() {
    local node_id="$1"
    local hosts_dir="${WORK_DIR}/hosts/${PREFIX}${node_id}ns"
    local hosts_file="${hosts_dir}/hosts"
    
    log_debug "Creating L3BGP hosts file for node $node_id"
    
    execute_cmd "mkdir -p $hosts_dir"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_debug "[DRY-RUN] Would create L3BGP hosts file: $hosts_file"
        return 0
    fi
    
    cat > "$hosts_file" << EOF
127.0.0.1   localhost
::1         localhost ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters

# L3BGP Cluster nodes
EOF

    # Add entries for all cluster nodes (custom IPs and hostnames)
    for ((j=1; j<=NODES; j++)); do
        local node_ip="$(get_node_ip "$j")"
        local node_hostname="$(get_node_hostname "$j")"
        echo "$node_ip    $node_hostname" >> "$hosts_file"
    done
    
    # Add manager if enabled
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        echo "$MANAGER_IP    manager.cluster.local" >> "$hosts_file"
    fi
}

# Create all L3BGP hosts files
create_l3bgp_hosts_files() {
    log_info "Creating L3BGP hosts files..."
    
    for ((i=1; i<=NODES; i++)); do
        create_l3bgp_hosts_file "$i"
    done
}

# Create FRR runtime directories for all nodes
create_frr_directories() {
    log_info "Creating FRR runtime directories..."
    
    # Create FRR directories in /var/run (like the example script)
    for ((i=1; i<=NODES; i++)); do
        local frr_dir="/var/run/frr-${PREFIX}${i}ns"
        
        log_debug "Creating FRR directory: $frr_dir"
        execute_cmd "sudo mkdir -p $frr_dir"
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            # Clean up any existing files first
            execute_cmd "sudo rm -f ${frr_dir}/*"
            
            # Set proper ownership and permissions for FRR
            execute_cmd "sudo chown frr:frr $frr_dir"
            execute_cmd "sudo chmod 755 $frr_dir"
        fi
    done
    
    # Create manager FRR directory if enabled
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_frr_dir="/var/run/frr-${PREFIX}manager"
        
        log_debug "Creating manager FRR directory: $mgr_frr_dir"
        execute_cmd "sudo mkdir -p $mgr_frr_dir"
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            execute_cmd "sudo rm -f ${mgr_frr_dir}/*"
            execute_cmd "sudo chown frr:frr $mgr_frr_dir"
            execute_cmd "sudo chmod 755 $mgr_frr_dir"
        fi
    fi
}

# Create L3BGP virtual ethernet pairs
create_l3bgp_veth_pairs() {
    log_info "Creating L3BGP virtual ethernet pairs..."
    
    for ((i=1; i<=NODES; i++)); do
        local veth_a="${PREFIX}${i}a"
        local veth_b="${PREFIX}${i}b"
        
        log_debug "Creating L3BGP veth pair: $veth_a <-> $veth_b"
        execute_cmd "sudo ip link add dev $veth_a type veth peer name $veth_b"
    done
    
    # Create manager veth pair if enabled
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_veth_a="${PREFIX}mgra"
        local mgr_veth_b="${PREFIX}mgrb"
        
        log_debug "Creating manager veth pair: $mgr_veth_a <-> $mgr_veth_b"
        execute_cmd "sudo ip link add dev $mgr_veth_a type veth peer name $mgr_veth_b"
    fi
}

# Create L3BGP network namespaces
create_l3bgp_namespaces() {
    log_info "Creating L3BGP network namespaces..."
    
    for ((i=1; i<=NODES; i++)); do
        local netns="${PREFIX}${i}ns"
        local veth_a="${PREFIX}${i}a"
        local node_ip="$(get_node_ip "$i")"
        local node_hostname="$(get_node_hostname "$i")"
        
        log_info "Creating L3BGP namespace: $netns ($node_hostname)"
        
        # Create namespace
        execute_cmd "sudo ip netns add $netns"
        
        # Create /etc/var directory in namespace to avoid bind mount warnings
        execute_cmd "sudo ip netns exec $netns mkdir -p /etc/var"
        
        # Move veth interface to namespace
        execute_cmd "sudo ip link set dev $veth_a netns $netns"
        
        # Configure interface in namespace with custom IP
        execute_cmd "sudo ip -n $netns addr add ${node_ip}/24 dev $veth_a"
        execute_cmd "sudo ip -n $netns link set dev $veth_a up"
        execute_cmd "sudo ip -n $netns link set dev lo up"
        
        # Add routing for L3BGP topology
        # Each node needs to know how to reach other subnets through the bridge
        local node_subnet="$(get_node_subnet "$i")"
        local subnet_prefix=$(echo "$node_subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)
        local gateway_ip="${subnet_prefix}.254"
        
        # Add routes to other node subnets
        for ((j=1; j<=NODES; j++)); do
            if [[ $j -ne $i ]]; then
                local target_subnet="$(get_node_subnet "$j")"
                execute_cmd "sudo ip -n $netns route add $target_subnet via $gateway_ip dev $veth_a"
            fi
        done
        
        # Add default route through gateway
        execute_cmd "sudo ip -n $netns route add default via $gateway_ip dev $veth_a"
        
        # Add hosts file
        add_hosts_to_namespace "$i"
        
        log_info "L3BGP namespace $netns created successfully with IP $node_ip"
    done
    
    log_info "All L3BGP namespaces created successfully"
}

# Setup L3BGP bridges (simplified for now)
setup_l3bgp_bridges() {
    log_info "Setting up L3BGP bridge network..."
    
    # Create main bridge
    execute_cmd "sudo ip link add dev $BRIDGE_NAME type bridge"
    log_info "L3BGP bridge $BRIDGE_NAME created"
    
    # Connect all veth interfaces to bridge
    for ((i=1; i<=NODES; i++)); do
        local veth_b="${PREFIX}${i}b"
        
        log_debug "Connecting $veth_b to L3BGP bridge $BRIDGE_NAME"
        execute_cmd "sudo ip link set dev $veth_b master $BRIDGE_NAME"
        execute_cmd "sudo ip link set dev $veth_b up"
    done
    
    # Connect manager if enabled
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_veth_b="${PREFIX}mgrb"
        execute_cmd "sudo ip link set dev $mgr_veth_b master $BRIDGE_NAME"
        execute_cmd "sudo ip link set dev $mgr_veth_b up"
    fi
    
    # Add gateway address to bridge
    execute_cmd "sudo ip addr add ${NETWORK_PREFIX}.0.254/16 dev $BRIDGE_NAME"
    
    # Add gateway IPs for each L3BGP subnet
    for ((i=1; i<=NODES; i++)); do
        local node_subnet="$(get_node_subnet "$i")"
        local subnet_prefix=$(echo "$node_subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)
        local subnet_gateway="${subnet_prefix}.254"
        execute_cmd "sudo ip addr add ${subnet_gateway}/24 dev $BRIDGE_NAME"
        log_debug "Added L3BGP gateway: ${subnet_gateway}/24"
    done
    execute_cmd "sudo ip link set dev $BRIDGE_NAME up"
    
    # Enable IP forwarding for L3BGP routing
    execute_cmd "sudo sysctl -w net.ipv4.ip_forward=1"
}

# Setup manager node
setup_manager_node() {
    log_info "Setting up manager node at $MANAGER_IP..."
    
    local mgr_ns="${PREFIX}manager"
    local mgr_veth_a="${PREFIX}mgra"
    
    # Create manager namespace
    execute_cmd "sudo ip netns add $mgr_ns"
    
    # Create /etc/var directory in manager namespace to avoid bind mount warnings
    execute_cmd "sudo ip netns exec $mgr_ns mkdir -p /etc/var"
    
    # Move veth interface to namespace
    execute_cmd "sudo ip link set dev $mgr_veth_a netns $mgr_ns"
    
    # Configure manager bridge interface (172.17.0.2/16)
    execute_cmd "sudo ip -n $mgr_ns addr add ${MANAGER_IP}/16 dev $mgr_veth_a"
    execute_cmd "sudo ip -n $mgr_ns link set dev $mgr_veth_a up"
    execute_cmd "sudo ip -n $mgr_ns link set dev lo up"
    
    # Add interfaces for each node subnet (matching your example)
    for ((i=1; i<=NODES; i++)); do
        local node_ip="$(eval echo \$NODE_${i}_IP)"
        local subnet_prefix="$(echo $node_ip | cut -d'.' -f1-3)"
        local mgr_subnet_ip="${subnet_prefix}.2"  # Manager gets .2 in each subnet
        
        log_debug "Adding manager interface: ${mgr_subnet_ip}/24"
        execute_cmd "sudo ip -n $mgr_ns addr add ${mgr_subnet_ip}/24 dev $mgr_veth_a"
    done
    
    log_info "Manager node created successfully with interfaces for all subnets"
}

# Start Zebra daemons in all namespaces
start_zebra_daemons() {
    log_info "Starting Zebra daemons in all namespaces..."
    
    # Start all zebra processes first (like the working example)
    for ((i=1; i<=NODES; i++)); do
        local netns="${PREFIX}${i}ns"
        local frr_dir="/var/run/frr-${PREFIX}${i}ns"
        local zebra_pid="${frr_dir}/zebra.pid"
        local zebra_socket="${frr_dir}/zserv.api"
        local zebra_log="${WORK_DIR}/gobgp/zebra-${netns}.log"
        
        log_debug "Starting zebra in namespace $netns"
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            # Make sure log directory exists
            execute_cmd "mkdir -p $(dirname $zebra_log)"
            
            # Start zebra daemon (don't wait yet)
            log_debug "Starting zebra: sudo ip netns exec $netns /usr/lib/frr/zebra -d -i $zebra_pid -z $zebra_socket -A 127.0.0.1"
            if [[ "${VERBOSE}" == "true" ]]; then
                sudo ip netns exec $netns /usr/lib/frr/zebra -d \
                    -i $zebra_pid \
                    -z $zebra_socket \
                    -A 127.0.0.1 > $zebra_log 2>&1
            else
                sudo ip netns exec $netns /usr/lib/frr/zebra -d \
                    -i $zebra_pid \
                    -z $zebra_socket \
                    -A 127.0.0.1 > $zebra_log 2>&1
            fi
        else
            log_debug "[DRY-RUN] Would start zebra in namespace $netns"
        fi
    done
    
    # Start manager zebra if enabled
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_ns="${PREFIX}manager"
        local mgr_frr_dir="/var/run/frr-${PREFIX}manager"
        local mgr_zebra_pid="${mgr_frr_dir}/zebra.pid"
        local mgr_zebra_socket="${mgr_frr_dir}/zserv.api"
        local mgr_zebra_log="${WORK_DIR}/gobgp/zebra-${mgr_ns}.log"
        
        log_debug "Starting zebra in manager namespace $mgr_ns"
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            execute_cmd "mkdir -p $(dirname $mgr_zebra_log)"
            
            log_debug "Starting manager zebra: sudo ip netns exec $mgr_ns /usr/lib/frr/zebra -d -i $mgr_zebra_pid -z $mgr_zebra_socket -A 127.0.0.1"
            if [[ "${VERBOSE}" == "true" ]]; then
                sudo ip netns exec $mgr_ns /usr/lib/frr/zebra -d \
                    -i $mgr_zebra_pid \
                    -z $mgr_zebra_socket \
                    -A 127.0.0.1 > $mgr_zebra_log 2>&1
            else
                sudo ip netns exec $mgr_ns /usr/lib/frr/zebra -d \
                    -i $mgr_zebra_pid \
                    -z $mgr_zebra_socket \
                    -A 127.0.0.1 > $mgr_zebra_log 2>&1
            fi
        else
            log_debug "[DRY-RUN] Would start zebra in manager namespace"
        fi
    fi
    
    # Now wait for all zebra sockets to be ready
    log_debug "Waiting for all zebra sockets to be ready..."
    
    # Wait for each node's zebra socket explicitly (like the working script)
    if [[ "${DRY_RUN}" != "true" ]]; then
        if ! wait_for_zebra "${PREFIX}1ns" "/var/run/frr-${PREFIX}1ns/zserv.api"; then
            log_error "Failed to start zebra in namespace ${PREFIX}1ns"
            return 1
        fi
        
        if [[ $NODES -ge 2 ]]; then
            if ! wait_for_zebra "${PREFIX}2ns" "/var/run/frr-${PREFIX}2ns/zserv.api"; then
                log_error "Failed to start zebra in namespace ${PREFIX}2ns"
                return 1
            fi
        fi
        
        if [[ $NODES -ge 3 ]]; then
            if ! wait_for_zebra "${PREFIX}3ns" "/var/run/frr-${PREFIX}3ns/zserv.api"; then
                log_error "Failed to start zebra in namespace ${PREFIX}3ns"
                return 1
            fi
        fi
        
        # Add more nodes as needed based on NODES value
        for ((i=4; i<=NODES; i++)); do
            if ! wait_for_zebra "${PREFIX}${i}ns" "/var/run/frr-${PREFIX}${i}ns/zserv.api"; then
                log_error "Failed to start zebra in namespace ${PREFIX}${i}ns"
                return 1
            fi
        done
    fi
    
    # Wait for manager zebra if enabled
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_ns="${PREFIX}manager"
        local mgr_zebra_socket="/var/run/frr-${PREFIX}manager/zserv.api"
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            if ! wait_for_zebra "$mgr_ns" "$mgr_zebra_socket"; then
                log_error "Failed to start zebra in manager namespace"
                return 1
            fi
        fi
    fi
    
    log_info "All Zebra daemons started successfully"
}

# Create GoBGP configuration files for all nodes
create_gobgp_configs() {
    log_info "Creating GoBGP configuration files..."
    
    local gobgp_dir="${WORK_DIR}/gobgp"
    execute_cmd "mkdir -p $gobgp_dir"
    
    # Create config for each node
    for ((i=1; i<=NODES; i++)); do
        local node_ip="$(eval echo \$NODE_${i}_IP)"
        local node_asn="$(eval echo \$NODE_${i}_ASN)"
        local config_file="${gobgp_dir}/node${i}.yaml"
        
        create_node_gobgp_config "$i" "$node_ip" "$node_asn" "$config_file"
    done
    
    # Create manager config if enabled
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local manager_asn="${manager_asn:-64500}"
        local manager_config="${gobgp_dir}/manager.yaml"
        create_manager_gobgp_config "$MANAGER_IP" "$manager_asn" "$manager_config"
    fi
}

# Create GoBGP config for a specific node
create_node_gobgp_config() {
    local node_id="$1"
    local node_ip="$2"
    local node_asn="$3"
    local config_file="$4"
    
    log_debug "Creating GoBGP config for node $node_id: $config_file"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_debug "[DRY-RUN] Would create GoBGP config: $config_file"
        return 0
    fi

    # Each node peers only with the manager (hub-and-spoke topology)
    # In this topology, nodes connect to manager using manager's subnet-specific address
    # Calculate manager IP based on node's actual subnet
    local node_subnet="$(get_node_subnet "$node_id")"
    local subnet_prefix=$(echo "$node_subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)
    local manager_subnet_ip="${subnet_prefix}.2"
    local zebra_socket="/var/run/frr-${PREFIX}${node_id}ns/zserv.api"
    
    cat > "$config_file" << EOF
global:
  config:
    as: $node_asn
    router-id: $node_ip

zebra:
  config:
    enabled: true
    url: unix:$zebra_socket

neighbors:
  - config:
      neighbor-address: $manager_subnet_ip
      peer-as: ${manager_asn:-64500}
    transport:
      config:
        local-address: $node_ip

EOF
}

# Create GoBGP config for manager (route reflector)
create_manager_gobgp_config() {
    local manager_ip="$1"
    local manager_asn="$2"
    local config_file="$3"
    
    log_debug "Creating manager GoBGP config: $config_file"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_debug "[DRY-RUN] Would create manager GoBGP config: $config_file"
        return 0
    fi
    
    local mgr_zebra_socket="/var/run/frr-${PREFIX}manager/zserv.api"
    
    cat > "$config_file" << EOF
global:
  config:
    as: $manager_asn
    router-id: $manager_ip

zebra:
  config:
    enabled: true
    url: unix:$mgr_zebra_socket

neighbors:
EOF

    # Add all nodes as neighbors (hub-and-spoke topology)
    for ((i=1; i<=NODES; i++)); do
        local node_ip="$(eval echo \$NODE_${i}_IP)"
        local node_asn="$(eval echo \$NODE_${i}_ASN)"
        # Manager uses its subnet-specific address for each neighbor
        local manager_local_ip="192.168.${i}.2"
        cat >> "$config_file" << EOF
  - config:
      neighbor-address: $node_ip
      peer-as: $node_asn
    transport:
      config:
        local-address: $manager_local_ip
EOF
    done
}

# Start GoBGP daemons in all namespaces
start_gobgp_daemons() {
    log_info "Starting GoBGP daemons..."
    
    local gobgp_dir="${WORK_DIR}/gobgp"
    
    # Debug: Show NODES value and loop range
    log_debug "NODES=$NODES, starting GoBGP daemon loop from 1 to $NODES"
    
    # Start gobgpd in each node namespace
    for ((i=1; i<=NODES; i++)); do
        local netns="${PREFIX}${i}ns"
        local config_file="${gobgp_dir}/node${i}.yaml"
        local log_file="${gobgp_dir}/node${i}.log"
        
        log_debug "Starting gobgpd in namespace $netns"
        if [[ "${DRY_RUN}" != "true" ]]; then
            log_debug "Command: sudo ip netns exec $netns gobgpd -f $config_file -l debug > $log_file 2>&1 &"
            # Use explicit command to avoid variable expansion issues
            sudo ip netns exec "$netns" gobgpd -f "$config_file" -l debug > "$log_file" 2>&1 &
            
            # Wait for GoBGP to connect to Zebra
            if ! wait_for_gobgp_zebra "$netns" "$log_file"; then
                log_error "Failed to start GoBGP in namespace $netns"
                return 1
            fi
        else
            log_debug "[DRY-RUN] Would start: sudo ip netns exec $netns gobgpd -f $config_file"
        fi
    done
    
    # Start manager gobgpd if enabled
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_ns="${PREFIX}manager"
        local manager_config="${gobgp_dir}/manager.yaml"
        local manager_log="${gobgp_dir}/manager.log"
        
        log_debug "Starting manager gobgpd in namespace $mgr_ns"
        if [[ "${DRY_RUN}" != "true" ]]; then
            log_debug "Command: sudo ip netns exec $mgr_ns gobgpd -f $manager_config -l debug > $manager_log 2>&1 &"
            sudo ip netns exec "$mgr_ns" gobgpd -f "$manager_config" -l debug > "$manager_log" 2>&1 &
            
            # Wait for manager GoBGP to connect to Zebra
            if ! wait_for_gobgp_zebra "$mgr_ns" "$manager_log"; then
                log_error "Failed to start manager GoBGP"
                return 1
            fi
        else
            log_debug "[DRY-RUN] Would start: sudo ip netns exec $mgr_ns gobgpd -f $manager_config"
        fi
    fi
    
    log_info "All GoBGP daemons started successfully"
    
    # The gobgpd output is messing with the terminal, so reset it!
    stty sane  # restore sane tty settings
    echo
    
}

# Validate L3BGP network
validate_l3bgp_network() {
    log_info "Validating L3BGP network connectivity..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_debug "[DRY-RUN] Skipping L3BGP network validation"
        return 0
    fi
    
    for ((i=1; i<=NODES; i++)); do
        local node_ip="$(get_node_ip "$i")"
        local node_hostname="$(get_node_hostname "$i")"
        local netns="${PREFIX}${i}ns"
        local veth_a="${PREFIX}${i}a"
        
        # Check namespace interface
        if ! sudo ip -n "$netns" addr show "$veth_a" | grep -q "UP,LOWER_UP"; then
            log_error "L3BGP namespace interface $veth_a in $netns is not up"
            return 1
        fi
        
        if ! sudo ip -n "$netns" addr show "$veth_a" | grep -q "inet ${node_ip}/24"; then
            log_error "L3BGP namespace interface missing IP address: $node_ip"
            return 1
        fi
        
        log_debug "✅ Node $i ($node_hostname) validation passed"
    done
    
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_ns="${PREFIX}manager"
        local mgr_veth_a="${PREFIX}mgra"
        
        if ! sudo ip -n "$mgr_ns" addr show "$mgr_veth_a" | grep -q "inet ${MANAGER_IP}/16"; then
            log_error "Manager namespace missing IP address: $MANAGER_IP"
            return 1
        fi
        
        log_debug "✅ Manager node validation passed"
    fi
    
    log_info "L3BGP network validation passed"
}

# Test L3BGP network connectivity
test_l3bgp_connectivity() {
    log_info "Testing L3BGP network connectivity..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_debug "[DRY-RUN] Skipping L3BGP connectivity tests"
        return 0
    fi
    
    for ((i=1; i<=NODES; i++)); do
        local netns="${PREFIX}${i}ns"
        local node_hostname="$(get_node_hostname "$i")"
        
        # Test ping to manager if enabled
        if [[ "$MANAGER_ENABLED" == "true" ]]; then
            # In hub-and-spoke topology, nodes reach manager via subnet-specific address
            # Calculate manager IP based on node's actual subnet
            local node_subnet="$(get_node_subnet "$i")"
            local subnet_prefix=$(echo "$node_subnet" | cut -d'/' -f1 | cut -d'.' -f1-3)
            local manager_subnet_ip="${subnet_prefix}.2"
            log_debug "Testing ping from $node_hostname to manager ($manager_subnet_ip)"
            if ! execute_cmd "sudo ip netns exec $netns ping -c 1 -W 2 $manager_subnet_ip"; then
                log_error "Ping failed from $node_hostname to manager"
                return 1
            fi
        fi
        
        # Test hostname resolution to other nodes
        for ((j=1; j<=NODES; j++)); do
            if [[ "$i" != "$j" ]]; then
                local target_hostname="$(get_node_hostname "$j")"
                log_debug "Testing hostname resolution from $node_hostname to $target_hostname"
                if ! execute_cmd "sudo ip netns exec $netns ping -c 1 -W 2 $target_hostname"; then
                    log_error "Hostname resolution failed from $node_hostname to $target_hostname"
                    return 1
                fi
            fi
        done
    done
    
    log_info "L3BGP network connectivity test passed"
}

# Cleanup L3BGP network
cleanup_l3bgp_network() {
    log_info "Cleaning up L3BGP network infrastructure..."
    
    # Stop GoBGP daemons
    stop_gobgp_daemons
    
    # Stop Zebra daemons
    stop_zebra_daemons
    
    # Cleanup manager namespace if exists
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_ns="${PREFIX}manager"
        if ip netns list | grep -q "^$mgr_ns"; then
            execute_cmd "sudo ip netns del $mgr_ns"
        fi
    fi
    
    # Use the same cleanup functions as simple network
    cleanup_bridge
    delete_namespaces
    delete_veth_pairs
    
    # Clean up manager veth pair
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_veth_b="${PREFIX}mgrb"
        if ip link show "$mgr_veth_b" >/dev/null 2>&1; then
            execute_cmd "sudo ip link del dev $mgr_veth_b"
        fi
    fi
    
    # Clean up hosts files
    if [[ -d "${WORK_DIR}/hosts" ]]; then
        execute_cmd "rm -rf ${WORK_DIR}/hosts"
    fi
    
    # Clean up GoBGP files
    if [[ -d "${WORK_DIR}/gobgp" ]]; then
        execute_cmd "rm -rf ${WORK_DIR}/gobgp"
    fi
    
    log_info "L3BGP network cleanup completed"
}

# Stop all Zebra daemons
stop_zebra_daemons() {
    log_info "Stopping Zebra daemons..."
    
    # Stop zebra in each node namespace
    for ((i=1; i<=NODES; i++)); do
        local netns="${PREFIX}${i}ns"
        local zebra_pid="/var/run/frr-${PREFIX}${i}ns/zebra.pid"
        
        if [[ "${DRY_RUN}" != "true" ]] && [[ -f "$zebra_pid" ]]; then
            log_debug "Stopping zebra in namespace $netns"
            local pid=$(cat "$zebra_pid" 2>/dev/null)
            if [[ -n "$pid" ]]; then
                execute_cmd "sudo kill $pid" || true
            fi
        fi
    done
    
    # Stop manager zebra if enabled
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_zebra_pid="/var/run/frr-${PREFIX}manager/zebra.pid"
        
        if [[ "${DRY_RUN}" != "true" ]] && [[ -f "$mgr_zebra_pid" ]]; then
            log_debug "Stopping manager zebra"
            local pid=$(cat "$mgr_zebra_pid" 2>/dev/null)
            if [[ -n "$pid" ]]; then
                execute_cmd "sudo kill $pid" || true
            fi
        fi
    fi
    
    # Also kill any remaining zebra processes via pkill as fallback
    if [[ "${DRY_RUN}" != "true" ]] && command -v pkill >/dev/null 2>&1; then
        execute_cmd "sudo pkill -f '/usr/lib/frr/zebra'" || true
    fi
    
    # Clean up FRR directories
    for ((i=1; i<=NODES; i++)); do
        local frr_dir="/var/run/frr-${PREFIX}${i}ns"
        if [[ "${DRY_RUN}" != "true" ]] && [[ -d "$frr_dir" ]]; then
            execute_cmd "sudo rm -rf $frr_dir"
        fi
    done
    
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_frr_dir="/var/run/frr-${PREFIX}manager"
        if [[ "${DRY_RUN}" != "true" ]] && [[ -d "$mgr_frr_dir" ]]; then
            execute_cmd "sudo rm -rf $mgr_frr_dir"
        fi
    fi
}

# Stop all GoBGP daemons
stop_gobgp_daemons() {
    log_info "Stopping GoBGP daemons..."
    
    # Kill gobgpd processes
    if ! command -v pkill >/dev/null 2>&1; then
        log_warn "pkill not available, GoBGP processes may still be running"
        return
    fi
    
    # Stop gobgpd processes (they should be in namespaces anyway)
    if [[ "${DRY_RUN}" != "true" ]]; then
        execute_cmd "sudo pkill -f gobgpd" || true
    else
        log_debug "[DRY-RUN] Would stop GoBGP daemons"
    fi
}

# Show BGP status for all nodes
show_bgp_status() {
    log_info "BGP Status Summary..."
    
    for ((i=1; i<=NODES; i++)); do
        local netns="${PREFIX}${i}ns"
        local node_hostname="$(eval echo \$NODE_${i}_HOSTNAME)"
        
        echo ""
        echo "=== Node $i ($node_hostname) ==="
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_debug "[DRY-RUN] Would show BGP status for $netns"
            continue
        fi
        
        # Check if gobgpd is running
        if ! sudo ip netns exec "$netns" pgrep gobgpd >/dev/null 2>&1; then
            echo "❌ GoBGP daemon not running"
            continue
        fi
        
        # Check if zebra is running  
        if ! sudo ip netns exec "$netns" pgrep zebra >/dev/null 2>&1; then
            echo "❌ Zebra daemon not running"
            continue
        fi
        
        echo "✅ GoBGP and Zebra daemons running"
        
        # Show neighbor status
        echo "BGP Neighbors:"
        sudo ip netns exec "$netns" gobgp neighbor || echo "  Failed to get neighbor status"
        
        # Show BGP routes
        echo "BGP Routes:"
        sudo ip netns exec "$netns" gobgp global rib || echo "  Failed to get BGP routes"
        
        # Show kernel routes
        echo "Kernel Routes:"
        sudo ip netns exec "$netns" ip route show | grep -E "(proto bgp|proto zebra)" || echo "  No BGP routes in kernel"
    done
    
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        local mgr_ns="${PREFIX}manager"
        echo ""
        echo "=== Manager ==="
        
        if [[ "${DRY_RUN}" != "true" ]] && sudo ip netns exec "$mgr_ns" pgrep gobgpd >/dev/null 2>&1; then
            if sudo ip netns exec "$mgr_ns" pgrep zebra >/dev/null 2>&1; then
                echo "✅ Manager GoBGP and Zebra daemons running"
                
                echo "BGP Neighbors:"
                sudo ip netns exec "$mgr_ns" gobgp neighbor || echo "  Failed to get neighbor status"
                
                echo "BGP Routes:"
                sudo ip netns exec "$mgr_ns" gobgp global rib || echo "  Failed to get BGP routes"
                
                echo "Kernel Routes:"
                sudo ip netns exec "$mgr_ns" ip route show | grep -E "(proto bgp|proto zebra)" || echo "  No BGP routes in kernel"
            else
                echo "❌ Manager Zebra daemon not running"
            fi
        else
            echo "❌ Manager GoBGP daemon not running"
        fi
    fi
}

# Add test routes to demonstrate BGP with Zebra integration
add_test_routes() {
    log_info "Adding test routes for BGP demonstration..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_debug "[DRY-RUN] Would add test routes"
        return 0
    fi
    
    # Add test routes from each node to demonstrate cross-node routing
    for ((i=1; i<=NODES; i++)); do
        local netns="${PREFIX}${i}ns"
        local test_network="10.${i}00.${i}00.0/24"
        local next_hop_node=$(( (i % NODES) + 1 ))
        local next_hop_ip="$(get_node_ip "$next_hop_node")"
        
        log_debug "Adding test route $test_network via $next_hop_ip in namespace $netns"
        
        # Add route via GoBGP, which will automatically install it in kernel via Zebra
        if sudo ip netns exec "$netns" pgrep gobgpd >/dev/null 2>&1; then
            execute_cmd "sudo ip netns exec $netns gobgp global rib add $test_network nexthop $next_hop_ip" || true
        fi
    done
    
    # Wait a moment for routes to propagate
    sleep 2
    
    log_info "Test routes added - check with 'show_bgp_status' to see BGP and kernel routing tables"
}
