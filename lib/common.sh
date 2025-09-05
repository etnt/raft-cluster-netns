#!/bin/bash
# Common utilities for RAFT cluster management
# Shared functions used across all modules

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

# Execute command with logging and dry-run support
execute_cmd() {
    local cmd="$*"
    log_debug "Executing: $cmd"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] $cmd"
        return 0
    fi
    
    if [[ "${VERBOSE}" == "true" ]]; then
        eval "$cmd"
    else
        eval "$cmd" >/dev/null 2>&1
    fi
}

# Validation functions  
validate_parameters() {
    # Validate prefix for security (no path traversal)
    if [[ "$PREFIX" =~ \.\.|/ ]]; then
        log_error "Invalid prefix: $PREFIX (cannot contain '..' or '/')"
        exit 1
    fi
    
    # Validate prefix characters (alphanumeric and basic symbols only)
    if ! [[ "$PREFIX" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid prefix: $PREFIX (only alphanumeric, underscore, and hyphen allowed)"
        exit 1
    fi
    
    # Validate number of nodes if specified
    if [[ -n "$NODES" ]] && (! [[ "$NODES" =~ ^[0-9]+$ ]] || [[ "$NODES" -lt 1 ]]); then
        log_error "Invalid number of nodes: $NODES"
        exit 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Basic prerequisite checks (common to all network types)
check_basic_prerequisites() {
    log_info "Checking basic prerequisites..."
    
    local missing_commands=()
    local required_commands=("ip" "sudo" "mkdir" "rm" "ln")
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        exit 1
    fi
    
    # Check if we can use sudo
    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo access. Please run with sudo or configure passwordless sudo."
        exit 1
    fi
    
    log_debug "✅ Basic prerequisites satisfied"
}

# Fix Docker's network interface mess
fix_dockers_mess() {
    log_debug "Checking for Docker network interface conflicts..."
    
    # Check if docker0 bridge is interfering
    local docker_bridge_down=false
    if ip link show docker0 >/dev/null 2>&1; then
        if ip addr show docker0 | grep -q "192.168"; then
            log_warn "Docker bridge docker0 is using 192.168.x.x network, this might conflict"
            log_warn "Consider reconfiguring Docker to use a different network range"
        fi
    fi
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
