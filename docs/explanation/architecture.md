# Architecture

The system is two layers: a **datapath layer** that does not care which
transport is in use, and a **scheme layer** that is nothing but the transport.
Keeping them disjoint is what lets a scheme be swapped without touching the
kernel-side machinery, and lets the datapath be reasoned about once.

---

## 1. End-to-End System Topology

```text
[Client Applications]
        |
        v
+-----------------------------------------------------------------------------+
| CLIENT HOST — workstation / gateway datapath (scheme-independent)           |
| 1. nftables: Marks external TCP/UDP packets with fwmark=1 (bypasses mark 2) |
| 2. Policy Routing: fwmark=1 -> Table 110 -> local delivery to loopback     |
| 3. Xray TProxy (:12345): Recovers original destination IP (IP_TRANSPARENT)   |
| 4. Smart DNS: localhost for portals, 223.5.5.5 for CN, DoH for foreign      |
| 5. Routing: Classifies direct / blocked / proxy                             |
+-------------------------------------+---------------------------------------+
                                      |
                     Pluggable Transport Scheme Tunnel
                     (e.g., VLESS + TCP + XTLS-Vision + REALITY or TLS)
                                      |
                                      v
+-----------------------------------------------------------------------------+
| SERVER HOST — VPS egress datapath (scheme-independent)                      |
| 1. nftables: Stateful baseline firewall (drops invalid, admits 22/80/443)   |
| 2. Kernel Tuning: BBR congestion control, TCP Fast Open, 64MB buffers       |
| 3. Xray Server (:443): Terminates outer TLS/REALITY, authenticates VLESS    |
| 4. Active Probing Defense: Direct deflection (REALITY) or Fallback (TLS)    |
| 5. Outbound Freedom: High-speed egress to the global Internet               |
+-----------------------------------------------------------------------------+
```

---

## 2. Layer Boundary: Scheme versus Datapath

The transport tunnel between client and server is decoupled from the underlying operating system datapaths:
- **Client Datapath Invariant**: The client's kernel Netfilter rules, routing policy table 110, Smart DNS split, and local application interceptions remain identical regardless of which transport scheme is selected.
- **Server Datapath Invariant**: The server's kernel BBR tuning, firewall rules, and systemd service sandboxing remain identical across schemes.
- **Scheme Pluggability**: A scheme directory in `schemes/` pairs a complete
  client config (`client.json`) with a complete server config (`server.json`),
  so switching schemes means deploying the other directory's pair and touching
  nothing else. What each scheme does with an unauthenticated connection, and
  how they differ, is described in
  [Transport Schemes](../../schemes/README.md).

---

## 3. Client Datapath Mechanics

The client moves application traffic through Xray without any per-application proxy configuration:

```text
[Application] -> [OUTPUT chain] -> [Policy Routing] -> [Loopback Interface] -> [Xray]
      |               |                  |                    |                |
   Creates         nftables          fwmark=1 lookup      table 110        Xray reads
   traffic         sets mark         110 selects          local route       original dst
                                      table 110           delivers to lo    and forwards
```

1. nftables marks intercepted application packets with `fwmark=1`.
2. Policy routing sends mark-1 packets into routing table `110`.
3. Table `110` contains a `local` route to loopback, delivering packets to Xray while preserving the original destination IP.
4. Xray inspects original destinations, performs domain sniffing, queries Smart DNS, and forwards traffic according to routing rules.

See [Traffic Selection Reference](../reference/traffic-selection.md) and [Data Packet Lifecycle](packet-lifecycle.md).

---

## 4. Component Ownership Boundaries

| Component | Owner |
| :--- | :--- |
| **Client nftables tables (`xray_v4` / `xray_v6`)** | `xray-tproxy.service` (`ExecStartPre` loads, `ExecStopPost` removes on explicit stop) |
| **Client Table 110 routes** | `xray-tproxy.service` (`ExecStartPre`) |
| **Client fwmark policy rule** | `systemd-networkd` drop-in (`xray-policy.conf`), installed per uplink; unit repairs if missing |
| **Client Xray daemon** | `xray-tproxy.service`, running as unprivileged user `xray` |
| **Server Kernel Tuning** | `sysctl.d/99-xray-tuning.conf` (BBR, TFO, socket buffers) |
| **Server Firewall** | `host/server/xray-server.nft` |
| **Server Xray daemon** | `xray-server.service`, running as unprivileged user `xray` with `CAP_NET_BIND_SERVICE` |
| **Server Web Fallback** | Local Nginx or Caddy listening on `127.0.0.1:8080` |

---

## 5. Reliability & Security Guarantees

### Suspend and Resume Resiliency
On `systemd-networkd` client hosts, a suspend/resume cycle may reconfigure the uplink and drop foreign `ip rule` entries while leaving route tables intact. The client unit uses an uplink drop-in owned by networkd, so networkd automatically reapplies the rule upon reconfiguring the link.

### Fail-Closed Restarts
On the client, `ExecStopPost` branches on `$SERVICE_RESULT`:
- `success` (operator stop/restart): Tables and routes are removed, restoring direct networking.
- Anything else (crash, signal, timeout): The datapath stays installed. The `Restart=always` window drops traffic rather than leaking unencrypted packets.

### Privilege Sandboxing
Both client and server run as the unprivileged `xray` user with strict systemd security boundaries (`ProtectHome`, `ProtectSystem=strict`, `NoNewPrivileges=true`, `PrivateDevices`, `MemoryDenyWriteExecute`).
