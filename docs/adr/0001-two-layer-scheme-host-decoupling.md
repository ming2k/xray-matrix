---
id: ADR-0001
title: "Two-Layer Scheme and Host OS Decoupling"
status: accepted
date: 2026-10-26
scope: [schemes, host]
superseded_by: null
invariants: ["[INV-SCHEME-ISOMORPHISM]"]
---

# ADR-0001: Two-Layer Scheme and Host OS Decoupling

## Context & Problem Statement
In typical proxy setups, transport configurations (VLESS, REALITY, TLS) and operating system artifacts (systemd service units, nftables scripts, sysctl tunings) are tightly coupled or generated on-the-fly through complex templates and helper scripts. This introduces fragile templating engines, hidden environment dependencies, and confusing multi-role directory structures.

We require a clean architectural separation that allows transport protocols to be selected or switched without modifying system integration scripts, and system integrations to be maintained without touching transport configs.

## Decision Drivers
- Zero templating engines or opaque generation scripts.
- Ability to switch transports by copying a single directory without altering OS-level unit files or firewall rules.
- Maintain identical shared datapath semantics across all deployment choices.

## Considered Options
1. **Monolithic Role Hierarchy (`client/` and `server/` at root)**: Grouping everything by machine role.
2. **Template-Driven Dynamic Generator**: A CLI or Bash script that compiles jinja/mustache templates into final configs.
3. **Two-Layer Static Separation (`schemes/` vs. `host/`)**: Complete separation between "what you run" and "where it runs".

## Decision Outcome
Chosen option: **Option 3: Two-Layer Static Separation**.

- **`schemes/` (What you run)**: Each transport scheme lives in a self-contained directory containing the complete client configuration (`client.json`), server configuration (`server.json`), and dedicated documentation (`README.md`).
- **`host/` (Where it runs)**: All OS-level artifacts (nftables rulesets, systemd units, sysusers accounts, networkd drop-ins, and kernel tuning) reside exclusively in `host/client/` and `host/server/`.

### Ratified Invariants
- `[INV-SCHEME-ISOMORPHISM]`: Across all schemes under `schemes/`, the shared datapath (TProxy port, DNS resolution, policy routing, bypass rules) must be identical. Switching transport schemes touches only `schemes/` and leaves `host/` unchanged.

## Negative Knowledge & Discarded Alternatives
- **Why not Monolithic Role Hierarchy?** Grouping by `client/` and `server/` conflates OS integration with transport protocol definitions, making it impossible to support multiple transport schemes cleanly without copying firewall rules and service definitions.
- **Why not Template Generators?** Template generators introduce runtime dependencies (Python, Bash templating), hide the concrete Xray JSON structure, and make manual inspection and debugging difficult.
