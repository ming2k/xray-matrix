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
| `table ip xray_v4`, `table ip6 xray_v6` | the client unit | Deleted and reloaded on every start; deleted only on an explicit stop |
| `local default dev lo` route in table `110`, v4 and v6 | the client unit | Added on start if absent; flushed on an explicit stop |
| `fwmark 0x1 lookup 110` policy rule, v4 and v6 | the `systemd-networkd` drop-in | One per uplink profile; the unit **repairs** it if missing and never removes it |
| `/var/log/xray`, `/var/lib/xray` | the client unit (`LogsDirectory`, `StateDirectory`) | Created and owned by systemd |

The split is deliberate: `systemd-networkd` owns the rule because it is the
component that knows when the uplink is reconfigured, and the unit asserts the
rule rather than owning it. A profile without the drop-in would otherwise run
unprotected while the unit reports healthy.

### Start sequence

| Phase | Action | Failure behaviour |
|-------|--------|-------------------|
| `ExecStartPre` | Add the table-110 routes and repair the policy rule if missing | Fails the start |
| `ExecStartPre` | Delete both nftables tables, then load them from `/etc/nftables/xray-tproxy.nft` | Fails the start |
| `ExecStartPre` | `xray run -test` on the config | Refuses to start; a bad config never replaces a working process |
| `ExecStart` | Run Xray as `xray` | — |
| `ExecStartPost` | Assert the policy rule, both tables, and the `12345` listener | Fails the start |

The listener is *polled* (up to 10 s) rather than checked once: `Type=simple`
runs `ExecStartPost` as soon as the process is forked, while Xray still has to
load `geoip.dat`/`geosite.dat` before it binds. A single check would race the
start and turn a healthy service into a restart loop.

### Stop sequence

`ExecStopPost` branches on `$SERVICE_RESULT`:

| Result | Action |
|--------|--------|
| `success` (operator stop or restart) | Flush table 110, delete both tables — networking is direct again |
| Anything else (crash, signal, timeout) | Keep the datapath installed |

Keeping the datapath on failure is the fail-closed choice: during the
`RestartSec` window, traffic is dropped rather than leaking unproxied.

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

## 3. Server Unit

Same shape, without the datapath ownership: no nftables tables, no routes, no
policy rule. Its `ExecStartPre` runs `xray run -test` only.

| Setting | Value | Why |
|---------|-------|-----|
| Capabilities | `CAP_NET_BIND_SERVICE`, `CAP_NET_ADMIN` | Bind `443` as the unprivileged `xray` user |
| `XRAY_LOCATION_ASSET` | `/usr/share/xray:/usr/share/v2ray-rules-dat` | Two asset directories, so either layout works |
| `RestrictAddressFamilies` | `AF_INET AF_INET6 AF_UNIX` | No netlink needed; the server does not touch kernel state |
| `TimeoutStartSec` | `15` | Shorter than the client's: no listener polling after start |

The fallback web server (Nginx or Caddy) is a separate service and is not
managed by this unit.

## 4. Kernel Tuning (server)

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
