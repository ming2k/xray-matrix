# Traffic Selection Reference

Lookup for what the nftables rules in
[host/client/xray-tproxy.nft](../../host/client/xray-tproxy.nft) intercept and what they bypass.
The tables are `ip xray_v4` and `ip6 xray_v6`; each has a `prerouting`
chain (traffic passing through) and an `output` chain (locally generated
traffic).

## Constants

| Name | Value | Meaning |
|------|-------|---------|
| `XRAY_MARK` | `1` | fwmark on intercepted packets; policy routing sends it to table `110` |
| `BYPASS_MARK` | `2` | fwmark that skips interception; Xray outbounds set it via `sockopt.mark` |
| `XRAY_TPROXY_PORT` | `12345` | Xray `dokodemo-door` inbound port |
| routing table | `110` | Contains `local default dev lo` for mark-1 packets |
| policy rule | `32765` | `from all fwmark 0x1 lookup 110`, owned by the systemd-networkd drop-in `xray-policy.conf`; the unit repairs it if missing |

## Intercepted and Bypassed Rule Order

Rules evaluate top to bottom in both `prerouting` and `output` chains; first match applies:

1. **Mark-2 bypass** (`meta mark $BYPASS_MARK return`): Xray's own outbound connections must not loop.
2. **ICMP bypass** (`ip protocol icmp return`, `icmpv6 type { ... } return`): Ping and neighbor discovery stay direct.
3. **DHCP bypass** (`udp sport 67 udp dport 68 return` in `prerouting`, `udp dport 67 return` in `output`): A lease reply can be unicast to an address the host does not own yet, so the reserved-range checks below never see it and TProxy would blackhole the renewal.
4. **DNS loop exemption** (`meta skuid "xray"/"systemd-resolve" dport 53 ... meta mark 0 return` in `output`; `ip daddr 127.0.0.53 dport 53 meta mark 0 return` in IPv4 `prerouting`): Xray's `localhost` queries and resolved's upstream forwards leave unmarked and reach their real destinations. Without this pair the localhost DNS path re-intercepts itself and starves.
5. **DNS interception** (`tcp/udp dport 53` -> TProxy / mark 1): Intercepted **before** IP range bypass so DNS queries to LAN gateways (e.g. `192.168.1.1:53`) do not bypass Xray and leak plaintext queries to GFW.
6. **Reserved & LAN IP bypass** (`ip daddr $RESERVED_IP return`, `ip daddr 192.168.0.0/16 return`): Non-DNS traffic to router web interfaces, local NAS, and LAN services stays direct.
7. **Remaining TCP/UDP interception** (`ip protocol tcp/udp` -> TProxy / mark 1): Redirected to Xray dokodemo-door for Smart Routing.

| Traffic | Action / Rule | Reason |
|---------|---------------|--------|
| Mark-2 packets | `meta mark $BYPASS_MARK return` | Xray outbounds |
| ICMP / essential ICMPv6 | `ip protocol icmp return` | Native ping & discovery |
| DHCP (67/68) | `udp sport 67 udp dport 68 return`, `udp dport 67 return` | Lease renewal must not depend on the tunnel |
| DNS from `xray` / `systemd-resolve` users (mark 0) | `meta skuid ... return` | Break the localhost/forward loop |
| Unmarked port-53 to `127.0.0.53` | `ip daddr 127.0.0.53 ... return` (prerouting) | Deliver Xray's `localhost` queries to the stub |
| DNS (port 53) | Intercepted to Xray | Clean DNS via DoH / Smart Split |
| Non-DNS Reserved & LAN (`0/8`, `10/8`, `127/8`, `169.254/16`, `172.16/12`, `192.0.2/24`, `192.88.99/24`, `198.18/15`, `198.51.100/24`, `203.0.113/24`, `224/4`, `240/4`, `192.168/16`) | `return` | Local services, CGNAT/VPN tunnels and documentation ranges direct |
| All other TCP/UDP | Intercepted to Xray | Transparent proxy |

Note: Higher-level application traffic (DNS port 53, HTTP port 80, Root processes) is intercepted by nftables and classified by Xray's routing engine (`geosite:cn`, `geosite:private`, captive portal probes, `geoip:cn`, etc.).

## Live Inspection

```sh
sudo nft list table ip xray_v4
sudo nft list table ip6 xray_v6
```

Every intercept rule carries a `counter`. Zero counters mean the chain is
not intercepting, however healthy the service looks:

```sh
sudo nft -j list table ip xray_v4 | \
  jq '[.. | objects | select(has("counter")) | .counter.packets] | add'
```

## Ownership

The tables are not part of `/etc/nftables.conf`: the unit recreates them on
every start and removes them on an explicit stop, so a `flush ruleset`
cannot leave a half-broken state. The `fwmark 1 -> table 110` policy rule is
owned elsewhere — by the networkd drop-in `xray-policy.conf`, one per uplink
profile. See [Architecture](../explanation/architecture.md#component-ownership).

