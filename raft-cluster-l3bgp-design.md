# RAFT Cluster L3 BGP Network Design

## Overview

This document outlines the extension of `raft-cluster-netns.sh` to support Layer 3 BGP-enabled network topologies with custom node configurations.

## Configuration Format

### Network Type Detection

The script would detect the network type from the config file:

```bash
network_type=l3bgp    # Enables L3 BGP mode
network_type=simple   # Default flat network mode
```

### Node Configuration Schema

Each node can have custom properties:

```bash
# Node-specific settings
node_<id>_name=<custom_name>          # Default: ha<id>
node_<id>_ip=<ip_address>             # Default: 192.168.<id>.1
node_<id>_subnet=<subnet_cidr>        # Default: 192.168.<id>.0/24
node_<id>_asn=<bgp_asn>               # BGP Autonomous System Number
node_<id>_hostname=<fqdn>             # Custom hostname
```

### Manager Node Configuration

Optional manager node for BGP route reflection:

```bash
manager_enabled=true
manager_name=manager
manager_ip=172.17.0.2
manager_subnet=172.17.0.0/16
manager_asn=64514
manager_bridge=docker0               # Use existing bridge
```

## Implementation Strategy

### 1. Configuration Parsing

Extend `load_config_file()` to parse node-specific configurations:

```bash
parse_node_config() {
    local node_id="$1"
    
    # Parse node-specific settings with defaults
    eval "NODE_${node_id}_NAME=\${node_${node_id}_name:-ha${node_id}}"
    eval "NODE_${node_id}_IP=\${node_${node_id}_ip:-192.168.${node_id}.1}"
    eval "NODE_${node_id}_SUBNET=\${node_${node_id}_subnet:-192.168.${node_id}.0/24}"
    eval "NODE_${node_id}_ASN=\${node_${node_id}_asn:-}"
    eval "NODE_${node_id}_HOSTNAME=\${node_${node_id}_hostname:-ha${node_id}.ha-cluster}"
}
```

### 2. Network Topology Creation

#### L3 BGP Mode Network Setup

```bash
setup_l3bgp_network() {
    log_info "Setting up L3 BGP network topology"
    
    # 1. Create manager node if enabled
    if [[ "$manager_enabled" == "true" ]]; then
        setup_manager_node
    fi
    
    # 2. Create individual subnets for each node
    for ((i=1; i<=NODES; i++)); do
        setup_node_l3_network "$i"
    done
    
    # 3. Configure BGP peering between nodes
    if [[ "$bgp_enabled" == "true" ]]; then
        setup_bgp_peering
    fi
    
    # 4. Setup inter-node routing
    setup_l3_routing
}
```

#### Manager Node Setup

```bash
setup_manager_node() {
    local manager_ns="${prefix}manager"
    local manager_veth="${prefix}mgr"
    
    # Create manager namespace
    execute_cmd "Create manager namespace" \
        sudo ip netns add "$manager_ns"
    
    # Connect to existing bridge (docker0 or custom)
    setup_manager_bridge_connection
    
    # Configure manager IP
    execute_cmd "Configure manager IP" \
        sudo ip netns exec "$manager_ns" ip addr add "$manager_ip/$(get_subnet_mask "$manager_subnet")" dev "${manager_veth}a"
}
```

#### Individual Node Networks

```bash
setup_node_l3_network() {
    local node_id="$1"
    local node_name="$(get_node_name "$node_id")"
    local node_ip="$(get_node_ip "$node_id")"
    local node_subnet="$(get_node_subnet "$node_id")"
    
    # Create dedicated bridge for this node
    local bridge_name="${prefix}br${node_id}"
    execute_cmd "Create bridge for $node_name" \
        sudo ip link add name "$bridge_name" type bridge
    
    # Create namespace with custom name
    local ns_name="${prefix}${node_name}"
    execute_cmd "Create namespace for $node_name" \
        sudo ip netns add "$ns_name"
    
    # Setup veth pair and bridge connection
    setup_node_veth_pair "$node_id" "$bridge_name"
    
    # Configure node IP from subnet
    execute_cmd "Configure $node_name IP" \
        sudo ip netns exec "$ns_name" ip addr add "$node_ip/$(get_subnet_mask "$node_subnet")" dev "${prefix}${node_id}a"
}
```

### 3. BGP Configuration

#### FRRouting Integration

```bash
setup_bgp_peering() {
    log_info "Configuring BGP peering"
    
    for ((i=1; i<=NODES; i++)); do
        setup_node_bgp "$i"
    done
    
    # Configure manager as route reflector if enabled
    if [[ "$manager_enabled" == "true" ]]; then
        setup_manager_bgp
    fi
}

setup_node_bgp() {
    local node_id="$1"
    local node_name="$(get_node_name "$node_id")"
    local node_asn="$(get_node_asn "$node_id")"
    local router_id="${bgp_router_id_base}.${node_id}"
    
    # Generate FRRouting configuration
    create_frr_config "$node_name" "$node_asn" "$router_id"
    
    # Start FRRouting in namespace
    start_frr_in_namespace "$node_name"
}
```

#### FRRouting Configuration Template

```bash
create_frr_config() {
    local node_name="$1"
    local asn="$2"
    local router_id="$3"
    
    cat > "/tmp/frr-${node_name}.conf" << EOF
frr version 8.1
frr defaults traditional
hostname ${node_name}
no ipv6 forwarding

router bgp ${asn}
 bgp router-id ${router_id}
 bgp log-neighbor-changes
 
 ! Manager peering
 neighbor ${manager_ip} remote-as ${manager_asn}
 neighbor ${manager_ip} description "Manager Route Reflector"
 
 ! Peer with other RAFT nodes
$(generate_peer_config "$node_name")

 address-family ipv4 unicast
  network $(get_node_subnet_announcement "$node_name")
  neighbor ${manager_ip} route-reflector-client
 exit-address-family

line vty
EOF
}
```

### 4. Inter-Node Connectivity

```bash
setup_l3_routing() {
    log_info "Setting up L3 routing between nodes"
    
    # Create routing rules based on connectivity matrix
    for ((i=1; i<=NODES; i++)); do
        for ((j=1; j<=NODES; j++)); do
            if [[ "$i" != "$j" ]]; then
                setup_node_to_node_route "$i" "$j"
            fi
        done
    done
}

setup_node_to_node_route() {
    local from_node="$1"
    local to_node="$2"
    local connection_type="$(get_connection_type "$from_node" "$to_node")"
    
    case "$connection_type" in
        "direct")
            setup_direct_route "$from_node" "$to_node"
            ;;
        "bgp_peering")
            # BGP will handle routing
            log_debug "BGP routing for ${from_node} -> ${to_node}"
            ;;
        "via_manager")
            setup_manager_route "$from_node" "$to_node"
            ;;
    esac
}
```

## Configuration Examples

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

# Manager (simulating internet exchange)
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

## Benefits

1. **Realistic Network Simulation**: Closer to real-world multi-site deployments
2. **BGP Failover Testing**: Test RAFT behavior during BGP convergence
3. **Custom Topologies**: Support various network architectures
4. **Scalable Configuration**: Easy to add/modify nodes and connections
5. **Protocol Testing**: Validate NSO behavior with complex routing

## Migration Path

1. **Phase 1**: Extend configuration parsing for node-specific settings
2. **Phase 2**: Implement L3 network setup functions
3. **Phase 3**: Add BGP/FRRouting integration
4. **Phase 4**: Enhanced partition simulation for L3 scenarios
5. **Phase 5**: Documentation and examples

This design maintains backward compatibility while enabling sophisticated network topologies for advanced RAFT cluster testing.
