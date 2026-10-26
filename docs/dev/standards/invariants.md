# Invariant & Constraint Governance

This document codifies the definition, categorization, and mechanical lifecycle of invariants within `xray-matrix`. It establishes an uncompromising policy: invariants must be high-signal architectural anchors backed by automated enforcement mechanisms, not empty natural-language exhortations.

---

## 1. Core Principle: Mechanisms Over Exhortations

In production network architecture, an invariant is a state condition that unconditionally holds across all operational phases (startup, runtime, crash, reboot). 

**The Golden Rule**:
> **If a rule has neither a kernel-level enforcement mechanism, a git hook check, nor an automated validation command, it is NOT an invariant — it is merely an aspiration.**

---

## 2. Constraint Admissibility Matrix

Every operational and structural rule in `xray-matrix` maps deterministically into one of four categories:

| Category | Definition & Scope | Identifier Policy | Mandatory Enforcement Mechanism |
| :--- | :--- | :--- | :--- |
| **System Invariant** | Non-negotiable structural red-lines with high security/reliability blast radius (e.g. credential leakage, unproxied data leak, admin API exposure). | Formally ratified in ADRs and this standard (`[INV-*]`). | 1. Kernel packet dropping / nftables state.<br>2. Automated git commit hooks (`.githooks/pre-commit`).<br>3. Automated config validation (`xray run -test`). |
| **Domain Contract** | Structural rules within a specific layer (e.g. scheme configuration JSON schema, networkd drop-in format). | Named contract rules without `INV-` prefix. | JSON schema parser, systemd-analyze verify. |
| **Operational Specification** | System tuning values (sysctl buffer sizes, BBR parameters), suggested timeouts. | Documented constants in `host/`. | Sysctl assertions, benchmark scripts. |
| **Implementation Note** | Transient workarounds, distro-specific package paths. | Standard inline comments. | Explicit inline doc comments. |

---

## 3. Ratified System Invariants

### `[INV-FAIL-CLOSED]` Fail-Closed Leak Prevention
- **Definition**: If the Xray transparent proxy process crashes, terminates, or fails to start, unproxied client plaintext traffic must NEVER bypass the proxy and leak to the WAN.
- **Enforcement Mechanism**:
  1. Policy routing rule (`fwmark 1 lookup 110`) and local routing entry (`ip route add local default dev lo table 110`) remain active in the kernel across unit restarts.
  2. With no process listening on TProxy port `12345`, the kernel drops all intercepted traffic with TCP RST / ICMP unreachable rather than falling back to table `main`.

### `[INV-SECRETS-ZERO-COMMIT]` Zero Credential Leakage
- **Definition**: Production credentials (UUIDs, REALITY private keys, domain names, server IP addresses) must NEVER be committed to version control.
- **Enforcement Mechanism**:
  1. All tracked templates in `schemes/` use clearly invalid synthetic placeholders (e.g., `00000000-0000-0000-0000-000000000000`, `<REALITY_PRIVATE_KEY:…>`).
  2. Live credentials reside exclusively in `*.local.json`, which is covered by `.gitignore`.
  3. Git pre-commit hook (`.githooks/pre-commit`) programmatically scans staged files and blocks any commit containing real keys or unexpanded placeholders. Verified by `.githooks/test-pre-commit.sh`.

### `[INV-LOCAL-API-LOOPBACK]` Local API Isolation
- **Definition**: The Xray local administrative management API (`127.0.0.1:10085`) must never listen on non-loopback interfaces or accept off-host packets.
- **Enforcement Mechanism**:
  1. `inbounds` configuration strictly binds to `127.0.0.1`.
  2. `routing.rules` enforces that inboundTag `api` routes directly to outboundTag `api` as the highest priority rule.
  3. nftables explicitly drops incoming off-host traffic destined for the API port.

### `[INV-SCHEME-ISOMORPHISM]` Multi-Scheme Datapath Isomorphism
- **Definition**: All transport schemes must maintain identical shared datapath semantics (TProxy port, DNS routing, direct/proxy routing rules, sniffing logic).
- **Enforcement Mechanism**:
  1. Differences between schemes are restricted to transport inbound/outbound blocks.
  2. Automated test command `xray run -test -config <file>` executed across all schemes on any configuration update.

### `[INV-REAL-IP-NO-FAKEIP]` Real-IP Integrity
- **Definition**: Client networking stacks must receive authentic, unpolluted destination IP addresses via DoH, avoiding FakeIP address translation anomalies.
- **Enforcement Mechanism**:
  1. Port 53 direct bypass in nftables for local gateway discovery.
  2. Encrypted DoH outbound (`1.1.1.1`) managed through Xray's internal DNS module with strict domain matching.
