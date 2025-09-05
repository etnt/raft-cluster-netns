# RAFT Cluster L3 BGP Network Design

## Current Status

**ISSUE IDENTIFIED**: The script 5. **Parse L3BGP Node Configuration**
   ```7. **Manager Node Implement8. **Test wi9. **Network Connectivity Validation**
   ```bash
 6. **Parse L3BGP Node Configuration**
   ```8. **Manager Node Implement9. **Test wi10. **Network Connectivity Validation**
   ```bash
   validate_l3bgp_network() {
       log_info "Validating L3BGP network connectivity..."
       
       for ((i=1; i<=NODES; i++)); do
           local node_ip="$(get_node_ip "$i")"
           local node_hostname="$(get_node_hostname "$i")"
           
           test_node_connectivity "$i" "$node_ip"
           test_hostname_resolution "$i" "$node_hostname"
       done
       
       if [[ "$MANAGER_ENABLED" == "true" ]]; then
           test_manager_connectivity
       fi
   }
   ```

## Prerequisites for L3BGP Setup

### Required Software Dependencies

#### 1. GoBGP Daemon (gobgpd)
**Purpose**: BGP routing daemon for L3BGP functionality
**Installation**:
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install gobgp

# CentOS/RHEL/Fedora  
sudo yum install gobgp
# OR
sudo dnf install gobgp

# From source (if package not available)
go install github.com/osrg/gobgp/v3/cmd/gobgpd@latest
go install github.com/osrg/gobgp/v3/cmd/gobgp@latest
```

**Verification**:
```bash
# Check installation
gobgpd --version
gobgp --version

# Expected output
# gobgpd version X.X.X (commit: xxxxx)
```

#### 2. Git (for tailf-hcc clone)
**Purpose**: Clone NSO package repository
**Installation**:
```bash
# Usually pre-installed on development systems
sudo apt-get install git    # Ubuntu/Debian
sudo yum install git        # CentOS/RHEL
```

#### 3. Prerequisite Check Implementation
```bash
check_l3bgp_prerequisites() {
    log_info "Checking L3BGP prerequisites..."
    local missing_deps=()
    
    # Check for gobgpd
    if ! command -v gobgpd >/dev/null 2>&1; then
        log_error "❌ gobgpd not found in PATH"
        missing_deps+=("gobgp")
    else
        local gobgp_version=$(gobgpd --version 2>/dev/null | head -1)
        log_info "✅ Found gobgpd: $gobgp_version"
    fi
    
    # Check for git
    if ! command -v git >/dev/null 2>&1; then
        log_error "❌ git not found in PATH"
        missing_deps+=("git")
    else
        log_info "✅ Found git: $(git --version)"
    fi
    
    # Abort if dependencies missing
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies for L3BGP setup:"
        for dep in "${missing_deps[@]}"; do
            log_error "  - $dep"
        done
        log_error ""
        log_error "Installation commands:"
        log_error "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
        log_error "  CentOS/RHEL:   sudo yum install ${missing_deps[*]}"
        log_error "  GoBGP source:  https://github.com/osrg/gobgp"
        exit 1
    fi
    
    log_info "✅ All L3BGP prerequisites satisfied"
}
```-cluster.conf`**
   - Verify SSL certificates work with custom hostnames
   - Test node communication with custom IPs
   - Validate RAFT cluster formation with L3BGP topology
   - Compare logs between simple and L3BGP setups

10. **Network Connectivity Validation**
   ```bash
   setup_manager_node_if_enabled() {
       if [[ "$MANAGER_ENABLED" == "true" ]]; then
           log_info "Creating manager node at $MANAGER_IP"
           create_manager_namespace
           connect_manager_to_docker0
           configure_manager_network
       fi
   }
   ```

### Phase 3: Testing Current Configuration 🧪 CRITICAL

9. **Test with Existing `.raft-cluster.conf`**3bgp_config() {
       for ((i=1; i<=NODES; i++)); do
           eval "NODE_${i}_IP=\${node_${i}_ip:-192.168.${i}.1}"
           eval "NODE_${i}_SUBNET=\${node_${i}_subnet:-192.168.${i}.0/24}"
           eval "NODE_${i}_HOSTNAME=\${node_${i}_hostname:-${PREFIX}${i}.ha-cluster}"
           eval "NODE_${i}_ASN=\${node_${i}_asn:-}"
       done
       
       # Parse manager config
       MANAGER_IP="${manager_ip:-172.17.0.2}"
       MANAGER_ENABLED="${manager_enabled:-false}"
   }
   ```

