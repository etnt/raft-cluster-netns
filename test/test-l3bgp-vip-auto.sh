#!/bin/bash

# Test script for L3BGP VIP functionality with automatic route installation via zebra
# This script tests the HCC-like behavior where:
# 1. VIP is assigned to loopback interface
# 2. VIP is advertised via BGP
# 3. Routes are automatically installed via zebra integration

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Setup VIP on a node (assign to loopback and advertise via BGP)
setup_vip() {
    local vip="$1"
    local node="$2"
    local netns="l3bgp${node}ns"
    local api_port
    
    case "$node" in
        "1") api_port="60051" ;;
        "2") api_port="60052" ;;
        "3") api_port="60053" ;;
        *) error "Invalid node: $node" ;;
    esac
    
    log_info "Setting up VIP $vip on $node (namespace: $netns)"
    
    # 1. Assign VIP to loopback interface (as per HCC docs)
    execute_cmd "sudo ip netns exec $netns ip addr add $vip/32 dev lo"
    
    # 2. Advertise VIP via BGP
    execute_cmd "sudo ip netns exec $netns gobgp --api-hosts=:$api_port global rib add $vip/32 -a ipv4"
    
    log "VIP $vip setup complete on $node"
}

# Remove VIP from a node
cleanup_vip() {
    local vip="$1"
    local node="$2"
    local netns="l3bgp${node}ns"
    local api_port
    
    case "$node" in
        "1") api_port="60051" ;;
        "2") api_port="60052" ;;
        "3") api_port="60053" ;;
        *) error "Invalid node: $node" ;;
    esac
    
    log "Cleaning up VIP $vip from $node"
    
    # Remove BGP advertisement
    if sudo ip netns exec "$netns" gobgp --api-hosts=:$api_port global rib del "$vip/32" 2>/dev/null; then
        log "Removed BGP advertisement for $vip"
    fi
    
    # Remove from loopback interface
    if sudo ip netns exec "$netns" ip addr del "$vip/32" dev lo 2>/dev/null; then
        log "Removed $vip from loopback interface"
    fi
}

# Test VIP connectivity and automatic route installation
test_vip() {
    local vip="$1"
    local primary_node="$2"
    
    log "Testing VIP $vip with primary node $primary_node"
    
    # Setup VIP on primary node
    setup_vip "$vip" "$primary_node"
    
    # Wait for BGP convergence
    log "Waiting for BGP convergence..."
    sleep 3
    
    # Check if route was automatically installed on manager
    log "Checking if route was automatically installed on manager..."
    if sudo ip netns exec l3bgpmanager ip route show "$vip/32" | grep -q "$vip"; then
        log "✓ Route for $vip automatically installed on manager"
        sudo ip netns exec l3bgpmanager ip route show "$vip/32"
    else
        error "✗ Route for $vip NOT found on manager"
        return 1
    fi
    
    # Test connectivity from manager to VIP
    log "Testing connectivity from manager to VIP $vip..."
    if sudo ip netns exec l3bgpmanager ping -c 3 -W 2 "$vip" >/dev/null 2>&1; then
        log "✓ Ping to $vip successful from manager"
    else
        log "✗ Ping to $vip failed from manager"
    fi
    
    # Show BGP table on manager
    log "BGP table on manager:"
    sudo ip netns exec l3bgpmanager gobgp --api-hosts=:60050 global rib -a ipv4 | grep -E "(Network|$vip)" || true
    
    # Show BGP neighbors on manager
    log "BGP neighbors on manager:"
    sudo ip netns exec l3bgpmanager gobgp --api-hosts=:60050 neighbor | grep -E "(Neighbor|State|192\.168\.[123]\.1)" || true
    
    log "VIP test completed"
}

# Test failover scenario
test_vip_failover() {
    local vip="$1"
    local primary_node="$2"
    local secondary_node="$3"
    
    log "Testing VIP failover: $vip from node$primary_node to node$secondary_node"
    
    # Setup VIP on primary
    setup_vip "$vip" "$primary_node"
    sleep 2
    
    # Verify primary has the VIP
    log "Verifying primary node$primary_node has VIP"
    sudo ip netns exec "l3bgp${primary_node}ns" ip addr show lo | grep "$vip" || error "VIP not found on primary"
    
    # Test connectivity
    sudo ip netns exec l3bgpmanager ping -c 1 -W 1 "$vip" >/dev/null || error "Cannot reach VIP on primary"
    log "✓ VIP reachable on primary node$primary_node"
    
    # Simulate failover: remove VIP from primary and add to secondary
    log "Simulating failover..."
    cleanup_vip "$vip" "$primary_node"
    setup_vip "$vip" "$secondary_node"
    
    # Wait for BGP convergence
    sleep 3
    
    # Test connectivity to new primary
    if sudo ip netns exec l3bgpmanager ping -c 3 -W 2 "$vip" >/dev/null 2>&1; then
        log "✓ VIP failover successful - now reachable on node$secondary_node"
    else
        log "✗ VIP failover failed - cannot reach on node$secondary_node"
    fi
    
    # Cleanup
    cleanup_vip "$vip" "$secondary_node"
}

# Show BGP and routing status
show_status() {
    log "=== BGP and Routing Status ==="
    
    for node in 1 2 3; do
        local netns="l3bgp${node}ns"
        local api_port="6005${node}"
        log "Node $node (namespace: $netns):"
        echo "  BGP neighbors:"
        sudo ip netns exec "$netns" gobgp --api-hosts=:$api_port neighbor 2>/dev/null | grep -E "(Neighbor|State)" | head -4 || echo "    No BGP data"
        echo "  Loopback IPs:"
        sudo ip netns exec "$netns" ip addr show lo | grep "inet " | grep -v "127.0.0.1" || echo "    Only localhost"
        echo
    done
    
    log "Manager (l3bgpmanager):"
    echo "  BGP neighbors:"
    sudo ip netns exec l3bgpmanager gobgp --api-hosts=:60050 neighbor 2>/dev/null | grep -E "(Neighbor|State)" | head -6 || echo "    No BGP data"
    echo "  Installed routes (via zebra):"
    sudo ip netns exec l3bgpmanager ip route show | grep -E "192\.168\.100\.|10\.0\.0\." || echo "    No VIP routes"
    echo
}

# Main test function
main() {
    case "${1:-}" in
        "setup")
            setup_vip "$2" "$3"
            ;;
        "cleanup")
            cleanup_vip "$2" "$3"
            ;;
        "test")
            test_vip "$2" "$3"
            ;;
        "failover")
            test_vip_failover "$2" "$3" "$4"
            ;;
        "status")
            show_status
            ;;
        *)
            cat << 'EOF'
Usage: test-l3bgp-vip-auto.sh <command> [args...]

Commands:
  setup <vip> <node>           Setup VIP on node (assign to lo + advertise BGP)
  cleanup <vip> <node>         Remove VIP from node
  test <vip> <node>           Test VIP functionality
  failover <vip> <from> <to>  Test VIP failover between nodes
  status                       Show BGP and routing status

Examples:
  ./test-l3bgp-vip-auto.sh setup 192.168.100.1 1
  ./test-l3bgp-vip-auto.sh test 192.168.100.1 1
  ./test-l3bgp-vip-auto.sh failover 192.168.100.1 1 2
  ./test-l3bgp-vip-auto.sh status
EOF
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
