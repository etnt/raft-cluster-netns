#!/bin/bash

# SSL Certificate Setup Script for NSO RAFT Cluster
# Replicates the functionality of disterl_tls.mk for Distributed Erlang over TLS

set -euo pipefail

# Script metadata
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"

# Default configuration
NODES="${NODES:-0 1 2 3 4 5}"
CAS="${CAS:-1 2 12}"
OPENSSL="${OPENSSL:-openssl}"
OPENSSL_CONF_IN="${OPENSSL_CONF_IN:-./openssl.conf.in}"
CA_SERIAL_START_INDEX="${CA_SERIAL_START_INDEX:-FF}"
WORK_DIR="${WORK_DIR:-$(pwd)}"
VERBOSE="${VERBOSE:-false}"
DRY_RUN="${DRY_RUN:-false}"

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

# Calculate end date (48 days from now)
get_end_date() {
    if date --version >/dev/null 2>&1; then
        # GNU date
        date -u -d '48days' +'%Y%m%d%H%M%SZ'
    else
        # BSD date (macOS)
        date -u -v+'48d' +'%Y%m%d%H%M%SZ'
    fi
}

# Create OpenSSL configuration from template
create_openssl_conf() {
    local ca_num="$1"
    local conf_file="$WORK_DIR/erldist/ssl/ca${ca_num}/openssl.conf"
    
    log_debug "Creating OpenSSL config for CA${ca_num}: $conf_file"
    
    if [[ ! -f "$OPENSSL_CONF_IN" ]]; then
        log_error "OpenSSL config template not found: $OPENSSL_CONF_IN"
        return 1
    fi
    
    execute_cmd "sed 's/__CA__/ca${ca_num}/' '$OPENSSL_CONF_IN' > '$conf_file'"
}

# Create default OpenSSL configuration template if missing
create_default_openssl_template() {
    local template_file="$OPENSSL_CONF_IN"
    
    if [[ -f "$template_file" ]]; then
        return 0
    fi
    
    log_info "Creating default OpenSSL configuration template: $template_file"
    
    cat > "$template_file" << 'EOF'
[ca]
default_ca = ca_default

[ca_default]
dir = erldist/ssl/__CA__
certificate = $dir/cert.pem
private_key = $dir/key.pem
database = $dir/index.txt
default_md = sha256
default_crl_days = 30
RANDFILE = $dir/private/.rand
policy = policy_any
serial = $dir/serial.txt
new_certs_dir = $dir/certs

[req]
distinguished_name = req_distinguished_name

[req_distinguished_name]

[policy_any]
commonName = supplied
EOF
}

# Create directory structure
create_directories() {
    local dirs=(
        "erldist/ssl/crl"
    )
    
    # Add CA directories
    for ca in $CAS; do
        dirs+=(
            "erldist/ssl/ca${ca}"
            "erldist/ssl/ca${ca}/csr" 
            "erldist/ssl/ca${ca}/certs"
            "erldist/ssl/ca${ca}/private"
        )
    done
    
    # Add node directories
    for node in $NODES; do
        dirs+=("erldist/ssl/ncs${node}")
    done
    
    log_info "Creating directory structure..."
    for dir in "${dirs[@]}"; do
        local full_path="$WORK_DIR/$dir"
        log_debug "Creating directory: $full_path"
        execute_cmd "mkdir -p '$full_path'"
    done
}

# Initialize CA files
init_ca_files() {
    local ca_num="$1"
    local ca_dir="$WORK_DIR/erldist/ssl/ca${ca_num}"
    
    log_debug "Initializing CA${ca_num} files"
    
    # Create index.txt
    execute_cmd "touch '$ca_dir/index.txt'"
    
    # Create index.txt.attr
    execute_cmd "echo 'unique_subject = no' > '$ca_dir/index.txt.attr'"
    
    # Create serial.txt
    execute_cmd "echo '$CA_SERIAL_START_INDEX' > '$ca_dir/serial.txt'"
    
    # Create crlnumber.txt for CRL generation
    execute_cmd "echo '01' > '$ca_dir/crlnumber.txt'"
    
    # Create random file
    execute_cmd "$OPENSSL rand -out '$ca_dir/private/.rand' 256"
}

