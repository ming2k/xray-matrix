# Agent Directives

## 1. Operational Guardrails (Hard Constraints)
- **Zero Live Secrets in Commits**: NEVER commit live private keys, real UUIDs, actual server domains, or IP addresses. All templates in `schemes/` must use synthetic placeholder values (`[INV-SECRETS-ZERO-COMMIT]`).
- **Never Commit `*.local.json`**: Operator credentials reside exclusively in git-ignored `*.local.json` files.
- **Hook Enforcement**: Activate `.githooks/pre-commit` via `git config core.hooksPath .githooks`. Always run `sh .githooks/test-pre-commit.sh` after modifying the hook.
- **Command Termination**: All commands executed must be finite and self-terminating. Never start background servers or unbounded loops without a strict timeout.

## 2. Core Mental Model & Two-Layer Architecture
- **Two-Layer Anti-Overlap**: `schemes/` (what you run) and `host/` (where it runs) are strictly decoupled. Switching or adding transports touches only `schemes/<scheme>/` and leaves `host/` completely untouched (ADR-0001).
- **Scheme Datapath Isomorphism**: The shared datapath (`inbounds`, `dns`, `routing`, `policy`) must remain strictly identical across all scheme templates in `schemes/*` (`[INV-SCHEME-ISOMORPHISM]`).
- **Fail-Closed Datapath**: On daemon restart or crash, kernel tables and policy routes must remain intact (`[INV-FAIL-CLOSED]`). The service fails closed rather than leaking unencrypted traffic (ADR-0004).
- **Single-Owner Kernel Objects**: The policy rule (`fwmark 1 -> table 110`) belongs to the networkd drop-in; table `110` and nftables belong to `xray-tproxy.service`.
- **Local API Loopback Purity**: The administrative API (`127.0.0.1:10085`) must strictly listen on loopback, and its routing rule must remain the very first rule in `routing.rules` (`[INV-LOCAL-API-LOOPBACK]`).

## 3. Engineering Discipline
- **Mechanisms Over Exhortations**: Rely on kernel routing tables, nftables rules, unprivileged systemd sandboxes, and git pre-commit hooks to enforce constraints rather than natural-language warnings.
- **Anti-Inflation**: Only architectural red-lines with high blast radius qualify as `[INV-*]` system invariants.
- **Configuration Validation**: Always verify configuration integrity with `xray run -test -config <file>` before declaring changes complete.
- **Clean Epistemic Lineage**: All architectural decisions must resolve directly within `docs/adr/`.

## 4. On-Demand Standards Routing
Do not guess repository rules or rely on stale assumptions. Consult authoritative specifications in `docs/dev/standards/` as needed:
- Topology & Subsystem Boundaries: [`docs/dev/standards/architecture.md`](docs/dev/standards/architecture.md)
- Invariant & Constraint Policy: [`docs/dev/standards/invariants.md`](docs/dev/standards/invariants.md)
- ADR Authoring & Lifecycle: [`docs/dev/standards/adr.md`](docs/dev/standards/adr.md)
- RFC Deliberation & Proposals: [`docs/dev/standards/rfc.md`](docs/dev/standards/rfc.md)
- Documentation Taxonomy & Firewalls: [`docs/dev/standards/taxonomy.md`](docs/dev/standards/taxonomy.md)
- Markdown & Hyperlink Style: [`docs/dev/standards/style.md`](docs/dev/standards/style.md)
- Testing & Verification Gates: [`docs/dev/testing.md`](docs/dev/testing.md)
- Blameless Incident Postmortems: [`docs/dev/standards/postmortems.md`](docs/dev/standards/postmortems.md)
- Testing Strategy & Verification: [`docs/dev/testing.md`](docs/dev/testing.md)
- Architectural Decision Registry: [`docs/adr/index.md`](docs/adr/index.md)