7. **Custom Hostname and IP Support**
   - Replace hardcoded `${NETWORK_PREFIX}.${i}.1` with `${NODE_${i}_IP}`
   - Replace hardcoded `${PREFIX}${i}.ha-cluster` with `${NODE_${i}_HOSTNAME}`
   - Update `create_hosts_file()` for custom hostnames
   - Update `create_namespaces()` for custom IPs

8. **Manager Node Implementation**p_network() {
       log_info "Validating L3BGP network connectivity..."
       
       for ((i=1; i<=NODES; i++)); do
           local node_ip="$(get_node_ip "$i")"
           local node_hostname="$(get_node_hostname "$i")"
           
           test_node_connectivity "$i" "$node_ip"
           test_hostname_resolution "$i" "$node_hostname"
       done
       
       if [[ "$MANAGER_ENABLED" == "true" ]]; then
           test_manager_connectivity
       fi
   }
   ```

## Script Architecture Considerations

### Current State Analysis

**Script Size**: 2,417 lines with 60+ functions
**Complexity**: The monolithic `raft-cluster-netns.sh` has grown significantly and now handles:
- Configuration management 
- Network setup (simple & L3BGP)
- SSL certificate management
- NSO cluster orchestration
- Partition simulation
- Status monitoring
- Interactive configuration generation

### Proposed Modular Architecture 🏗️

Breaking the script into focused modules would improve:
- **Maintainability**: Easier to modify specific functionality
- **Testing**: Independent testing of network vs NSO components
- **Readability**: Smaller, focused files
- **Collaboration**: Multiple developers can work on different components
- **Reusability**: Network setup could be used independently

#### Suggested Module Structure

```
raft-cluster-netns.sh              # Main orchestrator (CLI + coordination)
├── lib/
│   ├── common.sh                   # Shared utilities (logging, execute_cmd, etc.)
│   ├── config.sh                   # Configuration loading/saving/generation
│   ├── network-simple.sh           # Simple network setup functions
│   ├── network-l3bgp.sh            # L3BGP network setup functions  
│   ├── ssl.sh                      # SSL certificate management
│   ├── nso.sh                      # NSO cluster setup and management
│   └── partition.sh                # Network partition simulation
├── templates/                      # Configuration templates
│   ├── simple-config.template
│   └── l3bgp-config.template
└── docs/                          # Documentation
    └── raft-cluster-l3bgp-design.md
```

#### Main Script Responsibilities (Reduced)
```bash
#!/bin/bash
# raft-cluster-netns.sh - Main orchestrator

# Source modules
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/config.sh"
source "$(dirname "$0")/lib/ssl.sh"
source "$(dirname "$0")/lib/nso.sh"
source "$(dirname "$0")/lib/partition.sh"

# Conditional network module loading
case "$NETWORK_TYPE" in
    "l3bgp")
        source "$(dirname "$0")/lib/network-l3bgp.sh"
        ;;
    *)
        source "$(dirname "$0")/lib/network-simple.sh"
        ;;
esac

main() {
    parse_args "$@"
    # Route to appropriate module functions
}
```

#### Module Examples

**lib/network-l3bgp.sh**:
```bash
#!/bin/bash
# L3BGP network setup module

check_l3bgp_prerequisites() { ... }
setup_l3bgp_network() { ... }
setup_l3bgp_nso_packages() { ... }
parse_l3bgp_config() { ... }
# ... other L3BGP functions
```

**lib/network-simple.sh**:
```bash
#!/bin/bash
# Simple network setup module