# Generate private key
generate_private_key() {
    local key_file="$1"
    
    # Only generate if key doesn't already exist
    if [[ ! -f "$key_file" ]]; then
        log_debug "Generating private key: $key_file"
        execute_cmd "$OPENSSL genrsa -out '$key_file' 2048"
    else
        log_debug "Private key already exists: $key_file"
    fi
}

# Generate Certificate Signing Request
generate_csr() {
    local key_file="$1"
    local csr_file="$2"
    local subject="$3"
    local config_file="$4"
    
    log_debug "Generating CSR: $csr_file with subject: $subject"
    execute_cmd "$OPENSSL req -config '$config_file' -new -key '$key_file' -out '$csr_file' -subj '$subject'"
}

# Generate CA certificate (self-signed)
generate_ca_cert() {
    local ca_num="$1"
    local ca_dir="$WORK_DIR/erldist/ssl/ca${ca_num}"
    local config_file="$ca_dir/openssl.conf"
    local key_file="$ca_dir/key.pem"
    local csr_file="$ca_dir/csr.pem"
    local cert_file="$ca_dir/cert.pem"
    local end_date="$(get_end_date)"
    
    log_debug "Generating CA${ca_num} certificate"
    
    # Generate CA private key
    generate_private_key "$key_file"
    
    # Generate CA CSR
    generate_csr "$key_file" "$csr_file" "/CN=ca${ca_num}" "$config_file"
    
    # Generate self-signed CA certificate
    execute_cmd "$OPENSSL ca -batch -config '$config_file' -selfsign -keyfile '$key_file' -in '$csr_file' -enddate '$end_date' -out '$cert_file'"
}

# Generate server certificate
generate_server_cert() {
    local ca_num="$1"
    local node="$2"
    local ca_dir="$WORK_DIR/erldist/ssl/ca${ca_num}"
    local node_dir="$WORK_DIR/erldist/ssl/ncs${node}"
    local config_file="$ca_dir/openssl.conf"
    local end_date="$(get_end_date)"
    
    # Server key and CSR
    local server_key="$node_dir/server_key.pem"
    local server_csr="$ca_dir/csr/ncs${node}_csr.pem"
    local server_cert="$ca_dir/certs/ncs${node}_cert.pem"
    
    # HA cluster key and CSR with 1-based indexing for certificate names
    local ha_node_id=$((node + 1))
    local ha_csr="$ca_dir/csr/ha${ha_node_id}_csr.pem"
    local ha_cert="$ca_dir/certs/ha${ha_node_id}_cert.pem"
    
    log_debug "Generating server certificate for node ${node} with CA${ca_num}"
    
    # Generate server private key
    generate_private_key "$server_key"
    
    # Generate server CSR for localhost
    generate_csr "$server_key" "$server_csr" "/CN=localhost.localdomain" "$config_file"
    
    # Generate HA cluster CSR with 1-based indexing for hostnames
    local ha_node_id=$((node + 1))
    generate_csr "$server_key" "$ha_csr" "/CN=ha${ha_node_id}.ha-cluster" "$config_file"
    
    # Generate server certificate with SAN for localhost
    log_debug "Signing server certificate with subjectAltName"
    execute_cmd "$OPENSSL ca -config '$config_file' -batch -enddate '$end_date' -out '$server_cert' -in '$server_csr' -extfile <(printf 'subjectAltName=DNS:localhost.localdomain,IP:127.0.0.1')"
    
    # Generate HA cluster certificate with proper SubjectAltName
    local ha_hostname="ha${ha_node_id}.ha-cluster"
    local ha_ip="192.168.${ha_node_id}.1"
    log_debug "Signing HA certificate with subjectAltName for ${ha_hostname} (${ha_ip})"
    execute_cmd "$OPENSSL ca -config '$config_file' -batch -enddate '$end_date' -out '$ha_cert' -in '$ha_csr' -extfile <(printf 'subjectAltName=DNS:${ha_hostname},IP:${ha_ip}')"
}

