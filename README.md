# RAFT Cluster Virtual Network Setup

This script provides a complete solution for setting up isolated virtual network
environments for NSO RAFT cluster testing. It creates network namespaces,
configures virtual networking, and sets up NSO instances for realistic cluster
testing scenarios.

## Overview

The `raft-cluster-netns.sh` script automates the creation of complete NSO RAFT
cluster testing environments using Linux network namespaces. It provides:

- **Virtual Network Infrastructure**: Isolated network namespaces with bridge networking
- **NSO Cluster Configuration**: Complete RAFT setup with SSL/TLS enabled by default  
- **Tailf-hcc**: Prepared for running BGP advertisment using the tailf-hcc package
- **Network Partition Simulation**: Test split-brain scenarios with node isolation and healing
- **Management & Debugging**: Interactive shells, command execution, and comprehensive status reporting
- **Developer-Friendly**: Dry-run mode, verbose logging, and configuration persistence

## Quick Start

### Basic Setup

```bash
# Create (default) config file: .raft_cluster.conf
./raft-cluster-netns.sh configure --auto --type tailf_hcc

# Setup a RAFT cluster according to (default) config file
./raft-cluster-netns.sh setup

# Check cluster status
./raft-cluster-netns.sh status

# Test network connectivity
./raft-cluster-netns.sh test

# Start NSO nodes
./raft-cluster-netns.sh start

# Enter a bash shell on node 1
./raft-cluster-netns.sh shell 1

# Run command  to enter NSO CLI on node 1
./raft-cluster-netns.sh exec 1 "ncs_cli -u admin"

# Create HA-Raft cluster from node 1
./raft-cluster-netns.sh exec 1 'ncs_cmd -c "maction /ha-raft/create-cluster member [ ncsd2@tailf_hcc2.ha-cluster ncsd3@tailf_hcc3.ha-cluster ]"'

# Get HA-Raft leader from node 1
./raft-cluster-netns.sh exec 1 'ncs_cmd -I -c "mget /ha-raft/status/leader"'


# Simulate network failures
./raft-cluster-netns.sh isolate 1          # Isolate node 1
./raft-cluster-netns.sh partition 1,2      # Create 2-node partition 
./raft-cluster-netns.sh heal               # Restore connectivity

# Clean up everything
./raft-cluster-netns.sh cleanup --force

# Get help
./raft-cluster-netns.sh help
```

### Tailf-HCC Topology Configuration

The script also supports a Tailf-HCC topology designed for scenarios where BGP routing is centralized on a manager node:

```bash
# Generate Tailf-HCC configuration file
./raft-cluster-netns.sh configure --auto --type tailf_hcc -n 3

# Setup cluster using the generated Tailf-HCC configuration
./raft-cluster-netns.sh setup -c .raft-cluster.conf
```

**Tailf-HCC features:**
- **Manager-Only BGP**: BGP and Zebra daemons run only on the manager node
- **Simplified Worker Nodes**: Worker nodes use direct routing without BGP complexity
- **Centralized Routing Control**: All routing decisions handled by the manager
- **Hybrid Topology**: Combines L3BGP benefits with simplified worker configuration
- **Resource Efficient**: Reduces resource usage on worker nodes

**Tailf-HCC configuration includes:**
- A `hcc.xml` config file is created for each node.
- L3BGP-style network topology with per-node subnets
- BGP/Zebra configuration only on manager node
- Direct routing from worker nodes to manager
- Full network connectivity without worker-node routing complexity

### L3 BGP Topology Configuration

The script supports advanced L3 BGP topology generation for testing complex network scenarios:

```bash
# Generate L3 BGP configuration file
./raft-cluster-netns.sh configure --auto --type l3bgp -n 5

# Setup cluster using the generated BGP configuration
./raft-cluster-netns.sh setup
```

