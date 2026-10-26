# Transport Schemes

One directory per transport scheme, each self-contained and deployable as-is:

| File | Contents |
|------|----------|
| `client.json` | The complete client Xray config: transparent-proxy datapath (TProxy inbound, Smart DNS, routing, policy) plus this scheme's outbound. |
| `server.json` | The complete server Xray config: this scheme's inbound plus the `freedom` / `blackhole` outbounds. |
| `README.md` | Mechanism, threat model, key generation, operational limits — the scheme's own documentation. |
| `client.local.json`, `server.local.json` | Your host-specific copy of a config with real credentials. Never committed (`.gitignore`). |
| *(scheme-specific extras)* | Only if the scheme needs one, e.g. `vless-xtls-vision-tls/cert-guide.md`. |

Deploy a scheme by copying its config to a sibling `.local.json`, filling in
every `<PLACEHOLDER:...>`, and validating with `xray run -test`. Both ends of
one deployment come from the same scheme directory, so the values that must
agree (UUID, `serverName`, short ID) are taken from a single source.

The OS artifacts that do **not** depend on the scheme — nftables rules, unit
files, sysusers entries, kernel tuning, and the
[TProxy Datapath Contract](../host/client/README.md) — live in `../host/client/`
and `../host/server/`.

The two schemes share XTLS-Vision and a whole client datapath, and differ only
in the outer security layer. Everything else about them — what the server
does with an unauthenticated connection — is in each scheme's `README.md`:

- [VLESS + Vision + REALITY](vless-xtls-vision-reality/README.md)
- [VLESS + Vision + TLS with Web Fallback](vless-xtls-vision-tls/README.md)

---

## 1. Scheme Comparison & Selection Matrix

