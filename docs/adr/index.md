# Architectural Decision Records (ADR)

This registry records the authoritative architectural decisions, non-negotiable system invariants, and historical trade-offs for `xray-matrix`.

Every record is evaluated against the 3-Question Test defined in [ADR Standards](../dev/standards/adr.md) and maintained in-place with YAML frontmatter.

---

## Architectural Decision Registry

| ID | Title | Status | Scope | Ratified Invariants |
| :--- | :--- | :--- | :--- | :--- |
| **[ADR-0001](0001-two-layer-scheme-host-decoupling.md)** | Two-Layer Scheme and Host OS Decoupling | `accepted` | `schemes`, `host` | `[INV-SCHEME-ISOMORPHISM]` |
| **[ADR-0002](0002-tproxy-policy-routing-over-tun.md)** | TProxy and Policy Routing over TUN/Redirect | `accepted` | `host/client` | `[INV-FAIL-CLOSED]` |
| **[ADR-0003](0003-real-ip-smart-dns-split-over-fakeip.md)** | Real-IP Smart DNS Split over FakeIP | `accepted` | `host/client`, `schemes` | `[INV-REAL-IP-NO-FAKEIP]` |
| **[ADR-0004](0004-fail-closed-nftables-resilience.md)** | Fail-Closed Kernel nftables and Route Resilience | `accepted` | `host/client` | `[INV-FAIL-CLOSED]` |
| **[ADR-0005](0005-reality-and-web-fallback-anti-probing.md)** | Active Probing Camouflage: REALITY and TLS Web Fallback | `accepted` | `schemes`, `host/server` | `[INV-LOCAL-API-LOOPBACK]` |
| **[ADR-0006](0006-port-443-ownership-l4-demux.md)** | Port 443 Ownership on Hosts That Already Serve Websites | `accepted` | `host/server`, `schemes` | `[INV-443-SINGLE-OWNER]`, `[INV-CAMOUFLAGE-NO-LOCAL-CERT]` |

---

## Decision Lifecycle

ADRs follow an in-place lifecycle:
- `draft`: Under review and active deliberation.
- `accepted`: Formally ratified and binding on the repository.
- `superseded`: Replaced by a newer decision record (`superseded_by: ADR-NNNN`).
- `rejected`: Discarded proposal preserved for negative knowledge and auditing.
