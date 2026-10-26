---
id: ADR-0005
title: "Active Probing Camouflage: REALITY and TLS Web Fallback"
status: accepted
date: 2026-10-26
scope: [schemes, host/server]
superseded_by: null
invariants: ["[INV-LOCAL-API-LOOPBACK]"]
---

# ADR-0005: Active Probing Camouflage: REALITY and TLS Web Fallback

## Context & Problem Statement
Modern nation-state firewalls deploy sophisticated active probing infrastructure. When an outbound encrypted connection is detected, automated scanners immediately initiate follow-up probes against the server IP and port to fingerprint the protocol (e.g., sending abnormal TLS ClientHello, replaying handshakes, or injecting malformed HTTP requests). If the port behaves like an abnormal proxy, drops connections unexpectedly, or presents an untrusted self-signed certificate, the IP is blacklisted.

We must deploy robust active probing deflection architectures that provide zero recognizable proxy signatures.

## Decision Drivers
- Resistance against automated active scanning and protocol fingerprinting.
- Support both domain-less deployment (zero domain registration) and authentic domain deployments.
- Genuine TLS 1.3 handshake responses and authentic web content presentation.

## Considered Options
1. **Self-Signed Certificates or Pre-Shared Keys**: Plain TLS without public CA signatures.
2. **Standard VLESS / VMess with Connection Dropping**: Resetting connection on unauthenticated requests.
3. **Dual Camouflage Lanes: REALITY & Web Fallback via PROXY Protocol**:
   - **LANE A (REALITY)**: Borrow public TLS SNI of authentic external domains without registering domains.
   - **LANE B (TLS Web Fallback)**: Genuine CA certificate with PROXY protocol fallback to local Nginx/Caddy.

## Decision Outcome
Chosen option: **REALITY as Primary Anti-Censorship Standard (`schemes/vless-xtls-vision-reality`)** with **TLS Web Fallback (`schemes/vless-xtls-vision-tls`) relegated to Legacy / Corporate-Only status**.

- **Primary Anti-Censorship Standard: REALITY Lane (`schemes/vless-xtls-vision-reality`)**:
  - Authenticated clients provide ephemeral credentials via the TLS 1.3 `Session ID` field.
  - Active scanners sending unauthenticated handshakes are transparently relayed at layer 4 directly to the authentic remote target website (`dest:443`), returning the genuine site's CA certificate.
  - **Eliminates the entire domain attack surface**: zero domain purchase, zero DNS records, zero Certificate Transparency log traces, and high-collateral-damage SNI camouflage against state censors.

- **Legacy / Corporate Profile: TLS Web Fallback Lane (`schemes/vless-xtls-vision-tls`)**:
  - Uses an authentic domain with an automated Let's Encrypt / ZeroSSL certificate.
  - Unauthenticated connections are forwarded via the PROXY protocol (`xver: 1`) to a local web server (Nginx or Caddy) hosting a genuine disguise website.
  - **Classified as Deprecated / High Risk for GFW Evasion**: Retained strictly for corporate or institutional networks that actively enforce SNI-to-IP ASN mapping. Not recommended for general censorship circumvention.

### Ratified Invariants
- `[INV-LOCAL-API-LOOPBACK]`: Administrative API inbounds must remain strictly isolated on `127.0.0.1:10085` and never exposed on the camouflage ingress port.

## Negative Knowledge & Discarded Alternatives
- **Why not drop unauthenticated connections?** Active scanners detect connection resets (`TCP RST`) or timeouts as distinct signatures of censorship circumvention proxies. Genuine web servers always respond with valid TLS alerts or HTTP responses.
- **Why is TLS Web Fallback inadequate for modern GFW circumvention?**
  1. **Zero-Collateral-Damage SNI Bans**: In TLS 1.3 without ECH, the personal domain SNI is visible in plaintext. Censors can block a personal domain with zero collateral impact on domestic users.
  2. **Certificate Transparency (CT) Harvesting**: Public CA issuance (Let's Encrypt) records the domain in public CT logs (RFC 6962), allowing censors to discover foreign proxy endpoints proactively upon certificate issuance.
  3. **Flow Profiling Mismatch**: NetFlow/IPFIX classifiers easily detect long-lived, high-bandwidth flows directed at obscure personal domains that ostensibly host static websites.
