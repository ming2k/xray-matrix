# Scheme: VLESS + TCP + XTLS-Vision + REALITY

This scheme eliminates the requirement for a personal domain name or certificate authority while providing state-of-the-art protection against TLS-in-TLS identification and active scanner probing.

---

## 1. Underlying Mechanics

### 1.1 How REALITY Works
Traditional TLS proxies require either a self-signed certificate (which active scanners easily detect and flag) or a valid CA certificate registered to your own domain (which risks domain-level SNI blocks).

REALITY borrows the cryptographic identity of an existing, high-reputation foreign website (the `dest`, such as Apple, Google, Cloudflare, or Yahoo):
1. **ClientHello**: The client sends a standard TLS 1.3 `ClientHello` with the target server's SNI (e.g., `gateway.icloud.com`). Inside the `Session ID` field, the client embeds an ephemeral Curve25519 ECDH public key and an HMAC authentication tag derived from the server's `publicKey` and `shortId`.
2. **Server Inspection**:
   - The Xray server receives the connection on port 443.
   - It parses the `Session ID`. Using its `privateKey`, the server authenticates the client.
3. **Branch A (Authenticated Client)**:
   - ECDH shared secret derivation succeeds.
   - The server completes the TLS 1.3 handshake using synthesized handshake extensions mimicking the target destination.
   - Traffic enters the VLESS tunnel.
4. **Branch B (Unauthenticated Prober or Scanner)**:
   - If the prober does not present a valid HMAC authentication in the `Session ID`, Xray does not terminate the TLS connection.
   - Instead, Xray opens an outbound TCP connection to the genuine target server (`dest: gateway.icloud.com:443`) and transparently proxies the prober's packets bidirectionally.
   - The active prober receives a 100% authentic TLS handshake directly signed by Apple's CA private key. The prober cannot distinguish the server from an authentic reverse proxy or edge node.

### 1.2 How XTLS-Vision Integrates
- **Handshake Phase**: When applications open TLS connections (such as HTTPS browsing) inside the proxy, Vision injects calculated padding records into the handshake messages. This eliminates the deterministic length correlation of "TLS-in-TLS" that machine-learning DPI relies on.
- **Data Phase**: Once inner TLS is negotiated, Vision uses Linux kernel `splice()` zero-copy forwarding. Outer TLS encryption is stopped; inner encrypted TLS flows straight to the network without double encryption or protocol wrapper fingerprints.

---

## 2. Key Generation

Run these commands on either machine with `xray` installed:

```sh
# Generate Server Keys (Private Key + Public Key)
xray x25519
# Output example:
# PrivateKey: <SERVER_PRIVATE_KEY>
# Password (PublicKey): <CLIENT_PUBLIC_KEY>

# Generate Client UUID
xray uuid

# Generate Short ID (8 hex bytes)
openssl rand -hex 8
```

---

## 3. Configuration Files

- `client.json`: The complete client config — TProxy datapath plus this
  scheme's outbound. Deploys to `/etc/xray/config.json` on the client host.
- `server.json`: The complete server config. Deploys to
  `/etc/xray/config.json` on the server host.

Both come from this one directory, so the values that must agree (`id`,
`serverName`, `shortIds`) have a single source. Copy a config to a sibling
`client.local.json` / `server.local.json`, fill in every `<PLACEHOLDER:...>`,
and validate with `xray run -test` before installing. That suffix is
git-ignored, so credentials never reach the repository.

---

## 4. Destination Selection Guidelines

When choosing `<DEST_DOMAIN:example.com:443>`:
1. **Must support TLS 1.3 and HTTP/2**: Verify with `curl -Iv https://<domain>`.
2. **Geographical Proximity**: Choose a destination served by CDNs close to the server's datacenter.
3. **Clean OCSP Stapling**: The target should return valid OCSP responses.
4. Recommended targets:
   - `gateway.icloud.com:443`
   - `swdist.apple.com:443`
   - `dl.google.com:443`
   - `update.microsoft.com:443`
