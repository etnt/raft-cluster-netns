# Network Impairment Simulation Plan

## Goal

Extend `raft-cluster-netns.sh` to simulate **network latency** and **packet loss** between nodes in the RAFT cluster. This enables testing how NSO RAFT consensus behaves under degraded network conditions — not just hard partitions (which already exist), but also the grey-failure scenarios common in real deployments.

---

## Background: Current Architecture

Traffic between nodes flows through **veth pairs** connected to a **Linux bridge**:

```
Node1 (ha1ns)          Node2 (ha2ns)          Node3 (ha3ns)
  ha1a                   ha2a                   ha3a
   │                      │                      │
   │ veth pair            │ veth pair            │ veth pair
   │                      │                      │
  ha1b                   ha2b                   ha3b
   └──────────┬───────────┴──────────┬───────────┘
              │      Bridge (ha-cluster)         │
              └──────────────────────────────────┘
```

Existing partition simulation works at **Layer 2** by detaching veth-b interfaces from the bridge. The new impairment features should integrate naturally alongside this mechanism.

---

## Approach: Linux `tc` / `netem`

The standard Linux tool for network impairment is **`tc` (traffic control)** with the **`netem`** (network emulator) queueing discipline. It is part of the `iproute2` package (already a prerequisite) and works per-interface inside network namespaces.

### Why `netem`

- **Kernel-native** — no extra daemons or dependencies beyond `iproute2`
- **Per-interface granularity** — can be applied asymmetrically
- **Composable** — latency, jitter, loss, corruption, reordering, duplication can all be combined
- **Namespace-aware** — `tc` rules applied inside a netns only affect that namespace's traffic

### Where to Apply

Apply `netem` on the **veth-a interface inside each namespace** (the node-facing side). This ensures all traffic leaving a node is impaired, regardless of the network topology module in use (simple, l3bgp, tailf_hcc).

```
Node1 namespace (ha1ns)
  ┌─────────────────┐
  │  ha1a ← tc netem applied here
  └────────┬────────┘
           │ veth pair
  ┌────────┴────────┐
  │  ha1b (bridge side, no tc)
  └─────────────────┘
```

Applying on veth-a (inside the namespace) rather than veth-b (bridge side) has advantages:
- Works uniformly across all three network topologies
- Does not interfere with bridge forwarding logic
- Can be set per-node independently
- Rules are automatically cleaned up when the namespace is deleted

---

## Key Terminology

- **Jitter** — Variation in delay. Without jitter, every packet gets exactly the same delay (e.g., 100ms). With jitter, the delay varies randomly around the base value. `delay 100ms 20ms` means each packet gets a delay between ~80ms and ~120ms (normal distribution). Real networks always have some jitter — constant latency is unrealistic.

- **Correlation** — How much the current packet's random value depends on the previous packet's. `loss 10% 25%` means 10% base loss rate, but each packet's drop decision is 25% influenced by whether the previous packet was dropped. This creates **bursty** loss patterns (drops tend to cluster together), which is how real packet loss behaves — rather than perfectly uniform random loss.

- **Corruption** — Random bit-flipping in packet payloads. `corrupt 0.1%` means 0.1% of packets will have a random bit flipped. The packet still arrives (unlike loss), but with bad data — TCP checksums will catch this and trigger retransmission, while UDP applications may process garbage. This simulates hardware faults, electromagnetic interference, or faulty cables.

All three are standard `tc netem` parameters. Jitter and correlation are the most useful for RAFT testing since they stress election timeouts and heartbeat detection. Corruption is more niche but included for completeness.

---

## New Commands

### `delay` — Add latency

```bash
# Add 100ms latency to all traffic from node 1
./raft-cluster-netns.sh delay 1 100ms

# Add 100ms ± 20ms jitter to node 2
./raft-cluster-netns.sh delay 2 100ms 20ms

# Add latency to ALL nodes
./raft-cluster-netns.sh delay all 50ms

# Remove latency from node 1
./raft-cluster-netns.sh delay 1 reset
```

### `loss` — Add packet loss

```bash
# 5% packet loss on node 3
./raft-cluster-netns.sh loss 3 5%

# 10% loss with 25% correlation (bursty loss)
./raft-cluster-netns.sh loss 2 10% 25%

# Remove packet loss from node 3
./raft-cluster-netns.sh loss 3 reset
```

