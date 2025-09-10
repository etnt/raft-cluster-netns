#!/bin/bash
# tailf_hcc network configuration
# Similar to L3BGP but only manager node has BGP/Zebra

# Source the L3BGP functions since tailf_hcc builds on top of it
source "$SCRIPT_DIR/lib/network-l3bgp.sh"

log_info "Loaded tailf_hcc network module"

# Override the start_gobgp_daemons function to only start on manager
start_gobgp_daemons() {
    log_info "Starting GoBGP daemons (tailf_hcc mode: manager only)"
    
    # Only start GoBGP on the manager node
    local manager_node=$(get_manager_node)
    if [[ -z "$manager_node" ]]; then
        log_error "No manager node found"
        return 1
    fi
    
    log_info "Starting GoBGP daemon on manager node: $manager_node"
    
    local mgr_ns="${PREFIX}manager"
    local gobgp_dir="${WORK_DIR}/gobgp"
    local manager_config="${gobgp_dir}/manager.yaml"
    local manager_log="${gobgp_dir}/manager.log"
    
    if [[ ! -f "$manager_config" ]]; then
        log_error "GoBGP config file not found: $manager_config"
        return 1
    fi
    
    log_debug "Starting GoBGP manager in namespace $mgr_ns"
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        # Start GoBGP manager daemon
        log_debug "Starting manager GoBGP daemon: sudo ip netns exec $mgr_ns gobgpd -f $manager_config -l debug"
        sudo ip netns exec "$mgr_ns" gobgpd -f "$manager_config" -l debug > "$manager_log" 2>&1 &
        
        # Wait a moment for startup
        sleep 3
        
        # Verify GoBGP is running
        if sudo ip netns exec "$mgr_ns" pgrep -f "gobgpd.*manager.yaml" > /dev/null; then
            log_info "GoBGP daemon started successfully on $manager_node"
        else
            log_error "Failed to start GoBGP daemon on $manager_node"
            return 1
        fi
    fi
    
    # The gobgpd output is messing with the terminal, so reset it!
    stty sane  # restore sane tty settings
    echo
}

# Override the start_zebra_daemons function to only start on manager
start_zebra_daemons() {
    log_info "Starting Zebra daemons (tailf_hcc mode: manager only)"
    
    # Only start Zebra on the manager node
    local manager_node=$(get_manager_node)
    if [[ -z "$manager_node" ]]; then
        log_error "No manager node found"
        return 1
    fi
    
    log_info "Starting Zebra daemon on manager node: $manager_node"
    
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
                -A 127.0.0.1 > $mgr_zebra_log 2>&1 &
        fi
    fi
    
    # Wait for manager zebra socket to be available
    if ! wait_for_zebra "$mgr_ns" "$mgr_zebra_socket"; then
        log_error "Manager Zebra socket not available: $mgr_zebra_socket"
        return 1
    fi
    
    log_info "Zebra daemon started successfully on $manager_node"
}

# Override cleanup to only clean manager node BGP/Zebra processes
cleanup_l3bgp_processes() {
    log_info "Cleaning up tailf_hcc processes (manager only)"
    
    local manager_node=$(get_manager_node)
    if [[ -z "$manager_node" ]]; then
        log_info "No manager node found for cleanup"
        return 0
    fi
    
    local node_ns="${PREFIX}manager"
    
    # Clean up GoBGP processes on manager
    log_info "Stopping GoBGP processes on manager node: $manager_node"
    if ip netns list | grep -q "^${node_ns}$"; then
        ip netns exec "$node_ns" pkill -f "gobgp.*${manager_node}.yaml" 2>/dev/null || true
    fi
    
    # Clean up Zebra processes on manager
    log_info "Stopping Zebra processes on manager node: $manager_node"
    if ip netns list | grep -q "^${node_ns}$"; then
        ip netns exec "$node_ns" pkill -f "/usr/lib/frr/zebra.*${manager_node}" 2>/dev/null || true
    fi
    
    # Remove PID files
    local zebra_pid_file="${CONFIG_DIR}/zebra/${manager_node}/zebra.pid"
    if [[ -f "$zebra_pid_file" ]]; then
        rm -f "$zebra_pid_file"
    fi
}

# Helper function to get the manager node
get_manager_node() {
    # Look for manager node in the configuration
    if [[ -n "${MANAGER_NAME:-}" ]]; then
        echo "$MANAGER_NAME"
        return 0
    fi
    
    # Check if MANAGER_NODE is set
    if [[ -n "${MANAGER_NODE:-}" ]]; then
        echo "$MANAGER_NODE"
        return 0
    fi
    
    # Fallback to manager naming convention
    echo "manager"
}

