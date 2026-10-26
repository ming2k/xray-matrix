# How to Share Port 443 with an Existing Website

A deployment recipe for hosts that already terminate TLS for real websites on
port 443 and now must also serve a REALITY inbound on the same port. The pattern
keeps the websites byte-for-byte untouched (same certificates, same HTTP/2
settings, same ACME renewal path) while the proxy borrows a third-party CDN
identity, so a probe of the port answers as that CDN rather than as your domain.

---

## 1. Why Not Just Move Xray to 443

Two naive layouts both fail:

| Layout | What breaks |
|--------|-------------|
| Xray binds `0.0.0.0:443`, websites move to another port | The personal domain becomes the visible SNI: zero-collateral-damage blocking, plus public Certificate Transparency records point at the host. |
| Xray terminates TLS for the personal domain and falls back to nginx | Xray must read every site's private key, every ACME renewal needs a daemon reload, and the fallback leg is plaintext HTTP — SSE streaming, S3 signatures and WebSocket upgrades all need rework. |

The layout that keeps both properties is a **layer-4 SNI demultiplexer**: nginx
`stream` peeks at the `ClientHello`, and routes by SNI without decrypting
anything.

```text
                    :443  (nginx stream, ssl_preread)
                              |
        +---------------------+----------------------+
        |                                            |
  SNI = borrowed CDN                      any other SNI (your domains)
        |                                            |
        v                                            v
  127.0.0.1:18443                            127.0.0.1:8443
  (PROXY header stripped)                   (nginx http, TLS as before)
        |                                            |
        v                                            v
  127.0.0.1:10443                            real certificates, HTTP/2,
  (Xray REALITY)                             ACME, SSE, S3, WebSocket
```

---

## 2. Constraint: REALITY Cannot Consume PROXY Protocol

The demultiplexer must forward the real client address, otherwise every access
log entry reads `127.0.0.1`. The standard tool for that is the PROXY protocol
header. **Xray's REALITY inbound cannot parse it**: it is peeled only by the
plain TLS/tcp transports, and enabling `sockopt.acceptProxyProtocol` on a REALITY
inbound makes every handshake fail with:

```text
tls: first record does not look like a TLS handshake
```

Reproduced on Xray 26.3.27 and 26.10.21; the identical config without the header
works, so the relay and key material are not at fault. The fix is the extra hop
in the diagram: the REALITY branch terminates the header at a loopback stream
server and re-emits plain TCP.

---

## 3. Move the Websites to Loopback

Change every TLS listener from the wildcard address to loopback, and mark it as
PROXY-aware. Only the `listen 443 ssl` variants move; port 80 stays on the
wildcard address so ACME HTTP-01 challenges keep working.

```sh
cd /etc/nginx/sites-available
sed -i -E \
  -e 's/^(\s*)listen 443 ssl http2;/\1listen 127.0.0.1:8443 ssl http2 proxy_protocol;/' \
  -e 's/^(\s*)listen 443 ssl;/\1listen 127.0.0.1:8443 ssl proxy_protocol;/' \
  -e 's/^(\s*)listen \[::\]:443 ssl http2;/\1listen [::1]:8443 ssl http2 proxy_protocol;/' \
  -e 's/^(\s*)listen \[::\]:443 ssl;/\1listen [::1]:8443 ssl proxy_protocol;/' \
  *
grep -Hn 'listen' *
```

`proxy_protocol` on the listener is what lets `$remote_addr` recover the real
peer, provided the `http` block trusts the demultiplexer:

```nginx
http {
    set_real_ip_from 127.0.0.1;
    set_real_ip_from ::1;
    real_ip_header proxy_protocol;
}
```

---

## 4. Install the Demultiplexer

Debian's `nginx` package does not ship the stream module, and `stream` fails to
load without it — even though `nginx -V` reports `--with-stream` build flags:

```sh
sudo apt-get install -y libnginx-mod-stream
ls /etc/nginx/modules-enabled/          # must contain 50-mod-stream.conf
```

`/etc/nginx/nginx.conf` loads that module at the top (`include
/etc/nginx/modules-enabled/*.conf;`) and gets one new block at the end:

```nginx
# Layer-4 :443 demultiplexer (websites vs REALITY).
stream {
    include /etc/nginx/stream.d/*.conf;
}
```

`/etc/nginx/stream.d/reality.conf` holds the routing rules. `map` must live
inside `stream {}` — at the main context nginx rejects it with `"map" directive
is not allowed here`:

```nginx
upstream site_web    { server 127.0.0.1:8443; }
upstream reality_hop { server 127.0.0.1:18443; }

# Enumerate the names that really exist in DNS and must reach the websites.
# Everything else is answered by the REALITY branch, which relays to the borrowed
# site: a scanner that connects with an arbitrary SNI then gets the borrowed
# CDN's answer instead of this host's own certificate.
map $ssl_preread_server_name $backend_443 {
    example.com        site_web;
    www.example.com    site_web;

    download.docker.com reality_hop;
    default             reality_hop;
}

server {
    listen 443;
    listen [::]:443;
    ssl_preread on;
    proxy_pass $backend_443;
    proxy_protocol on;
    proxy_timeout 1h;        # long-lived tunnels and large downloads
    proxy_buffer_size 16k;   # must exceed the ClientHello record size
}

# PROXY-protocol stripping hop for the REALITY branch.
server {
    listen 127.0.0.1:18443 proxy_protocol;
    proxy_pass 127.0.0.1:10443;
    proxy_timeout 1h;
    proxy_buffer_size 16k;
}
```

An unknown SNI reaching the REALITY branch receives `handshake failure` from the
borrowed CDN's own edge, which is what any single-name server does — no local
certificate, no hint of the personal domain.

---

## 5. Point the Xray Inbound at Loopback

The REALITY inbound binds loopback only — the demultiplexer is the sole way in,
so port 10443 is never exposed:

```json
{
  "inbounds": [
    {
      "tag": "reality-in",
      "listen": "127.0.0.1",
      "port": 10443,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "<UUID>", "flow": "xtls-rprx-vision" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "download.docker.com:443",
          "xver": 0,
          "serverNames": ["download.docker.com"],
          "privateKey": "<PRIVATE_KEY>",
          "shortIds": ["", "<SHORT_ID>"]
        },
        "sockopt": { "tcpFastOpen": true }
      }
    }
  ]
}
```

**No `acceptProxyProtocol`.** The stripping hop already produced plain TCP.

Switch in this order, so the port is never left without an owner and the proxy
never sees a header it cannot parse:

```sh
sudo systemctl restart xray     # now 127.0.0.1:10443
sudo systemctl restart nginx    # now 0.0.0.0:443 (stream) + 127.0.0.1:8443
```

---

## 6. Verify All Three Paths

The deployable version of the demultiplexer is
`host/server/nginx-stream/reality.conf`; the block in section 4 is the same file
with real hostnames filled in.

```sh
# 1. Websites still answer on 443, with the same certificates and HTTP/2
for h in example.com www.example.com; do
  curl -s -o /dev/null -w "$h -> %{http_code} (%{http_version})\n" \
    --resolve "$h:443:127.0.0.1" "https://$h/"
done

# 2. Real client address survives the demultiplexer
tail -n 3 /var/log/nginx/access.log        # must show the client IP, not 127.0.0.1

# 3. A probe with the borrowed SNI gets the CDN's own answer, not yours
curl -sI --resolve download.docker.com:443:127.0.0.1 https://download.docker.com/ | head -n 1

# 4. The tunnel itself, from a separate machine
curl -s --socks5 127.0.0.1:1080 https://www.google.com/generate_204 -o /dev/null -w '%{http_code}\n'
```

### 6.1 Camouflage Checks That Catch Silent Leaks

Both failures below look like "everything works" until a scanner notices.

```sh
# A. An arbitrary or missing SNI must never receive a local certificate.
echo | openssl s_client -connect <IP>:443 -servername not-your-domain.example 2>&1 |
  grep -E "subject=|alert"
# Expect: an alert (the borrowed site's own handshake failure).
# A local subject= line means `default` still points at the website backend.

# B. A probe with the borrowed SNI must see the real site's issuer, not yours.
echo | openssl s_client -connect <IP>:443 -servername download.docker.com 2>/dev/null |
  openssl x509 -noout -subject -issuer
# Expect the borrowed site's identity, e.g. subject=CN=*.docker.com
#                                  issuer=C=US, O=Amazon, CN=Amazon RSA 2048 M04
```

Check B is also the fastest way to confirm the relay target is still reachable:
if the issuer comes back as anything else, `dest` or the demultiplexer map is
wrong, and every unauthenticated prober is being handed the wrong identity.

Expect `HTTP/2 200` on the website, the peer IP in the log, `HTTP/2 200` from the
CDN probe, and `204` through the tunnel.

### 6.2 Streaming Endpoints Behind the Demultiplexer

A website that keeps its own certificate is usually also the website that streams
(server-sent events for an AI chat, for instance). The demultiplexer does not
change how the stream is delivered, but the site's own proxy block must not
buffer it, or every "token by token" response arrives as one blob when it ends:

```nginx
location / {
    proxy_pass http://127.0.0.1:7777;

    proxy_http_version 1.1;          # chunked upstream instead of HTTP/1.0
    proxy_set_header Connection "";  # keep the upstream connection open

    proxy_buffering off;   # each event reaches the client as it is produced
    proxy_cache off;
    gzip off;              # compressing an event stream re-buffers it
    chunked_transfer_encoding on;

    proxy_send_timeout 3600s;   # a paused stream is not cut at the origin
    proxy_read_timeout 3600s;
}
```