**L3 BGP features:**
- **Realistic Network Topologies**: Auto-generates configurations with city-based node names (Berlin, London, Paris, Tokyo, Sydney)
- **Unique Subnets**: Each node gets its own subnet for true L3 separation
- **BGP ASN Assignment**: Automatic ASN allocation for BGP peering
- **Full Mesh Connectivity**: BGP peering relationships between all nodes
- **Manager Node**: Centralized management node with direct connections
- **Production-Like Testing**: Simulates real-world distributed environments

**Generated BGP configuration includes:**
- Node-specific IP subnets (e.g., 192.168.30.0/24 for Berlin)
- Unique ASN numbers (e.g., AS64511 for Berlin, AS64512 for London)
- BGP router IDs based on geographic locations
- Inter-node BGP peering configurations
- Hostname resolution for realistic multi-site scenarios

## Installation & Prerequisites

### System Requirements

- Linux with network namespace support
- Sudo privileges for network operations
- NSO (Network Services Orchestrator) installation

### Required Commands

The script checks for these system commands:
- `ip` - Network configuration
- `iptables` - Firewall rules
- `ncs-setup`, `ncs`, `ncs_cmd` - NSO tools (if using NSO features)

### NSO Environment Setup

The script automatically detects your NSO environment by:

1. **Auto-detection via PATH**: Looks for `ncs` command and finds `env.sh` relative to NSO installation
2. **Standard search paths**: Checks common locations for `env.sh`
3. **Interactive prompting**: Asks for the path if auto-detection fails

```bash
# The script searches these locations automatically:
./env.sh
../env.sh  
../../env.sh
$NCS_DIR/../env.sh
$(dirname $(which ncs))/../env.sh    # Auto-detected from ncs command
```

Or specify manually:
```bash
export ENV_SH_PATH="/path/to/your/env.sh"
```

## Command Reference

### Core Commands

| Command | Description | Example |
|---------|-------------|---------|
| `setup` | Create complete environment | `./raft-cluster-netns.sh setup` |
| `configure` | Configure NSO nodes without network setup | `./raft-cluster-netns.sh configure` |
| `start` | Start NSO nodes | `./raft-cluster-netns.sh start` |
| `stop` | Stop NSO nodes | `./raft-cluster-netns.sh stop` |
| `cleanup` | Remove all resources | `./raft-cluster-netns.sh cleanup --force` |
| `status` | Show cluster status | `./raft-cluster-netns.sh status` |
| `test` | Test connectivity | `./raft-cluster-netns.sh test` |

### Network Partition Commands

| Command | Description | Example |
|---------|-------------|---------|
| `isolate` | Isolate single node | `./raft-cluster-netns.sh isolate 1` |
| `partition` | Create network partition | `./raft-cluster-netns.sh partition 1,2` |
| `heal` | Heal network partitions | `./raft-cluster-netns.sh heal` |

### Debugging Commands

| Command | Description | Example |
|---------|-------------|---------|
| `shell` | Enter namespace shell | `./raft-cluster-netns.sh shell 2` |
| `exec` | Execute command in namespace | `./raft-cluster-netns.sh exec 1 "ip addr"` |

### Key Options

| Option | Description | Default |
|--------|-------------|---------|
| `-n, --nodes` | Number of cluster nodes | 3 |
| `-p, --prefix` | Node name prefix | ha |
| `--cluster-name` | RAFT cluster name | test-cluster |
| `--network-prefix` | Network address prefix | 192.168 |
| `--no-ssl` | Disable SSL for Erlang | false (SSL enabled by default) |
| `--type` | Configuration type (simple, l3bgp, tailf_hcc) | simple |
| `--auto` | Auto-generate configuration | - |
| `--dry-run` | Show commands without executing | - |
| `-v, --verbose` | Verbose output | - |
| `-c, --config` | Configuration file | .raft-cluster.conf |

## Running the HCC Package with NSO as a Non-Root User

GoBGP uses TCP port 179 for its communications and binds to it at startup.
As port 179 is considered a privileged port it is normally required to run
`gobgpd` as root.

When NSO is running as a non-root user the gobgpd command will be executed as
the same user as NSO and will prevent `gobgpd` from binding to port 179.

There a multiple ways of handling this and two are listed here.

