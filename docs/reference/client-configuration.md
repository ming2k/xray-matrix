# Client Configuration Reference

Lookup for the Xray client config. The template lives at
[xray-config/client/config-example.json](../../xray-config/client/config-example.json);
the deployed copy is `/etc/xray/config.json`. The unit starts Xray with
`-config /etc/xray/config.json`, so exactly one file is loaded: extra
`*.json` files placed in `/etc/xray/` are ignored, not merged.

## Placeholders

Replace every placeholder before starting the service.

| Placeholder | Meaning | Where to get it |
|-------------|---------|-----------------|
| `<SERVER_IP:...>` | Server public IP | Your server provider |
| `<SERVER_IP_2:...>` | Any further server address used by this profile | Your server provider |
| `<OWN_DOMAIN:...>` | A host you reach directly by name (panel, own site) | You |
| `<UUID:...>` | VLESS user ID | The `id` field in the server config |
| `<SERVER_NAME:...>` | REALITY camouflage SNI | The server `serverNames` entry |
| `<PUBLIC_KEY:...>` | REALITY public key | Public half of `xray x25519` on the server |
| `<SHORT_ID:...>` | REALITY short ID | One of the server `shortIds` |

`dns.servers` pins its private-domain resolver to `localhost`, which is
`systemd-resolved`; it follows whatever upstream the current link got via
DHCP, so no gateway address needs editing when the LAN changes.

## Inbound

| Key | Value | Effect |
|-----|-------|--------|
| `protocol` | `dokodemo-door` | Accepts intercepted traffic |
| `listen` | `127.0.0.1` | TProxy redirects to loopback (`tproxy to 127.0.0.1:$XRAY_TPROXY_PORT`); binding `0.0.0.0` would expose a transparent-proxy port to the LAN |
| `port` | `12345` | Matches `XRAY_TPROXY_PORT` in the nftables rules |
| `settings.followRedirect` | `true` | Honors the kernel redirect |
| `streamSettings.sockopt.tproxy` | `"tproxy"` | Enables TProxy socket mode |
| `sniffing.enabled` | `true` | Reads HTTP Host / TLS SNI / QUIC SNI |
| `sniffing.destOverride` | `["http", "tls", "quic"]` | Supplies the domain to the routing engine (SNI, Host, QUIC SNI) |
| `sniffing.routeOnly` | `true` | Sniffed domain is used **only** for rule matching; the outbound still dials the original destination address |

## Local SOCKS Inbound

A loopback-only SOCKS5 endpoint exists for applications that cannot be
classified by sniffing (for example `git` or `ssh`); point them at it with
their own proxy settings.

| Key | Value | Effect |
|-----|-------|--------|
| `listen` / `port` | `127.0.0.1:1080` | Loopback only; no LAN exposure |
| `protocol` / `settings.auth` | `socks` / `noauth` | SOCKS5 with UDP support |
| `sniffing.destOverride` | `["http", "tls", "quic"]` | Same routing-only domain extraction as the TProxy inbound |

Usage examples: `git config --global http.proxy socks5h://127.0.0.1:1080`,
`ssh -o ProxyCommand='nc -X 5 -x 127.0.0.1:1080 %h %p' host`.

## Local API Inbound and Statistics

Turns "which outbound carried this connection" into a query. Without
them the only evidence is the nftables counters, which cannot tell direct
from proxied.

| Key | Value | Effect |
|-----|-------|--------|
| `stats` | `{}` | Enables the per-outbound/per-inbound counters |
| `policy.system.statsOutboundUplink` / `statsOutboundDownlink` | `true` | Count bytes per outbound tag |
| `api.tag` | `api` | Name the routing rules target |
| `api.services` | `StatsService`, `HandlerService`, `RoutingService` | Query stats, inspect and hot-change routing |
| `inbounds[tag=api]` | `dokodemo-door` on `127.0.0.1:10085` | Transport for the API |

Loopback only: `HandlerService` can change routing at runtime. Its routing
rule stays first, since it may never be shadowed.

Read the counters with:

```sh
xray api statsquery --server=127.0.0.1:10085 -pattern 'outbound>>>' | \
  jq -r '.stat[] | "\(.name)\t\(.value)"'
```

Add `-reset` to zero them. Whether
`outbound>>>direct>>>traffic>>>uplink` or
`outbound>>><proxy tag>>>>traffic>>>uplink` grows tells you which path the
connection actually took.

## Outbounds

| Tag | Protocol | Purpose |
|-----|----------|---------|
| `proxy` | `vless` (REALITY, `xtls-rprx-vision`) | Remote server |
| `direct` | `freedom` | Local/direct forwarding |
| `dns-out` | `dns` | Xray internal DNS loopback |
| `blocked` | `blackhole` | Drop; referenced by the ad-domain rule |

The `proxy` tag is local to this template — a deployment may rename it
(for example after the server it points at). Every `outboundTag` in
`routing.rules` must be renamed with it.

The two dialing outbounds (`proxy`, `direct`) set
`streamSettings.sockopt.mark: 2`, which matches `BYPASS_MARK` in the
nftables rules so Xray's own connections are never re-intercepted;
`dns-out` and `blocked` never open a socket and need no mark. They also
configure `tcpKeepAliveIdle: 15` and `tcpKeepAliveInterval: 5` to prune
stale sockets quickly after sleep/wake or network interface switches.