Verify that events arrive one at a time — the only check that matters, and it
does not need any CDN to be meaningful:

```sh
curl -skN https://example.com/<sse-endpoint> | while IFS= read -r line; do
  [ -n "$line" ] && printf '+%s  %s\n' "$(date +%S.%2N)" "$line"
done
```

Intervals between lines must match the application's emit rate (`+2s`, `+4s`), not
collapse into one burst at the end. Measured on a host following this guide:
`tick 0` at `+51.72s`, `tick 1` at `+53.72s`, `tick 2` at `+55.72s` — incremental,
so the buffering path is gone.

Note what nginx can and cannot fix: it can stop buffering and stop cutting the
stream on its own timeouts, but a TLS-terminating CDN in front still enforces its
own idle limit, and only the application can emit a keep-alive comment inside that
window.

---

## 7. Two Failure Modes That Look Alike

Both present as "the site does not open", and both are invisible in the nginx
error log. They need different fixes, so separate them before touching anything
else.

### 7.1 `proxy_pass` with a `host:port` variable drops connections

```nginx
# WRONG: silently drops a fifth to a half of all connections
map $ssl_preread_server_name $backend { default 127.0.0.1:8443; }
server { listen 443; ssl_preread on; proxy_pass $backend; proxy_protocol on; }
```

A variable whose value is re-parsed per connection loses connections with no
error anywhere: measured `12/50` failures on `:443` against `0/20` for the same
routing expressed through upstream group names, interleaved in the same minute,
and `0/100` for the backend itself from another host. Use groups:

```nginx
upstream site_web   { server 127.0.0.1:8443; }
upstream reality_hop { server 127.0.0.1:18443; }

map $ssl_preread_server_name $backend_443 {
    example.com           site_web;
    download.docker.com   reality_hop;
    default               reality_hop;
}
server {
    listen 443;
    ssl_preread on;
    proxy_pass $backend_443;
    proxy_protocol on;
}
```

### 7.2 On-path SYNs to `(ip, 443)` are dropped, so nginx never sees them

Carriers and the firewall treat `443` to a given address differently from other
ports, and can drop new SYNs probabilistically for hours at a time. The site is
healthy; the connection never lands.

How to prove it, in order:

```sh
# 1. Does the demultiplexer log the attempt at all?
#    (needs the access_log line from section 4)
sudo tail -n 20 /var/log/nginx/stream.log

# 2. Do kernel counters move? A dropped SYN moves none of them.
ssh root@<host> 'nstat -az | grep -E "ListenOverflows|ListenDrops|SyncookiesSent"'
```

If the log shows fewer connections than you attempted and no counter moved, the
packet died on the path. Confirm the asymmetry with a spare port carrying the
same routing (`listen 8446;`), then confirm it is not nationwide:

```sh
# from the failing host
for i in $(seq 20); do curl -s -o /dev/null --max-time 6 https://example.com/ ; echo $?; done
for i in $(seq 20); do curl -sk -o /dev/null --max-time 6 \
  --resolve example.com:8446:<IP> https://example.com:8446/ ; echo $?; done

# from several Chinese networks, via Globalping (see diagnose-gfw-blocks.md)
```

A spare listener on a non-standard port costs one `server {}` block and turns
"my site is broken" into "this line drops :443 to that IP right now", which is
the difference between debugging infrastructure and waiting it out.

---

## 8. Choosing the Borrowed Domain Here

The target must be adjacent to this host **and** independent of the websites:

```sh
TARGET="download.docker.com"
ping -c 3 "$TARGET" | tail -1 | awk -F '/' '{print "Average RTT: " $5 " ms"}'
curl -Iv --tlsv1.3 --http2 -s -m 5 "https://$TARGET/" 2>&1 | \
  grep -E "(SSL connection using TLSv1.3|using HTTP/2|HTTP/2 [0-9]{3})"
```

`download.docker.com` measured `1.6 ms` from a Fremont VPS with TLS 1.3,
HTTP/2 and a `200` root — well inside the `ΔT < 15 ms` budget from
[REALITY Target Selection](../explanation/reality-target-selection.md).

Never borrow one of your own hostnames: that reintroduces both the plaintext SNI
and the Certificate Transparency trail this layout exists to avoid.

---

## Related Documentation

- [How to Deploy an Xray Proxy Server on a VPS](deploy-server.md)
- [How to Set Up VLESS + Vision + TLS with Web Fallback](setup-tls-fallback.md)
- [How to Diagnose GFW Blocks and Network Anomalies](diagnose-gfw-blocks.md)
- [REALITY Target Selection & Camouflage](../explanation/reality-target-selection.md)
