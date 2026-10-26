# Testing & Verification Runbook

This runbook documents the automated checks, configuration validation procedures, and diagnostic tools used to verify changes in `xray-matrix`.

---

## 1. Unified Automated Verification

The authoritative way to verify repository integrity is the top-level test suite:

```sh
sh scripts/verify_all.sh
```

This single runner mechanically executes:
1. **Documentation Link & Audience Firewall Verification** (`python3 scripts/check_doc_links.py`):
   - Confirms that every relative markdown link resolves to a valid target file on disk.
   - Verifies all heading anchors (`#fragment`) against GitHub's slug rules.
   - Enforces the audience firewall: blocks any link from public surfaces (`docs/{tutorials,how-to,reference,explanation}/`, `schemes/`, `host/`, `docs/index.md`) into internal maintainer spaces (`docs/dev/`, `docs/adr/`).
2. **ADR Lineage Integrity** (`python3 scripts/check_adr_lineage.py`):
   - Confirms that every `ADR-NNNN` citation across the codebase resolves to an existing file in `docs/adr/`.
3. **Commit Guard Regression Suite** (`sh .githooks/test-pre-commit.sh`):
   - Validates that git commit hooks refuse staged credentials, non-placeholder keys, real IP addresses, and `*.local.json` files.

---

## 2. Automated Commit Guard Setup

Activate the pre-commit hook once per clone:
```sh
git config core.hooksPath .githooks
```

Whenever `.githooks/pre-commit` or related regex rules are modified, run its automated regression test suite:
```sh
sh .githooks/test-pre-commit.sh
```
All 11 test cases must pass.

---

## 3. Configuration Validation Workflow

Because scheme templates in `schemes/` contain synthetic `<PLACEHOLDER:...>` tokens:
1. **Template Hygiene**: Validated mechanically by `.githooks/test-pre-commit.sh` to ensure no live secrets are committed.
2. **Local Deployment Validation**: When an operator copies a template to `*.local.json` and fills in genuine keys, test syntax before deployment:
   ```sh
   xray run -test -config schemes/vless-xtls-vision-reality/client.local.json
   xray run -test -config schemes/vless-xtls-vision-reality/server.local.json
   ```

---

## 4. Local Datapath & Kernel Verification

When validating datapath modifications on a live Linux workstation or gateway:

1. **Verify Systemd Service**:
   ```sh
   systemctl status xray-tproxy.service
   ```
2. **Verify Policy Routing Rules**:
   ```sh
   ip rule show | grep 110
   # Expected: fwmark 0x1 lookup 110
   ip route show table 110
   # Expected: local default dev lo scope host
   ```
3. **Verify nftables Interception**:
   ```sh
   sudo nft list table inet xray_v4
   sudo nft list table inet xray_v6
   ```
4. **End-to-End Leak Test**:
   ```sh
   curl -I https://www.google.com
   curl https://api.ipify.org
   ```
