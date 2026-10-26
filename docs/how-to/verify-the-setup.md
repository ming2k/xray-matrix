# How to Verify the Setup

Run after installing, and after any change to the ruleset or the client
config.

## The Datapath, End To End

The static checks below prove the rules are installed; these prove traffic
is still being *split*. Stop at the first failure.

```sh
# 1. domestic and overseas DNS both answer (system resolver -> Xray DNS)
getent ahostsv4 www.baidu.com
getent ahostsv4 www.gstatic.com

# 2. direct path
curl -s -o /dev/null -w '%{http_code}\n' -m 8 https://www.baidu.com/     # 200

# 3. proxied path: an overseas destination answers through the tunnel
curl -s -m 10 https://www.gstatic.com/generate_204 -o /dev/null -w '%{http_code}\n'   # 204

# 4. which outbound actually carried the traffic (needs the api inbound)
xray api statsquery --server=127.0.0.1:10085 -pattern 'outbound>>>' | \
  jq -r '.stat[] | "\(.name)\t\(.value)"'

# 5. the kernel is still intercepting, not just the process running
sudo nft -j list table ip xray_v4 | \
  jq '[.. | objects | select(has("counter")) | .counter.packets] | add'
```

Step 4 separates "worked" from "worked through the wrong path":
`outbound>>>direct>>>traffic>>>uplink` must grow for domestic traffic and
`outbound>>><proxy tag>>>>traffic>>>uplink` for overseas traffic. Add
`-reset` to zero the counters.

## Check the Static State

```sh
systemctl status xray-tproxy.service
ip rule show                     # expect: fwmark 0x1 lookup 110 (or "lookup xray")
ip -6 rule show                  # expect: the same
ip route show table 110          # expect: local default dev lo
sudo nft list tables             # expect: ip xray_v4 and ip6 xray_v6
```

## Check the Installed Unit

`systemctl status` proves a unit is *running*, not that it is the unit this
repository ships. A stale `xray-tproxy.service` shadows nothing and fails
nothing — it just behaves the way its own revision did, so a fixed start path
can keep failing after the fix is committed.

```sh
sudo cmp /usr/lib/systemd/system/xray-tproxy.service ./host/client/xray-tproxy.service
```

Installed through `wright`, compare against the sealed source instead — the one
the package actually built from:

```sh
sudo cmp /usr/lib/systemd/system/xray-tproxy.service \
         /var/lib/wright/sources/xray-tproxy-xray-tproxy.service
```

`differ` on the first form means the repository is ahead of the host; run
`sudo wright install xray-tproxy` (or the `install -Dm644` line from
[How to Install and Start the Transparent Proxy](install-and-start.md#install-the-os-layer)).
`differ` on the second form, right after a successful install, means the plan
was edited but never re-sealed.

Two lines are worth reading even when the files match:

```sh
systemctl cat xray-tproxy.service | grep -E '^(User|ExecStartPre)='
```

- `User=xray` — an older revision ran as `root`, which breaks the
  `skuid "xray"` DNS-loop exemption in the ruleset.
- The config preflight (`ExecStartPre=/usr/bin/xray run -test …`) has **no**
  `+` in front: with `+` it runs as root and can pass while the real start
  fails on a permission the service user does not have.

## Check That Traffic Is Intercepted

The nftables rules carry packet counters. Generate some traffic, then
read the table:

```sh
curl -s https://api.ipify.org >/dev/null
sudo nft list table ip xray_v4
```

The counters on the `tproxy` / `meta mark set` rules should grow.

## Check the Forwarding Result

```sh
curl -s https://api.ipify.org    # expect: your server's IP (proxied)
curl -s http://api.ipify.org     # expect: your server's IP (proxied; port 80 is protected)
dig +short google.com            # expect: authentic overseas IP (Real-IP via DoH)
dig +short edge.prelude.dev      # expect: answers — any domain outside the geosite lists must still resolve via the DoH fallback
```

Both HTTP (port 80) and HTTPS (port 443) for overseas destinations travel through the proxy tunnel. Domain resolution uses Real-IP via DoH without FakeIP subnet anomalies. See
[Traffic Selection Reference](../reference/traffic-selection.md) and [DNS](../explanation/dns.md).


## Check the Logs

```sh
journalctl -u xray-tproxy.service -n 50 --no-pager
sudo tail -n 50 /var/log/xray/error.log
```

If any check fails, go to
[How to Troubleshoot Common Problems](troubleshoot-common-problems.md).
