# Request for Comments (RFC) Standards

This document defines the process for authoring, reviewing, and ratifying Request for Comments (RFC) proposals in `xray-matrix`.

---

## 1. When to Author an RFC

While an **ADR** records an accepted architectural decision and its binding invariants, an **RFC** is an upfront exploratory proposal used during early deliberation when:
- The problem space has multiple competing solutions with divergent networking trade-offs.
- The proposed change alters cross-layer boundaries (e.g., refactoring the nftables packet capture hook, changing the TProxy port contract, or introducing a new transport paradigm).
- Consensus across operators and maintainers is required before writing deployment artifacts.

---

## 2. RFC Lifecycle

```text
  [ Proposed ] ──► [ Under Review ] ──► [ Approved ] ──► [ Migrated to ADR ]
                          │
                          └──► [ Closed / Withdrawn ]
```

1. **Proposed**: Draft RFC submitted for peer review.
2. **Under Review**: Active review period with architectural deliberation.
3. **Approved**: Consensus achieved; implementation may proceed.
4. **Migrated to ADR**: Once the implementation lands and is verified in code, the RFC conclusions are synthesized into a permanent Architectural Decision Record (`docs/adr/`).
5. **Closed / Withdrawn**: Proposal rejected or superseded prior to implementation.

---

## 3. RFC Structure

An effective RFC must address:

1. **Motivation & Threat Model**: What network censorship, routing, or deployment problem requires this change?
2. **Detailed Design**: Precise packet flows, kernel table allocations, Xray JSON schemas, and systemd service changes.
3. **Failure Modes & Leak Analysis**: How does the system behave during process crash, network interface flap, or captive portal interception?
4. **Migration & Deployment**: How do existing live hosts upgrade without connection drops or plaintext leakage?
5. **Unresolved Questions**: Known unknowns and trade-offs explicitly listed for feedback.
