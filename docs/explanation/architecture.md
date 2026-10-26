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
- **The Socket & Netfilter Contract**: While schemes are pluggable, the client
  datapath enforces a strict interface contract with Xray Core: the OS layer
  provides `CAP_NET_ADMIN` and routes intercepted traffic to loopback port `12345`,
  while Xray must bind with `IP_TRANSPARENT` (`sockopt.tproxy: "tproxy"`),
  perform payload domain sniffing, and mark all dialing outbounds with
  `sockopt.mark: 2` (`BYPASS_MARK`) to prevent infinite routing loops.
  See [host/client/README.md](../../host/client/README.md) and
  [Client Datapath Contract](../reference/host-artifacts.md#3-client-datapath-contract-xray-interface-requirements).

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

## 4. Component Ownership

Ownership is exclusive: each piece of kernel state has exactly one writer, so
recovery is deterministic and no component has to guess whether another has
already done its part.

| State or component | Owner | Why that owner |
| :--- | :--- | :--- |
| Client nftables tables | the client unit | It loads them on every start, so a `flush ruleset` cannot leave a half-broken state |
| Client table-110 routes | the client unit | Same lifecycle as the tables |
| Client fwmark policy rule | the networkd uplink drop-in | networkd is the component that knows the uplink was reconfigured; the unit repairs the rule but never removes it |
| Both Xray daemons | their units, as the unprivileged `xray` user | Least privilege, and the account name is itself part of the ruleset's contract |
| Server firewall | the server host's own nftables configuration | Independent of Xray's lifecycle |
| Server kernel tuning | the server host's sysctl configuration | Applied at boot, not per service start |
| Web fallback | a separate local web server | It must outlive Xray restarts, so the Xray unit cannot own it |

The concrete files, sysctl keys, sandbox flags and start/stop sequences behind
this table are lookup material:
[Host Artifacts Reference](../reference/host-artifacts.md).

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
