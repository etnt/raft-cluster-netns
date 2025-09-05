#!/bin/bash
# Simple network topology module
# Implements flat bridge network with simple IP assignment

# Setup simple network topology (original implementation)
setup_simple_network() {
    log_info "Setting up simple network topology..."
    
    check_basic_prerequisites
    fix_dockers_mess
    create_hosts_files
    create_veth_pairs
    create_namespaces
    setup_bridge
    validate_simple_network
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        test_simple_connectivity
    fi
    
    log_info "Simple network setup completed successfully"
}

# Create virtual ethernet pairs
create_veth_pairs() {
    log_info "Creating virtual ethernet pairs..."
    
    for ((i=1; i<=NODES; i++)); do
        local veth_a="${PREFIX}${i}a"
        local veth_b="${PREFIX}${i}b"
        
        log_debug "Creating veth pair: $veth_a <-> $veth_b"
        execute_cmd "sudo ip link add dev $veth_a type veth peer name $veth_b"
    done
}

# Delete virtual ethernet pairs
delete_veth_pairs() {
    log_info "Deleting virtual ethernet pairs..."
    
    for ((i=1; i<=NODES; i++)); do
        local veth_b="${PREFIX}${i}b"
        
        if ip link show "$veth_b" >/dev/null 2>&1; then
            log_debug "Deleting veth pair: $veth_b"
            execute_cmd "sudo ip link del dev $veth_b"
        fi
    done
}

# Create hosts file for a namespace (simple network)
create_hosts_file() {
    local node_id="$1"
    local hosts_dir="${WORK_DIR}/hosts/${PREFIX}${node_id}ns"
    local hosts_file="${hosts_dir}/hosts"
    
    log_debug "Creating hosts file for node $node_id"
    
    execute_cmd "mkdir -p $hosts_dir"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_debug "[DRY-RUN] Would create hosts file: $hosts_file"
        return 0
    fi
    
    cat > "$hosts_file" << EOF
127.0.0.1   localhost
::1         localhost ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters

# HA Cluster nodes
EOF

    # Add entries for all cluster nodes (simple pattern)
    for ((j=1; j<=NODES; j++)); do
        echo "${NETWORK_PREFIX}.${j}.1    ${PREFIX}${j}.ha-cluster" >> "$hosts_file"
    done
}

# Create all hosts files
create_hosts_files() {
    log_info "Creating hosts files..."
    
    for ((i=1; i<=NODES; i++)); do
        create_hosts_file "$i"
    done
}

# Add hosts file to namespace
add_hosts_to_namespace() {
    local node_id="$1"
    local netns_dir="/etc/netns/${PREFIX}${node_id}ns"
    local hosts_src="${WORK_DIR}/hosts/${PREFIX}${node_id}ns/hosts"
    
    log_debug "Adding hosts file to namespace ${PREFIX}${node_id}ns"
    
    execute_cmd "sudo mkdir -p $netns_dir"
    execute_cmd "sudo cp $hosts_src $netns_dir/hosts"
}

# Remove hosts file from namespace
remove_hosts_from_namespace() {
    local node_id="$1"
    local netns_dir="/etc/netns/${PREFIX}${node_id}ns"
    
    if [[ -f "$netns_dir/hosts" ]]; then
        log_debug "Removing hosts file from namespace ${PREFIX}${node_id}ns"
        execute_cmd "sudo rm $netns_dir/hosts"
        execute_cmd "sudo rmdir $netns_dir" || true
    fi
}

# Create network namespaces (simple network)
create_namespaces() {
    log_info "Creating network namespaces..."
    
    for ((i=1; i<=NODES; i++)); do
        local netns="${PREFIX}${i}ns"
        local veth_a="${PREFIX}${i}a"
        local node_ip="${NETWORK_PREFIX}.${i}.1"
        
        log_info "Creating namespace: $netns"
        
        # Create namespace
        execute_cmd "sudo ip netns add $netns"
        
        # Move veth interface to namespace
        execute_cmd "sudo ip link set dev $veth_a netns $netns"
        
        # Configure interface in namespace
        execute_cmd "sudo ip -n $netns addr add ${node_ip}/16 dev $veth_a"
        execute_cmd "sudo ip -n $netns link set dev $veth_a up"
        execute_cmd "sudo ip -n $netns link set dev lo up"
        
        # Add default route
        execute_cmd "sudo ip -n $netns route add default via ${node_ip} dev $veth_a"
        
        # Add hosts file
        add_hosts_to_namespace "$i"
        
        log_info "Namespace $netns created successfully"
    done
    
    log_info "All namespaces created successfully"
}

# Delete network namespaces
delete_namespaces() {
    log_info "Deleting network namespaces..."
    
    for ((i=1; i<=NODES; i++)); do
        local netns="${PREFIX}${i}ns"
        local veth_a="${PREFIX}${i}a"
        
        if ip netns list | grep -q "^$netns"; then
            log_debug "Deleting namespace: $netns"
            
            # Move interface back to root namespace (if it exists)
            if sudo ip -n "$netns" link show "$veth_a" >/dev/null 2>&1; then
                execute_cmd "sudo ip -n $netns link set dev $veth_a netns 1" || true
            fi
            
            # Delete namespace
            execute_cmd "sudo ip netns del $netns"
            
            # Remove hosts file
            remove_hosts_from_namespace "$i"
        fi
    done
}

