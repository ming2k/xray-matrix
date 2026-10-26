# How to Deploy an Xray Proxy Server on a VPS

A complete, production-grade deployment runbook for provisioning an Xray proxy
server on a Linux VPS. This guide covers binary installation, kernel BDP and BBR
tuning, REALITY target domain selection, unprivileged sandboxing, systemd preflight
hardening, and external verification.

---

## Prerequisites

- A Linux VPS with a dedicated public IPv4 address running **Debian 12+** or
  **Ubuntu 22.04+**.
- Direct root or `sudo` access to the machine.
- Port **443** free and unallocated (no Apache, Nginx, or Caddy bound to 443).
- Required administrative packages installed:
  ```sh
  sudo apt-get update && sudo apt-get install -y curl unzip openssl
  ```

---

## 1. Install or Upgrade Xray Core

Install the latest official Xray binary release using the upstream installation
script:

```sh
# Execute the official installer
sudo bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Verify the installed binary version
xray version
```

The installer establishes:
- Binary executable at `/usr/local/bin/xray`.
- Dedicated unprivileged system user and group `xray:xray`.
- Asset files at `/usr/local/share/xray/` (`geoip.dat`, `geosite.dat`).
- Systemd service at `/etc/systemd/system/xray.service` with `CAP_NET_BIND_SERVICE`
  and `CAP_NET_ADMIN` capabilities.

> If this host already terminates TLS for real websites on port 443, do not give
> the port to Xray: use
> [How to Share Port 443 with an Existing Website](share-port-443-with-a-website.md)
> instead. There nginx owns `:443`, Xray binds `127.0.0.1:10443`, and the
> `CAP_NET_BIND_SERVICE` capability above becomes unnecessary.

---

## 2. Apply Kernel BBR & Socket Buffer Tuning

Cross-border transit typically features a high Bandwidth-Delay Product (BDP).
Default Linux socket buffer limits cap single-connection throughput. Apply
production sysctl tuning:

```sh
sudo tee /etc/sysctl.d/99-xray-tuning.conf << 'EOF'
# /etc/sysctl.d/99-xray-tuning.conf
# Optimized for high Bandwidth-Delay Product (BDP) cross-border transit.

# 1. Congestion Control & Queueing (BBR + FQ)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 2. TCP Fast Open (3 = Enable both client and server)
net.ipv4.tcp_fastopen = 3

# 3. Maximum and Default Socket Buffers (Supports 64MB window for high BDP links)
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# 4. Connection Backlog & Listen Queue
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# 5. Socket Lifecycle & Port Allocation
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 1440000

# 6. TCP KeepAlive Optimization
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5

# 7. IP Forwarding & Security
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.tcp_syncookies = 1
EOF

# Activate changes immediately
sudo sysctl -p /etc/sysctl.d/99-xray-tuning.conf
```

---

## 3. REALITY Target Selection ("Borrowing a Domain")

In the REALITY scheme, the server presents no TLS certificate of its own. It
impersonates a genuine third-party website and relays unauthenticated probes to
that site.

### 3.1 Selection Rules

The target domain (`dest` and `serverNames`) must satisfy four constraints:

1. **Port 443 Mandatory**: Never run REALITY on high-numbered ports (e.g., 10443).
   GFW heuristic classifiers heavily flag and block non-443 TLS tunnels.
2. **Low Physical RTT ($\Delta T < 15\text{ms}$)**: The borrowed target must be
   geographically adjacent to your VPS (ideally $< 5\text{ms}$ within the same
   datacenter or metropolitan internet exchange).
3. **Clean HTTP/2 200 OK**: The root path must return `HTTP/2 200 OK` without
   `301/302` redirects and without hostile WAF blocks (e.g. CloudFront or
   Cloudflare `403 Forbidden`).
4. **Bulk Traffic Disguise**: Choose high-volume CDN edges, software mirrors, or
   telecom portals that naturally carry long-lived, high-throughput flows.

See [REALITY Target Selection](../explanation/reality-target-selection.md)
for the full regional target catalogs.

### 3.2 Candidate Verification Pipeline (Run on the VPS)

```sh
TARGET="cdn.softbank.jp"

# 1. Verify RTT (must be < 15ms)
ping -c 3 "$TARGET" | tail -1 | awk -F '/' '{print "Average RTT: " $5 " ms"}'

# 2. Verify TLS 1.3, HTTP/2, and status code
curl -Iv --tlsv1.3 --http2 -s -m 5 "https://$TARGET/" 2>&1 | \
  grep -E "(SSL connection using TLSv1.3|using HTTP/2|HTTP/2 [0-9]{3})"
```

