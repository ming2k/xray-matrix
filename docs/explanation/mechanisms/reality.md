# REALITY Protocol Mechanism and Active Probing Deflection

This document explains the cryptographic architecture of **XTLS/REALITY**, how it borrows genuine foreign TLS identities without holding private keys, and how it neutralizes active probing attacks.

---

## 1. Problem Statement: The Certificate Paradox

Traditional circumvention setups face a dilemma:
- **Self-Signed Certificates**: Easily flagged by automated scanners because public root CAs do not sign them.
- **Self-Owned Domain Certificates**: Requires purchasing a domain, configuring DNS records, and renewing CA certificates (e.g. Let's Encrypt). This leaves the domain vulnerable to SNI filtering, DNS poisoning, and domain blacklisting.

REALITY resolves this paradox by allowing the proxy server to **borrow the TLS certificate and identity of an existing, authoritative third-party website**.

---

## 2. Cryptographic Architecture

```text
[Client]                                                        [Xray Server]                                 [Genuine Target (dest)]
   |                                                                  |                                                   |
   |-- 1. ClientHello (SNI: dest, SessionID: EphemeralPubKey+HMAC) -->|                                                   |
   |                                                                  |                                                   |
   |                                                        [Auth Verification]                                           |
   |                                                        Valid HMAC & Key?                                             |
   |                                                           /             \                                            |
   |                                                 (YES)   /                 \  (NO - Active Scanner)                   |
   |                                                        v                   v                                         |
   |                                              [Derive Shared Secret]   [Open TCP Connection] ------------------------>|
   |                                                        |                                                             |
   |<-- 2. Synthesized ServerHello (Mimicked Ciphers/Exts) -|              |<-- 3. Transparent Relay: Scanner <--> dest ->|
   |                                                        |                                                             |
   |<============ 4. VLESS Proxy Tunnel Established =======>|                                                             |
```

### 2.1 Handshake Steganography (The Session ID Channel)
In standard TLS 1.3, the `Session ID` field in the `ClientHello` is legacy data retained for middlebox compatibility (RFC 8446 Section 4.1.2) and typically contains 32 randomized bytes.

REALITY repurposes this field:
1. **Ephemeral Key Generation**: The client generates a Curve25519 key pair for the session.
2. **Payload Packing**: The client embeds its ephemeral public key and an HMAC authentication tag into the 32-byte `Session ID`. The HMAC is computed over the handshake using a key derived from the server's `publicKey` and the agreed `shortId`.
3. **PFS (Perfect Forward Secrecy)**: Even if the server's public key is known, eavesdroppers cannot decrypt past sessions because each handshake uses fresh ephemeral Curve25519 pairs.

### 2.2 Server Verification
Upon receiving a `ClientHello`:
1. The Xray server reads the `Session ID` bytes.
2. It uses its X25519 `privateKey` to perform ECDH with the embedded ephemeral public key and computes the expected authentication tag.
3. **If authentication succeeds**: The connection belongs to an authorized client. The server generates a matching `ServerHello` mimicking the target site's cipher suites, extensions, and certificate parameters, and transitions into the VLESS tunnel.

---

## 3. Active Probing Deflection (The Honey-Pot Defense)

If a censor's automated scanner discovers the IP address and sends test packets to port 443:
1. The scanner sends an ordinary TLS `ClientHello` or randomized test data.
2. Because the scanner does not possess the server's `publicKey` or `shortId`, the `Session ID` authentication check fails immediately.
3. **The Deflection Mechanism**:
   - Xray does **not** close the connection (which would signal an anomalous service).
   - Xray does **not** return an error.
   - Instead, Xray opens an outbound TCP socket to the configured destination server (`dest`, e.g., `gateway.icloud.com:443`).
   - Xray forwards the scanner's raw packets to `dest` and streams `dest`'s responses back to the scanner.
4. **The Outcome**:
   - The scanner completes a 100% genuine TLS 1.3 handshake with Apple or Google.
   - The scanner receives a cryptographically valid certificate signed by Apple's root CA.
   - Automated probing classifies the host as an authentic CDN node or reverse proxy, discarding it from active blacklists.

---

## 4. Operational Considerations & Limitations

1. **Dest Selection Matching**:
   - The destination domain (`serverNames`) must match the server's network characteristics (TLS 1.3 support, ALPN `h2`, OCSP stapling).
2. **ASN/IP Discrepancy**:
   - In sophisticated corporate DPI environments, firewalls may check whether an IP belongs to the ASN owning the domain (e.g. connecting to a Hetzner IP with an Apple SNI). For such environments, the [VLESS + TLS Fallback scheme](tls-fallback.md) with a self-owned domain is recommended.
