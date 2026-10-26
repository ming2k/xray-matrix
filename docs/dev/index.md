# Contributor & Maintainer Documentation

This directory contains internal documentation for developers, system maintainers, and automation agents contributing to `xray-matrix`. 

Public user-facing documentation lives under `docs/tutorials/`, `docs/how-to/`, `docs/reference/`, and `docs/explanation/`; per the [Taxonomy Standard](standards/taxonomy.md), public documents must never link into this directory.

---

## Developer Governance & Standards

| Page | Purpose & Authority |
| :--- | :--- |
| **[Engineering Standards](standards/taxonomy.md)** | Authoritative suite defining topology, invariants, ADRs, style, and PR gates: [taxonomy](standards/taxonomy.md), [architecture](standards/architecture.md), [invariants](standards/invariants.md), [ADR authoring](standards/adr.md), [style](standards/style.md), [postmortems](standards/postmortems.md), [RFC](standards/rfc.md). |
| **[Project Layout](project-layout.md)** | Repository tree map, physical asset boundaries, and file routing rules. |
| **[Testing & Verification Runbook](testing.md)** | Automated commit hooks, configuration verification, and diagnostic workflows. |
| **[Incident Postmortems](postmortems/2026-10-18-reality-template-private-key-exposure.md)** | Blameless incident analyses, detection gaps, and defense-in-depth mitigations. Later: [2026-10-26 transparent proxy restart loop](postmortems/2026-10-26-tproxy-start-verification-loop.md), [2026-10-26 unreachable egress node](postmortems/2026-10-26-bwg-jp-ip-blackhole.md). |
| **[Architectural Decision Records (ADRs)](../adr/index.md)** | Binding decision registry, historical trade-offs, and negative knowledge. |

---

## Operational Notes for Contributors

- **Automated Commit Guard**: Activate the pre-commit guard once per clone with:
  ```sh
  git config core.hooksPath .githooks
  ```
  It inspects staged changes and mechanically refuses commits that contain live credentials or unexpanded placeholder values. Test the hook with `sh .githooks/test-pre-commit.sh`.
- **Configuration Validation**: All changes to template JSON files in `schemes/` must pass validation with `xray run -test -config <file>`.
- **Fail-Closed Datapath**: The transparent proxy service intentionally leaves policy routing rules and routing tables intact upon service crash to prevent unproxied plaintext leaks. See [ADR-0004](../adr/0004-fail-closed-nftables-resilience.md).
