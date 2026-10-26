---
id: ADR-0006
title: "Port 443 Ownership on Hosts That Already Serve Websites"
status: accepted
date: 2026-10-26
scope: [host/server, schemes/vless-xtls-vision-reality]
superseded_by: null
invariants: ["[INV-443-SINGLE-OWNER]", "[INV-CAMOUFLAGE-NO-LOCAL-CERT]"]
---

# ADR-0006: Port 443 Ownership on Hosts That Already Serve Websites

## Context & Problem Statement

An egress node often already terminates TLS for real websites on port 443. Adding
a REALITY inbound to the same host forces a choice about who owns that port, and
every naive choice destroys something:

- If Xray binds `0.0.0.0:443`, the websites must move to another port, so their
  URLs change and the personal domain becomes the visible SNI on the proxy — the
  exact condition REALITY exists to avoid.
- If Xray terminates TLS for the personal domain and falls back to a web server,
  Xray must read every site's private key, every ACME renewal needs a daemon
  reload, and the fallback leg is plaintext HTTP, which breaks SSE streaming, S3
  request signatures and WebSocket upgrades.
- If the two services alternate ports over time, every client configuration and
  every DNS-facing promise has to change with them.

The constraint is asymmetric: the websites need their certificates, their HTTP/2
and their streaming semantics untouched; the proxy needs a borrowed SNI on a
standard port and must remain indistinguishable from the real third party.

## Decision Drivers

- Website continuity: no certificate, protocol or streaming behaviour may change.
- Camouflage integrity: the observable identity of port 443 must be the borrowed
  CDN name, and nothing local may leak to a prober.
- Least privilege: the proxy daemon must not hold a privileged port on this host.
- Operational reversibility: rolling back must not require touching client configs.

## Considered Options

1. **Xray owns 443; websites move to another port.** Rejected: changes public URLs
   and puts a personal domain in the SNI of the proxy.
2. **Xray terminates TLS and falls back to nginx over HTTP.** Rejected: private
   keys leave the web server's trust boundary, ACME renewals couple to Xray
   restarts, and plaintext fallback breaks streaming and signature semantics.
3. **nginx owns 443 as a layer-4 SNI demultiplexer; REALITY sits behind it on
   loopback.** Chosen.

## Decision Outcome

Chosen option: **option 3.** nginx `stream` with `ssl_preread` reads only the
`ClientHello` SNI and forwards raw TCP; it never decrypts proxy traffic.

```text
                        nginx :443  (ssl_preread, no decryption)
                              |
        +---------------------+----------------------+
   SNI = borrowed CDN                    any own domain
        |                                            |
        v                                            v
  nginx 127.0.0.1:18443                      nginx 127.0.0.1:8443
  (PROXY header stripped)                    (TLS terminated, HTTP/2 kept)
        |                                            |
        v                                            v
  xray  127.0.0.1:10443                      sites, ACME, SSE, S3
  (REALITY, unprivileged user)
```

Port ownership on such a host: `443`, `8443` and `18443` belong to nginx; `10443`
belongs to Xray and is loopback-only. `host/server/nginx-stream/reality.conf` is
the deployable artifact.

### Ratified Invariants & Contracts

- `[INV-443-SINGLE-OWNER]`: Exactly one process may bind the wildcard `:443`.
  On hosts with websites that process is nginx; Xray binds loopback only and
  never holds `CAP_NET_BIND_SERVICE` for this purpose.
  **Enforcement**: `ss -tlnH 'sport = :443'` names a single service, and
  `host/server/xray-server.nft` admits inbound `443` regardless of which daemon
  owns it, so a misplaced bind is a visible port conflict at start, not a silent
  configuration drift.
- `[INV-CAMOUFLAGE-NO-LOCAL-CERT]`: A connection whose SNI is neither an own
  domain nor the borrowed name must be answered by the REALITY branch, i.e. with
  the borrowed site's own handshake or alert — never with a local certificate.
  **Enforcement**: the `map` enumerates own domains explicitly and defaults to
  the REALITY backend; verification is a single `openssl s_client` probe with an
  unknown SNI, documented in the deployment guide.

## Negative Knowledge & Discarded Alternatives

- **Xray cannot consume a PROXY protocol header on a REALITY inbound.** Enabling
  `sockopt.acceptProxyProtocol` makes every handshake fail with
  `tls: first record does not look like a TLS handshake` (reproduced on 26.3.27
  and 26.10.21; the same configuration without the header works). This is why the
  demultiplexer needs the second hop at `18443` instead of forwarding the header
  straight to Xray.
- **`proxy_pass` must name an upstream group, never a `host:port` variable.**
  A variable value is re-parsed per connection and drops connections with no log
  entry anywhere: measured 12 failures in 50 attempts on `:443` against 0 in 20
  for the identical routing expressed through group names, interleaved in the
  same minute.
- **The demultiplexer must not lose the client address.** Forwarding with
  `proxy_protocol on` and listening on the web backend with `proxy_protocol`,
  plus `real_ip_header proxy_protocol`, keeps access logs and IP-based rules
  correct; omitting either half silently logs `127.0.0.1` for every visitor.
- **Serving the borrowed name from a CDN-proxied domain of your own is
  forbidden.** Probes would then be answered with your own site's identity,
  reintroducing the exact signal the scheme removes.
- **Deploying a CDN for the website is a separate decision, and is not part of
  this ADR**: it moves public visitors to a third party's edge and does nothing
  for the proxy, so it is evaluated on its own costs and currently not adopted.
