# RAFT Cluster Virtual Network Setup - Shell Script Implementation Plan

## Overview
This document outlines the plan for creating a bash shell script that replicates the virtual network setup functionality currently implemented in the Lux test scripts for RAFT cluster testing. The script will create isolated network namespaces for each NSO node in the cluster, allowing for realistic network testing scenarios.

## Current Lux Implementation Analysis

Based on the existing Lux test scripts (`raft_netns.luxinc` and `network-conn-debug.lux`), the virtual network setup involves:

### Network Infrastructure
1. **Virtual Ethernet Pairs (veth)**: Creates paired network interfaces (`ha${id}a` and `ha${id}b`)
2. **Network Namespaces**: Isolates each node in its own network namespace (`ha${id}ns`)
3. **Bridge Network**: Connects all nodes via a bridge (`ha-cluster`)
4. **IP Addressing**: Assigns `192.168.${id}.1/16` to each node
5. **DNS Resolution**: Uses custom hosts files for hostname resolution
6. **Gateway**: Provides a gateway interface at `192.168.0.254/16` for external access

### NSO Configuration
1. **Node Setup**: Creates individual NSO runtime directories (`ncs-run${id}`)
2. **Configuration Templating**: Modifies `ncs.conf` for RAFT cluster settings
3. **SSL/TLS Support**: Configures certificates for secure Erlang distribution
4. **Node Addressing**: Sets up proper node addresses and seed nodes

## Shell Script Design

### Script Name
`raft-cluster-netns.sh`

### Core Functions

#### Network Management Functions
- `setup_network()` - Complete network infrastructure setup
- `cleanup_network()` - Tear down all network components
- `create_veth_pairs()` - Create virtual ethernet pairs
- `create_namespaces()` - Create and configure network namespaces
- `setup_bridge()` - Create and configure the cluster bridge
- `setup_routing()` - Configure routing and IP addresses
- `create_hosts_files()` - Generate custom hosts files for DNS resolution

#### NSO Management Functions
- `setup_nso_nodes()` - Create NSO runtime directories and configurations
- `start_nso_nodes()` - Start NSO instances in their respective namespaces
- `stop_nso_nodes()` - Stop all NSO instances
- `cleanup_nso_nodes()` - Remove NSO runtime directories

#### Utility Functions
- `check_prerequisites()` - Verify system requirements and permissions
- `validate_network()` - Test network connectivity between nodes
- `show_status()` - Display current cluster status
- `exec_in_namespace()` - Execute commands in specific namespaces

### Command Line Interface

#### Main Commands
```bash
raft-cluster-netns.sh setup [options]    # Setup the complete environment
raft-cluster-netns.sh start [options]    # Start NSO nodes
raft-cluster-netns.sh stop [options]     # Stop NSO nodes
raft-cluster-netns.sh cleanup [options]  # Cleanup everything
raft-cluster-netns.sh status [options]   # Show cluster status
raft-cluster-netns.sh shell <node_id>    # Enter namespace shell
raft-cluster-netns.sh exec <node_id> <command>  # Execute command in namespace
```

#### Global Options
- `-n, --nodes <count>` - Number of nodes in cluster (default: 3)
- `-p, --prefix <prefix>` - Node name prefix (default: ha)
- `-d, --work-dir <dir>` - Working directory (default: current)
- `-v, --verbose` - Verbose output
- `-h, --help` - Show help
- `--dry-run` - Show commands without executing

#### Setup-specific Options
- `--cluster-name <name>` - RAFT cluster name (default: test-cluster)
- `--ssl-enabled` - Enable SSL for Erlang distribution
- `--ssl-cert-dir <dir>` - SSL certificate directory
- `--network-prefix <prefix>` - Network address prefix (default: 192.168)
- `--bridge-name <name>` - Bridge interface name (default: ha-cluster)
- `--no-nso` - Setup only network, skip NSO configuration
- `--ncs-flags <flags>` - Additional flags to pass to NCS

#### Start-specific Options
- `--node <id>` - Start specific node only
- `--wait-for-leader` - Wait for leader election
- `--timeout <seconds>` - Timeout for operations (default: 30)

#### Cleanup-specific Options
- `--force` - Force cleanup even if nodes are running
- `--keep-config` - Keep NSO configuration directories

### Configuration File Support

The script should support an optional configuration file (`.raft-cluster.conf`) to store default settings:

```ini
# Default cluster configuration
nodes=3
cluster_name=test-cluster
work_dir=/tmp/raft-test
ssl_enabled=false
network_prefix=192.168
bridge_name=ha-cluster
ncs_flags=

# SSL Configuration
ssl_cert_dir=./erldist/ssl

# Node configuration
node_prefix=ha
```

### Implementation Details

#### Prerequisites Check
- Verify running as root or with sudo access
- Check for required commands: `ip`, `iptables`, `ncs-setup`, `ncs`, etc.
- Validate NSO environment variables (`NCS_DIR`, etc.)
- Check for Docker iptables interference (fix if needed)

#### Error Handling
- Comprehensive error checking after each network command
- Rollback capabilities for partial failures
- Cleanup on script interruption (trap handlers)
- Detailed error messages with troubleshooting hints

#### Logging and Debugging
- Structured logging with timestamps
- Debug mode with command tracing
- Log files for each node's NSO instance
- Network connectivity validation

#### Security Considerations
- Require explicit sudo/root permissions
- Validate input parameters to prevent injection
- Secure cleanup of sensitive files
- Proper handling of SSL certificates

### Directory Structure

```
<work_dir>/
├── ncs-run1/          # NSO node 1 runtime
├── ncs-run2/          # NSO node 2 runtime  
├── ncs-run3/          # NSO node 3 runtime
├── hosts/             # Custom hosts files
│   ├── ha1ns/
│   ├── ha2ns/
│   └── ha3ns/
├── logs/              # Script logs
├── erldist/           # SSL certificates (if enabled)
└── .cluster-state     # Current cluster state
```

### Testing and Validation

#### Network Connectivity Tests
- Ping tests between all nodes
- Port scanning for NSO services
- DNS resolution verification
- Bridge interface validation

### Usage Examples

```bash
# Basic 3-node cluster setup
./raft-cluster-netns.sh setup

# Start all nodes and wait for leader
./raft-cluster-netns.sh start --wait-for-leader

# Setup 5-node cluster with SSL
./raft-cluster-netns.sh setup -n 5 --ssl-enabled --cluster-name prod-test

# Enter node 2 shell for debugging
./raft-cluster-netns.sh shell 2

# Check cluster status
./raft-cluster-netns.sh status

# Execute NCS command on node 1
./raft-cluster-netns.sh exec 1 "ncs_cli -u admin -C"

# Complete cleanup
./raft-cluster-netns.sh cleanup --force
```

### Future Enhancements

1. **IPv6 Support**: Add support for IPv6 addressing
2. **Network Simulation**: Add packet loss, latency, bandwidth limitations
3. **Docker Integration**: Optional Docker container isolation
4. **Monitoring Integration**: Export metrics for monitoring systems
5. **Configuration Templates**: Support for custom NSO configurations
6. **Multi-Host**: Support for spreading nodes across multiple physical hosts

## Implementation Priority

1. **Phase 1**: Core network setup and NSO configuration
2. **Phase 2**: Command-line interface and basic operations
3. **Phase 3**: Error handling, logging, and validation
4. **Phase 4**: Advanced features and SSL support
5. **Phase 5**: Testing utilities and documentation

This plan provides a comprehensive foundation for implementing a robust shell script that can replace the Lux test functionality while providing additional features for development and testing scenarios.
