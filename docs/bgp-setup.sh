#!/bin/bash
set -e

# Config
BRIDGE=br0
VIP=192.0.2.100/32

# Cleanup function
cleanup() {
    echo "[*] Cleaning up..."
    ip netns del r1 2>/dev/null || true
    ip netns del r2 2>/dev/null || true
    ip netns del client 2>/dev/null || true
    ip link del br0 2>/dev/null || true
}
trap cleanup EXIT

echo "[*] Creating namespaces"
ip netns add r1
ip netns add r2
ip netns add client

echo "[*] Creating bridge"
ip link add name $BRIDGE type bridge
ip link set $BRIDGE up

# Function to connect a namespace to the bridge
add_ns_to_bridge() {
    NS=$1
    VETH_HOST=veth-${NS}
    VETH_NS=eth0

    echo "[*] Connecting $NS to bridge"
    ip link add ${VETH_HOST} type veth peer name ${VETH_NS}-${NS}
    ip link set ${VETH_NS}-${NS} netns ${NS}
    ip link set ${VETH_HOST} master $BRIDGE
    ip link set ${VETH_HOST} up

    ip netns exec ${NS} ip link set ${VETH_NS}-${NS} name eth0
    ip netns exec ${NS} ip link set eth0 up
    ip netns exec ${NS} ip link set lo up
}

add_ns_to_bridge r1
add_ns_to_bridge r2
add_ns_to_bridge client

echo "[*] Assigning IP addresses"
ip netns exec r1 ip addr add 10.0.0.1/24 dev eth0
ip netns exec r2 ip addr add 10.0.0.2/24 dev eth0
ip netns exec client ip addr add 10.0.0.100/24 dev eth0

echo "[*] Creating GoBGP configs"

mkdir -p /tmp/gobgp-demo

# r1 config
cat <<EOF > /tmp/gobgp-demo/r1.yaml
global:
  config:
    as: 65001
    router-id: 10.0.0.1
neighbors:
  - config:
      neighbor-address: 10.0.0.2
      peer-as: 65002
  - config:
      neighbor-address: 10.0.0.100
      peer-as: 65003
EOF

# r2 config
cat <<EOF > /tmp/gobgp-demo/r2.yaml
global:
  config:
    as: 65002
    router-id: 10.0.0.2
neighbors:
  - config:
      neighbor-address: 10.0.0.1
      peer-as: 65001
  - config:
      neighbor-address: 10.0.0.100
      peer-as: 65003
EOF

# client config
cat <<EOF > /tmp/gobgp-demo/client.yaml
global:
  config:
    as: 65003
    router-id: 10.0.0.100
neighbors:
  - config:
      neighbor-address: 10.0.0.1
      peer-as: 65001
  - config:
      neighbor-address: 10.0.0.2
      peer-as: 65002
EOF

echo "[*] Starting gobgpd in all namespaces"

ip netns exec r1 gobgpd -f /tmp/gobgp-demo/r1.yaml > /tmp/gobgp-demo/r1.log 2>&1 &
ip netns exec r2 gobgpd -f /tmp/gobgp-demo/r2.yaml > /tmp/gobgp-demo/r2.log 2>&1 &
ip netns exec client gobgpd -f /tmp/gobgp-demo/client.yaml > /tmp/gobgp-demo/client.log 2>&1 &

sleep 2

echo "[*] Assigning VIP and announcing route on r1"
ip netns exec r1 ip addr add 192.0.2.100/32 dev eth0
ip netns exec r1 gobgp global rib add 192.0.2.100/32

echo "[*] Starting HTTP server on r1"
ip netns exec r1 python3 -m http.server 80 --bind 192.0.2.100 > /tmp/gobgp-demo/http.log 2>&1 &

sleep 2

echo "[*] Checking VIP route in client"
ip netns exec client gobgp global rib | grep 192.0.2.100 || {
    echo "[!] VIP route not received in client"
    exit 1
}

echo "[*] Making HTTP request from client"
ip netns exec client curl -s http://192.0.2.100 | head -n 5

echo "[✅] Success — client reached VIP via BGP route!" 
