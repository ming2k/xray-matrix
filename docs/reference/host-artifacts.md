# Host Artifacts Reference

Lookup for the OS-layer files in `host/client/` and `host/server/`: what they
install, and what they own while running. Installation steps are in
[How to Install and Start the Transparent Proxy](../how-to/install-and-start.md)
and [How to Deploy an Xray Proxy Server on a VPS](../how-to/deploy-server.md);
this page is the behaviour behind them.

## 1. Service Accounts

| Name | Created by | Home | Note |
|------|-----------|------|------|
| `xray` (system user, no login shell) | `sysusers.d` entry | `/var/lib/xray` | Shared by both roles |

The name is part of the contract, not a preference: the client ruleset's
DNS-loop exemption matches `meta skuid "xray"`, and the units name the user in
`User=`. A deployment that renames the account loses the exemption.

## 2. Client Unit: What It Owns

| Kernel object | Owner | Lifecycle |
|---------------|-------|-----------|
| `table ip xray_v4`, `table ip6 xray_v6` | the client unit | Deleted and reloaded on start; deleted on stop |
| `local default dev lo` route in table `110`, v4 and v6 | the client unit | Added on start if absent; flushed on stop |
| `fwmark 0x1 lookup 110` policy rule, v4 and v6 | the client unit / networkd drop-in | Added on start if missing; removed on stop |
| `/var/log/xray`, `/var/lib/xray` | the client unit (`LogsDirectory`, `StateDirectory`) | The directories are created and owned by systemd; the two log files are re-owned to `xray` on every start |

The split is deliberate: `systemd-networkd` owns the rule because it is the
component that knows when the uplink is reconfigured, and the unit asserts the
rule rather than owning it. A profile without the drop-in would otherwise run
unprotected while the unit reports healthy.

### Start sequence

| Phase | Action | Failure behaviour |
|-------|--------|-------------------|
| `ExecStartPre` | Add the table-110 routes and repair the policy rule if missing | Fails the start |
| `ExecStartPre` | Delete both nftables tables, then load them from `/etc/nftables/xray-tproxy.nft` | Fails the start |
| `ExecStartPre` | Re-own `/var/log/xray/{access,error}.log` to `xray` | Fails the start |
| `ExecStartPre` | `xray run -test` on the config, as `xray` | Fails the start; a bad config never replaces a working process |
| `ExecStart` | Run Xray as `xray` | — |
| `ExecStartPost` | Assert the policy rule, both tables, and the `12345` listener | Fails the start |

The listener is *polled* (up to 10 s) rather than checked once: `Type=simple`
runs `ExecStartPost` as soon as the process is forked, while Xray still has to
load `geoip.dat`/`geosite.dat` before it binds. A single check would race the
start and turn a healthy service into a restart loop.

The config preflight is the one step without the `+` prefix, deliberately: a
preflight that runs as root answers the wrong question. It reads a
`config.json` the service user cannot read and writes the log files as
`root:root`, so a permission problem passes the check and reappears as
`status=23` in `ExecStart`. Running it as `xray` makes the preflight fail for
exactly the reasons the real start would fail. The ownership step before it
covers the remaining case: `LogsDirectory=` owns the directory, not the files
a root-run `xray` may have left inside it.

### Stop sequence

When the service stops, `ExecStopPost` tears down all proxy networking state:

1. Deletes the `ip xray_v4` and `ip6 xray_v6` nftables tables.
2. Flushes routing table `110` (both IPv4 and IPv6).
3. Deletes the `fwmark 0x1 table 110` policy routing rules.

This cleanly restores the pre-start network state so traffic falls back to normal direct networking.

During daemon failure or crash, systemd's `Restart=always` immediately schedules a restart without running `ExecStopPost`, keeping the datapath armed during the `RestartSec` window so intercepted traffic fails closed rather than leaking unencrypted.

### Capabilities and sandbox