setup_simple_network() { ... }
create_veth_pairs() { ... }
create_namespaces() { ... }
setup_bridge() { ... }
# ... other simple network functions
```

### Implementation Strategy

#### Phase 1: Extract Common Utilities ⚡
1. **lib/common.sh**: Move logging, execute_cmd, validation functions
2. **Minimal changes**: Main script sources common.sh
3. **Test compatibility**: Ensure no functionality breaks

#### Phase 2: Extract Network Modules 🎯
1. **lib/network-simple.sh**: Extract existing network functions
2. **lib/network-l3bgp.sh**: Add new L3BGP functions here
3. **Conditional loading**: Main script chooses network module based on config

#### Phase 3: Extract Domain-Specific Modules 📋
1. **lib/ssl.sh**: SSL certificate management
2. **lib/nso.sh**: NSO cluster operations
3. **lib/partition.sh**: Network partition simulation
4. **lib/config.sh**: Configuration management

#### Phase 4: Template Extraction 🔄
1. **templates/**: Move configuration generation to templates
2. **Clean separation**: Logic vs data

### Benefits of Modular Approach

#### For L3BGP Implementation
- ✅ **Clean implementation**: L3BGP functions in dedicated module
- ✅ **No simple network impact**: Existing functionality untouched
- ✅ **Easier testing**: Test L3BGP module independently
- ✅ **Focused development**: Work on L3BGP without navigating 2400+ lines

#### For Maintenance
- ✅ **Easier debugging**: Smaller files to navigate
- ✅ **Faster development**: Less cognitive load per file
- ✅ **Better testing**: Unit test individual modules
- ✅ **Cleaner git history**: Changes isolated to relevant modules

#### For Users
- ✅ **Same interface**: Main script behavior unchanged
- ✅ **Better error messages**: Module-specific error context
- ✅ **Faster startup**: Only load needed modules

### Migration Considerations

#### Backward Compatibility ✅
- Main script interface remains identical
- All existing commands continue working
- Configuration files unchanged
- Gradual migration possible

#### Development Workflow 🔄
- Could implement L3BGP in new module while keeping simple network in main script
- Test thoroughly before extracting simple network
- Refactor incrementally to minimize risk

### Recommendation

**For L3BGP Implementation**: Consider starting with a **hybrid approach**:

1. **Immediate**: Implement L3BGP functions in main script (faster to deliver)
2. **Phase 2**: Extract to `lib/network-l3bgp.sh` once L3BGP is working
3. **Phase 3**: Extract other modules gradually

This balances **delivery speed** vs **long-term maintainability**.

**Alternative**: If team has bandwidth, implement L3BGP directly in modular structure - it would provide a cleaner foundation for future development.

## NSO Package Requirements for L3BGP

### tailf-hcc Package Integration

The L3BGP setup requires the **tailf-hcc** NSO package, which provides crucial functionality for BGP VIP announcements:

#### Package Purpose
- **VIP Management**: Announces the local Virtual IP (VIP) to the BGP server when it becomes active
- **Failover Coordination**: Withdraws BGP announcements when the local node is no longer the RAFT leader
- **Service Discovery**: Enables external clients to automatically route to the current RAFT leader

#### Implementation Steps
```bash
# 1. Clone tailf-hcc repository
TAILF_HCC_REPO="ssh://git@stash.tail-f.com/pkg/tailf-hcc.git"
HCC_DIR="${WORK_DIR}/tailf-hcc"

if [[ ! -d "$HCC_DIR" ]]; then
    git clone "$TAILF_HCC_REPO" "$HCC_DIR"
fi

# 2. Create symbolic links in each NSO node
for ((i=1; i<=NODES; i++)); do
    PACKAGES_DIR="${WORK_DIR}/ncs-run${i}/packages"
    ln -sf "$HCC_DIR" "$PACKAGES_DIR/tailf-hcc"
