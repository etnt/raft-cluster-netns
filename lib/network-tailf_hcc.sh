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