**Passing Output Example**:
```text
Average RTT: 0.617 ms
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519MLKEM768 / RSASSA-PSS
* using HTTP/2
< HTTP/2 200
```

---

## 4. Key Generation

Generate the cryptographic keys for the server configuration:

```sh
# Generate X25519 keypair for REALITY
xray x25519
# Output:
# Private key: <SERVER_PRIVATE_KEY>
# Public key:  <CLIENT_PUBLIC_KEY>  (Provide to client)

# Generate a client UUID
xray uuid
# Output:
# <CLIENT_UUID>

# Generate an 8-byte hexadecimal shortId
openssl rand -hex 8
# Output:
# <SHORT_ID>
```

---

## 5. Deploy Server Configuration

Write the hardened server configuration to `/usr/local/etc/xray/config.json`.
Set `dest` and `serverNames` to your verified target, and paste the generated keys:

```json
{
  "log": {
    "loglevel": "warning",
    "error": "/var/log/xray/error.log",
    "access": "/var/log/xray/access.log"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "<CLIENT_UUID:00000000-0000-0000-0000-000000000000>",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "cdn.softbank.jp:443",
          "xver": 0,
          "serverNames": [
            "cdn.softbank.jp"
          ],
          "privateKey": "<SERVER_PRIVATE_KEY:REDACTED>",
          "shortIds": [
            "",
            "<SHORT_ID:0123456789abcdef>"
          ]
        },
        "sockopt": {
          "tcpFastOpen": true
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "streamSettings": {
        "sockopt": {
          "domainStrategy": "UseIPv4"
        }
      }
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
      }
    ]
  }
}
```

Lock file permissions so the private key is shielded from unauthorized access:

```sh
sudo chown -R xray:xray /usr/local/etc/xray
sudo chmod 750 /usr/local/etc/xray
sudo chmod 640 /usr/local/etc/xray/config.json
```

---

## 6. Systemd Hardening & Preflight Verification

Add an `ExecStartPre` preflight test drop-in to `/etc/systemd/system/xray.service.d/20-preflight.conf`.
This ensures a malformed configuration file can never replace or crash a running
daemon process:

```sh
sudo mkdir -p /etc/systemd/system/xray.service.d
sudo tee /etc/systemd/system/xray.service.d/20-preflight.conf << 'EOF'
[Service]
# Validate syntax and schemas prior to launching daemon
ExecStartPre=+/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
EOF

# Test configuration syntax manually
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json

# Reload systemd and start the service
sudo systemctl daemon-reload
sudo systemctl restart xray.service
sudo systemctl enable xray.service
```

---

## 7. Configure Log Rotation

Prevent `/var/log/xray/*.log` from consuming disk space over time:

```sh
sudo tee /etc/logrotate.d/xray << 'EOF'
/var/log/xray/*.log {
    weekly
    rotate 4
    missingok
    notifempty
    compress
    delaycompress
    postrotate
        systemctl try-restart xray.service 2>/dev/null || true
    endscript
}
EOF

sudo chmod 644 /etc/logrotate.d/xray
```

---

## 8. Outside-In Verification

Always confirm the service from an external machine:

### 8.1 Active Probe Deflection Test (Stranger Perspective)

Execute from an external workstation:

```sh
curl -Iv --tlsv1.3 --http2 --resolve cdn.softbank.jp:443:<SERVER_IP> https://cdn.softbank.jp/
```

**Passing Verification Criteria**:
- SSL handshake completes with genuine target certificate (e.g., SoftBank EV SSL).
- ALPN confirms `using HTTP/2`.
- Status code is `HTTP/2 200 OK`.
- Unauthenticated probers receive the authentic borrowed website content.

### 8.2 Client Tunnel Test (Authorized User Perspective)

Configure the client with the matching `id` (UUID), `flow` (`xtls-rprx-vision`),
`publicKey`, and `shortId`.

Confirm that:
1. `curl -s --socks5 127.0.0.1:1080 http://ip-api.com/line` returns the VPS IP.
2. `curl -sI --socks5 127.0.0.1:1080 https://www.google.com/generate_204` returns `HTTP/2 204`.
3. Check `/var/log/xray/access.log` on the server to verify inbound connections
   are accepted via `[direct]`.

---

## Related Documentation

- [How to Diagnose GFW Blocks and Network Anomalies](diagnose-gfw-blocks.md)
- [REALITY Target Selection & Camouflage](../explanation/reality-target-selection.md)
- [XTLS-Vision Deep Dive](../explanation/xtls-vision.md)
- [Host Artifacts Reference](../reference/host-artifacts.md)