1. Set capability CAP_NET_BIND_SERVICE on the gobgpd file.
   May not be supported by all Linux distributions.

```bash
$ sudo setcap 'cap_net_bind_service=+ep' /usr/bin/gobgpd
```

2. Set the owner to root and the setuid bit of the gobgpd file.
   Works on all Linux distributions.

```bash
$ sudo chown root /usr/bin/gobgpd
$ sudo chmod u+s /usr/bin/gobgpd
```

## Example run: using tailf-hcc and ha-raft

```bash
# NOTE THE VIP: 192.168.30.55 CURRENTLY SETUP ON NODE 1
✦ ❯ ./raft-cluster-netns.sh exec 1 "ip a ls"
[INFO] Parsing tailf_hcc configuration...
sudo: unable to resolve host ubuntu24-desktop: Temporary failure in name resolution
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet 192.168.30.55/32 scope global lo                 <<<==== VIP !!
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
945: tailf_hcc1a@if944: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 8e:d7:45:eb:16:98 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 192.168.30.97/24 scope global tailf_hcc1a
       valid_lft forever preferred_lft forever
    inet6 fe80::8cd7:45ff:feeb:1698/64 scope link
       valid_lft forever preferred_lft forever


✦ ❯ ping 192.168.30.55
PING 192.168.30.55 (192.168.30.55) 56(84) bytes of data.
64 bytes from 192.168.30.55: icmp_seq=1 ttl=64 time=0.307 ms
64 bytes from 192.168.30.55: icmp_seq=2 ttl=64 time=0.052 ms
^C
--- 192.168.30.55 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1047ms
rtt min/avg/max/mdev = 0.052/0.179/0.307/0.127 ms

# STOP NSO AT NODE 1
✦ ❯ ./raft-cluster-netns.sh exec 1 "ncs --stop"
[INFO] Parsing tailf_hcc configuration...
sudo: unable to resolve host ubuntu24-desktop: Temporary failure in name resolution

# WE GET A REDIRECT FROM NODE 1 !
✦ ❯ ping 192.168.30.55
PING 192.168.30.55 (192.168.30.55) 56(84) bytes of data.
From 192.168.30.97: icmp_seq=1 Redirect Host(New nexthop: 192.168.30.55)
64 bytes from 192.168.30.55: icmp_seq=1 ttl=64 time=0.532 ms
From 192.168.30.97: icmp_seq=2 Redirect Host(New nexthop: 192.168.30.55)
64 bytes from 192.168.30.55: icmp_seq=2 ttl=64 time=0.101 ms
From 192.168.30.97: icmp_seq=3 Redirect Host(New nexthop: 192.168.30.55)
64 bytes from 192.168.30.55: icmp_seq=3 ttl=64 time=0.100 ms
^C
--- 192.168.30.55 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2039ms
rtt min/avg/max/mdev = 0.100/0.244/0.532/0.203 ms

# THE VIP IS GONE AT NODE 1 !
✦ ❯ ./raft-cluster-netns.sh exec 1 "ip a ls"
[INFO] Parsing tailf_hcc configuration...
sudo: unable to resolve host ubuntu24-desktop: Temporary failure in name resolution
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
945: tailf_hcc1a@if944: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 8e:d7:45:eb:16:98 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 192.168.30.97/24 scope global tailf_hcc1a
       valid_lft forever preferred_lft forever
    inet6 fe80::8cd7:45ff:feeb:1698/64 scope link
       valid_lft forever preferred_lft forever

# NO VIP AT NODE 2 ...
✦ ❯ ./raft-cluster-netns.sh exec 2 "ip a ls"
[INFO] Parsing tailf_hcc configuration...
sudo: unable to resolve host ubuntu24-desktop: Temporary failure in name resolution
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
947: tailf_hcc2a@if946: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether ce:07:36:d9:e5:3a brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 192.168.31.98/24 scope global tailf_hcc2a
       valid_lft forever preferred_lft forever
    inet6 fe80::cc07:36ff:fed9:e53a/64 scope link
       valid_lft forever preferred_lft forever

# HERE WE FIND THE VIP, AT NODE 3
✦ ❯ ./raft-cluster-netns.sh exec 3 "ip a ls"
[INFO] Parsing tailf_hcc configuration...
sudo: unable to resolve host ubuntu24-desktop: Temporary failure in name resolution
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
949: tailf_hcc3a@if948: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether e2:c4:18:f1:a0:59 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 192.168.32.99/24 scope global tailf_hcc3a
       valid_lft forever preferred_lft forever
    inet 192.168.30.55/32 scope global tailf_hcc3a           <<<=== VIP !!
       valid_lft forever preferred_lft forever
    inet6 fe80::e0c4:18ff:fef1:a059/64 scope link
       valid_lft forever preferred_lft forever

# CHECK THE HA-RAFT STATUS ON NODE 3
❯ ./raft-cluster-netns.sh exec 3 "ncs_cli -u admin"
[INFO] Parsing tailf_hcc configuration...
sudo: unable to resolve host ubuntu24-desktop: Temporary failure in name resolution

admin connected from 127.0.0.1 using console on ubuntu24-desktop
admin@ncs> show ha-raft
ha-raft status role leader
ha-raft status leader ncsd3@tailf_hcc3.ha-cluster
ha-raft status member [ ncsd1@tailf_hcc1.ha-cluster ncsd2@tailf_hcc2.ha-cluster ncsd3@tailf_hcc3.ha-cluster ]
ha-raft status connected-node [ ncsd2@tailf_hcc2.ha-cluster ]
ha-raft status local-node ncsd3@tailf_hcc3.ha-cluster
SERIAL
NUMBER  EXPIRATION DATE            FILE PATH
-----------------------------------------------------------------------------------------------------------------------------------------
0105    2025-10-27T21:26:48+01:00  /home/ttornkvi/git/raft-cluster-netns/work_dir/ncs-run3/../erldist/ssl/ca1/certs/tailf_hcc3_cert.pem

SERIAL
NUMBER  EXPIRATION DATE            FILE PATH
------------------------------------------------------------------------------------------------------------------------
FF      2025-10-27T21:26:47+01:00  /home/ttornkvi/git/raft-cluster-netns/work_dir/ncs-run3/../erldist/ssl/ca1/cert.pem

ha-raft status log current-index 53
ha-raft status log applied-index 53
ha-raft status log num-entries 12
NODE                         STATE    INDEX  LAG
--------------------------------------------------
ncsd2@tailf_hcc2.ha-cluster  in-sync  53     0

ha-raft status passive false
[ok][2025-09-10 08:35:31]
admin@ncs>  
```