### `impair` — Combined impairment (latency + loss + more)

```bash
# Full control: 100ms delay, 20ms jitter, 2% loss, 0.1% corruption
./raft-cluster-netns.sh impair 1 --delay 100ms --jitter 20ms --loss 2% --corrupt 0.1%

# Asymmetric: different impairment per node
./raft-cluster-netns.sh impair 1 --delay 200ms --loss 5%
./raft-cluster-netns.sh impair 2 --delay 50ms
./raft-cluster-netns.sh impair 3 --delay 50ms

# Clear all impairments on a node
./raft-cluster-netns.sh impair 1 reset

# Clear all impairments on all nodes
./raft-cluster-netns.sh impair all reset
```

### `impair-status` — Show current impairments

```bash
./raft-cluster-netns.sh impair-status
# Output:
#   Node 1 (ha1a): delay 100ms jitter 20ms loss 2%
#   Node 2 (ha2a): delay 50ms
#   Node 3 (ha3a): no impairment
```

### Integration with existing `status` command

The existing `show_status` function should be extended to include impairment info alongside the partition status.

---

## Implementation Plan

### Phase 1: Core `tc`/`netem` Functions (new module)

Create **`lib/network-impairment.sh`** with the core functions:

```
lib/network-impairment.sh
├── check_netem_prerequisites()    # Verify tc, netem kernel module
├── apply_netem()                  # Apply netem qdisc to a node's veth-a
├── remove_netem()                 # Remove netem qdisc from a node's veth-a
├── get_netem_status()             # Query current netem settings on a node
├── show_impairment_status()       # Display impairment for all nodes
├── apply_delay()                  # Convenience: apply latency (+ optional jitter)
├── apply_loss()                   # Convenience: apply packet loss (+ optional correlation)
├── apply_combined_impairment()    # Apply multiple netem parameters at once
└── reset_impairment()             # Remove all impairments from one or all nodes
```

**Key implementation details:**

- `netem` is applied as a **queueing discipline** (qdisc) on the interface:
  ```bash
  # Inside the namespace:
  sudo ip netns exec ha1ns tc qdisc add dev ha1a root netem delay 100ms loss 5%
  ```
- To **modify** existing impairment, use `tc qdisc change` (not `add`):
  ```bash
  sudo ip netns exec ha1ns tc qdisc change dev ha1a root netem delay 200ms
  ```
- To **remove**, delete the qdisc:
  ```bash
  sudo ip netns exec ha1ns tc qdisc del dev ha1a root
  ```
- To **query** current state:
  ```bash
  sudo ip netns exec ha1ns tc qdisc show dev ha1a
  ```
- The functions should detect whether a netem qdisc already exists and use `change` vs `add` accordingly.

### Phase 2: CLI Integration

Extend `parse_args()` in `raft-cluster-netns.sh` to handle the new commands:

1. Add `delay`, `loss`, `impair`, `impair-status` to the command case statement
2. Parse the node ID (or `all`) and impairment parameters
3. Source `lib/network-impairment.sh` and call the appropriate function
4. Add new commands to `show_usage()` help text

New argument parsing needed:
- `delay <node|all> <time> [jitter]` or `delay <node> reset`
- `loss <node|all> <percent> [correlation]` or `loss <node> reset`
- `impair <node|all> [--delay T] [--jitter T] [--loss P] [--corrupt P] [--duplicate P] [--reorder P]` or `impair <node|all> reset`

### Phase 3: Status Integration

Extend the existing `show_status()` and `show_partition_status()` to also display active impairments:

```
  Network Impairment Status:
    Node 1 (ha1a): delay 100.0ms 20.0ms loss 2%
    Node 2 (ha2a): no impairment
    Node 3 (ha3a): delay 50.0ms
```

### Phase 4: Cleanup Integration

Ensure impairments are cleaned up properly:
- `heal` command should optionally clear impairments (add `--clear-impairments` flag, or always clear)
- `cleanup` command already deletes namespaces which removes all `tc` rules automatically
- `reset` sub-command for each impairment command provides explicit cleanup

### Phase 5: Configuration File Support

Add optional impairment defaults to the config file format:

```ini
# Network impairment defaults (applied on 'setup' if present)
default_delay=0ms
default_loss=0%

# Per-node impairment presets (applied on 'start' if present)
node_1_delay=100ms
node_1_jitter=20ms
node_1_loss=2%
node_2_delay=50ms
```

