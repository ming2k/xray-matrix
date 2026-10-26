# Transport Schemes

One directory per transport scheme, and each one is self-contained and
deployable as-is:

| File | Contents |
|------|----------|
| `client.json` | The complete client Xray config: transparent-proxy datapath (TProxy inbound, Smart DNS, routing, policy) plus this scheme's outbound. |
| `server.json` | The complete server Xray config: this scheme's inbound plus the `freedom` / `blackhole` outbounds. |
| `README.md` | Mechanism, threat model, key generation, and operational notes. |
| `client.local.json`, `server.local.json` | Your host-specific copy of a config with real credentials. Never committed (`.gitignore`). |

Deploy a scheme by copying its config to a sibling `.local.json`, filling in
every `<PLACEHOLDER:...>`, and validating with `xray run -test`. Both ends of
one deployment come from the same scheme directory, so the values that must
agree (UUID, `serverName`, short ID) are taken from a single source.

The OS artifacts that do **not** depend on the scheme — nftables rules, unit
files, sysusers entries, kernel tuning — live in `../host/client/` and `../host/server/`.

---

## 1. Scheme Comparison & Selection Matrix

| Dimension | Scheme 1: VLESS + Vision + REALITY | Scheme 2: VLESS + Vision + TLS (Fallback) |
| :--- | :--- | :--- |
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
| **Maintenance Burden** | Near zero (no renewal, no web server) | Medium (certificate renewal, Nginx fallback maintenance) |
| **Corporate / Strict Firewall** | Might raise alert if borrowed cert SNI mismatches IP ASN | 100% standard TLS; valid cert signed for genuine domain |
| **Primary Use Case** | Ephemeral VPS, personal workstations, zero-domain setup | Long-term high-reputation servers, disguised as real websites |

---

## 2. Decision Tree: Which Scheme to Select?

```text
Do you have a personal domain name pointing to your VPS?
  ├── NO  ──> Use [VLESS + Vision + REALITY]
  │           - Zero domain cost
  │           - No certificate renewal
  │           - High resilience against active scanners
  │
  └── YES ──> Are you operating under strict corporate DPI / ASN checking?
                ├── YES ──> Use [VLESS + Vision + TLS with Web Fallback]
                │           - Genuine CA certificate matches domain & IP
                │           - Indistinguishable from real enterprise website
                │
                └── NO  ──> Either scheme works; REALITY has lower maintenance overhead.
```

---

## 3. Threat Models & Defense Strategies

### Threat 1: Active Probing (主动探测)
* **The Attack**: The censor's DPI engine detects an anomalous TLS connection to a foreign IP. Automated scanners then replay the TLS handshake or send randomized HTTP/TLS payloads to port 443 to observe how the server responds.
* **REALITY Defense**:
  - The server inspects the TLS `Session ID` (carrying an ECDH public key and HMAC auth tag).
  - If valid: Xray terminates the connection and accepts the VLESS session.
  - If invalid (active scanner): Xray transparently connects to the genuine destination server (`dest`, e.g., Apple or Google) on port 443 and pipes the scanner's raw packets directly through. The scanner receives 100% authentic TLS handshake responses signed by Apple's private key.
* **TLS + Fallback Defense**:
  - The server terminates standard TLS with a genuine certificate.
  - If the client payload starts with a valid VLESS header and UUID, it routes into the proxy tunnel.
  - If the payload is normal HTTP or probe garbage, Xray triggers `fallbacks` and hands the socket over to local Nginx/Caddy on port 8080 via the PROXY protocol (`xver: 1`). The scanner receives standard HTTP 200/404 responses from a real web server.

### Threat 2: TLS-in-TLS Pattern Recognition (双层 TLS 模式识别)
* **The Attack**: When browsing HTTPS websites through a TLS proxy, inner TLS records are wrapped inside outer TLS records. Record sizes correlate in a deterministic pattern that machine learning DPI detects without decrypting the payload.
* **XTLS-Vision Defense**:
  - **Handshake phase**: Injects randomized padding records (`Vision Padding`) during the initial exchange, destroying the deterministic record length correlation.
  - **Data phase**: Once inner TLS is verified, Vision switches to zero-copy direct streaming (`splice()` on Linux). The outer layer stops double-encrypting already encrypted TLS packets, matching the profile of a native TLS stream with zero CPU overhead.

---

## 4. How to Switch Schemes

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
3. The OS layer (`../host/client/`, `../host/server/`) is untouched by a scheme switch.