`CapabilityBoundingSet` / `AmbientCapabilities`: `CAP_NET_ADMIN` (nftables and
routing), `CAP_NET_BIND_SERVICE` (`12345`), `CAP_NET_RAW`.

The sandbox is the common systemd set — `ProtectSystem=strict`,
`ProtectHome`, `PrivateTmp`, `PrivateDevices`, `ProtectKernelTunables`,
`ProtectKernelModules`, `ProtectControlGroups`, `ProtectClock`,
`RestrictNamespaces`, `RestrictSUIDSGID`, `LockPersonality`,
`MemoryDenyWriteExecute`, `RemoveIPC`, `RestrictAddressFamilies` limited to
`AF_INET AF_INET6 AF_UNIX AF_NETLINK`, `LimitNOFILE=1048576`.

`ExecStartPre` commands that touch kernel state carry the `+` prefix, which is
what lets them run outside the sandbox. `SystemCallFilter` is deliberately
absent — see [Policy Decisions](../explanation/policy-decisions.md#systemcallfilter-is-opt-in).

## 3. Client Datapath Contract (Xray Interface Requirements)

The client host layer (`host/client/`) and Xray Core operate across a strict
interface contract. Any client configuration deployed to `/etc/xray/config.json`
must satisfy these invariants; violating them breaks the transparent proxy or
causes immediate network failure:

| Kernel / OS Mechanism | Host Layer Source | Required Xray Configuration | Consequence if Missing |
|-----------------------|-------------------|-----------------------------|------------------------|
| TProxy listener | `xray-tproxy.nft`, `xray-tproxy.service` | `inbounds[].protocol = "dokodemo-door"`, `port = 12345` | Unit startup healthcheck poll fails after 10s |
| `IP_TRANSPARENT` | Linux TProxy routing table 110 | `inbounds[].streamSettings.sockopt.tproxy = "tproxy"` | TCP connections reset (RST); UDP packets dropped |
| Original destination recovery | Netfilter TProxy redirect | `inbounds[].settings.followRedirect = true` | Original destination IP lost |
| Loop prevention (`BYPASS_MARK`) | `xray-tproxy.nft` output chain (`mark 2`) | `streamSettings.sockopt.mark: 2` on all dialing outbounds (`proxy`, `direct`) | **Infinite routing loop / packet storm; system halts** |
| Payload SNI extraction | TProxy delivers raw IP without domain | `inbounds[].sniffing.enabled = true`, `routeOnly = true` | Domain-based routing (`geosite:*`, `domain:*`) never matches |
| DNS loop exemption | `xray-tproxy.nft` output chain (`meta skuid "xray"`) | `User=xray` in service unit; Smart DNS via `dns-out` | Localhost DNS resolution deadlock on `127.0.0.53` |

See [host/client/README.md](../../host/client/README.md) for the minimal
compliant skeleton and [Client Configuration Reference](client-configuration.md)
for field details.

## 4. Server Unit

Same shape, without the datapath ownership: no nftables tables, no routes, no
policy rule. Both start checks carry over from the client — the log files are
re-owned to `xray`, and the `xray run -test` preflight runs *as* `xray`, with
no `+` — because the schemes log to `/var/log/xray/` on the server too, and the
failure they prevent (`status=23`, `permission denied` on the log file) is
identical. See [Start sequence](#start-sequence).

| Setting | Value | Why |
|---------|-------|-----|
| Capabilities | `CAP_NET_BIND_SERVICE`, `CAP_NET_ADMIN` | Bind `443` directly as the unprivileged `xray` user. **Not needed on a host that demultiplexes `:443`** — there Xray binds `127.0.0.1:10443` and nginx holds the privileged port (see §5) |
| `XRAY_LOCATION_ASSET` | `/usr/share/xray:/usr/share/v2ray-rules-dat` | Two asset directories, so either layout works |
| `RestrictAddressFamilies` | `AF_INET AF_INET6 AF_UNIX` | No netlink needed; the server does not touch kernel state |
| `TimeoutStartSec` | `15` | Shorter than the client's: no listener polling after start |

The fallback web server (Nginx or Caddy) is a separate service and is not
managed by this unit.

## 5. Host That Serves Websites on 443

A server that already terminates TLS for real sites cannot give `:443` to Xray
without breaking them: nginx owns the wildcard port as a layer-4 SNI
demultiplexer and Xray sits behind it on loopback.

`host/server/nginx-stream/reality.conf` installs to
`/etc/nginx/stream.d/reality.conf`, and `nginx.conf` gains one include:

```nginx
stream {
    include /etc/nginx/stream.d/*.conf;
}
```

Port ownership on such a host — one owner per port, no shared binds:

| Port | Owner | Role |
| :--- | :--- | :--- |
| `0.0.0.0:443`, `[::]:443` | nginx (`www-data` workers) | L4 SNI demultiplexer; reads `ClientHello`, decrypts nothing |
| `127.0.0.1:8443`, `[::1]:8443` | nginx | Website TLS termination, unchanged certificates and HTTP/2 |
| `127.0.0.1:18443` | nginx | Strips the PROXY protocol header for the REALITY branch |
| `127.0.0.1:10443` | xray (`xray` user) | REALITY inbound, loopback only |

Three consequences worth knowing before editing anything:

- The website listeners must carry `ssl proxy_protocol`, and the `http` block must
  trust the demultiplexer (`set_real_ip_from 127.0.0.1; real_ip_header
  proxy_protocol;`). Missing either half logs every visit as `127.0.0.1`.
- `stream` is a separate module: Debian's `nginx` package needs
  `libnginx-mod-stream`, otherwise the directive is unknown even though
  `nginx -V` reports `--with-stream`.
- `/var/log/nginx/stream.log` records the demultiplexer's own verdicts
  (`sni=`, `backend=`, `status=`), which is what makes "the packet never arrived"
  distinguishable from "the backend failed".

## 6. Kernel Tuning (server)

`host/server/99-xray-tuning.conf` installs to `/etc/sysctl.d/` and needs the
server to host hundreds of concurrent tunnels:

| Setting | Value | Purpose |
|---------|-------|---------|
| `net.core.default_qdisc` | `fq` | The queue discipline BBR requires |
| `net.ipv4.tcp_congestion_control` | `bbr` | Congestion control for lossy long-haul paths |
| `net.ipv4.tcp_fastopen` | `3` | Enables TFO for both directions; `1` would be client-only |
| `net.core.rmem_max`, `net.core.wmem_max` | `67108864` | 64 MB socket buffer ceiling for high-BDP links |
| `net.ipv4.tcp_rmem`, `net.ipv4.tcp_wmem` | up to `67108864` | Per-socket auto-tuning ceiling |
| `net.core.somaxconn`, `net.core.netdev_max_backlog`, `net.ipv4.tcp_max_syn_backlog` | `65535` | Accept and backlog queues for a burst of new tunnels |
| `net.ipv4.ip_local_port_range` | `1024 65535` | Ephemeral source ports for egress connections |
| `net.ipv4.tcp_tw_reuse`, `net.ipv4.tcp_fin_timeout` | `1`, `15` | Recycle time-wait sockets under load |
| `net.ipv4.tcp_keepalive_*` | `300/15/5` | Drop dead peers |
| `net.ipv4.ip_forward`, `net.ipv6.conf.all.forwarding` | `1` | Allows the host to route, for deployments that use it as a gateway |
| `net.ipv4.tcp_syncookies` | `1` | Survive SYN floods |

Two couplings worth knowing:

- **`bbr` must exist as a module.** The client config sets no
  `tcpCongestion` for this reason; see
  [Policy Decisions](../explanation/policy-decisions.md#bbr-is-documented-not-configured).
- **The client needs the TFO client bit too.** The client config sets
  `tcpFastOpen: true`, which requires `net.ipv4.tcp_fastopen` to include bit
  `1` on the *client* host. `1` or `3` both work; `2` alone does not.
