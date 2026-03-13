#!/bin/bash
# Network impairment module for RAFT cluster management
# Provides tc/netem-based network latency, packet loss, and corruption simulation
#
# This module uses Linux Traffic Control (tc) with the netem queueing discipline
# to simulate various network conditions on the veth-a interface inside each
# network namespace. This approach works uniformly across all network topologies
# (simple, l3bgp, tailf_hcc).
#
# FUNCTIONS:
#   check_netem_prerequisites()    - Verify tc command and netem kernel module
#   has_netem_qdisc()              - Check if netem qdisc exists on a node's interface
#   apply_netem()                  - Apply/update netem qdisc on a node's veth-a
#   remove_netem()                 - Remove netem qdisc from a node's veth-a
#   get_netem_status()             - Query current netem settings on a node
#   show_impairment_status()       - Display impairment status for all nodes
#   apply_delay()                  - Apply latency with optional jitter
#   apply_loss()                   - Apply packet loss with optional correlation
#   apply_combined_impairment()    - Apply multiple netem parameters at once
#   reset_impairment()             - Remove all impairments from one or all nodes
#
# GLOBAL VARIABLES USED:
#   PREFIX   - Namespace prefix for network resources
#   NODES    - Number of cluster nodes
#   VERBOSE  - Enable debug logging when true
#   DRY_RUN  - Enable dry-run mode when true

# Check that tc and netem are available
check_netem_prerequisites() {
    if ! command_exists "tc"; then
        log_error "Required command not found: tc"
        log_error "Install with: sudo apt-get install iproute2  (or: sudo yum install iproute)"
        return 1
    fi

    # Try to load the netem kernel module (may already be loaded or built-in)
    if ! sudo modprobe sch_netem 2>/dev/null; then
        log_warn "Could not load sch_netem kernel module - netem may not work"
        log_warn "This module is required for network impairment simulation"
    fi

    return 0
}

# Get the veth-a interface name for a node
get_node_veth_a() {
    local node_id="$1"
    echo "${PREFIX}${node_id}a"
}

# Get the namespace name for a node
get_node_netns() {
    local node_id="$1"
    echo "${PREFIX}${node_id}ns"
}

# Check if a netem qdisc already exists on a node's interface
has_netem_qdisc() {
    local node_id="$1"
    local netns
    netns=$(get_node_netns "$node_id")
    local veth_a
    veth_a=$(get_node_veth_a "$node_id")

    sudo ip netns exec "$netns" tc qdisc show dev "$veth_a" 2>/dev/null | grep -q "netem"
}

# Apply or update netem qdisc on a node's veth-a interface
# Usage: apply_netem <node_id> <netem_params...>
# Example: apply_netem 1 delay 100ms loss 5%
apply_netem() {
    local node_id="$1"
    shift
    local netem_params="$*"

    local netns
    netns=$(get_node_netns "$node_id")
    local veth_a
    veth_a=$(get_node_veth_a "$node_id")

    # Verify namespace exists
    if ! ip netns list | grep -q "^$netns"; then
        log_error "Namespace $netns does not exist"
        return 1
    fi

    # Verify interface exists inside namespace
    if ! sudo ip netns exec "$netns" ip link show "$veth_a" >/dev/null 2>&1; then
        log_error "Interface $veth_a does not exist in namespace $netns"
        return 1
    fi

    # Use 'change' if netem qdisc already exists, 'add' otherwise
    local action="add"
    if has_netem_qdisc "$node_id"; then
        action="change"
    fi

    log_debug "Applying netem ($action) on $veth_a in $netns: $netem_params"
    execute_cmd "sudo ip netns exec $netns tc qdisc $action dev $veth_a root netem $netem_params"
}

# Remove netem qdisc from a node's veth-a interface
remove_netem() {
    local node_id="$1"
    local netns
    netns=$(get_node_netns "$node_id")
    local veth_a
    veth_a=$(get_node_veth_a "$node_id")

    # Verify namespace exists
    if ! ip netns list | grep -q "^$netns"; then
        log_debug "Namespace $netns does not exist, skipping netem removal"
        return 0
    fi

    if has_netem_qdisc "$node_id"; then
        log_debug "Removing netem qdisc from $veth_a in $netns"
        execute_cmd "sudo ip netns exec $netns tc qdisc del dev $veth_a root"
    else
        log_debug "No netem qdisc on $veth_a in $netns, nothing to remove"
    fi
}