## Troubleshooting: Downgrading GoBGP and FRR

Newer versions of GoBGP (≥ 3.x) and FRR (≥ 8.4.x) introduced changes in
the Zebra protocol message formats. We simply didn't see a success
message in the output when starting gobgpd, like in:

```
{"Topic":"Zebra","level":"info","msg":"success to connect to Zebra with message
 version 6.","time":"2025-09-08T21:36:29+02:00"}
```

To maintain compatibility in this example setup using Linux namespaces
and Zebra, it is recommended to use GoBGP 2.25.0 and FRR 8.1, which are known
to work together correctly.

First check what versions you have:

```bash
gobgpd --version   # GoBGP version
vtysh --help       # FRR version
```

### Steps to Downgrade

1. Remove the current FRR and GoBGP packages:

```bash
sudo apt-get remove --purge frr frr-pythontools gobgpd
sudo apt-get autoremove
```

2. Install required dependencies:

```bash
sudo apt-get update
sudo apt-get install -y git build-essential pkg-config libjson-c-dev \
     libelf-dev libyang2-dev autoconf automake libtool golang
```

3. Build and install FRR 8.1 from source:

```bash
git clone https://github.com/FRRouting/frr.git
cd frr
git checkout v8.1
./bootstrap.sh
./configure \
  --prefix=/usr \
  --sysconfdir=/etc/frr \
  --sbindir=/usr/lib/frr \
  --localstatedir=/var/run/frr
make
sudo make install
```

