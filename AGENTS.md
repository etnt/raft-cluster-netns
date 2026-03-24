# Agent Instructions for raft-cluster-netns

## Project Overview

This project provides a complete solution for setting up isolated virtual network
environments for **NSO RAFT cluster testing** using Linux network namespaces. The
main entry point is `raft-cluster-netns.sh`, which orchestrates network creation,
NSO node setup, SSL certificates, and network partition/impairment simulation.

## Repository Structure

```
raft-cluster-netns.sh       # Main entry point — modular command dispatcher
setup-ssl-certs.sh          # SSL certificate generation for Erlang-over-TLS
lib/
  common.sh                 # Core utilities: logging, validation, command execution, cleanup
  network-simple.sh         # Basic bridge network topology
  network-l3bgp.sh          # L3 BGP topology with FRR Zebra + GoBGP
  network-tailf_hcc.sh      # HCC-specific BGP configuration extension
  network-impairment.sh     # Network failure simulation (latency, jitter, packet loss)
docs/                       # Design documents, implementation plans, examples
test/                       # Integration and unit tests
packages/foo/               # NSO package for load-generation testing
misc/                       # Supplementary/experimental scripts
```

## Shell Scripting Conventions

All shell scripts in this project **must** follow these conventions:

- **Strict mode**: Every script starts with `set -euo pipefail`
- **Functions**: Use descriptive `snake_case` names grouped by operation category
  (`setup_*`, `cleanup_*`, `create_*`, `test_*`, `get_*`)
- **Global variables**: `UPPERCASE` names (e.g., `NODES`, `PREFIX`, `WORK_DIR`)
- **Local variables**: Declared with `local` keyword, lowercase names
- **Quoting**: Always double-quote variables: `"$variable"`, `"${array[@]}"`
- **Logging**: Use the logging functions from `lib/common.sh`:
  - `log_info` — informational (green)
  - `log_warn` — warnings (yellow, stderr)
  - `log_error` — errors (red, stderr)
  - `log_debug` — debug output (blue, only when `VERBOSE=true`)
- **Command execution**: Use `execute_cmd` wrapper for operations that should
  respect `DRY_RUN` mode and verbose logging
- **Documentation**: Include a header block in each script/module explaining
  purpose, functions provided, and globals used

## Security Requirements

- **Parameter validation**: `PREFIX` must match `[a-zA-Z0-9_-]` only — no `..` or `/`
- **Privileged operations**: Use explicit `sudo` commands; never assume root
- **No path traversal**: Validate user-supplied paths before use
- **No `eval`**: Do not use `eval` on user-supplied input

## Modular Architecture

The project uses a modular topology-plugin design:

- `lib/common.sh` — Shared foundation sourced by all other modules
- `lib/network-*.sh` — Each file implements a network topology with a consistent
  interface: `setup_*_network()`, `cleanup_*_network()`, etc.
- New network topologies should follow the same pattern and be added as a new
  `lib/network-<name>.sh` module

Do **not** add new top-level scripts. Extend existing modules or add new library
files under `lib/`.

## Testing

- Tests live in `test/` and follow the same shell conventions
- Integration tests should: validate prerequisites, set up, run assertions, and
  clean up — even on failure
- Test filenames: `test-<feature>.sh` or `test_<feature>.sh`

## Git Workflow

- **License**: Apache 2.0
- **Sign-off required**: Every commit must be signed off (`git commit -s`) by the
  contributor certifying they have the right to submit it
- **Branches**: Feature branches off `main` (e.g., `l3bgp-setup`,
  `latency-and-packet-loss`)
- Keep commits focused — one logical change per commit
