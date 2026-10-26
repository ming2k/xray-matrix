# Architecture

The setup moves application traffic through Xray without any
per-application proxy configuration. Four components cooperate, and each
has exactly one owner.

## Traffic Flow

```text
[Application] -> [OUTPUT chain] -> [Policy Routing] -> [Loopback Interface] -> [Xray]
      |               |                  |                    |                |
   Creates         nftables          fwmark=1 lookup      table 110        Xray reads
   traffic         sets mark         110 selects          local route       original dst
                                      table 110           delivers to lo    and forwards
```

1. nftables marks intercepted application packets with `fwmark=1`.
2. Policy routing sends mark-1 packets into routing table `110`.
3. Table `110` contains a `local` route to loopback, so the kernel
   delivers the packet to Xray while preserving the original destination.
4. Xray inspects the original destination and forwards the traffic
   according to the configured routing rules (`direct` / `proxy` /
   `blocked`).

The exact match/bypass list is in
[Traffic Selection Reference](../reference/traffic-selection.md); the
defaults that are choices rather than facts are in
[Policy Decisions](policy-decisions.md).

## Component Ownership

| Component | Owner |
|-----------|-------|
| nftables tables `xray_v4` / `xray_v6` | `xray-tproxy.service` (`ExecStartPre` loads, `ExecStopPost` deletes on explicit stop) |
| `local default` routes in table `110` | `xray-tproxy.service` (`ExecStartPre`) |
| `fwmark 1 -> table 110` policy rule | `systemd-networkd` drop-in ([xray-policy.conf](../../xray-policy.conf)), installed per uplink profile; the unit only *repairs* it when missing and never removes it |
| Xray process | `xray-tproxy.service`, running as the unprivileged `xray` user |

Both halves fail silently on their own, which is why the unit asserts them:

- An uplink profile without the drop-in has no policy rule, so marked
  packets route normally: proxying is bypassed while the unit reports
  `active`. `ExecStartPre` repairs the rule and logs it; `ExecStartPost`
  fails if it is still missing.
- `flush ruleset` in `/etc/nftables.conf` deletes both tables, so the unit
  recreates them on every start instead of assuming they persist.

Stopping the service therefore restores plain networking completely: the
unit's `ExecStopPost` removes the nftables tables and flushes table `110`.
This property is what the captive-portal workaround in
[How to Use Captive Portal Networks](../how-to/use-captive-portal-networks.md)
relies on.

## Suspend And Resume

On `systemd-networkd` hosts, a suspend/resume cycle may reconfigure the
uplink and remove foreign `ip rule` entries while leaving nftables tables
and custom route tables intact. The typical symptom after resume:

- `sudo nft list tables` still shows `xray_v4` and `xray_v6`
- `ip route show table 110` still shows `local default dev lo`
- `ip rule show` no longer shows `fwmark 0x1 lookup 110`

Traffic then bypasses the proxy silently. Because the policy rule lives in
a networkd drop-in instead of in the service unit, networkd reapplies the
rule itself whenever it reconfigures the uplink, and
`networkctl reconfigure <uplink>` restores it manually. If the uplink has
no drop-in at all, the unit's repair path and its post-start assertion are
what surface it.

## Privilege Boundaries

Xray runs as `xray` with only
`CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW`, and with
`ProtectHome`, `ProtectSystem=strict`, `ProtectKernelModules` and
`PrivateDevices` set. Commands that touch kernel state carry the `+` prefix,
so they are the only unsandboxed part of the unit. Loop prevention relies
on mark matching:
Xray's own outbound connections carry `sockopt.mark: 2`, which the
nftables rules (`meta mark 2 return`) bypass explicitly. All process traffic
(including root administrative processes) is transparently intercepted and
routed according to Xray's rules.


## Fail-Closed Restart

`ExecStopPost` branches on `$SERVICE_RESULT`:

- `success` (operator stop/restart): tables and the `local default` route
  are removed, and the machine returns to plain networking;
- anything else (crash, signal, timeout): the datapath stays installed, so
  the `Restart=always` window drops traffic instead of leaking it unproxied.

A permanently failing unit therefore leaves the machine without
connectivity. That is the intended trade-off: silent bypass is worse than
no network.
