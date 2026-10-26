# System Architecture Governance

This document codifies the workspace topology, subsystem boundaries, and non-negotiable architectural red-lines of `xray-matrix`.

---

## 1. Two-Layer Decoupled Topology

The repository is structured into two fundamental layers that never overlap:

```text
┌────────────────────────────────────────────────────────────────────────┐
│  Layer 1: Schemes (`schemes/`) — What You Run                          │
│  - Self-contained, deployable transport configurations.                │
│  - Exactly one directory per transport scheme:                         │
│    ├── `vless-xtls-vision-reality/` (Zero-domain, borrowed TLS SNI)    │
│    └── `vless-xtls-vision-tls/`     (Domain certificate + Web Fallback)│
│  - Contains `client.json` (TProxy outbound) and `server.json` (inbound)│
│  - Operator copies (`*.local.json`) git-ignored and never committed.   │
├────────────────────────────────────────────────────────────────────────┤
│  Layer 2: Host OS Integrations (`host/`) — Where It Runs               │
│  - Generic Linux system-level artifacts, identical across all schemes. │
│  - `host/client/`: Transparent Proxy (TProxy) on Linux workstations:   │
│    ├── `xray-tproxy.service` (Self-contained lifecycle, setup & clean teardown) │
│    ├── `xray-tproxy.nft`     (Self-cleaning nftables tables: xray_v4, xray_v6)   │
│    └── `xray-tproxy.sysusers.conf` (Unprivileged user allocation)      │
│  - `host/server/`: VPS egress node hardening:                          │
│    ├── `xray-server.service` (Sandboxed systemd unit)                  │
│    ├── `xray-server.nft`     (Minimal stateful ingress firewall)       │
│    ├── `99-xray-tuning.conf` (BBR, TCP Fast Open, 64MB buffers)        │
│    └── `fallback/{nginx,caddy}/` (Local disguise web server)           │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Architectural Red-Lines

### 2.1 Two-Layer Anti-Overlap Rule
- **Red-Line**: Adding, updating, or removing a transport scheme must NEVER alter any file under `host/`.
- Changing transport protocols touches exactly one directory under `schemes/<scheme>/`.
- Systemd units, nftables tables, policy routing rules, sysctl parameters, and web fallback services exist exactly once under `host/`.

### 2.2 Scheme Datapath Isomorphism
- **Red-Line**: Across all schemes in `schemes/*`, the non-transport blocks (`inbounds` on client, `outbounds` on server, `dns`, `routing`, `policy`) must remain strictly identical.
- A scheme directory may only differ from its siblings in the specific outbound (client) and inbound (server) transport parameters.
- Any change to the shared datapath (e.g., DNS resolver, routing rules order) must be applied symmetrically to every scheme.

### 2.3 Single-Owner Kernel Object Rule
- **Red-Line**: Every Linux kernel object (nftables table, policy routing rule, routing table entry) must have exactly one authoritative owner.
- The `fwmark 1 -> table 110` policy routing rule, the `local default dev lo table 110` route, and the nftables tables (`xray_v4`, `xray_v6`) belong exclusively to `xray-tproxy.service`.
- The service unit asserts and ensures the rules and routes on start, and cleanly tears them down on stop (`RemainAfterExit=no`) to restore direct networking without relying on external network managers.

### 2.4 Local API Isolation
- **Red-Line**: The Xray Local API inbound (`127.0.0.1:10085`) is an administrative attack surface.
- It must NEVER be bound to any address other than loopback (`127.0.0.1`).
- Its routing rule must remain the very first rule in `routing.rules` to prevent traffic hijacking.

### 2.5 Real-IP Split DNS Architecture
- **Red-Line**: DNS resolution for clients must resolve authentic, unpolluted IPs via encrypted DoH (`https://1.1.1.1/dns-query`).
- The architecture strictly rejects FakeIP (`198.18.0.0/15`) to prevent subnet anomalies, routing table pollution, and broken LAN connectivity.
- Local port 53 traffic remains direct to allow local DHCP/router resolution and captive portal detection.