# Generate CRL (Certificate Revocation List)
generate_crl() {
    local ca_num="$1"
    local ca_dir="$WORK_DIR/erldist/ssl/ca${ca_num}"
    local config_file="$ca_dir/openssl.conf"
    local crl_file="$ca_dir/crl.pem"
    
    log_debug "Generating CRL for CA${ca_num}"
    execute_cmd "$OPENSSL ca -gencrl -config '$config_file' -out '$crl_file'"
}

# Copy CRL to hash-named files
setup_crl_hashes() {
    log_info "Setting up CRL hash links..."
    
    # Generate hash-named CRL files (names from original Makefile)
    local ca1_crl="$WORK_DIR/erldist/ssl/crl/90a3ab2b.r0"
    local ca2_crl="$WORK_DIR/erldist/ssl/crl/ac53703c.r0"
    
    if [[ -f "$WORK_DIR/erldist/ssl/ca1/crl.pem" ]]; then
        execute_cmd "cp '$WORK_DIR/erldist/ssl/ca1/crl.pem' '$ca1_crl'"
    fi
    
    if [[ -f "$WORK_DIR/erldist/ssl/ca2/crl.pem" ]]; then
        execute_cmd "cp '$WORK_DIR/erldist/ssl/ca2/crl.pem' '$ca2_crl'"
    fi
}

# Create combined CA certificate
create_combined_ca_cert() {
    log_info "Creating combined CA certificate..."
    
    local ca12_dir="$WORK_DIR/erldist/ssl/ca12"
    local combined_cert="$ca12_dir/cert.pem"
    
    execute_cmd "mkdir -p '$ca12_dir'"
    
    if [[ -f "$WORK_DIR/erldist/ssl/ca1/cert.pem" ]] && [[ -f "$WORK_DIR/erldist/ssl/ca2/cert.pem" ]]; then
        execute_cmd "cat '$WORK_DIR/erldist/ssl/ca1/cert.pem' '$WORK_DIR/erldist/ssl/ca2/cert.pem' > '$combined_cert'"
    fi
}

# Create symbolic link for ca directory
create_ca_symlink() {
    log_debug "Creating CA symbolic link"
    local ca_link="$WORK_DIR/erldist/ssl/ca"
    local ca1_dir="$WORK_DIR/erldist/ssl/ca1"
    
    if [[ -d "$ca1_dir" ]]; then
        execute_cmd "ln -sf ca1 '$ca_link'"
    fi
}

# Revoke a certificate
revoke_certificate() {
    local node="$1"
    local ca_num="${2:-1}"  # Default to CA1
    
    local config_file="$WORK_DIR/erldist/ssl/ca${ca_num}/openssl.conf"
    local cert_file="$WORK_DIR/erldist/ssl/ca${ca_num}/certs/ncs${node}_cert.pem"
    
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate not found: $cert_file"
        return 1
    fi
    
    log_info "Revoking certificate for node ${node}"
    execute_cmd "$OPENSSL ca -config '$config_file' -revoke '$cert_file'"
    
    # Regenerate CRL after revocation
    generate_crl "$ca_num"
    setup_crl_hashes
}

# Clean up all SSL certificates
cleanup_ssl() {
    log_info "Cleaning up SSL certificates..."
    execute_cmd "rm -rf '$WORK_DIR/erldist'"
}

# Main setup function
setup_ssl_certificates() {
    local end_date="$(get_end_date)"
    
    log_info "Setting up SSL certificates for NSO RAFT cluster"
    log_info "Certificate validity until: $end_date"
    log_info "Nodes: $NODES"
    log_info "CAs: $CAS"
    
    # Create default OpenSSL template if needed
    create_default_openssl_template
    
    # Create directory structure
    create_directories
    
    # Setup each CA
    for ca in $CAS; do
        if [[ "$ca" == "12" ]]; then
            continue  # Skip CA12, it's a combined certificate
        fi
        
        log_info "Setting up CA${ca}..."
        
        # Initialize CA files
        init_ca_files "$ca"
        
        # Create OpenSSL config
        create_openssl_conf "$ca"
        
        # Generate CA certificate
        generate_ca_cert "$ca"
        
        # Generate server certificates for each node
        for node in $NODES; do
            generate_server_cert "$ca" "$node"
        done
        
        # Generate CRL
        generate_crl "$ca"
    done
    
    # Setup CRL hashes
    setup_crl_hashes
    
    # Create combined CA certificate
    create_combined_ca_cert
    
    # Create CA symlink
    create_ca_symlink
    
    log_info "SSL certificate setup completed successfully!"
    log_info "Certificates are valid until: $end_date"
}

