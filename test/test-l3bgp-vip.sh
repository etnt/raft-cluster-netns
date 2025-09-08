#!/bin/bash

# L3BGP VIP Testing Script
# This script tests BGP route advertisement and propagation using Virtual IPs
# Usage: ./test-l3bgp-vip.sh [command] [options]

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Default values
VIP_BASE="10.0"
DEFAULT_SUBNET="24"
TEST_TIMEOUT=10
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}

# Help function
show_help() {
    cat << EOF
L3BGP VIP Testing Script

USAGE:
    $0 <command> [options]

COMMANDS:
    setup <node_id> <vip>     Set up VIP on specified node and advertise via BGP
    test <node_id> <vip>      Test connectivity to VIP from all other nodes
    cleanup <node_id> <vip>   Remove VIP and BGP advertisement
    full-test                 Run complete VIP test cycle
    status                    Show current VIP status

OPTIONS:
    --timeout <seconds>       Ping timeout (default: $TEST_TIMEOUT)
    --help                    Show this help

EXAMPLES:
    $0 setup 1 10.0.1.100     Set up VIP 10.0.1.100 on node 1
    $0 test 1 10.0.1.100      Test connectivity to VIP from other nodes
    $0 full-test              Run complete test with default VIPs
    $0 cleanup 1 10.0.1.100   Remove VIP from node 1

EOF
}

# Get node namespace
get_node_namespace() {
    local node_id="$1"
    echo "${PREFIX:-l3bgp}${node_id}ns"
}

# Get all other node IDs
get_other_nodes() {
    local current_node="$1"
    local nodes="${NODES:-3}"
    
    for ((i=1; i<=nodes; i++)); do
        if [[ "$i" != "$current_node" ]]; then
            echo "$i"
        fi
    done
}

# Set up VIP on node
setup_vip() {
    local node_id="$1"
    local vip="$2"
    local netns="$(get_node_namespace "$node_id")"
    
    log_info "Setting up VIP $vip on node $node_id (namespace: $netns)"
    
    # Add VIP to loopback interface
    log_debug "Adding VIP $vip/32 to loopback interface"
    execute_cmd "sudo ip netns exec $netns ip addr add $vip/32 dev lo"
    
    # Advertise via BGP
    log_debug "Advertising VIP $vip/32 via BGP"
    execute_cmd "sudo ip netns exec $netns gobgp global rib add $vip/32"
    
    # Wait for BGP propagation
    sleep 2
    
    # Install forwarding route on manager based on BGP information
    log_debug "Installing forwarding route on manager"
    local node_ip="192.168.${node_id}.1"
    if ! sudo ip route add "$vip/32" via "$node_ip" dev ha-cluster 2>/dev/null; then
        log_debug "Manager route for $vip already exists or failed to add"
    fi
    
    log_info "✅ VIP $vip setup completed on node $node_id"
}

# Test VIP connectivity
test_vip() {
    local source_node="$1"
    local vip="$2"
    local timeout="${3:-$TEST_TIMEOUT}"
    local source_netns="$(get_node_namespace "$source_node")"
    
    log_debug "Testing connectivity from node $source_node to VIP $vip"
    
    # Check if route exists in BGP table
    if ! sudo ip netns exec "$source_netns" gobgp global rib | grep -q "$vip"; then
        log_error "VIP route $vip not found in BGP table of node $source_node"
        return 1
    fi
    
    # Install kernel route based on BGP next-hop if not present
    if ! sudo ip netns exec "$source_netns" ip route show | grep -q "$vip"; then
        log_debug "Installing kernel route for VIP $vip on node $source_node"
        # Use the gateway for this node's subnet
        local gateway="192.168.${source_node}.254"
        if ! sudo ip netns exec "$source_netns" ip route add "$vip/32" via "$gateway" 2>/dev/null; then
            log_warning "Could not install kernel route for $vip on node $source_node"
        fi
    fi
    
    # Test ping
    if execute_cmd "sudo ip netns exec $source_netns ping -c 1 -W $timeout $vip" >/dev/null 2>&1; then
        log_info "✅ Node $source_node can reach VIP $vip"
        return 0
    else
        log_error "❌ Node $source_node cannot reach VIP $vip"
        return 1
    fi
}