4. Install GoBGP 2.25.0:

```bash
git clone https://github.com/osrg/gobgp.git
cd gobgp
git checkout v2.25.0
# Installs in $HOME/go/bin
go install ./cmd/gobgpd
go install ./cmd/gobgp
# Make globally available
sudo cp ${HOME}/go/bin/gobgpd /usr/local/bin
sudo cp ${HOME}/go/bin/gobgp /usr/local/bin
```

5. Verify versions:

```bash
gobgpd --version   # should show 2.25.0
vtysh --help       # should show FRR 8.1
```

## Network Partition Testing

### Overview

One of the most critical aspects of RAFT cluster testing is verifying behavior under network partition scenarios. The script provides comprehensive tools to simulate various types of network failures and split-brain situations.

### Partition Types

#### 1. **Node Isolation** (`isolate`)
Simulates individual node failures by disconnecting a single node:

```bash
# Isolate node 1 (simulate cable disconnect)
./raft-cluster-netns.sh isolate 1

# Check the impact
./raft-cluster-netns.sh status
```

**Result**: Node 1 cannot communicate with any other nodes. In a 3-node cluster, this creates a 1 vs 2 partition where the majority partition (nodes 2,3) continues operating.

#### 2. **Network Partitions** (`partition`)
Creates balanced or unbalanced network splits:

```bash
# Create balanced partition in 3-node cluster
./raft-cluster-netns.sh partition 1,2    # Nodes 1,2 vs Node 3

# Create specific groupings in larger clusters
./raft-cluster-netns.sh partition 1,3,5  # Nodes 1,3,5 vs 2,4,6,7
```

**Result**: Creates two separate network segments where nodes within each segment can communicate, but segments cannot reach each other.

### Testing Scenarios

#### **Leader Isolation Test**
Test what happens when the current leader becomes isolated:

```bash
# 1. Check current leader
./raft-cluster-netns.sh status | grep Leader

# 2. Isolate the leader (assume node 1 is leader)
./raft-cluster-netns.sh isolate 1

# 3. Observe leader election in remaining nodes
./raft-cluster-netns.sh status

# 4. Restore connectivity and observe behavior
./raft-cluster-netns.sh heal 1
./raft-cluster-netns.sh status
```

#### **Split-Brain Scenarios**
Test RAFT's split-brain prevention:

```bash
# Create equal partition (only works with even number of nodes)
./raft-cluster-netns.sh setup -n 4
./raft-cluster-netns.sh start
./raft-cluster-netns.sh partition 1,2    # 2 vs 2 split

# Observe that no new leader can be elected
./raft-cluster-netns.sh status

# Heal and watch cluster recovery
./raft-cluster-netns.sh heal
```

#### **Minority Partition Behavior**
Test how minority partitions behave:

```bash
# Create minority partition
./raft-cluster-netns.sh partition 1      # 1 vs 2 partition

# Check that isolated node becomes follower/candidate
./raft-cluster-netns.sh exec 1 "ncs_cmd -c 'mget /ha-raft/status/role'"

# Verify majority partition continues with leader
./raft-cluster-netns.sh exec 2 "ncs_cmd -c 'mget /ha-raft/status/leader'"
```

### Connectivity Visualization

The status command provides a connectivity matrix showing network reachability:

```bash
./raft-cluster-netns.sh status
```

Example output:
```
Node Connectivity Matrix:
  From\To:    Node1   Node2   Node3
    Node1:    SELF     ✓     ✗
    Node2:     ✓    SELF     ✗  
    Node3:     ✗     ✗    SELF
```

This shows nodes 1,2 can communicate with each other, but node 3 is isolated.

### Healing Partitions

#### **Heal Specific Node**
```bash
# Restore connectivity for specific node
./raft-cluster-netns.sh heal 1
```

#### **Heal All Partitions**
```bash
# Restore full cluster connectivity
./raft-cluster-netns.sh heal
```

### Troubleshooting Partitions

