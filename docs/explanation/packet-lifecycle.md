# Data Packet Lifecycle and Traffic Steering

This document explains the end-to-end journey of an application data packet through the transparent proxy system, and details the **three-tier steering and constraint architecture** used to plan, classify, and route traffic safely without loopbacks or leaks.

---

## 1. The Three-Tier Steering and Constraint Architecture

Instead of brute-force global gateway hijacking or heavy virtual TUN interfaces, this system applies a **progressive three-tier filtering and constraint model**:

```text
+-----------------------------------------------------------------------------+
| Layer 1: Kernel Netfilter (nftables)                                        |
| - Fast, coarse-grained packet marking                                       |
| - Loop prevention (mark 2 bypass)                                           |
| - DNS interception priority (port 53 before IP bypass)                      |
| - Local/LAN traffic bypass (10/8, 192.168/16, etc.)                          |
+-------------------------------------+---------------------------------------+
                                      | fwmark 1
                                      v
+-----------------------------------------------------------------------------+
| Layer 2: Kernel Policy Routing (RPDB & FIB Table 110)                       |
| - fwmark 1 matches Priority 32765 rule                                      |
| - Table 110 delivers foreign destinations to `dev lo` via `local default`   |
| - Kernel delivers packet to Xray TProxy socket without changing dst IP:port |
+-------------------------------------+---------------------------------------+
                                      | Delivered to :12345
                                      v
+-----------------------------------------------------------------------------+
| Layer 3: Application Proxy Engine (Xray Core)                               |
| - Inbound: dokodemo-door (IP_TRANSPARENT) recovers original destination     |
| - Sniffing: Extracts TLS SNI, HTTP Host, QUIC Server Name                   |
| - Smart DNS: Local resolver for portals, DoH for foreign domains            |
| - Routing: Fine-grained classification (direct / proxy / blackhole)         |
| - Outbound: Marks tunnel packets with mark 2 (preventing loops)             |
+-----------------------------------------------------------------------------+
```

### What each layer is allowed to decide

The three layers are not three passes over the same decision. Each one answers
a question the others cannot:

- **Netfilter** decides nothing about the destination. It marks candidates for
  interception and exempts what must not be touched — Xray's own outbound
  sockets, the DNS path, ICMP, and anything local. It never looks at a name.
- **Policy routing** decides nothing about the application. It takes a mark and
  hands the packet to loopback *with the original destination intact*, which
  is the single trick that makes a transparent proxy possible: Xray can still
  see where the packet was really going.
- **Xray** decides everything else, because it is the only layer that knows
  domains. Every policy about what to proxy, what to bypass, and how to resolve
  lives here and nowhere else.

Within each layer the order of the rules is load-bearing — in particular, DNS
must be intercepted before the LAN and reserved-range bypasses, or queries on
their way to a router's resolver travel in plaintext. The exact rule order,
mark values, route contents and DNS server list are lookup material, not
architecture: see the
[Traffic Selection Reference](../reference/traffic-selection.md) and
[Real-IP DNS Architecture](dns.md).

---

## 2. End-to-End Round-Trip Lifecycle (Packet Perspective)

Consider a typical request, e.g. `curl https://www.google.com`:

```mermaid
sequenceDiagram
    autonumber
    actor App as Application (curl)
    participant Res as System Resolver (systemd-resolved)
    participant Kernel as Linux Kernel (Netfilter & RPDB)
    participant XrayIn as Xray Inbound (dokodemo-door)
    participant XrayDNS as Xray Smart DNS
    participant XrayOut as Xray Outbound (VLESS/REALITY)
    participant VPS as Remote Proxy Server
    participant Dest as Target Server (Google)

    Note over App,Dest: Phase 0: DNS Resolution (Real-IP & Smart Split)
    App->>Res: 1. Resolves www.google.com
    Res->>Kernel: 2. Sends UDP 53 query
    Kernel->>Kernel: 3. Intercepted by nftables (dport 53) -> mark 1 -> Table 110
    Kernel->>XrayIn: 4. Delivered to dokodemo-door :12345
    XrayIn->>XrayDNS: 5. Routed to internal dns-out module
    XrayDNS->>VPS: 6. Queries Cloudflare DoH via proxy outbound
    VPS-->>XrayDNS: 7. Returns authentic unpolluted IP (e.g. 142.250.72.196)
    XrayDNS-->>App: 8. App receives authentic Real-IP

    Note over App,Dest: Phase 1: TCP Handshake & TProxy Interception
    App->>Kernel: 9. Emits TCP SYN to 142.250.72.196:443
    Kernel->>Kernel: 10. [nftables output] Non-mark-2 -> marks with fwmark 1
    Kernel->>Kernel: 11. [RPDB] Matches Priority 32765 (fwmark 1) -> Table 110
    Kernel->>Kernel: 12. [Table 110] local 0.0.0.0/0 dev lo -> routes to loopback
    Kernel->>XrayIn: 13. Delivered to Xray with original destination intact

    Note over App,Dest: Phase 2: Sniffing & Tunnel Encapsulation
    XrayIn->>XrayIn: 14. Accepts socket, sniffs TLS SNI: www.google.com
    XrayIn->>XrayOut: 15. Routing matches geosite:google -> selects proxy outbound
    XrayOut->>Kernel: 16. Encapsulates into VLESS+REALITY TCP stream (sockopt.mark = 2)

    Note over App,Dest: Phase 3: Outbound Egress
    Kernel->>Kernel: 17. [nftables] Matches meta mark 2 return (bypass)
    Kernel->>Kernel: 18. [RPDB] Skips 32765 -> matches 32766 (Table main default route)
    Kernel->>VPS: 19. Transmits encrypted packet across physical interface (wlan0)
    VPS->>Dest: 20. VPS connects to Google:443 and receives HTTP response

    Note over App,Dest: Phase 4: Inbound Return & Delivery
    VPS-->>XrayOut: 21. Encrypted response arrives at physical interface
    XrayOut->>XrayIn: 22. Xray decrypts stream and extracts original HTTP payload
    XrayIn-->>Kernel: 23. Writes payload to the local transparent socket
    Kernel-->>App: 24. curl reads data seamlessly from its TCP socket
```

---

## 3. System Invariants

Four properties hold at all times, and each one is why a whole class of bug
cannot happen here.

1. **Loop-free.** Xray's own outbound sockets are marked, and that mark is the
   first thing both nftables chains test. A tunnel packet therefore cannot be
   intercepted a second time, whatever else the ruleset contains.
2. **No plaintext DNS escape.** Port 53 is intercepted before any IP-range
   bypass, so a query aimed at a local ISP resolver is still resolved through
   Xray, and a poisoned answer from an uplink middlebox is never reachable.
3. **The host's own routing is untouched.** Table `main` and the default
   gateway are never rewritten; the proxy lives entirely in a separate routing
   table. Stopping the service therefore restores direct networking in one
   step instead of by undoing a rewrite.
4. **No stale tunnels.** Keepalive is configured on every outbound, so a
   connection whose peer vanished during a suspend or a Wi-Fi roam is detected
   and replaced rather than stalling the application's socket.

What implements each invariant — rule order, mark values, route contents,
keepalive settings — is lookup material:
[Traffic Selection Reference](../reference/traffic-selection.md) and
[Host Artifacts Reference](../reference/host-artifacts.md).