done
```

#### Directory Structure After Setup
```
work_dir/
├── tailf-hcc/                 # Cloned repository
│   ├── src/
│   ├── python/
│   └── package-meta-data.xml
├── ncs-run1/packages/
│   └── tailf-hcc -> ../../tailf-hcc  # Symbolic link
├── ncs-run2/packages/  
│   └── tailf-hcc -> ../../tailf-hcc  # Symbolic link
└── ncs-run3/packages/
    └── tailf-hcc -> ../../tailf-hcc  # Symbolic link
```

#### Integration with L3BGP Setup
The package setup must occur **before** NSO node initialization to ensure:
1. ✅ Package is available during NSO startup
2. ✅ BGP announcements begin immediately when RAFT leadership is established  
3. ✅ Proper cleanup of BGP routes during failover scenarios-cluster.conf`**
   - Verify SSL certificates work with custom hostnames
   - Test node communication with custom IPs
   - Validate RAFT cluster formation with L3BGP topology
   - Compare logs between simple and L3BGP setups

9. **Network Connectivity Validation**
   ```bash
   setup_manager_node_if_enabled() {
       if [[ "$MANAGER_ENABLED" == "true" ]]; then
           log_info "Creating manager node at $MANAGER_IP"
           create_manager_namespace
           connect_manager_to_docker0
           configure_manager_network
       fi
   }
   ```

### Phase 3: Testing Current Configuration 🧪 CRITICAL

