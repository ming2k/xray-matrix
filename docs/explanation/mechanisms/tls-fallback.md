# Standard TLS with Web Fallback Architecture

This document explains the mechanism of **VLESS over standard TLS with Fallback**, how protocol demultiplexing occurs behind port 443, and how active scanner probes are neutralized using local web servers.

---

## 1. System Topology

```text
                               Internet
                                  |
                                  | TLS 1.3 on Port 443 (Valid CA Certificate)
                                  v
+-----------------------------------------------------------------------------+
| Layer 1: Xray Front-End Termination (:443)                                  |
| - Terminates TLS with valid Let's Encrypt / ZeroSSL certificate             |
| - Enforces ALPN negotiation (h2, http/1.1)                                  |
| - Inspects decrypted first-packet payload                                   |
+-------------------------------------+---------------------------------------+
                                      |
                      Decrypted Payload Classification
                                      |
         +----------------------------+----------------------------+
         | Payload starts with valid  | Non-proxy traffic (HTTP/1.1|
         | VLESS Header & UUID?       | GET, HTTP/2 frames, probes)|
         v                                                         v
+-------------------------------+             +-------------------------------+
| Layer 2: Proxy Ingestion      |             | Layer 3: Fallback Hand-off    |
| - XTLS-Vision flow management |             | - Prepends PROXY protocol v1  |
| - Splice zero-copy routing    |             | - Passes socket to :8080      |
| - Outbound transit forwarding |             | - Real client IP preserved    |
+-------------------------------+             +---------------+---------------+
                                                              |
                                                              v
                                              +-------------------------------+
                                              | Layer 4: Disguise Web Server  |
                                              | - Local Nginx / Caddy (:8080) |
                                              | - Returns genuine 200 OK      |
                                              | - Serves static documentation |
                                              +-------------------------------+
```

---

## 2. Protocol Demultiplexing Mechanics

In this design, Xray acts as a TLS termination reverse proxy with protocol-level routing:

### 2.1 First-Packet Inspection
When an incoming connection completes the TLS 1.3 handshake:
1. Xray inspects the first decrypted data packet before routing the connection.
2. If the client is an authorized Xray client:
   - The stream begins with the VLESS protocol header: `[1 byte version] + [16 bytes UUID] + [1 byte addons] + ...`.
   - The UUID matches an entry in `settings.clients`.
   - Xray claims the stream and connects to the requested destination outbound.
3. If the client is an unauthorized scanner, search engine crawler, or browser:
   - The stream begins with HTTP methods (`GET / HTTP/1.1\r\n`, `POST ...`) or HTTP/2 connection prefaces (`PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`).
   - The VLESS authentication fails.
   - Xray immediately executes the configured `fallbacks` rule.

### 2.2 Socket Hand-Off and PROXY Protocol
When handing the socket to the fallback backend:
- **Direct TCP Stream**: Xray connects to `127.0.0.1:8080` (where Nginx or Caddy is listening) and transparently pipes all data.
- **Client IP Preservation (`xver: 1`)**:
  - Without PROXY protocol, Nginx would see all web requests as originating from `127.0.0.1`.
  - When `xver: 1` is configured, Xray prepends an RFC 7239-compliant PROXY header (`PROXY TCP4 <Client_IP> <Server_IP> <Client_Port> 443\r\n`) before forwarding the payload.
  - Nginx extracts the real client IP for rate limiting, analytics, and security logging.

---

## 3. Active Probing Defense Comparison

| Attack Vector | REALITY Behavior | TLS + Fallback Behavior |
| :--- | :--- | :--- |
| **Direct IP Probe (No SNI)** | Forwards connection to `dest` target | **Rejected immediately** (`rejectUnknownSni: true`) |
| **Invalid SNI Probe** | Forwards connection to `dest` target | **Rejected immediately** (`rejectUnknownSni: true`) |
| **Valid SNI + HTTP GET Probe** | Forwards connection to `dest` target | **Serves authentic website** via local Nginx/Caddy with 200 OK |
| **Valid SNI + Random Bytes** | Forwards connection to `dest` target | Nginx parses garbage, returns standard `400 Bad Request` |
| **CA Certificate Validation** | Returns borrowed certificate from `dest` | Returns genuine certificate issued to own domain |

---

## 4. When to Choose TLS + Fallback over REALITY

1. **Self-Owned Domain Available**: You already manage a domain and want clean, standard TLS infrastructure.
2. **Corporate & Academic Firewalls**: Environments with enterprise DPI that correlate SNI against IP ASN registries. REALITY with an Apple SNI on a generic cloud VPS may trigger an anomaly score; TLS with your own domain matches DNS records exactly.
3. **Dual-Use Hosting**: The server can host a personal blog, API, or static documentation on the exact same IP and port (443) while serving proxy traffic invisibly.
