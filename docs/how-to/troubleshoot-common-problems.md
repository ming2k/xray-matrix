# How to Troubleshoot Common Problems

Match your symptom and apply the fix.

## Symptom Table

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Everything goes direct after suspend/resume | networkd reconfigured the uplink and dropped the policy rule | `sudo networkctl reconfigure wlan0`; the drop-in reapplies the rule |
| Service runs but nft counters stay at 0 | policy rule or table-110 route missing | check `ip rule show` and `ip route show table 110` |
| Xray fails to start | bad config, missing geodata, or missing log directory | `sudo -u xray xray run -test -config /etc/xray/config.json`; read the journal (`xray-tproxy preflight:` means the datapath, not the config, is the problem) |
| `Main process exited, code=exited, status=23`, journal says `open /var/log/xray/access.log: permission denied` | a root-run `xray` left `access.log`/`error.log` as `root:root 0600`, which the `xray` user cannot open | `sudo chown -R xray:xray /var/log/xray`; the unit re-owns both files on every start, so a restart also clears it. Never test with `sudo xray run` — use `sudo -u xray` |
| Restart loop, each attempt dies with `no TProxy listener on 12345` (no `after 10s`) | the deployed unit is an older revision that probes the listener once | `systemctl cat xray-tproxy.service`; reinstall the packaged unit, see [Check the Installed Unit](verify-the-setup.md#check-the-installed-unit) |
| IPv4 goes direct while IPv6 is proxied; `ip -6 rule show` has `fwmark 0x1` but `ip rule show` does not | the IPv4 `fwmark 0x1 lookup 110` rule was deleted — `ip rule del pref 32765` removes it, and the two families are separate rule sets | `sudo networkctl reconfigure wlan0` (or reinstall the drop-in) and restart the unit; the unit repairs the rule on start but a later `ip rule del` deletes it again |
| Service fails with `status=217/USER` | the `xray` user does not exist | `sudo useradd --system --no-create-home --shell /usr/bin/nologin xray` |
| Unit fails with `no TProxy listener on 12345 after 10s` | inbound port mismatch, wrong protocol, or missing `CAP_NET_BIND_SERVICE` | inbound must use `protocol: dokodemo-door`, `port: 12345`, and `sockopt.tproxy: "tproxy"`; see [Client Datapath Contract](../reference/host-artifacts.md#3-client-datapath-contract-xray-interface-requirements) |
| Starting the service triggers 100% CPU, packet storm, or network freeze | missing `sockopt.mark: 2` on an outbound dialing external hosts, causing an infinite routing loop | add `"streamSettings": { "sockopt": { "mark": 2 } }` to `proxy` and `direct` outbounds; see [Client Datapath Contract](../reference/host-artifacts.md#3-client-datapath-contract-xray-interface-requirements) |

| `geoip:cn` / `geosite:cn` rules never match | `geoip.dat` / `geosite.dat` not found | `XRAY_LOCATION_ASSET` must point at the directory holding the data files (the unit sets `/usr/share/v2ray-rules-dat`); the unit refuses to start when a referenced tag cannot be loaded — see [Where Each File Goes](install-and-start.md#where-each-file-goes) |
| A domain in `geosite:cn` fails DNS but resolves from another network | Domestic resolver returns an address the app cannot reach directly | Check with `getent ahostsv4 <domain>`; if the domestic answer is genuinely wrong, list the domain in the DoH entry — but do not re-introduce `expectedIPs`, it causes this; see [DNS](../explanation/dns.md) |
| Only unlisted/new domains fail DNS (e.g. `edge.prelude.dev`), geosite domains fine | `localhost` DNS server has `finalQuery: true`, truncating the fallback list | replace with `skipFallback: true`; see [DNS](../explanation/dns.md#the-dns-loop-hazard) |
| Portal probes (`captive.apple.com` etc.) time out; `resolvectl query` works but `getent` hangs | localhost DNS path re-intercepted: missing nft exemption for `xray`/`systemd-resolve` users | reinstall `xray-tproxy.nft` and restart the service; see [DNS](../explanation/dns.md#the-dns-loop-hazard) |
| Public Wi-Fi login page never opens | portal login page hosted on public HTTPS | see [How to Use Captive Portal Networks](use-captive-portal-networks.md) |
| Slow DNS right after joining a hotspot | walled garden blocks resolution pre-auth | expected; resolves itself after portal login |
| Blocked sites unreachable on a trusted network | DoH server unreachable or routing rule mismatch | check `journalctl -u xray-tproxy` and verify `dns-out` tag; see [DNS](../explanation/dns.md) |

## Server Symptoms

These belong to an egress node, with or without websites on port 443.

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `nginx: [emerg] unknown directive "stream"` although `nginx -V` shows `--with-stream` | Debian's `nginx` package does not bundle the stream module | `sudo apt-get install -y libnginx-mod-stream`, then confirm `/etc/nginx/modules-enabled/50-mod-stream.conf` exists |
| `nginx: [emerg] "map" directive is not allowed here` | `map` was placed at the main context | put it inside `stream { }`; the demultiplexer file is included from there |
| REALITY handshakes fail with `tls: first record does not look like a TLS handshake` | `sockopt.acceptProxyProtocol` is set on a REALITY inbound, which cannot parse the header | remove it and terminate the PROXY header one hop earlier; see [How to Share Port 443 with an Existing Website](share-port-443-with-a-website.md) |
| Roughly one connection in five fails, nothing in any log, and it started after a demultiplexer change | `proxy_pass` names a `host:port` variable, which is re-parsed per connection | declare `upstream` blocks and point the map at group names |
| Website access log shows `127.0.0.1` for every visitor | the PROXY header is sent but not consumed, or `real_ip` is not configured | add `proxy_protocol` to the site's `listen` line **and** `set_real_ip_from 127.0.0.1; real_ip_header proxy_protocol;` to the `http` block |
| Every visitor's IP looks correct, but the server's own health checks fail on the public name | the loopback backend requires the PROXY header and the probe does not send one | probe with `--resolve <name>:443:127.0.0.1` through the demultiplexer, not against `8443` directly |
| A website is unreachable for one network while the server is demonstrably healthy | on-path SYN loss to that `(IP, 443)` pair, or the demultiplexer never saw the connection | follow [Confirm Whether the Packet Reached the Server](diagnose-gfw-blocks.md#step-4-confirm-whether-the-packet-reached-the-server) before changing any configuration |
| The website works but a long-lived stream (SSE) delivers everything at once at the end | a proxy layer is buffering the response | `proxy_buffering off; proxy_cache off; gzip off;` plus HTTP/1.1 to the upstream; see [Streaming Endpoints](share-port-443-with-a-website.md#62-streaming-endpoints-behind-the-demultiplexer) |


## Check the Suspend/Resume Case

After a suspend cycle, compare these three:

```sh
sudo nft list tables             # tables still present
ip route show table 110          # local default still present
ip rule show                     # fwmark 0x1 lookup 110 missing?
```

A missing `fwmark` rule with the other two intact is the signature of the
networkd reconfiguration problem. The fix is the drop-in described in
[How to Install and Start the Transparent Proxy](install-and-start.md#install-the-policy-rule-drop-in);
background is in [Architecture](../explanation/architecture.md#suspend-and-resume-resiliency).

## Silent Bypass

Pages load, nothing is proxied, and `systemctl status xray-tproxy` is
green.

```sh
ip rule show | grep 'fwmark 0x1 lookup'          # must not be empty
ip route show table 110                          # must contain "local default dev lo"
sudo nft list tables | grep xray_v4              # must exist
sudo nft -j list table ip xray_v4 | jq '[.. | objects | select(has("counter")) | .counter.packets] | add'
xray api statsquery --server=127.0.0.1:10085 -pattern 'outbound>>>'   # direct vs proxy bytes
```

In the order they occur: an uplink profile without
`<profile>.network.d/xray-policy.conf`; `systemctl restart nftables` having
flushed the tables (restart the unit); a unit in `/etc/systemd/system/`
shadowing the packaged one — older copies set `User=root`, which breaks the
`skuid "xray"` DNS-loop exemption.