# Get the current netem status for a node (human-readable)
# Returns the netem line from tc qdisc show, or "no impairment"
get_netem_status() {
    local node_id="$1"
    local netns
    netns=$(get_node_netns "$node_id")
    local veth_a
    veth_a=$(get_node_veth_a "$node_id")

    if ! ip netns list | grep -q "^$netns"; then
        echo "namespace missing"
        return
    fi

    local tc_output
    tc_output=$(sudo ip netns exec "$netns" tc qdisc show dev "$veth_a" 2>/dev/null)

    local netem_line
    netem_line=$(echo "$tc_output" | grep "netem" || true)

    if [[ -n "$netem_line" ]]; then
        # Extract the netem parameters (everything after "netem")
        echo "$netem_line" | sed 's/.*netem //'
    else
        echo "no impairment"
    fi
}

# Display impairment status for all nodes
show_impairment_status() {
    echo "  Network Impairment Status:"

    for ((i=1; i<=NODES; i++)); do
        local veth_a
        veth_a=$(get_node_veth_a "$i")
        local status
        status=$(get_netem_status "$i")
        echo "    Node $i ($veth_a): $status"
    done
}

# Apply delay (latency) to a node or all nodes
# Usage: apply_delay <node_id|all> <delay> [jitter]
apply_delay() {
    local target="$1"
    local delay_val="$2"
    local jitter_val="${3:-}"

    local netem_params="delay $delay_val"
    if [[ -n "$jitter_val" ]]; then
        netem_params="$netem_params $jitter_val"
    fi

    if [[ "$target" == "all" ]]; then
        for ((i=1; i<=NODES; i++)); do
            apply_netem "$i" $netem_params
        done
        log_info "Applied $netem_params to all $NODES nodes"
    else
        apply_netem "$target" $netem_params
        log_info "Applied $netem_params to node $target"
    fi
}

# Apply packet loss to a node or all nodes
# Usage: apply_loss <node_id|all> <percent> [correlation]
apply_loss() {
    local target="$1"
    local loss_val="$2"
    local correlation_val="${3:-}"

    local netem_params="loss $loss_val"
    if [[ -n "$correlation_val" ]]; then
        netem_params="$netem_params $correlation_val"
    fi

    if [[ "$target" == "all" ]]; then
        for ((i=1; i<=NODES; i++)); do
            apply_netem "$i" $netem_params
        done
        log_info "Applied $netem_params to all $NODES nodes"
    else
        apply_netem "$target" $netem_params
        log_info "Applied $netem_params to node $target"
    fi
}

# Apply combined impairment with multiple parameters
# Usage: apply_combined_impairment <node_id|all> <netem_params...>
# Example: apply_combined_impairment 1 delay 100ms 20ms loss 2% corrupt 0.1%
apply_combined_impairment() {
    local target="$1"
    shift
    local netem_params="$*"

    if [[ -z "$netem_params" ]]; then
        log_error "No impairment parameters specified"
        return 1
    fi

    if [[ "$target" == "all" ]]; then
        for ((i=1; i<=NODES; i++)); do
            apply_netem "$i" $netem_params
        done
        log_info "Applied impairment to all $NODES nodes: $netem_params"
    else
        apply_netem "$target" $netem_params
        log_info "Applied impairment to node $target: $netem_params"
    fi
}

# Reset (remove) all impairments from one or all nodes
reset_impairment() {
    local target="$1"

    if [[ "$target" == "all" ]]; then
        for ((i=1; i<=NODES; i++)); do
            remove_netem "$i"
        done
        log_info "Cleared all network impairments from all nodes"
    else
        remove_netem "$target"
        log_info "Cleared network impairments from node $target"
    fi
}

# Apply a predefined impairment scenario to one or all nodes
# Usage: apply_scenario <scenario_name> [node_id|all]
apply_scenario() {
    local scenario="$1"
    local target="${2:-all}"

    local netem_params=""
    case "$scenario" in
        lan)
            netem_params="delay 1ms 0.5ms"
            ;;
        wan)
            netem_params="delay 50ms 10ms loss 0.1%"
            ;;
        satellite)
            netem_params="delay 300ms 50ms loss 1%"
            ;;
        flaky)
            netem_params="delay 20ms 50ms loss 5%"
            ;;
        congested)
            netem_params="delay 100ms 100ms loss 2%"
            ;;
        lossy)
            netem_params="delay 5ms 2ms loss 10%"
            ;;
        *)
            log_error "Unknown scenario: $scenario"
            log_error "Available scenarios: lan, wan, satellite, flaky, congested, lossy"
            return 1
            ;;
    esac

    log_info "Applying '$scenario' scenario: $netem_params"
    apply_combined_impairment "$target" $netem_params
}
