# Documentation Taxonomy & Layout

This document defines the organization, scope boundaries, and classification of all documentation assets in the `xray-matrix` repository.

---

## 1. The Four-Quadrant System (Diátaxis)

Public documentation in `docs/` strictly follows the Diátaxis architecture:

```text
               PRACTICAL                   THEORETICAL
          ┌─────────────────────────┬─────────────────────────┐
          │  Tutorials              │  How-To Guides          │
LEARNING  │  (Learning-Oriented)    │  (Task-Oriented)        │
          │  `docs/tutorials/`      │  `docs/how-to/`         │
          ├─────────────────────────┼─────────────────────────┤
          │  Reference              │  Explanation            │
WORKING   │  (Information-Oriented) │  (Understanding-Orient) │
          │  `docs/reference/`      │  `docs/explanation/`    │
          └─────────────────────────┴─────────────────────────┘
```

- **`docs/tutorials/`**: Guided walk-throughs taking a new operator or developer through their very first end-to-end deployment (e.g., deploying your first TProxy client and VPS server).
- **`docs/how-to/`**: Step-by-step problem-solving recipes for specific operator tasks (e.g., configuring TLS fallback with Nginx, troubleshooting connectivity, captive portal login).
- **`docs/reference/`**: Technical descriptions of configurations, nftables tables, systemd flags, and placeholders without narrative prose.
- **`docs/explanation/`**: Architectural deep dives, design rationale, packet lifecycles, and cryptographic background discussions (e.g., XTLS-Vision, REALITY target selection, Real-IP DNS).

---

## 2. Scope Boundaries (Public vs. Internal Firewall)

To maintain clarity for users while preserving thorough internal documentation for core maintainers, `xray-matrix` enforces a strict audience firewall:

```text
┌─────────────────────────────────────────────────────────────┐
│ Public Surface (Operators, Deployers, Users)                │
│ `docs/tutorials/`, `how-to/`, `reference/`, `explanation/`  │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               │ Scope Boundary: Public docs must
                               │ NEVER link to internal docs.
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Internal Surface (Maintainers, Core Contributors, Agents)   │
│ `docs/dev/` (internals, standards, testing runbooks)        │
│ `docs/adr/` (binding architectural decision records)        │
└─────────────────────────────────────────────────────────────┘
```

1. **Firewall Rule**: Public documentation surfaces (`docs/{tutorials,how-to,reference,explanation}/` and `docs/index.md`) must NEVER contain relative links pointing into internal maintainer spaces (`docs/dev/**` or `docs/adr/**`).
2. **Reverse Linking Permitted**: Internal documents in `docs/dev/` and `docs/adr/` may freely link to public reference, how-to, and explanation guides.

---

## 3. Subdirectory Index Mandate

Every subdirectory under `docs/` must provide an authoritative `index.md` serving as the curated catalog for that quadrant or domain:
- `docs/tutorials/index.md`
- `docs/how-to/index.md`
- `docs/reference/index.md`
- `docs/explanation/index.md`
- `docs/adr/index.md`
- `docs/dev/index.md`

---

## 4. Repository Root Whitelist

To keep the repository root clean, professional, and clutter-free, only canonical top-level documentation files are permitted at the root:
- `README.md` (and optional language variants like `README-zh.md`)
- `CHANGELOG.md`
- `CONTRIBUTING.md`
- `AGENTS.md`
- `LICENSE`

All other documentation and architecture governance must reside within `docs/`.