#### **Verify Partition State**
```bash
# Check bridge membership
bridge link show

# Test connectivity manually
./raft-cluster-netns.sh exec 1 "ping -c 1 192.168.2.1"
./raft-cluster-netns.sh exec 2 "ping -c 1 192.168.1.1"
```

#### **Force Cleanup**
If partitions get stuck:
```bash
# Force heal all partitions
./raft-cluster-netns.sh heal
sudo ip link del ha-clusterpart 2>/dev/null || true
```

#### **Monitor RAFT State Changes**
```bash
# Watch RAFT role changes in real-time
watch -n 1 './raft-cluster-netns.sh exec 1 "ncs_cmd -c \"mget /ha-raft/status/role\""'
```

## Network Topology Types

The script supports three different network topology types, each designed for specific testing scenarios:

### Network Type Comparison

| Feature | Simple | L3BGP | Tailf-HCC |
|---------|--------|-------|-----------|
| **Complexity** | Low | High | Medium |
| **Resource Usage** | Minimal | High | Medium |
| **BGP Routing** | None | All nodes | Manager only |
| **Subnets** | Single flat | Per-node | Per-node |
| **Use Case** | Basic testing | Multi-site simulation | Centralized routing |
| **Setup Time** | Fast | Slow | Medium |

### When to Use Each Type

#### **Simple Network** (`--type simple`)
**Best for**: Basic RAFT functionality testing, development, quick validation

```bash
./raft-cluster-netns.sh setup  # Default type
```

**Characteristics**:
- Single flat network (192.168.x.1/16)
- No routing protocols
- Minimal resource overhead
- Fast setup and teardown
- Direct node-to-node communication

#### **L3BGP Network** (`--type l3bgp`)
**Best for**: Production-like testing, multi-site scenarios, complex routing validation

```bash
./raft-cluster-netns.sh configure --auto --type l3bgp -n 5
./raft-cluster-netns.sh setup -c .raft-cluster.conf
```

**Characteristics**:
- Each node has its own subnet (192.168.30.0/24, 192.168.31.0/24, etc.)
- Full BGP mesh between all nodes
- FRR Zebra + GoBGP on every node
- Realistic multi-site network simulation
- Higher resource usage (BGP daemons on all nodes)

#### **Tailf-HCC Network** (`--type tailf_hcc`)
**Best for**: Hub-and-spoke scenarios, resource-constrained testing, centralized routing architectures

```bash
./raft-cluster-netns.sh configure --auto --type tailf_hcc -n 3
./raft-cluster-netns.sh setup -c .raft-cluster.conf
```

**Characteristics**:
- Per-node subnets like L3BGP (192.168.30.0/24, 192.168.31.0/24, etc.)
- BGP/Zebra only on manager node
- Worker nodes use simple routing through manager
- Reduced resource usage compared to L3BGP
- Simulates centralized routing control scenarios

### Choosing the Right Type

```bash
# For basic RAFT testing and development
./raft-cluster-netns.sh setup

# For testing distributed network scenarios with full BGP mesh
./raft-cluster-netns.sh configure --auto --type l3bgp -n 5
./raft-cluster-netns.sh setup -c .raft-cluster.conf

# For testing hub-and-spoke architectures with centralized routing
./raft-cluster-netns.sh configure --auto --type tailf_hcc -n 3
./raft-cluster-netns.sh setup -c .raft-cluster.conf
```

### Example: Default Network Layout

```
Host Network
├── Bridge: ha-cluster (192.168.0.254/16)
│
├── Node 1 Namespace (ha1ns)
│   ├── IP: 192.168.1.1/16
│   ├── Hostname: ha1.ha-cluster
│   └── NSO Node: ncsd1@ha1.ha-cluster
│
├── Node 2 Namespace (ha2ns)
│   ├── IP: 192.168.2.1/16  
│   ├── Hostname: ha2.ha-cluster
│   └── NSO Node: ncsd2@ha2.ha-cluster
│
└── Node 3 Namespace (ha3ns)
    ├── IP: 192.168.3.1/16
    ├── Hostname: ha3.ha-cluster
    └── NSO Node: ncsd3@ha3.ha-cluster
```