# Setup bridge network
setup_bridge() {
    log_info "Setting up bridge network..."
    
    # Create bridge
    execute_cmd "sudo ip link add dev $BRIDGE_NAME type bridge"
    log_info "Bridge $BRIDGE_NAME created"
    
    # Connect all veth interfaces to bridge
    for ((i=1; i<=NODES; i++)); do
        local veth_b="${PREFIX}${i}b"
        
        log_debug "Connecting $veth_b to bridge $BRIDGE_NAME"
        execute_cmd "sudo ip link set dev $veth_b master $BRIDGE_NAME"
        execute_cmd "sudo ip link set dev $veth_b up"
    done
    
    # Add gateway address to bridge
    execute_cmd "sudo ip addr add ${NETWORK_PREFIX}.0.254/16 dev $BRIDGE_NAME"
    execute_cmd "sudo ip link set dev $BRIDGE_NAME up"
}

# Cleanup bridge network
cleanup_bridge() {
    log_info "Cleaning up bridge network..."
    
    if ip link show "$BRIDGE_NAME" >/dev/null 2>&1; then
        # Disconnect interfaces from bridge
        for ((i=1; i<=NODES; i++)); do
            local veth_b="${PREFIX}${i}b"
            
            if ip link show "$veth_b" >/dev/null 2>&1; then
                log_debug "Disconnecting $veth_b from bridge"
                execute_cmd "sudo ip link set $veth_b nomaster" || true
                execute_cmd "sudo ip link set $veth_b down" || true
            fi
        done
        
        # Delete bridge
        execute_cmd "sudo ip link set dev $BRIDGE_NAME down"
        execute_cmd "sudo ip link del $BRIDGE_NAME"
    fi
}

# Validate simple network connectivity
validate_simple_network() {
    log_info "Validating simple network connectivity..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_debug "[DRY-RUN] Skipping network validation"
        return 0
    fi
    
    # Check bridge interface
    if ! ip addr show "$BRIDGE_NAME" | grep -q "UP,LOWER_UP"; then
        log_error "Bridge interface $BRIDGE_NAME is not up"
        return 1
    fi
    
    if ! ip addr show "$BRIDGE_NAME" | grep -q "inet ${NETWORK_PREFIX}.0.254/16"; then
        log_error "Bridge interface missing gateway address"
        return 1
    fi
    
    # Check namespace interfaces
    for ((i=1; i<=NODES; i++)); do
        local netns="${PREFIX}${i}ns"
        local veth_a="${PREFIX}${i}a"
        local veth_b="${PREFIX}${i}b"
        local node_ip="${NETWORK_PREFIX}.${i}.1"
        
        # Check veth pair is up
        if ! ip link show "$veth_b" | grep -q "UP,LOWER_UP"; then
            log_error "Interface $veth_b is not up"
            return 1
        fi
        
        # Check namespace interface
        if ! sudo ip -n "$netns" addr show "$veth_a" | grep -q "UP,LOWER_UP"; then
            log_error "Namespace interface $veth_a in $netns is not up"
            return 1
        fi
        
        if ! sudo ip -n "$netns" addr show "$veth_a" | grep -q "inet ${node_ip}/16"; then
            log_error "Namespace interface missing IP address: $node_ip"
            return 1
        fi
    done
    
    log_info "Simple network validation passed"
}

# Test simple network connectivity between nodes
test_simple_connectivity() {
    log_info "Testing simple network connectivity..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_debug "[DRY-RUN] Skipping connectivity tests"
        return 0
    fi
    
    for ((i=1; i<=NODES; i++)); do
        local netns="${PREFIX}${i}ns"
        
        # Test ping to next node (circular)
        local next_node=$((i % NODES + 1))
        local target_ip="${NETWORK_PREFIX}.${next_node}.1"
        
        log_debug "Testing ping from node $i to node $next_node"
        
        if ! execute_cmd "sudo ip netns exec $netns ping -c 1 -W 2 $target_ip"; then
            log_error "Ping failed from node $i to node $next_node"
            return 1
        fi
        
        # Test hostname resolution
        local target_hostname="${PREFIX}${next_node}.ha-cluster"
        if ! execute_cmd "sudo ip netns exec $netns ping -c 1 -W 2 $target_hostname"; then
            log_error "Hostname resolution failed from node $i to $target_hostname"
            return 1
        fi
    done
    
    log_info "Simple network connectivity test passed"
}

# Cleanup simple network
cleanup_simple_network() {
    log_info "Cleaning up simple network infrastructure..."
    
    cleanup_bridge
    delete_namespaces  
    delete_veth_pairs
    
    # Clean up hosts files
    if [[ -d "${WORK_DIR}/hosts" ]]; then
        execute_cmd "rm -rf ${WORK_DIR}/hosts"
    fi
    
    log_info "Simple network cleanup completed"
}
