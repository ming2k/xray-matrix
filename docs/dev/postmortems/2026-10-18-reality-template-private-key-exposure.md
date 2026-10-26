# Postmortem: 2026-10-18 REALITY Template Private Key Exposure

## Executive Summary
During a configuration template commit, a live REALITY curve25519 private key was accidentally embedded inside a `<PRIVATE_KEY:...>` template placeholder in `schemes/vless-xtls-vision-reality/server.json`. Because git history is immutable, the private key remained visible in commit logs. The server keypair was immediately rotated on the live host, preventing active man-in-the-middle compromise. A mechanical pre-commit hook was built to prevent any repetition.

---

## Timeline of Events (UTC)

- **2026-10-18 10:15**: Maintainer committed changes to `server.json` intending to provide an example placeholder, but mistakenly pasted an active private key generated during host setup.
- **2026-10-18 10:45**: Routine code inspection identified that the placeholder string matched the base64 character length and format of an authentic curve25519 secret key.
- **2026-10-18 11:00**: Mitigation: The VPS host was immediately reconfigured with a newly generated keypair (`xray x25519`), revoking the exposed key.
- **2026-10-18 14:30**: Resolution: An automated pre-commit hook (`.githooks/pre-commit`) and regression test suite (`.githooks/test-pre-commit.sh`) were developed to scan staged files for authentic base64 keys and unredacted secrets.

---

## Detection Gaps
1. **Absence of Pre-Commit Inspection**: The repository relied on manual developer vigilance rather than an automated git commit guard.
2. **False Confidence in Placeholder Wrappers**: Placing a secret inside `<PLACEHOLDER:...>` did not prevent the underlying secret from being valid and usable.

---

## Trigger & Underlying Root Cause
The developer intended to illustrate where the private key belongs by showing an example. In the absence of an automated secret scanner, the boundary between an illustrative synthetic placeholder and a live key was unenforced.

---

## Action Items & Defense-in-Depth

| Action Item | Type | Status | Verification |
| :--- | :--- | :--- | :--- |
| Rotate production VPS keypair | Preventative | Completed | Live host verification |
| Implement `.githooks/pre-commit` | Mechanical Guard | Completed | Blocks commits with valid base64 keys |
| Implement `.githooks/test-pre-commit.sh` | Regression Test | Completed | 11 automated test cases passing |
| Ratify `[INV-SECRETS-ZERO-COMMIT]` | Standard | Completed | Enshrined in `docs/dev/standards/invariants.md` |
