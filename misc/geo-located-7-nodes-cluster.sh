#!/bin/bash
#
# Geo-Located 7-Node Cluster Impairment Script
#
# Simulates a geographically distributed 7-node RAFT cluster by applying
# realistic network impairments (latency, jitter, packet loss) to each node.
#
# The cluster is modeled as two groups:
#
#   Geo-distributed nodes (cross-region links):
#     Node 1 (Geo A) - 50ms delay, 10ms jitter, 0.5% loss  (nearby region)
#     Node 2 (Geo B) - 200ms delay, 20ms jitter, 1% loss    (distant region)
#     Node 3 (Geo C) - 250ms delay, 20ms jitter, 2% loss    (remote region)
#
#   WAN nodes (same-region / datacenter links):
#     Node 4 (WAN A) - 10ms delay, 2ms jitter               (local WAN)
#     Node 5 (WAN B) - 5ms delay, 1ms jitter                (local WAN)
#     Node 6 (WAN C) - 5ms delay, 1ms jitter                (local WAN)
#     Node 7 (WAN D) - 10ms delay, 2ms jitter               (local WAN)
#
# Prerequisites:
#   - A 7-node cluster must already be set up and running:
#       ./raft-cluster-netns.sh setup -n 7
#       ./raft-cluster-netns.sh start
#
# Usage:
#   ./misc/geo-located-7-nodes-cluster.sh              # apply impairments
#   ./misc/geo-located-7-nodes-cluster.sh --dry-run    # preview tc commands
#
# To clear all impairments afterwards:
#   ./raft-cluster-netns.sh impair all reset
#

DRY_RUN=""
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN="--dry-run"
fi

echo "Geo node A(1): Delay=50ms , Jitter=10ms , Loss=0.5%"
./raft-cluster-netns.sh impair 1 $DRY_RUN --delay 50ms --jitter 10ms --loss 0.5%

echo "Geo node B(2): Delay=200ms , Jitter=20ms , Loss=1%"
./raft-cluster-netns.sh impair 2 $DRY_RUN --delay 200ms --jitter 20ms --loss 1%

echo "Geo node C(3): Delay=250ms , Jitter=20ms , Loss=2%"
./raft-cluster-netns.sh impair 3 $DRY_RUN --delay 250ms --jitter 20ms --loss 2%


echo "WAN node A(4): Delay=10ms , Jitter=2ms"
./raft-cluster-netns.sh impair 4 $DRY_RUN --delay 10ms --jitter 2ms

echo "WAN node B(5): Delay=5ms , Jitter=1ms"
./raft-cluster-netns.sh impair 5 $DRY_RUN --delay 5ms --jitter 1ms

echo "WAN node C(6): Delay=5ms , Jitter=1ms"
./raft-cluster-netns.sh impair 6 $DRY_RUN --delay 5ms --jitter 1ms

echo "WAN node D(7): Delay=10ms , Jitter=2ms"
./raft-cluster-netns.sh impair 7 $DRY_RUN --delay 10ms --jitter 2ms
