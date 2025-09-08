#!/bin/bash
# Test script for L3BGP implementation with Zebra integration
# This tests the basic functionality without NSO

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Test configuration
NODES=2
PREFIX="test"
WORK_DIR="/tmp/test-l3bgp"
NETWORK_TYPE="l3bgp"
BRIDGE_NAME="test-cluster"
NETWORK_PREFIX="192.168"
MANAGER_ENABLED="true"
MANAGER_IP="172.17.0.2"
VERBOSE="true"
DRY_RUN="false"

# Set up node configurations
node_1_ip="192.168.1.1"
node_1_hostname="test1.cluster.local"
node_1_subnet="192.168.1.0/24"
node_1_asn="64501"

node_2_ip="192.168.2.1"
node_2_hostname="test2.cluster.local"
node_2_subnet="192.168.2.0/24"
node_2_asn="64502"

cleanup_test() {
    log_info "Cleaning up test environment..."
    
    # Source L3BGP module for cleanup
    source "$SCRIPT_DIR/lib/network-l3bgp.sh"
    cleanup_l3bgp_network || true
    
    # Remove work directory
    rm -rf "$WORK_DIR" || true
    
    log_info "Test cleanup completed"
}

main() {
    log_info "Starting L3BGP integration test..."
    
    # Cleanup any previous test artifacts
    cleanup_test
    
    # Create work directory
    mkdir -p "$WORK_DIR"
    
    # Check prerequisites
    source "$SCRIPT_DIR/lib/network-l3bgp.sh"
    
    if ! check_l3bgp_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    # Setup L3BGP network
    log_info "Setting up L3BGP network..."
    if ! setup_l3bgp_network; then
        log_error "L3BGP network setup failed"
        cleanup_test
        exit 1
    fi
    
    # Wait for everything to settle
    log_info "Waiting for BGP convergence..."
    sleep 5
    
    # Show BGP status
    log_info "BGP Status:"
    show_bgp_status
    
    # Add test routes
    log_info "Adding test routes..."
    add_test_routes
    
    # Show status again
    log_info "BGP Status after adding test routes:"
    show_bgp_status
    
    log_info "Test completed successfully!"
    log_info "Use './test-l3bgp-integration.sh cleanup' to clean up"
}

# Handle cleanup argument
if [[ "${1:-}" == "cleanup" ]]; then
    cleanup_test
    exit 0
fi

# Set trap for cleanup on failure
trap cleanup_test ERR INT TERM

main "$@"