# Test VIP from all other nodes
test_vip_from_all() {
    local vip_node="$1"
    local vip="$2"
    local timeout="${3:-$TEST_TIMEOUT}"
    local success=0
    local total=0
    
    log_info "Testing VIP $vip connectivity from all nodes except node $vip_node"
    
    for other_node in $(get_other_nodes "$vip_node"); do
        ((total++))
        if test_vip "$other_node" "$vip" "$timeout"; then
            ((success++))
        fi
    done
    
    log_info "VIP connectivity test results: $success/$total nodes can reach VIP $vip"
    
    if [[ "$success" -eq "$total" ]]; then
        return 0
    else
        return 1
    fi
}

# Cleanup VIP
cleanup_vip() {
    local node_id="$1"
    local vip="$2"
    local netns="$(get_node_namespace "$node_id")"
    
    log_info "Cleaning up VIP $vip from node $node_id"
    
    # Remove from BGP
    log_debug "Removing VIP $vip/32 from BGP"
    execute_cmd "sudo ip netns exec $netns gobgp global rib del $vip/32" || true
    
    # Remove from loopback interface
    log_debug "Removing VIP $vip/32 from loopback interface"
    execute_cmd "sudo ip netns exec $netns ip addr del $vip/32 dev lo" || true
    
    # Remove route from manager
    log_debug "Removing VIP route from manager"
    execute_cmd "sudo ip route del $vip/32" || true
    
    log_info "✅ VIP $vip cleanup completed"
}

# Show VIP status
show_vip_status() {
    log_info "Current VIP Status:"
    
    local nodes="${NODES:-3}"
    for ((i=1; i<=nodes; i++)); do
        local netns="$(get_node_namespace "$i")"
        echo "=== Node $i (namespace: $netns) ==="
        
        echo "BGP Routes:"
        sudo ip netns exec "$netns" gobgp global rib 2>/dev/null || echo "  No BGP routes"
        
        echo "Loopback IPs:"
        sudo ip netns exec "$netns" ip addr show lo | grep "inet " | grep -v "127.0.0.1" || echo "  No additional IPs"
        
        echo ""
    done
    
    echo "=== Manager Routes ==="
    ip route show | grep -E "10\.|172\." || echo "No VIP routes on manager"
}

# Full test cycle
run_full_test() {
    local test_vip="10.0.1.100"
    local vip_node=1
    
    log_info "Running full L3BGP VIP test cycle"
    
    # Cleanup any existing test
    log_info "Cleaning up any existing test VIP"
    cleanup_vip "$vip_node" "$test_vip" 2>/dev/null || true
    
    # Setup VIP
    log_info "Step 1: Setting up test VIP $test_vip on node $vip_node"
    if ! setup_vip "$vip_node" "$test_vip"; then
        log_error "Failed to setup VIP"
        return 1
    fi
    
    # Wait for BGP propagation
    log_info "Step 2: Waiting for BGP route propagation..."
    sleep 3
    
    # Test connectivity
    log_info "Step 3: Testing VIP connectivity"
    if test_vip_from_all "$vip_node" "$test_vip"; then
        log_info "🎉 Full VIP test PASSED!"
        test_result=0
    else
        log_error "❌ Full VIP test FAILED!"
        test_result=1
    fi
    
    # Cleanup
    log_info "Step 4: Cleaning up test VIP"
    cleanup_vip "$vip_node" "$test_vip"
    
    return $test_result
}

# Main script logic
main() {
    local command="${1:-}"
    
    case "$command" in
        setup)
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 setup <node_id> <vip>"
                exit 1
            fi
            setup_vip "$2" "$3"
            ;;
        test)
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 test <vip_node> <vip>"
                exit 1
            fi
            test_vip_from_all "$2" "$3"
            ;;
        cleanup)
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 cleanup <node_id> <vip>"
                exit 1
            fi
            cleanup_vip "$2" "$3"
            ;;
        status)
            show_vip_status
            ;;
        full-test)
            run_full_test
            ;;
        --help|help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TEST_TIMEOUT="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Run main function with remaining arguments
main "$@"