8. **Test with Existing `.raft-cluster.conf`**3bgp_config() {
       for ((i=1; i<=NODES; i++)); do
           eval "NODE_${i}_IP=\${node_${i}_ip:-192.168.${i}.1}"
           eval "NODE_${i}_SUBNET=\${node_${i}_subnet:-192.168.${i}.0/24}"
           eval "NODE_${i}_HOSTNAME=\${node_${i}_hostname:-${PREFIX}${i}.ha-cluster}"
           eval "NODE_${i}_ASN=\${node_${i}_asn:-}"
       done
       
       # Parse manager config
       MANAGER_IP="${manager_ip:-172.17.0.2}"
       MANAGER_ENABLED="${manager_enabled:-false}"
   }
   ```

6. **Custom Hostname and IP Support**
   - Replace hardcoded `${NETWORK_PREFIX}.${i}.1` with `${NODE_${i}_IP}`
   - Replace hardcoded `${PREFIX}${i}.ha-cluster` with `${NODE_${i}_HOSTNAME}`
   - Update `create_hosts_file()` for custom hostnames
   - Update `create_namespaces()` for custom IPs

7. **Manager Node Implementation**guration generation capability but **does not implement L3BGP network topology**. 

### What Works
- ✅ SSL certificate generation with configurable prefixes
- ✅ L3BGP configuration file generation (`generate_l3bgp_config`)
- ✅ Configuration file loading and parsing

### What's Missing
- ❌ `network_type` parsing in `load_config_file()` - **ADDED**
- ❌ L3BGP network setup implementation - **NEEDS IMPLEMENTATION**
- ❌ Manager node creation - **NEEDS IMPLEMENTATION**
- ❌ Custom IP/hostname support - **NEEDS IMPLEMENTATION**

### Current vs. Configured Behavior

**Current (Simple Network)**:
- Node IPs: `192.168.1.1`, `192.168.2.1`, `192.168.3.1`
- Hostnames: `l3bgp1.ha-cluster`, `l3bgp2.ha-cluster`, `l3bgp3.ha-cluster`
- Topology: Flat bridge network

**Configured (L3BGP Network)**:
- Node IPs: `192.168.30.97`, `192.168.31.98`, `192.168.32.99`
- Hostnames: `berlin.cluster.local`, `london.cluster.local`, `paris.cluster.local`
- Manager: `172.17.0.2` on bridge
- Topology: BGP peering with ASNs 64511, 64512, 64513

## Implementation Plan

### Phase 1: Core L3BGP Support ⚡ IMMEDIATE

1. **Enhanced Configuration Loading** ✅ COMPLETED
   - Added `network_type` parsing to `load_config_file()`
   - Added `manager_enabled`, `manager_ip` parsing
   - Added wildcard `node_*` configuration parsing

2. **L3BGP Prerequisites Check** 📋 NEXT
   ```bash
   check_l3bgp_prerequisites() {
       log_info "Checking L3BGP prerequisites..."
       
       # Check for gobgpd binary
       if ! command -v gobgpd >/dev/null 2>&1; then
           log_error "gobgpd is required for L3BGP setup but not found in PATH"
           log_error "Please install GoBGP: https://github.com/osrg/gobgp"
           log_error "On Ubuntu/Debian: apt-get install gobgp"
           log_error "On CentOS/RHEL: yum install gobgp" 
           exit 1
       fi
       
       # Check gobgpd version
       local gobgp_version=$(gobgpd --version 2>/dev/null | head -1)
       log_info "Found gobgpd: $gobgp_version"
       
       # Check for git (needed for tailf-hcc clone)
       if ! command -v git >/dev/null 2>&1; then
           log_error "git is required for L3BGP setup but not found in PATH"
           exit 1
       fi
   }
   ```

3. **Network Type Detection** 🔄 IN PROGRESS
   ```bash
   # Add to setup_network()
   if [[ "$NETWORK_TYPE" == "l3bgp" ]]; then
       check_l3bgp_prerequisites
       setup_l3bgp_network
   else
       setup_simple_network  # Current implementation
   fi
   ```

4. **L3BGP Network Setup Function** 📋 NEXT
   ```bash
   setup_l3bgp_network() {
       log_info "Setting up L3 BGP network topology..."
       
       parse_l3bgp_config
       setup_l3bgp_nso_packages
       setup_manager_node_if_enabled
       setup_l3bgp_nodes
       setup_l3bgp_routing
       validate_l3bgp_network
   }
   ```

5. **L3BGP NSO Package Setup** 📋 NEXT
   ```bash
   setup_l3bgp_nso_packages() {
       log_info "Setting up L3BGP NSO packages..."
       
       # Clone tailf-hcc package if not exists
       local hcc_dir="${WORK_DIR}/tailf-hcc"
       if [[ ! -d "$hcc_dir" ]]; then
           log_info "Cloning tailf-hcc package..."
           execute_cmd "git clone ssh://git@stash.tail-f.com/pkg/tailf-hcc.git $hcc_dir"
       fi
       
       # Create package links in each NSO node
       for ((i=1; i<=NODES; i++)); do
           local packages_dir="${WORK_DIR}/ncs-run${i}/packages"
           local hcc_link="${packages_dir}/tailf-hcc"
           
           if [[ ! -L "$hcc_link" ]]; then
               log_info "Creating tailf-hcc package link for node $i"
               execute_cmd "ln -sf $hcc_dir $hcc_link"
           fi
       done
   }
   ```

### Phase 2: Node-Specific Configuration 📋 NEXT

6. **Parse L3BGP Node Configuration**
   ```bash
   parse_l3bgp_config() {
       for ((i=1; i<=NODES; i++)); do
           eval "NODE_${i}_IP=\${node_${i}_ip:-192.168.${i}.1}"
           eval "NODE_${i}_SUBNET=\${node_${i}_subnet:-192.168.${i}.0/24}"
           eval "NODE_${i}_HOSTNAME=\${node_${i}_hostname:-${PREFIX}${i}.ha-cluster}"
           eval "NODE_${i}_ASN=\${node_${i}_asn:-}"
       done
       
       # Parse manager config
       MANAGER_IP="${manager_ip:-172.17.0.2}"
       MANAGER_ENABLED="${manager_enabled:-false}"
   }
   ```

5. **Custom Hostname and IP Support**
   - Replace hardcoded `${NETWORK_PREFIX}.${i}.1` with `${NODE_${i}_IP}`
   - Replace hardcoded `${PREFIX}${i}.ha-cluster` with `${NODE_${i}_HOSTNAME}`
   - Update `create_hosts_file()` for custom hostnames
   - Update `create_namespaces()` for custom IPs

6. **Manager Node Implementation**
   ```bash
   setup_manager_node_if_enabled() {
       if [[ "$MANAGER_ENABLED" == "true" ]]; then
           log_info "Creating manager node at $MANAGER_IP"
           create_manager_namespace
           connect_manager_to_docker0
           configure_manager_network
       fi
   }
   ```

### Phase 3: Testing Current Configuration 🧪 CRITICAL

7. **Test with Existing `.raft-cluster.conf`**
   - Verify SSL certificates work with custom hostnames
   - Test node communication with custom IPs
   - Validate RAFT cluster formation with L3BGP topology
   - Compare logs between simple and L3BGP setups

8. **Network Connectivity Validation**
   ```bash
   validate_l3bgp_network() {
       log_info "Validating L3BGP network connectivity..."
       
       for ((i=1; i<=NODES; i++)); do
           local node_ip="$(get_node_ip "$i")"
           local node_hostname="$(get_node_hostname "$i")"
           
           test_node_connectivity "$i" "$node_ip"
           test_hostname_resolution "$i" "$node_hostname"
       done
       
       if [[ "$MANAGER_ENABLED" == "true" ]]; then
           test_manager_connectivity
       fi
   }
   ```

## Immediate Implementation Steps

### Step 1: Add Network Type Detection ⚡

**File**: `raft-cluster-netns.sh` around line 1457 (`setup_network()`)

```bash
# Setup complete network infrastructure  
setup_network() {
    log_info "Setting up virtual network infrastructure..."
    
    check_prerequisites
    fix_dockers_mess
    
    # Detect network type and branch accordingly
    if [[ "$NETWORK_TYPE" == "l3bgp" ]]; then
        log_info "Using L3BGP network topology"
        check_l3bgp_prerequisites  # Check gobgpd and dependencies
        setup_l3bgp_network
    else
        log_info "Using simple network topology"
        setup_simple_network
    fi
    
    log_info "Network setup completed successfully"
}

