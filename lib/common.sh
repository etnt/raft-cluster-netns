#!/bin/bash
# Common utilities for RAFT cluster management
# Core shared functions used across all network topology modules and main script
#
# This module provides essential utilities for logging, command execution, validation,
# and network cleanup operations. All other modules depend on these foundational
# functions for consistent behavior across different network topologies.
#
# LOGGING FUNCTIONS:
#   log_info()              - Display informational messages with green [INFO] prefix
#   log_warn()              - Display warning messages with yellow [WARN] prefix (stderr)
#   log_error()             - Display error messages with red [ERROR] prefix (stderr)
#   log_debug()             - Display debug messages with blue [DEBUG] prefix (verbose mode only)
#
# COMMAND EXECUTION:
#   execute_cmd()           - Execute commands with logging and dry-run support
#                            Supports verbose output and DRY_RUN mode for testing
#
# VALIDATION FUNCTIONS:
#   validate_parameters()   - Validate global parameters (PREFIX, NODES) for security
#   command_exists()        - Check if a command is available in PATH
#   check_basic_prerequisites() - Verify required system commands (ip, sudo, etc.)
#
# NETWORK UTILITY FUNCTIONS:
#   fix_dockers_mess()      - Check for Docker network conflicts with 192.168.x.x ranges
#   add_hosts_to_namespace() - Install custom hosts file in network namespace
#   remove_hosts_from_namespace() - Remove hosts file from network namespace
#
# CLEANUP FUNCTIONS:
#   delete_veth_pairs()     - Remove virtual ethernet pairs for all nodes
#   delete_namespaces()     - Remove network namespaces and associated resources
#   cleanup_bridge()        - Remove bridge network and disconnect interfaces
#
# GLOBAL VARIABLES USED:
#   PREFIX                  - Namespace prefix for all network resources
#   NODES                   - Number of cluster nodes
#   BRIDGE_NAME            - Name of bridge network interface
#   WORK_DIR               - Working directory for generated files
#   VERBOSE                - Enable debug logging when true
#   DRY_RUN                - Enable dry-run mode when true (commands logged but not executed)
#
# SECURITY FEATURES:
#   - Parameter validation prevents path traversal attacks
#   - PREFIX restricted to alphanumeric, underscore, and hyphen characters
#   - All privileged operations use sudo with explicit commands
#
# COLOR SCHEME:
#   GREEN   - Informational messages and success indicators
#   YELLOW  - Warning messages and non-critical issues
#   RED     - Error messages and failure indicators
#   BLUE    - Debug messages and detailed operation logs

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
    local required_commands=("ip" "sudo" "mkdir" "rm" "ln" "tc")
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_error ""
        log_error "These are core system utilities that should be installed by default."
        log_error "Installation hints:"
        for cmd in "${missing_commands[@]}"; do
            case "$cmd" in
                ip)
                    log_error "  ip: sudo apt-get install iproute2  (or: sudo yum install iproute)"
                    ;;
                tc)
                    log_error "  tc: sudo apt-get install iproute2  (or: sudo yum install iproute)"
                    ;;
                sudo)
                    log_error "  sudo: Please install sudo and add your user to the sudo group"
                    ;;
                *)
                    log_error "  $cmd: sudo apt-get install coreutils  (or: sudo yum install coreutils)"
                    ;;
            esac
        done
        exit 1
    fi
    
    # Check if we can use sudo
    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo access. Please run with sudo or configure passwordless sudo."
        log_error ""
        log_error "To configure passwordless sudo for this script, you can:"
        log_error "  1. Run: sudo visudo"
        log_error "  2. Add: $USER ALL=(ALL) NOPASSWD: ALL"
        log_error "  Or for more restricted access:"
        log_error "     $USER ALL=(ALL) NOPASSWD: /usr/sbin/ip, /usr/bin/mkdir, /usr/bin/rm"
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