| Dimension | Scheme 1: VLESS + Vision + REALITY (Standard) | Scheme 2: VLESS + Vision + TLS (Fallback) [Legacy / Corporate] |
| :--- | :--- | :--- |
| **Status** | **Production Standard (Recommended)** | **Legacy / Corporate Profile (Deprecated for GFW)** |
| **Directory** | `schemes/vless-xtls-vision-reality/` | `schemes/vless-xtls-vision-tls/` |
| **Protocol / Transport** | `vless` / `tcp` | `vless` / `tcp` |
| **Flow Control** | `xtls-rprx-vision` | `xtls-rprx-vision` |
| **Security Type** | `reality` | `tls` |
| **Domain Requirement** | **None** (No domain registration or DNS record needed) | **Required** (Self-owned domain pointing to server IP) |
| **Certificate Requirement** | **None** (Borrows foreign authority TLS identity) | **Required** (Valid CA cert via Let's Encrypt / ZeroSSL) |
| **Active Probing Defense** | **Destination Deflection**: Proxies scanners to real target site | **Web Fallback**: Hands non-proxy traffic to local Nginx/Caddy |
| **Fallback Protocol** | None (Raw TCP relay to `dest`) | PROXY protocol v1 (`xver: 1`) to port 8080 |
| **TLS-in-TLS Protection** | **XTLS-Vision** (Random padding + kernel splice) | **XTLS-Vision** (Random padding + kernel splice) |
| **Cipher Suites** | X25519, ChaCha20-Poly1305, AES-128-GCM | TLS 1.3 standard cipher suites |
| **ALPN** | Negotiated with target (`h2`, `http/1.1`) | Explicitly advertised: `["h2", "http/1.1"]` |
| **Fingerprint Emulation** | `chrome` (via uTLS) | `chrome` (via uTLS) |
| **0-RTT TFO Support** | Yes (`tcpFastOpen: true`) | Yes (`tcpFastOpen: true`) |
| **SNI Visibility** | Foreign target domain (e.g. `gateway.icloud.com`) | Self-owned domain (e.g. `node.yourdomain.com`) |
| **Censorship Vector** | VPS IP blocking if discovered | Domain SNI blocking, DNS poisoning, or VPS IP blocking |
| **Anti-Censorship Exposure** | **Low**. Borrows high-reputation domain (collateral damage deters SNI bans); no CT log trace | **Critical**. Self-owned domain exposed in plain SNI; zero-collateral bans, CT log scraping & flow profiling |
| **Maintenance Burden** | Near zero (no renewal, no web server) | Medium (certificate renewal, Nginx fallback maintenance) |
| **Corporate / Strict Firewall** | Might raise alert if borrowed cert SNI mismatches IP ASN | 100% standard TLS; valid cert signed for genuine domain |
| **Primary Use Case** | Standard modern anti-censorship for workstations, routers, and VPS nodes | Specialized enterprise networks strictly enforcing SNI-to-IP ASN mapping |

---

## 2. Decision Tree: Which Scheme to Select?

```text
What is your threat model?
  │
  ├── Circumventing nation-state censors (GFW) / Personal Anti-Censorship
  │     └──> ALWAYS USE [VLESS + Vision + REALITY]
  │           - Zero domain registration (zero personal identity exposure)
  │           - Zero public Certificate Transparency (CT) log trace
  │           - Borrows high-reputation SNI (high collateral damage prevents arbitrary bans)
  │           - Layer 4 active scanner deflection to authentic upstream servers
  │
  └── Operating inside enterprise / academic intranets checking SNI-to-IP ASN matching
        └──> Use [VLESS + Vision + TLS with Web Fallback] (Corporate Legacy Profile)
              - ⚠️ HIGH RISK FOR GFW: Personal SNI has zero collateral damage; easily blocked
              - ⚠️ Automated crawlers scrape CT logs upon Let's Encrypt certificate issuance
              - ⚠️ Requires genuine public web traffic to avoid NetFlow flow-profiling anomalies
```

---

## 3. How Each Defense Answers a Probe

Both schemes survive active probing, by opposite means: REALITY never refuses,
and TLS-fallback serves a real site. The observable behaviour differs per probe
type, and that difference is what to weigh when picking between them.

| Probe | REALITY | TLS + Fallback |
| :--- | :--- | :--- |
| Direct IP, no SNI | Forwarded to `dest` | Rejected in the handshake (`rejectUnknownSni`) |
| Wrong SNI | Forwarded to `dest` | Rejected in the handshake (`rejectUnknownSni`) |
| Valid SNI + HTTP GET | Forwarded to `dest` | Served the local static site, `200 OK` |
| Valid SNI + random bytes | Forwarded to `dest` | Nginx parses garbage, `400 Bad Request` |
| Certificate seen | The borrowed certificate from `dest` | A genuine certificate issued to your domain |

A rejection (row 1 and 2 for the TLS scheme) is not a weakness where the
domain is yours: an unknown SNI failing a handshake is what any correctly
configured web server does. It would be a weakness for a borrowed identity,
which is why REALITY cannot do it.

---

## 4. Switching Schemes

1. **Client**: copy `schemes/<scheme>/client.json` to `client.local.json` in
   the same directory, fill in the placeholders, validate, and install:
   ```sh
   S=./schemes/vless-xtls-vision-tls
   cp $S/client.json $S/client.local.json && $EDITOR $S/client.local.json
   xray run -test -config $S/client.local.json
   sudo install -Dm600 $S/client.local.json /etc/xray/config.json
   sudo systemctl restart xray-tproxy.service
   ```
2. **Server**: the same with `server.json` on the other host. Use the **same
   scheme directory** on both ends — the UUID, `serverName`, and short ID must
   match. For the TLS scheme, issue the certificate and start the fallback web
   server first (see `vless-xtls-vision-tls/cert-guide.md`).
   ```sh
   sudo systemctl restart xray-server.service
   ```
3. The OS layer (`../host/client/`, `../host/server/`) is untouched by a scheme
   switch: the client datapath, the unit files, the firewall and the kernel
   tuning are identical for every scheme.