# Original simple network setup (renamed)
setup_simple_network() {
    create_hosts_files
    create_veth_pairs  
    create_namespaces
    setup_bridge
    validate_network
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        test_connectivity
    fi
}
```

### Step 2: Implement Basic L3BGP Network ⚡

**New function**: `setup_l3bgp_network()`

```bash
# Setup L3BGP network topology
setup_l3bgp_network() {
    log_info "Setting up L3BGP network topology..."
    
    # Parse L3BGP-specific configuration
    parse_l3bgp_config
    
    # Setup NSO packages for L3BGP
    setup_l3bgp_nso_packages
    
    # Create L3BGP network components
    create_l3bgp_hosts_files
    create_l3bgp_veth_pairs
    create_l3bgp_namespaces
    setup_l3bgp_bridges
    
    # Setup manager node if enabled
    if [[ "$MANAGER_ENABLED" == "true" ]]; then
        setup_manager_node
    fi
    
    # Validate L3BGP network
    validate_l3bgp_network
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        test_l3bgp_connectivity
    fi
    
    log_info "L3BGP network setup completed"
}
```

### Step 3: Node Configuration Parsing ⚡

**New function**: `parse_l3bgp_config()`

```bash
# Parse L3BGP node configuration from loaded config
parse_l3bgp_config() {
    log_info "Parsing L3BGP configuration..."
    
    # Parse node-specific settings
    for ((i=1; i<=NODES; i++)); do
        local ip_var="node_${i}_ip"
        local hostname_var="node_${i}_hostname" 
        local subnet_var="node_${i}_subnet"
        local asn_var="node_${i}_asn"
        
        eval "NODE_${i}_IP=\${${ip_var}:-192.168.${i}.1}"
        eval "NODE_${i}_HOSTNAME=\${${hostname_var}:-${PREFIX}${i}.ha-cluster}"
        eval "NODE_${i}_SUBNET=\${${subnet_var}:-192.168.${i}.0/24}"
        eval "NODE_${i}_ASN=\${${asn_var}:-}"
        
        log_debug "Node $i: IP=$(eval echo \$NODE_${i}_IP), Hostname=$(eval echo \$NODE_${i}_HOSTNAME)"
    done
    
    # Parse manager configuration  
    MANAGER_IP="${manager_ip:-172.17.0.2}"
    MANAGER_ENABLED="${manager_enabled:-false}"
    
    log_debug "Manager: Enabled=$MANAGER_ENABLED, IP=$MANAGER_IP"
}
```

## Configuration Examples

### Current Working Example (Berlin/London/Paris)

```
    -----------------------   default bridge  -------------------
                                    | .1
                                    |
                              172.17.0.0/16
                                    |
                                    | .2
                          +------------------+
                          | manager          |
                          | ID: 172.17.0.2   |
                          | AS: 64514        |
                          +------------------+
                      .2 /         | .2       \ .2
                        /          |           \
            192.168.30.0/24  192.168.31.0/24   192.168.32.0/24
                      /            |             \
                  .97 /             | .98          \ .99
    +-------------------+ +-------------------+ +-------------------+
    | berlin            | | london            | | paris             |
    | ID: 192.168.30.97 | | ID: 192.168.31.98 | | ID: 192.168.32.99 |
    | AS: 64513         | | AS: 64512         | | AS: 64511         |
    +-------------------+ +-------------------+ +-------------------+