# Override setup_l3bgp_nso_packages to include HCC XML config generation
setup_l3bgp_nso_packages() {
    log_info "Setting up tailf_hcc NSO packages..."
    
    # Clone tailf-hcc package if not exists
    local hcc_dir="${WORK_DIR}/tailf-hcc"
    if [[ ! -d "$hcc_dir" ]]; then
        log_info "Cloning tailf-hcc package..."
        execute_cmd "git clone ssh://git@stash.tail-f.com/pkg/tailf-hcc.git $hcc_dir"
    fi
    
    # Create package links and HCC config files in each NSO node
    for ((i=1; i<=NODES; i++)); do
        local packages_dir="${WORK_DIR}/ncs-run${i}/packages"
        local hcc_link="${packages_dir}/tailf-hcc"
        
        if [[ ! -L "$hcc_link" ]]; then
            log_info "Creating tailf-hcc package link for node $i"
            execute_cmd "ln -sf $hcc_dir $hcc_link"
        fi
        
        # Generate HCC XML configuration for this node
        generate_hcc_config "$i"
    done
}

# Generate HCC XML configuration for a node
generate_hcc_config() {
    local node_id="$1"
    local node_dir="${WORK_DIR}/ncs-run${node_id}"
    local hcc_config="${node_dir}/hcc.xml"
    
    # Get node configuration
    local node_ip=$(get_node_ip "$node_id")
    local node_hostname=$(get_node_hostname "$node_id")
    local node_subnet=$(get_node_subnet "$node_id")
    local node_asn
    eval node_asn="\$NODE_${node_id}_ASN"
    
    # Generate the correct node-id format: ncsd{node_id}@tailf_hcc{node_id}.ha-cluster
    local hcc_node_id="ncsd${node_id}@tailf_hcc${node_id}.ha-cluster"
    
    # Extract the manager IP for neighbor configuration
    local manager_ip="${MANAGER_IP:-172.17.0.2}"
    local manager_subnet_ip
    
    # Calculate manager IP in this node's subnet (e.g., 192.168.30.2 for node 1)
    local subnet_base=$(echo "$node_subnet" | cut -d'.' -f1-3)
    manager_subnet_ip="${subnet_base}.2"
    
    log_info "Generating HCC config for node $node_id: $hcc_config"
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        cat > "$hcc_config" << EOF
<config xmlns="http://tail-f.com/ns/config/1.0">
  <hcc xmlns="http://cisco.com/pkg/tailf-hcc">
    <bgp>
      <node>
        <node-id>$hcc_node_id</node-id>
        <enabled>true</enabled>
        <as>$node_asn</as>
        <router-id>$node_ip</router-id>
        <neighbor>
          <address>$manager_subnet_ip</address>
          <as>${MANAGER_ASN:-64500}</as>
          <enabled>true</enabled>
        </neighbor>
EOF

        # Add neighbor entries for other nodes (full mesh BGP peering)
        for ((j=1; j<=NODES; j++)); do
            if [[ $j -ne $node_id ]]; then
                local peer_ip=$(get_node_ip "$j")
                local peer_asn
                eval peer_asn="\$NODE_${j}_ASN"
                
                cat >> "$hcc_config" << EOF
        <neighbor>
          <address>$peer_ip</address>
          <as>$peer_asn</as>
          <enabled>true</enabled>
        </neighbor>
EOF
            fi
        done
        
        cat >> "$hcc_config" << EOF
      </node>
    </bgp>
  </hcc>
</config>
EOF
    else
        log_debug "[DRY-RUN] Would generate HCC config: $hcc_config"
    fi
}

# Override manager GoBGP config generation for tailf_hcc
create_manager_gobgp_config() {
    local manager_ip="$1"
    local manager_asn="$2"
    local config_file="$3"
    
    log_debug "Creating tailf_hcc manager GoBGP config: $config_file"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_debug "[DRY-RUN] Would create tailf_hcc manager GoBGP config: $config_file"
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

    # Add all nodes as neighbors with simplified config
    for ((i=1; i<=NODES; i++)); do
        local node_ip="$(eval echo \$NODE_${i}_IP)"
        local node_asn="$(eval echo \$NODE_${i}_ASN)"
        cat >> "$config_file" << EOF
  - config:
      neighbor-address: $node_ip
      peer-as: $node_asn
EOF
    done
}