### Configuration File Format

Create `.raft-cluster.conf` to store persistent settings:

```bash
# Cluster settings
nodes=5
cluster_name=my-production-cluster
prefix=prod
work_dir=/tmp/raft-testing

# Network settings  
network_prefix=10.0
bridge_name=prod-cluster

# NSO settings
ssl_enabled=true
ssl_cert_dir=/path/to/certificates
ncs_flags=-v --debug
env_sh_path=/opt/ncs/current/ncsrc

# Operational settings
timeout=60
host=prod.example.com
```

### Configuration Precedence

1. **Command-line arguments** (highest priority)
2. **Configuration file** 
3. **Built-in defaults** (lowest priority)


## NSO Integration

### RAFT Configuration

The script automatically configures NSO with:

- **Cluster Identity**: Unique cluster name and node addresses
- **Seed Nodes**: Circular seed node configuration for bootstrapping
- **Network Binding**: Node-specific IP addresses
- **SSL Configuration**: Optional SSL/TLS for secure communication

For each node, the script creates:
- `ncs-run1/ncs.conf` - Main NSO configuration

## Troubleshooting

### Common Issues

#### "Command not found" errors
**Problem**: NSO commands not available  
**Solution**: Ensure `env.sh` path is correctly configured
```bash
./raft-cluster-netns.sh setup  # Script will prompt for env.sh location
```

#### "Permission denied" errors
**Problem**: Insufficient privileges for network operations  
**Solution**: Ensure sudo access or run as root
```bash
# Add to /etc/sudoers:
%sudo ALL=(ALL) NOPASSWD: /usr/sbin/ip,/usr/sbin/iptables
```

#### "Device already exists" errors
**Problem**: Previous setup not cleaned up  
**Solution**: Force cleanup before retrying
```bash
./raft-cluster-netns.sh cleanup --force
./raft-cluster-netns.sh setup
```

#### Network connectivity failures
**Problem**: Firewall blocking traffic  
**Solution**: Check iptables rules or Docker interference
```bash
sudo iptables --policy FORWARD ACCEPT
```

#### RAFT cluster communication issues
**Problem**: NSO nodes cannot form RAFT cluster  
**Solution**: Verify hostname resolution and node addresses
```bash
# Check if hostnames resolve correctly
./raft-cluster-netns.sh exec 1 "ping -c 1 ha2.ha-cluster"

# Verify NSO configuration has correct hostnames
grep -A 5 "<node-address>" ncs-run*/ncs.conf
grep -A 5 "<seed-node>" ncs-run*/ncs.conf

# Start nodes and check RAFT status
./raft-cluster-netns.sh start
./raft-cluster-netns.sh status
```

#### Network partition issues
**Problem**: Partitions not working as expected
**Solution**: Check bridge configuration and interface membership
```bash
# Verify bridge state
bridge link show
ip link show | grep ha-cluster

# Check connectivity matrix
./raft-cluster-netns.sh status

# Force clean partitions
./raft-cluster-netns.sh heal
sudo ip link del ha-clusterpart 2>/dev/null || true
```

#### Split-brain behavior unclear
**Problem**: Difficulty understanding RAFT behavior during partitions
**Solution**: Monitor role changes and leader election
```bash
# Watch role changes in real-time
watch -n 2 './raft-cluster-netns.sh exec 1 "ncs_cmd -c \"mget /ha-raft/status/role\""'

# Check leader from different nodes' perspectives
for i in {1..3}; do
  echo "Node $i view:"
  ./raft-cluster-netns.sh exec $i "ncs_cmd -c 'mget /ha-raft/status/leader'"
done
```

### Debug Mode

Use verbose mode for detailed troubleshooting:
```bash
./raft-cluster-netns.sh setup --verbose --dry-run
```

### L3BGP Network Connectivity Issues