```

From the existing `.raft-cluster.conf`:

```bash
# RAFT Cluster Configuration - L3BGP Topology
network_type=l3bgp
nodes=3
prefix=l3bgp
cluster_name=berlin-london-paris

# Manager node
manager_enabled=true  
manager_ip=172.17.0.2

# Berlin node (Node 1)
node_1_ip=192.168.30.97
node_1_subnet=192.168.30.0/24
node_1_hostname=berlin.cluster.local
node_1_asn=64511

# London node (Node 2)  
node_2_ip=192.168.31.98
node_2_subnet=192.168.31.0/24
node_2_hostname=london.cluster.local
node_2_asn=64512

# Paris node (Node 3)
node_3_ip=192.168.32.99
node_3_subnet=192.168.32.0/24  
node_3_hostname=paris.cluster.local
node_3_asn=64513

# BGP peering configuration
node_1_bgp_peers=manager,2,3
node_2_bgp_peers=manager,1,3  
node_3_bgp_peers=manager,1,2
```

**Expected Result**:
- ✅ SSL certificates: `berlin.cluster.local`, `london.cluster.local`, `paris.cluster.local`
- ✅ Node IPs: `192.168.30.97`, `192.168.31.98`, `192.168.32.99`
- ✅ Manager: `172.17.0.2` accessible from all nodes
- ✅ RAFT cluster: `ncsd1@berlin.cluster.local`, `ncsd2@london.cluster.local`, `ncsd3@paris.cluster.local`

### Simple 3-Node BGP Cluster

```bash
# Basic BGP setup with default subnets
network_type=l3bgp
nodes=3
bgp_enabled=true

# Manager for route reflection
manager_enabled=true
manager_asn=64500

# Nodes with different ASNs
node_1_asn=64501
node_2_asn=64502  
node_3_asn=64503
```

### Complex Multi-Site Topology

```bash
# Geographic distribution simulation
network_type=l3bgp
nodes=3

# Manager (simulating network switch)
manager_enabled=true
manager_name=ix
manager_asn=64500
manager_ip=10.0.0.1
manager_subnet=10.0.0.0/24

# Site-specific configurations
node_1_name=us-east
node_1_ip=192.168.10.1
node_1_subnet=192.168.10.0/24
node_1_asn=64510
node_1_hostname=us-east.example.com

node_2_name=eu-west  
node_2_ip=192.168.20.1
node_2_subnet=192.168.20.0/24
node_2_asn=64520
node_2_hostname=eu-west.example.com

