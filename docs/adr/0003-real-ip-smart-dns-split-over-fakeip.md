---
id: ADR-0003
title: "Real-IP Smart DNS Split over FakeIP"
status: accepted
date: 2026-10-26
scope: [host/client, schemes]
superseded_by: null
invariants: ["[INV-REAL-IP-NO-FAKEIP]"]
---

# ADR-0003: Real-IP Smart DNS Split over FakeIP

## Context & Problem Statement
Transparent proxies often struggle with DNS pollution and poisoning. Two prominent architectural strategies exist to bypass poisoned DNS:
1. **FakeIP (Synthetic IP Mapping)**: Responding immediately to all client DNS queries with a synthetic IP from a reserved range (e.g., `198.18.0.0/15`), while mapping the synthetic IP to the actual domain in a userspace table.
2. **Real-IP Smart DNS Split**: Resolving genuine, authentic destination IPs via encrypted DNS (DoH) while bypassing local DNS (port 53) to the physical gateway.

We must choose an architecture that ensures compatibility with local networks, captive portals, raw IP connections, and debugging utilities.

## Decision Drivers
- Avoid IP pool exhaustion and desynchronization in synthetic IP tables.
- Seamless compatibility with captive portal networks and DHCP option 121 / 249 static routes.
- Accurate behavior of diagnostic tools (`traceroute`, `ping`, direct IP socket bindings).
- Anti-leak protection against public DNS poisoning.

## Considered Options
1. **FakeIP Architecture**: Intercept port 53 and hand out `198.18.x.x` addresses.
2. **Real-IP Split DNS Architecture**: Bypass local port 53; resolve remote queries via DoH in Xray.

## Decision Outcome
Chosen option: **Option 2: Real-IP Smart DNS Split**.

- **Local Port 53 Direct**: Traditional UDP/TCP port 53 queries are explicitly exempted from TProxy interception in nftables. They flow directly to the local DHCP-assigned gateway.
- **DoH Proxy DNS**: For traffic handled by Xray, domain resolution is carried out through encrypted DNS-over-HTTPS (`https://1.1.1.1/dns-query`) using authentic upstream resolvers.
- **Sniffing and Real Destination**: Xray sniffs TLS SNI and HTTP Host headers directly from the intercepted stream. If a domain matches proxy routing rules, it routes remotely; if direct, it uses the authentic IP.

### Ratified Invariants
- `[INV-REAL-IP-NO-FAKEIP]`: Client networking stacks always operate on genuine, globally routable destination IPs. FakeIP address translation pools are prohibited across all configurations.

## Negative Knowledge & Discarded Alternatives
- **Why not FakeIP?** FakeIP causes severe issues when applications cache IPs across proxy restarts, breaks captive portal detection mechanisms, makes IP-based firewalling on the LAN impossible, and confuses network diagnostics by masquerading all destinations under the synthetic `198.18.0.0/15` subnet.
