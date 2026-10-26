# Policy Decisions

Defaults that are choices, not facts. Each entry records what was decided,
why, and what it costs, so a later reader can overturn it deliberately
instead of "optimizing" it back.

## QUIC is dropped for everything not already direct

Rule `network: udp, port: 443 -> blocked` sits **after** the `geoip:private`
direct rule and **before** every proxy rule. The tunnel is TCP (VLESS +
Vision), so QUIC inside it is UDP-over-TCP: two congestion controllers glued
together, and a single lost packet hits both. Browsers retry over HTTP/2 and
users do not notice; what they would notice is the stall pattern QUIC
produces through the tunnel.

The position before the proxy rules is the part that must not move. Routing
is decided per packet, while only the first QUIC packet carries an SNI: with
a domain rule in front, the handshake packet was tunnelled and the rest of
the same connection fell through to this rule and was dropped, so browsers
sat in that half-open state before falling back. Dropped uniformly, the
fallback starts at once.

LAN QUIC stays direct through the `geoip:private` rule above, which matches
on IP and needs no SNI. Domestic QUIC now falls back to HTTP/2 as well — a
deliberate trade: consistency beats the small gain from QUIC on domestic
video and gaming.

Cost: applications with no HTTP/2 path (some games, some QUIC-only
telemetry) simply fail to reach overseas endpoints. If you accept
UDP-in-TCP, delete the rule and mark it here.

## Torrents are dropped, not sent direct

`protocol: bittorrent -> blocked`. The previous `direct` was the worst of
both worlds: the real address is exposed to the swarm anyway, and nothing is
bypassed. Tunnelling them instead is a legitimate choice — change the
outbound to `proxy` — but that shifts the traffic to the server's terms of
service and bandwidth, which is the operator's call, not a default.

## IPv6 is not carried

The host has no global IPv6, so `dns.queryStrategy` is `UseIPv4` and the
IPv6 nftables table exists only to keep the v4 and v6 paths symmetric for
the day an uplink provides IPv6. Enabling IPv6 egress requires all three:
an AAAA path to the server, `queryStrategy: UseIPv4v6`, and re-checking that
the proxy outbound can dial it. Doing only the last one makes dual-stack
destinations hang for the DNS timeout.

## DNS is not filtered by expected IP

`expectedIPs: ["geoip:cn"]` on the domestic resolver was removed. It reads
as anti-pollution, but it drops legitimate answers when a CN-branded domain
is served from an overseas edge; the query then falls through to DoH, and
the app connects **direct** to that foreign address because `geosite:cn`
already routed it direct. See [DNS](dns.md).

## BBR is documented, not configured

`streamSettings.sockopt.tcpCongestion: "bbr"` is deliberately absent. On
this kernel `bbr` is a module that is not loaded, and the socket option is
applied per connection: every dial would fail until it is. Enable it in two
steps, in this order, or not at all:

```sh
sudo modprobe tcp_bbr
sysctl net.ipv4.tcp_congestion_control   # expect bbr after the module loads
```

Then add `"tcpCongestion": "bbr"` to the `sockopt` of the `proxy` outbound.
`tcpFastOpen` and `happyEyeballs` are set: TFO needs
`net.ipv4.tcp_fastopen` to include the client bit, which it does here.

## SystemCallFilter is opt-in

`SystemCallFilter=@system-service` is not in the unit. It would almost
certainly be fine for a Go daemon, but a wrong filter kills the process at
start, and with the datapath owned by the unit that means no network rather
than a degraded proxy. Add it in a maintenance window and check for
`status=31/SYS` in `systemctl show -p ExecMainStatus`. `MemoryDenyWriteExecute`
and the rest of the sandbox are enabled and safe for the Go runtime.

## Configuration is a secret

`/etc/xray/config.json` holds the VLESS user ID and the REALITY key: mode
`600`, owner `root`, never in the repository (`xray-config/client/` excludes
`config-*.json` except the example). Credential templating was considered
and rejected: it needs a renderer at start-up, and a generator script in
this project is the thing the guidebook exists to avoid.

## Geo data is a dependency with a manual refresh

`geosite.dat` / `geoip.dat` change under the deployment, and a tag that
disappears turns a rule into an empty match. `ExecStartPre` runs
`xray run -test`, so a config that no longer loads is refused — but a tag
that still loads with different content is invisible. After any ruleset
update:

```sh
systemctl restart xray-tproxy
nft list table ip xray_v4 >/dev/null && echo tables ok
```

and record the data version in the change note. There is no watcher, on
purpose: silent reloads of routing rules are harder to debug than a
restart.