node_3_name=ap-south
node_3_ip=192.168.30.1
node_3_subnet=192.168.30.0/24
node_3_asn=64530
node_3_hostname=ap-south.example.com
```

## Implementation Priority

### 🔥 **CRITICAL PATH** - Minimal L3BGP Support

**Goal**: Make existing `.raft-cluster.conf` work correctly

1. **Network Type Detection** - Branch between simple/L3BGP setup
2. **L3BGP Prerequisites Check** - Verify gobgpd and git are installed
3. **L3BGP NSO Packages** - Clone tailf-hcc and setup package links
4. **Custom Node IPs** - Use `node_*_ip` instead of `192.168.X.1` pattern  
5. **Custom Hostnames** - Use `node_*_hostname` instead of `${PREFIX}X.ha-cluster`
6. **Manager Node** - Basic namespace with `manager_ip` 
7. **L3BGP Hosts Files** - Generate custom `/etc/hosts` entries
8. **Validation** - Test with current config file

### 🎯 **SECONDARY** - Enhanced Features

9. **BGP Peering** - FRRouting integration
10. **Advanced Routing** - Complex topologies  
11. **Partition Testing** - L3BGP-aware network partitions
12. **Monitoring** - BGP status commands

### ⚠️ **COMPATIBILITY**

- ✅ Maintain backward compatibility with `network_type=simple` (default)
- ✅ Keep existing CLI interface unchanged
- ✅ Preserve SSL certificate generation
- ✅ Support existing simple network configurations

## Testing Strategy

### Unit Testing
```bash
# Test prerequisite checks
./raft-cluster-netns.sh setup --config test-l3bgp.conf --dry-run  # Should check gobgpd

# Test configuration parsing
./raft-cluster-netns.sh configure --auto --type l3bgp --output test.conf
source test.conf && echo "network_type=$network_type, node_1_ip=$node_1_ip"

# Test network type detection  
echo "network_type=l3bgp" > test-l3bgp.conf
./raft-cluster-netns.sh setup --config test-l3bgp.conf --dry-run
```

### Integration Testing
```bash
# Test full L3BGP setup with current config
./raft-cluster-netns.sh cleanup
./raft-cluster-netns.sh setup  # Should auto-detect L3BGP from .raft-cluster.conf

# Validate network connectivity
./raft-cluster-netns.sh exec 1 "ping -c1 192.168.31.98"  # berlin -> london
./raft-cluster-netns.sh exec 2 "ping -c1 192.168.32.99"  # london -> paris
./raft-cluster-netns.sh exec 3 "ping -c1 172.17.0.2"     # paris -> manager

# Test hostname resolution
./raft-cluster-netns.sh exec 1 "ping -c1 london.cluster.local"
./raft-cluster-netns.sh exec 2 "ping -c1 paris.cluster.local"  
./raft-cluster-netns.sh exec 3 "ping -c1 berlin.cluster.local"

# Test RAFT cluster formation with tailf-hcc package
./raft-cluster-netns.sh exec 1 "ncs_cli -u admin -p admin -C 'show cluster'"
./raft-cluster-netns.sh exec 1 "ncs_cli -u admin -p admin -C 'show packages'"

# Verify tailf-hcc package is loaded
./raft-cluster-netns.sh exec 1 "ls -la ncs-run1/packages/"
./raft-cluster-netns.sh exec 2 "ls -la ncs-run2/packages/"
./raft-cluster-netns.sh exec 3 "ls -la ncs-run3/packages/"
```

## Benefits

1. **Realistic Network Simulation**: Closer to real-world multi-site deployments
2. **BGP Failover Testing**: Test RAFT behavior during BGP convergence
3. **Custom Topologies**: Support various network architectures
4. **Scalable Configuration**: Easy to add/modify nodes and connections
5. **Protocol Testing**: Validate NSO behavior with complex routing
6. **Geographic Simulation**: Test latency and connectivity scenarios
