# Client Host TProxy Datapath

OS-level integration for transparent proxying (TProxy) on Linux workstations
and gateway routers.

This directory contains the **scheme-agnostic datapath layer**: the nftables
rules, policy routing, systemd service, and service account. This layer does
not change when switching transport schemes (REALITY, TLS, etc.).

---

## 1. File Overview & Component Ownership

| File | Target Location | Owner | Purpose |
|------|-----------------|-------|---------|
| `xray-tproxy.nft` | `/etc/nftables/xray-tproxy.nft` | `xray-tproxy.service` | nftables tables (`ip xray_v4`, `ip6 xray_v6`) for TProxy interception, bypass marks, and DNS loop protection |
| `xray-tproxy.service` | `/etc/systemd/system/xray-tproxy.service` | `systemd` | Manages the Xray daemon lifecycle, table-110 routing, capabilities, and pre/post assertions |
| `xray-policy.conf` | `/etc/systemd/network/<uplink>.network.d/` | `systemd-networkd` | Policy routing rule (`fwmark 0x1 lookup 110`) per uplink profile |
| `xray-tproxy.sysusers.conf` | `/usr/lib/sysusers.d/xray.conf` | `systemd-sysusers` | Declares the dedicated unprivileged `xray` system user and group |

---

## 2. The Xray Configuration Contract

Linux TProxy is an active kernel-to-userland contract. An Xray configuration
deployed to `/etc/xray/config.json` **must satisfy all of the following
requirements** to function with this host layer. Complete, ready-to-run
configurations implementing this contract are provided in `../../schemes/`.

### Summary of Requirements

| Requirement | System Constraint | Xray Configuration Key | Consequence if Missing |
|-------------|-------------------|------------------------|------------------------|
| **TProxy Inbound** | Intercepts to loopback port `12345` | `protocol: dokodemo-door`, `port: 12345` | `ExecStartPost` poll fails; unit aborts after 10s |
| **IP_TRANSPARENT** | Kernel requires socket transparent mode | `streamSettings.sockopt.tproxy: "tproxy"` | TCP connections receive RST; UDP packets dropped |
| **Original Destination** | Preserves application dest IP:port | `settings.followRedirect: true` | Target IP lost; traffic fails to route |
| **Loop Prevention** | Output chain bypasses `meta mark 2` | `streamSettings.sockopt.mark: 2` on all dialing outbounds | **Infinite routing loop / packet storm; system freezes** |
| **Traffic Sniffing** | TProxy delivers raw IPs without domains | `sniffing.enabled: true`, `routeOnly: true` | Domain & geosite routing rules fail to match |
| **User Identity** | Output chain exempts `meta skuid "xray"` | `User=xray` in service unit | Localhost DNS loop deadlock (`127.0.0.53`) |
| **Smart DNS Hook** | Port 53 redirected to dokodemo-door | `routing.rules` sends port 53 to `dns-out` | DNS queries blackholed or loop |

---

### Detailed Contract Specifications

#### A. Inbound Specification
The transparent proxy inbound must accept raw TCP and UDP streams, enable kernel
transparent socket binding, and sniff domain names from payloads:

```json
{
  "tag": "all-in",
  "listen": "127.0.0.1",
  "port": 12345,
  "protocol": "dokodemo-door",
  "settings": {
    "network": "tcp,udp",
    "followRedirect": true
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"],
    "routeOnly": true
  },
  "streamSettings": {
    "sockopt": {
      "tproxy": "tproxy"
    }
  }
}
```

- **`sockopt.tproxy: "tproxy"`**: Under the hood, this sets the `IP_TRANSPARENT`
  socket option. Without it, the Linux kernel refuses to deliver packets whose
  destination IP does not match a locally configured interface address.
- **`port: 12345`**: Matches `define XRAY_TPROXY_PORT = 12345` in
  `xray-tproxy.nft`. `xray-tproxy.service` asserts this via `ss -lnH "sport = :12345"`
  during startup; binding any other port fails the start sequence.
- **`sniffing`**: Because transparently intercepted packets contain only raw IP
  destinations, domain sniffing is mandatory. `routeOnly: true` ensures the
  extracted domain is used solely for routing rule evaluation while the original
  destination IP is retained for dialing.

#### B. Outbound Specification (Bypass Mark & Loop Prevention)
The `output` chain in `xray-tproxy.nft` intercepts all local outbound TCP/UDP
traffic and marks it with `fwmark 1` (sending it back into table 110 and Xray),
**except** packets carrying mark `2`:

```nft
chain output {
  ...
  meta mark $BYPASS_MARK return   # BYPASS_MARK = 2
  ...
  ip protocol tcp meta mark set $XRAY_MARK counter
  ip protocol udp meta mark set $XRAY_MARK counter
}
```

Therefore, **every outbound that dials external network sockets (both `proxy`
tunnels and `direct` connections) MUST set `sockopt.mark: 2`**:

```json
{
  "protocol": "freedom",
  "tag": "direct",
  "streamSettings": {
    "sockopt": {
      "mark": 2
    }
  }
}
```

> **FATAL FAILURE MODE**: If `mark: 2` is omitted from any dialing outbound,
> Xray's own outgoing packets will be caught by Netfilter, marked with `1`,
> routed into table 110, and delivered right back into Xray's inbound port
> `12345`. This produces an instantaneous infinite routing loop and packet
> storm that exhausts kernel sockets and halts all networking.

#### C. DNS Routing & Process Identity
1. **User Whitelist**: `xray-tproxy.nft` explicitly exempts DNS queries from the
   `xray` user (`meta skuid "xray"`) to allow Xray's built-in DNS module to
   query the local `127.0.0.53` stub resolver without looping. The daemon must
   run under `User=xray`.
2. **DNS Routing**: nftables redirects all destination port 53 traffic to
   Xray's dokodemo-door inbound. The Xray routing configuration must forward
   intercepted port-53 queries to internal DNS resolution:
   ```json
   {
     "type": "field",
     "inboundTag": ["all-in"],
     "port": 53,
     "outboundTag": "dns-out"
   }
   ```

#### D. Capabilities
Calling `setsockopt` with `IP_TRANSPARENT` (inbound) and `SO_MARK` (outbound)
requires Linux `CAP_NET_ADMIN`. `xray-tproxy.service` grants this via
`AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW`. Running
Xray manually from an unprivileged shell without these capabilities will result
in `permission denied` socket errors.

---

## 3. Minimal Compliant Configuration Skeleton

Below is a minimal, compliant structural skeleton satisfying the host TProxy
contract:

```json
{
  "log": { "loglevel": "warning" },
  "dns": {
    "servers": [
      {
        "address": "localhost",
        "domains": ["geosite:private", "geosite:cn"],
        "skipFallback": true
      },
      "https://1.1.1.1/dns-query"
    ],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "tag": "all-in",
      "listen": "127.0.0.1",
      "port": 12345,
      "protocol": "dokodemo-door",
      "settings": { "network": "tcp,udp", "followRedirect": true },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      },
      "streamSettings": { "sockopt": { "tproxy": "tproxy" } }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "tag": "proxy",
      "settings": {
        "vnext": [
          {
            "address": "203.0.113.10",
            "port": 443,
            "users": [
              {
                "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "sockopt": { "mark": 2 }
      }
    },
    {
      "protocol": "freedom",
      "tag": "direct",
      "streamSettings": {
        "sockopt": { "mark": 2, "domainStrategy": "UseIPv4v6" }
      }
    },
    { "protocol": "dns", "tag": "dns-out" },
    { "protocol": "blackhole", "tag": "blocked" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "inboundTag": ["all-in"], "port": 53, "outboundTag": "dns-out" },
      { "type": "field", "ip": ["geoip:private", "geoip:cn"], "outboundTag": "direct" },
      { "type": "field", "domain": ["geosite:cn"], "outboundTag": "direct" },
      { "type": "field", "network": "tcp,udp", "outboundTag": "proxy" }
    ]
  }
}
```

---

## 4. Documentation References

- **Installation & Setup**: [How to Install and Start the Transparent Proxy](../../docs/how-to/install-and-start.md)
- **Ready-to-Deploy Schemes**: [Transport Schemes](../../schemes/README.md)
- **Full Client Configuration Reference**: [Client Configuration Reference](../../docs/reference/client-configuration.md)
- **Host Artifacts & Lifecycles**: [Host Artifacts Reference](../../docs/reference/host-artifacts.md)
- **Traffic Interception Rules**: [Traffic Selection Reference](../../docs/reference/traffic-selection.md)
- **Packet Journey & 3-Tier Model**: [Data Packet Lifecycle](../../docs/explanation/packet-lifecycle.md)
