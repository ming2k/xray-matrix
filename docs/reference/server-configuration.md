# Server Configuration Reference

Reference for the server-side Xray config, `schemes/<scheme>/server.json`.

---

## 1. Top-Level Structure

A server configuration contains four core sections:

```json
{
  "log": { ... },
  "inbounds": [ ... ],
  "outbounds": [ ... ],
  "routing": { ... }
}
```

---

## 2. Inbound Keys (`inbounds[0]`)

### Common VLESS Fields
| Key | Type | Description |
| :--- | :--- | :--- |
| `listen` | string | `0.0.0.0` to bind all interfaces. |
| `port` | integer | `443` (standard HTTPS). |
| `protocol` | string | `"vless"`. |
| `settings.clients` | array | Array of client objects containing `id` (UUID) and `flow: "xtls-rprx-vision"`. |
| `settings.decryption` | string | Must be `"none"`. |
| `settings.fallbacks` | array | Rules for handling non-proxy traffic (used in TLS scheme). |

### Fallbacks Object
| Key | Type | Description |
| :--- | :--- | :--- |
| `dest` | string / int | Target address to forward to (e.g., `"127.0.0.1:8080"` or `8080`). |
| `xver` | integer | `1` to send PROXY protocol v1 header (preserves client IP for Nginx). |

---

## 3. StreamSettings Reference

### REALITY Settings (`streamSettings.realitySettings`)
| Key | Type | Description |
| :--- | :--- | :--- |
| `show` | boolean | Set to `false` in production. |
| `dest` | string | Target the unauthenticated branch is relayed to: the borrowed site's `host:port` (`gateway.icloud.com:443`), or a local TLS listener when the borrowed identity is your own site (`127.0.0.1:8443`). |
| `xver` | integer | PROXY protocol version sent *to `dest`* (`0` = disabled). Only meaningful when `dest` is a local listener that expects a header; a real remote site would reject it. |
| `serverNames` | array | SNI list to accept and match. Must contain the borrowed name verbatim, and must never contain a hostname that is itself CDN-proxied. |
| `privateKey` | string | X25519 private key generated via `xray x25519`. |
| `shortIds` | array | Valid shortId hex strings, 0–16 hex chars; the empty string `""` is accepted and makes the client-side `shortId` optional. |

### Compatibility Constraints

- **`sockopt.acceptProxyProtocol` must not be set on a REALITY inbound.** REALITY
  cannot consume the header: every handshake fails with
  `tls: first record does not look like a TLS handshake` (reproduced on Xray
  26.3.27 and 26.10.21). A front proxy that must speak PROXY protocol needs a
  stripping hop that re-emits plain TCP — see
  [How to Share Port 443 with an Existing Website](../how-to/share-port-443-with-a-website.md).
- **`xver` on a REALITY inbound is not the web-fallback mechanism.** It applies
  to the relay target only; the local web fallback with client-address
  preservation belongs to the TLS scheme's `settings.fallbacks` object.
- **`dest` must not point at a CDN-proxied name of your own.** Probes would be
  answered by your own site's identity, which removes the scheme's camouflage.

### TLS Settings (`streamSettings.tlsSettings`)
| Key | Type | Description |
| :--- | :--- | :--- |
| `rejectUnknownSni` | boolean | `true` drops connections scanning raw IP without valid domain SNI. |
| `minVersion` | string | `"1.3"` strictly enforces TLS 1.3 (required for XTLS-Vision; prevents TLS downgrade). |
| `alpn` | array | `["h2", "http/1.1"]` to support HTTP/2 and HTTP/1.1. |
| `certificates` | array | Path to `fullchain.pem` and `privkey.pem`. |
| `ocspStapling` | integer | Cache duration in seconds for OCSP responses (e.g. `3600`). |

---

## 4. Outbound Transit

```json
"outbounds": [
  {
    "protocol": "freedom",
    "tag": "direct",
    "streamSettings": {
      "sockopt": {
        "domainStrategy": "UseIPv4v6"
      }
    }
  },
  {
    "protocol": "blackhole",
    "tag": "blocked"
  }
]
```
- `freedom`: Directly dials target destinations from the server's network interface.
- `domainStrategy: UseIPv4v6`: Resolves DNS using the server's system resolver and tries IPv4/IPv6 according to kernel availability.
