# Incident Postmortem Standards

This document establishes the blameless postmortem standard, timeline reconstruction methodology, and defense-in-depth analysis for security and availability incidents in `xray-matrix`.

---

## 1. Blameless Culture & Intent

Network security incidents (credential leaks, plaintext traffic drops, active probing exposure) are opportunities to identify systemic fragility and testing gaps.
- **Strictly Blameless**: Postmortems must NEVER assign personal blame or attribute root causes to "human error".
- **Focus on Automated Safeguards**: The central question is always: *Why did the automated commit hooks, test suite, or systemd sandboxing allow an unsafe state to manifest?*

---

## 2. Postmortem Directory & Structure

Every postmortem recorded in `docs/dev/postmortems/` must follow this schema:

1. **Executive Summary**: High-level impact (credential exposure, potential blast radius, revocation status).
2. **Timeline of Events (UTC)**:
   - $T_0$: Introduction of defect (e.g. commit containing unredacted secret).
   - $T_{\text{impact}}$: First potential exposure in public git log.
   - $T_{\text{detect}}$: Detection by maintainer review or security scan.
   - $T_{\text{mitigate}}$: Key revocation, upstream key rollover, or firewall patch applied.
   - $T_{\text{resolve}}$: Mechanical defense (e.g. pre-commit git hook) merged and verified.
3. **Detection Gaps**: Why did git commit guards, linters, or review checklists fail to detect this before pushing?
4. **Trigger & Underlying Root Cause**: Detailed technical analysis of the failure.
5. **Action Items & Defense-in-Depth**:
   - Preventative actions (e.g., adding automated regex blocks to `.githooks/pre-commit`).
   - Automated regression test cases in `.githooks/test-pre-commit.sh`.
   - Documentation updates in `[INV-SECRETS-ZERO-COMMIT]`.