# Show usage information
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION - SSL Certificate Setup for NSO RAFT Cluster

USAGE:
    $SCRIPT_NAME [command] [options]

COMMANDS:
    setup                   Setup SSL certificates (default)
    revoke <node> [ca]      Revoke certificate for specific node
    cleanup                 Remove all SSL certificates
    help                    Show this help message

OPTIONS:
    --nodes <list>          Space-separated list of node numbers (default: "0 1 2 3 4 5")
    --cas <list>            Space-separated list of CA numbers (default: "1 2 12")
    --work-dir <dir>        Working directory (default: current directory)
    --openssl <path>        Path to openssl binary (default: openssl)
    --config-template <file> OpenSSL config template (default: ./openssl.conf.in)
    --verbose               Verbose output
    --dry-run               Show commands without executing
    -h, --help              Show help

EXAMPLES:
    # Setup SSL certificates with defaults
    $SCRIPT_NAME setup

    # Setup with custom nodes
    $SCRIPT_NAME setup --nodes "1 2 3"

    # Setup with verbose output
    $SCRIPT_NAME setup --verbose

    # Revoke certificate for node 2
    $SCRIPT_NAME revoke 2

    # Cleanup all certificates
    $SCRIPT_NAME cleanup

    # Dry run to see what would be executed
    $SCRIPT_NAME setup --dry-run

ENVIRONMENT VARIABLES:
    NODES                   Override default nodes
    CAS                     Override default CAs
    OPENSSL                 Override openssl binary path
    OPENSSL_CONF_IN         Override config template path
    WORK_DIR                Override working directory
    VERBOSE                 Enable verbose output (true/false)
    DRY_RUN                 Enable dry run mode (true/false)

EOF
}

# Parse command line arguments
parse_args() {
    local command="setup"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            setup|revoke|cleanup|help)
                command="$1"
                shift
                ;;
            --nodes)
                shift
                NODES="$1"
                shift
                ;;
            --cas)
                shift
                CAS="$1"
                shift
                ;;
            --work-dir)
                shift
                WORK_DIR="$(cd "$1" && pwd)"  # Convert to absolute path
                shift
                ;;
            --openssl)
                shift
                OPENSSL="$1"
                shift
                ;;
            --config-template)
                shift
                OPENSSL_CONF_IN="$1"
                shift
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                if [[ "$command" == "revoke" ]]; then
                    # Arguments for revoke command
                    REVOKE_NODE="$1"
                    shift
                    if [[ $# -gt 0 ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                        REVOKE_CA="$1"
                        shift
                    fi
                else
                    log_error "Unknown option: $1"
                    show_usage
                    exit 1
                fi
                ;;
        esac
    done
    
    # Execute command
    case "$command" in
        setup)
            setup_ssl_certificates
            ;;
        revoke)
            if [[ -z "${REVOKE_NODE:-}" ]]; then
                log_error "Node number required for revoke command"
                show_usage
                exit 1
            fi
            revoke_certificate "$REVOKE_NODE" "${REVOKE_CA:-1}"
            ;;
        cleanup)
            cleanup_ssl
            ;;
        help)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Main entry point
main() {
    # Check if openssl is available
    if ! command -v "$OPENSSL" >/dev/null 2>&1; then
        log_error "OpenSSL not found: $OPENSSL"
        log_error "Please install OpenSSL or specify correct path with --openssl"
        exit 1
    fi
    
    # Parse arguments and execute
    parse_args "$@"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
