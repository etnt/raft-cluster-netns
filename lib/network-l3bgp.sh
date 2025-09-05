#!/bin/bash
# L3BGP network topology module
# Implements Layer 3 BGP-enabled network with custom node configurations

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
    
    # Check for git
    if ! command_exists git; then
        log_error "❌ git not found in PATH"
        missing_deps+=("git")
    else
        log_info "✅ Found git: $(git --version)"
    fi
    
    # Abort if dependencies missing
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies for L3BGP setup:"
        for dep in "${missing_deps[@]}"; do
            log_error "  - $dep"
        done
        log_error ""
        log_error "Installation commands:"
        log_error "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
        log_error "  CentOS/RHEL:   sudo yum install ${missing_deps[*]}"
        log_error "  GoBGP source:  https://github.com/osrg/gobgp"
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
        eval "NODE_${i}_ASN=\${${asn_var}:-}"
        
        log_debug "Node $i: IP=$(eval echo \$NODE_${i}_IP), Hostname=$(eval echo \$NODE_${i}_HOSTNAME)"
    done
    
    # Parse manager configuration  
    MANAGER_IP="${manager_ip:-172.17.0.2}"
    MANAGER_ENABLED="${manager_enabled:-false}"
    
    log_debug "Manager: Enabled=$MANAGER_ENABLED, IP=$MANAGER_IP"
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
    
    # Compile tailf-hcc package
    log_info "Compiling tailf-hcc package..."
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_debug "[DRY-RUN] Would compile tailf-hcc package"
    else
        # Need to source env.sh first, then compile
        local compile_cmd="cd $hcc_dir && make -C src"
        if [[ -n "$ENV_SH_PATH" && -f "$ENV_SH_PATH" ]]; then
            compile_cmd=". '$ENV_SH_PATH' && $compile_cmd"
        fi
        log_debug "Executing: $compile_cmd"
        execute_cmd "bash -c \"$compile_cmd\""
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
    
    # Add ha-cluster hostnames for NSO RAFT connectivity
    echo "" >> "$hosts_file"
    echo "# NSO RAFT Cluster hostnames" >> "$hosts_file"
    for ((j=1; j<=NODES; j++)); do
        local node_ip="$(get_node_ip "$j")"
        echo "$node_ip    ${PREFIX}${j}.ha-cluster" >> "$hosts_file"
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
        
        # Move veth interface to namespace
        execute_cmd "sudo ip link set dev $veth_a netns $netns"
        
        # Configure interface in namespace with custom IP
        execute_cmd "sudo ip -n $netns addr add ${node_ip}/24 dev $veth_a"
        execute_cmd "sudo ip -n $netns link set dev $veth_a up"
        execute_cmd "sudo ip -n $netns link set dev lo up"
        
        # Add routing for L3BGP topology
        # Each node needs to know how to reach other subnets through the bridge
        local node_subnet="$(get_node_subnet "$i")"
        local subnet_base="${node_subnet%.*}" # Get 192.168.30 from 192.168.30.0/24
        local gateway_ip="${subnet_base}.254"
        
        # Add routes to other node subnets
        for ((j=1; j<=NODES; j++)); do
            if [[ $j -ne $i ]]; then
                local other_subnet="$(get_node_subnet "$j")"
                execute_cmd "sudo ip -n $netns route add $other_subnet via $gateway_ip dev $veth_a"
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
        local subnet_base="${node_subnet%.*}" # Get 192.168.30 from 192.168.30.0/24
        local subnet_gateway="${subnet_base}.254"
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
    
    # Move veth interface to namespace
    execute_cmd "sudo ip link set dev $mgr_veth_a netns $mgr_ns"
    
    # Configure manager IP
    execute_cmd "sudo ip -n $mgr_ns addr add ${MANAGER_IP}/16 dev $mgr_veth_a"
    execute_cmd "sudo ip -n $mgr_ns link set dev $mgr_veth_a up"
    execute_cmd "sudo ip -n $mgr_ns link set dev lo up"
    
    log_info "Manager node created successfully"
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
            log_debug "Testing ping from $node_hostname to manager"
            if ! execute_cmd "sudo ip netns exec $netns ping -c 1 -W 2 $MANAGER_IP"; then
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
    
    log_info "L3BGP network cleanup completed"
}