`direct` sets `streamSettings.sockopt.domainStrategy: "UseIPv4v6"`. The
older `settings.domainStrategy` key was deprecated: the current release
migrates it automatically and logs a warning, and it will be removed in a
future release, so keep it under `sockopt`.

## Routing Rules

`routing.domainStrategy` is `IPIfNonMatch`. Rules evaluate top to bottom;
first match wins.

| Order | Match | Outbound |
|-------|-------|----------|
| 0 | `inboundTag: api` | `api` — local gRPC, never proxied |
| 1 | `inboundTag: all-in, socks-in, port: 53` | `dns-out` — Smart DNS resolution |
| 2 | `ip: <SERVER_IP>, <SERVER_IP_2>` | `direct` — never proxy the proxy |
| 3 | `domain: <OWN_DOMAIN>` | `direct` — hosts reached by name |
| 4 | `domain: connectivity check hosts` | `direct` — must precede every proxy rule |
| 5 | `domain: kimi.ai, moonshot.ai, minimax.io, qoder.com, lovart.ai` | `direct` — domestic AI that `category-ai-!cn` also lists |
| 6 | `domain: geosite:github` | `proxy` |
| 7 | `domain: geosite:category-ads-all` | `blocked` — dropped, not proxied |
| 8 | `protocol: bittorrent` | `blocked` — dropped, not proxied |
| 9 | `ip: geoip:private` | `direct` |
| 10 | `network: udp, port: 443` | `blocked` — QUIC dropped for everything not already direct, before any proxy rule |
| 11 | `domain: full:ftp.gnu.org, domain:gnu.org, domain:kernel.org` | `proxy` |
| 12 | `domain: geosite:google, geosite:category-ai-!cn` | `proxy` — explicit proxy overrides before domestic list |
| 13 | `domain: geosite:private, geosite:cn` | `direct` |
| 14 | `ip: geoip:cn` | `direct` |
| 15 | `network: tcp,udp` (everything else) | `proxy` |

Ordering carries meaning, so insert new rules deliberately:

- Rule 0 is the API handler: it must precede every other rule, because a
  proxied API request would silently break `statsquery`.
- Rule 4 (connectivity checks) must precede every proxy rule. Every one of
  those names is also in `geosite:google` and `geosite:geolocation-!cn`, so
  a later position is not a weaker choice — it is dead configuration, and
  captive portals go undetected because the check answers through the
  tunnel.
- Proxy rules (6, 11, 12) sit **before** the domestic direct rule (13) so a
  domain listed in both `geosite:cn` and an overseas category still leaves
  through the proxy.
- The ad rule (7) and the bittorrent rule (8) also sit before rule 13;
  placed after it, a matching `geosite:cn` domain would be allowed through.
- Rule 5 is the mirror image of rule 12: `category-ai-!cn` lists five
  domains operated from inside China (`kimi.ai`, `moonshot.ai`,
  `minimax.io`, `qoder.com`, `lovart.ai`), which must stay direct.
- Rule 10 drops QUIC rather than tunnelling it: the tunnel is TCP (Vision),
  so QUIC becomes UDP-in-TCP. It sits **before** every proxy rule on
  purpose. Routing is decided per packet, but only the first QUIC packet
  carries an SNI, so a domain rule in front of it tunnels the first packet
  and drops the rest of the same connection — the browser then stalls on
  QUIC before falling back. Dropped uniformly, the fallback is immediate.
  The cost is that domestic QUIC also falls back to HTTP/2; LAN QUIC stays
  direct through rule 9, which matches on IP and needs no SNI.
- Rule 15 is the fallback, and it proxies: the list is allow-by-exception,
  so an outdated ruleset errs towards tunnelling rather than leaking.

## Built-In DNS

Xray uses its own `dns` module for Smart DNS resolution (see
[DNS](../explanation/dns.md)).

| Server | Used for | Verification / Notes |
|--------|----------|----------------------|
| `localhost` (system resolver / `127.0.0.53`) | `geosite:private`, `domain:local`, `domain:lan`, captive portal probes | `skipFallback: true` — pinned to its domains, never joins the fallback chain. Do not use `finalQuery: true` here: it truncates the fallback list at position 0 and kills resolution for every domain not present in the geosite lists |
| `https://1.1.1.1/dns-query` (Cloudflare DoH via `proxy`) | `geosite:geolocation-!cn`, `geosite:google`, `geosite:category-ai-!cn`, `geosite:github` | Encrypted inside proxy tunnel; must be listed before `223.5.5.5` |
| `223.5.5.5` (AliDNS) | `geosite:cn` | Deliberately **no** `expectedIPs`: filtering answers sends a CN domain with an overseas edge to the DoH fallback and then connects direct to a foreign IP |
| `https://1.1.1.1/dns-query` (Cloudflare DoH via `proxy`) | Default fallback | Encrypted inside proxy tunnel |

`localhost` automatically queries whatever upstream DNS is assigned by
DHCP to the current Wi-Fi/Ethernet link, enabling captive portal login
detection on any network without manual reconfiguration.

`dns.queryStrategy` is `UseIPv4`: the host has no global IPv6, and enabling
it without an IPv6 path to the server makes dual-stack destinations hang.

`dns.disableFallbackIfMatch` is `true`: the first server whose `domains`
match answers, and never falls through to the next entry — otherwise the
`geosite:cn` entry can be answered by the DoH entry. `serveStale` plus
`serveExpiredTTL: 3600` keep resolution working while an upstream is
unreachable.
