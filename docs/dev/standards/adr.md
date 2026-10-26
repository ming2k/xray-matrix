# Architectural Decision Records (ADR) Standards

This document establishes the qualification criteria, lifecycle progression, frontmatter schema, and canonical template for Architectural Decision Records (ADRs) in `xray-matrix`.

---

## 1. Intent & Qualification (The 3-Question Test)

To prevent ADR inflation and maintain a high-signal log, author an ADR only if a proposal meets **at least two** of these criteria:

1. **High Reversal Cost**: Would reversing this decision require multi-host reconfigurations, extensive kernel firewall rewrites, or breaking changes to network datapath behavior?
2. **Cross-Boundary Blast Radius**: Does it alter the boundary between `schemes/` and `host/`, modify kernel table allocations, change DNS resolution topology, or impact client/server contracts?
3. **Generates Binding Red-Lines**: Does it establish hard structural invariants (`[INV-*]`) that all contributors and automation agents must adhere to?

### Anti-Patterns to Reject
- **The Triviality Smear**: Authoring ADRs for routine configuration edits (e.g., adding a domain to direct routing or bumping a buffer size).
- **The Ephemeral Workaround**: Recording temporary distro-specific package quirks or transient network debugging steps.
- **The Toothless Declaration**: Recording natural-language aspirations that lack automated enforcement mechanisms.

---

## 2. In-Place Lifecycle & Frontmatter Schema

ADRs evolve strictly in-place through YAML frontmatter transitions. Files are never physically moved to an `archive/` directory:

```text
       [ draft ] ───► [ accepted ] ───► [ superseded ]
           │
           └───► [ rejected ]
```

- **`draft`**: Proposal under active evaluation.
- **`accepted`**: Ratified invariant or architectural contract binding on the repository.
- **`superseded`**: Formally replaced by a subsequent ADR (`superseded_by: ADR-NNNN`).
- **`rejected`**: Discarded alternative preserved in-place for negative knowledge audit.

### Frontmatter Schema
```yaml
---
id: ADR-NNNN
title: "[Title of Decision]"
status: accepted # [draft | accepted | superseded | rejected]
date: YYYY-MM-DD
scope: [subsystems affected, e.g. host/client, schemes/vless-xtls-vision-reality]
superseded_by: null # e.g., ADR-0004 (mandatory when status is superseded)
invariants: ["[INV-FAIL-CLOSED]"] # list of ratified invariants, if any
---
```

---

## 3. Canonical ADR Template

```markdown
---
id: ADR-NNNN
title: "Canonical Title"
status: accepted
date: YYYY-MM-DD
scope: [host/client, schemes]
superseded_by: null
invariants: ["[INV-NAME]"]
---

# ADR-NNNN: Canonical Title

## Context & Problem Statement
What problem are we solving? What are the network, kernel, or censorship constraints?

## Decision Drivers
- High throughput and zero-copy performance.
- Leak prevention across process failure.
- Minimal operational burden for multi-host deployments.

## Considered Options
1. Option A (e.g., TUN device)
2. Option B (e.g., TProxy + policy routing)

## Decision Outcome
Chosen option: Option B, because...

### Ratified Invariants & Contracts
- `[INV-NAME]`: Description of the non-negotiable rule.
- Enforcement mechanism: The concrete test or kernel state enforcing this.

## Negative Knowledge & Discarded Alternatives
Why were the other options rejected? What failure modes or trade-offs made them unsuitable?
```