This is lower priority — the CLI commands are the primary interface.

### Phase 6: Predefined Scenarios (optional, nice-to-have)

Add named impairment presets for common test scenarios:

```bash
# Simulate WAN-like latency between all nodes
./raft-cluster-netns.sh impair-scenario wan

# Simulate high-latency satellite link on node 1
./raft-cluster-netns.sh impair-scenario satellite 1

# Simulate flaky network (intermittent loss)
./raft-cluster-netns.sh impair-scenario flaky
```

Predefined scenarios:
| Scenario    | Delay     | Jitter  | Loss  | Notes                        |
|-------------|-----------|---------|-------|------------------------------|
| `lan`       | 1ms       | 0.5ms   | 0%    | Baseline local network       |
| `wan`       | 50ms      | 10ms    | 0.1%  | Cross-datacenter             |
| `satellite` | 300ms     | 50ms    | 1%    | High-latency link            |
| `flaky`     | 20ms      | 50ms    | 5%    | Unreliable network           |
| `congested` | 100ms     | 100ms   | 2%    | Overloaded network path      |
| `lossy`     | 5ms       | 2ms     | 10%   | High packet loss             |

---

## File Changes Summary

| File | Change |
|------|--------|
| `lib/network-impairment.sh` | **New file** — core `tc`/`netem` functions |
| `raft-cluster-netns.sh` | Add `delay`, `loss`, `impair`, `impair-status` commands to `parse_args()`, source new module, update `show_usage()`, extend `show_status()` |
| `lib/common.sh` | Add `netem` to prerequisite checks (optional, since `tc` is part of `iproute2` already required) |
| `docs/network-impairment-plan.md` | This document |

---

## Prerequisites / Dependencies

- **`tc` command** — part of `iproute2`, which is already a prerequisite (provides `ip`)
- **`sch_netem` kernel module** — standard on all modern Linux kernels (loaded automatically when netem qdisc is used). Verify with: `modprobe sch_netem` or `lsmod | grep netem`
- No new external dependencies required

---

## Testing Strategy

1. **Unit-level**: Verify `tc qdisc` rules are correctly applied and removed per-node
2. **Functional**: Apply latency, measure with `ping` from within namespaces, verify RTT matches
3. **Integration**: Run RAFT cluster with impairment and verify election timeouts / leader changes behave as expected
4. **Cleanup**: Verify `cleanup` and `reset` properly remove all `tc` rules

Example validation test:
```bash
# Setup cluster
./raft-cluster-netns.sh setup

# Apply 200ms delay to node 1  
./raft-cluster-netns.sh delay 1 200ms

# Verify: ping from node 2 to node 1 should show ~200ms RTT
./raft-cluster-netns.sh exec 2 "ping -c 5 ha1.ha-cluster"

# Verify: ping from node 1 to node 2 should also show ~200ms RTT (delay on egress)
./raft-cluster-netns.sh exec 1 "ping -c 5 ha2.ha-cluster"

# Check status
./raft-cluster-netns.sh impair-status

# Reset
./raft-cluster-netns.sh delay 1 reset

# Verify: ping RTT back to < 1ms
./raft-cluster-netns.sh exec 2 "ping -c 3 ha1.ha-cluster"
```

---

## Interaction with Existing Features

| Existing Feature | Interaction |
|------------------|-------------|
| `isolate` / `partition` | Impairment and partition are **independent and composable**. A node can have both latency and be in a partition. When healed, only bridge connectivity is restored — impairment persists unless explicitly reset. |
| `heal` | Does NOT reset impairments by default (partitioning and impairment are separate concerns). Add `--clear-impairments` flag to optionally clear both. |
| `cleanup` | Namespace deletion automatically removes all `tc` rules — no special handling needed. |
| Network topologies | Works identically across simple, l3bgp, and tailf_hcc since `tc` is applied on the node-side veth inside the namespace. |

---

## Implementation Priority

1. **Phase 1** (core module) + **Phase 2** (CLI) — minimum viable feature
2. **Phase 3** (status) — important for usability
3. **Phase 4** (cleanup integration) — important for correctness
4. **Phase 5** (config file) — nice-to-have
5. **Phase 6** (scenarios) — nice-to-have