#### Bridge netfilter blocking traffic
**Problem**: Bridge traffic being filtered by iptables, causing connectivity failures  
**Symptoms**: `ping` works between some interfaces but fails between network namespaces  
**Solution**: Disable bridge netfilter to allow unrestricted bridge traffic
```bash
# Disable bridge netfilter (applies iptables rules to bridge traffic)
sudo sysctl -w net.bridge.bridge-nf-call-iptables=0
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=0

# Make permanent by adding to /etc/sysctl.conf:
echo "net.bridge.bridge-nf-call-iptables=0" | sudo tee -a /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-ip6tables=0" | sudo tee -a /etc/sysctl.conf
```

#### iptables FORWARD policy blocking inter-subnet communication
**Problem**: Default FORWARD policy DROP prevents routing between L3BGP subnets  
**Symptoms**: 
- Nodes can reach bridge gateway (`192.168.X.254`)
- Cross-subnet communication fails (`192.168.30.97` → `192.168.31.98`)
- `traceroute` shows first hop working, then `* * *`
**Solution**: Add iptables rule to allow forwarding on bridge interface
```bash
# Allow forwarding between interfaces on the same bridge
sudo iptables -I FORWARD -i ha-cluster -o ha-cluster -j ACCEPT

# Or temporarily change policy (less secure)
sudo iptables --policy FORWARD ACCEPT

# Check current FORWARD policy
sudo iptables -L FORWARD -n -v | head -1
```

#### L3BGP configuration using default values instead of config file
**Problem**: Configuration parsing not loading node-specific variables  
**Symptoms**: 
- Parsed config shows `IP=192.168.1.1` instead of configured `IP=192.168.30.97`
- Manager connectivity fails to wrong IP addresses
**Solution**: Ensure config loading uses global variable scope
```bash
# Check if node variables are being set correctly
grep "node_1_ip" your-config.conf

# Verify the declare statement uses -g flag in load_config_file()
# In raft-cluster-netns.sh, ensure:
declare -g "$key=$value"  # Instead of just: declare "$key=$value"
```

#### Missing test_connectivity function
**Problem**: Script calls undefined function  
**Symptoms**: `./script.sh test` fails with "command not found"  
**Solution**: Function should route to appropriate network module
```bash
# Function should be implemented as:
test_connectivity() {
    if [[ "$NETWORK_TYPE" == "l3bgp" ]]; then
        source "$SCRIPT_DIR/lib/network-l3bgp.sh"
        parse_l3bgp_config  # Important: parse config first
        test_l3bgp_connectivity
    else
        # Handle simple network testing
    fi
}
```

#### Hard-coded subnet logic in L3BGP module
**Problem**: L3BGP setup uses default subnets (1, 2, 3) instead of configured subnets  
**Symptoms**: Bridge shows `192.168.1.254`, `192.168.2.254` instead of `192.168.30.254`, `192.168.31.254`  
**Solution**: Use actual configured subnets in routing and bridge setup
```bash
# Check bridge gateway addresses
ip addr show ha-cluster | grep inet

# Should show configured subnets like:
# inet 192.168.30.254/24 scope global ha-cluster
# inet 192.168.31.254/24 scope global ha-cluster
# Not: inet 192.168.1.254/24, inet 192.168.2.254/24
```

#### Debugging network connectivity step by step
```bash
# 1. Test basic namespace connectivity
sudo ip netns list | grep l3bgp

# 2. Test bridge gateway reachability
sudo ip netns exec l3bgp1ns ping -c 1 192.168.30.254

# 3. Test host-to-manager connectivity
ping -c 1 192.168.30.2

# 4. Check ARP tables
sudo ip netns exec l3bgp1ns ip neighbor show

# 5. Test cross-subnet routing
sudo ip netns exec l3bgp1ns ping -c 1 192.168.31.98

# 6. Check bridge netfilter settings
sudo sysctl net.bridge.bridge-nf-call-iptables

# 7. Check iptables FORWARD policy
sudo iptables -L FORWARD -n | head -1

# 8. Verify routing table
sudo ip netns exec l3bgp1ns ip route show

# 9. Test full connectivity
./raft-cluster-netns.sh test -c your-config.conf
```


## License

This project is part of the NSO development toolkit and follows the same licensing terms as the main NSO distribution.

