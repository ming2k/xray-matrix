# Scheme: VLESS + TCP + XTLS-Vision + TLS (with Web Fallback)

The domain scheme. The server terminates ordinary, publicly-trusted TLS with a
certificate for a domain you own, and anything on that port which is not a
valid VLESS client is handed to a local web server serving a real static site.

- **Needs**: a domain whose `A` record points at the VPS, a CA certificate
  (Let's Encrypt or similar), and a local Nginx or Caddy.
- **Config**: [`client.json`](client.json) and [`server.json`](server.json)
  are complete and deployable; certificates are covered in
  [cert-guide.md](cert-guide.md), deployment in
  [Deploying This Scheme](#5-deploying-this-scheme).

---

## 1. Topology

```text
                              Internet
                                 |
                    TLS 1.3 on port 443, valid CA certificate
                                 v
+-------------------------------------------------------------------+
| Xray front end (:443)                                             |
| terminates TLS, enforces ALPN (h2, http/1.1), inspects 1st packet |
+---------------------------------+---------------------------------+
                                  |
                     payload classification
                                  |
        +-------------------------+-------------------------+
        | valid VLESS header      | anything else: HTTP,    |
        | and matching UUID       | HTTP/2 preface, probes  |
        v                                                   v
+-----------------------+                +-------------------------------+
| VLESS ingestion       |                | Fallback hand-off             |
| XTLS-Vision flow      |                | PROXY protocol v1 prepended   |
| splice zero-copy      |                | socket passed to :8080        |
+-----------------------+                +---------------+---------------+
                                                         v
                                         +-------------------------------+
                                         | Nginx / Caddy (:8080)         |
                                         | returns a genuine 200 OK      |
                                         +-------------------------------+
```

The point of the lower branch: the answer to a probe is a real website on a
real certificate, not an anomaly.

## 2. Mechanism: One Port, Two Behaviours

### 2.1 First-packet inspection

Xray terminates TLS and then decides, from the first decrypted bytes, which
behaviour applies:

- **Authorised client** — the stream begins with the VLESS header
  (`[1 byte version] + [16 bytes UUID] + [1 byte addons] + ...`). The UUID
  matches an entry in `settings.clients`, Xray claims the stream, and the
  connection becomes a proxy session.
- **Anything else** — the stream begins with an HTTP method
  (`GET / HTTP/1.1`), an HTTP/2 preface
  (`PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`), or arbitrary bytes. The VLESS
  authentication fails and Xray immediately executes the configured
  `fallbacks` rule.

### 2.2 Socket hand-off and the PROXY protocol

The fallback is a plain TCP connection to `127.0.0.1:8080`, with one addition:

- Without `xver: 1`, the web server sees every request as coming from
  `127.0.0.1`, because it does.
- With `xver: 1`, Xray prepends a single PROXY protocol v1 line
  (`PROXY TCP4 <client_ip> <server_ip> <client_port> 443`) before the payload,
  and the web server recovers the real client address without any other change
  to the request.

So access logs, rate limiting and blocking all keep working on the disguise
site, which is what makes it a plausible website rather than a stub.

### 2.3 A genuinely standard handshake

This scheme is not imitating anyone. It performs an RFC 8446 TLS 1.3
handshake with a certificate issued to your domain by a public CA, and
advertises `h2` and `http/1.1` through ALPN.

That is the whole reason to prefer it over REALITY: a network that correlates
SNI against IP ASN registries, or validates the certificate chain against the
name it dialled, sees a perfect match — the domain resolves to this IP, and
the certificate names that domain.

Its exposure is the mirror image: the domain exists, so it can be
SNI-filtered, DNS-poisoned, or blacklisted, and the certificate must be
renewed.

`rejectUnknownSni` completes the picture for the boring probes: a connection
straight to the IP, or with the wrong SNI, is rejected during the handshake
and never reaches Xray's fallback logic at all.

## 3. Mechanism: XTLS-Vision

Shared with the REALITY scheme, so the full mechanism — the TLS-in-TLS length
signature it destroys, the randomized padding of the handshake stage, and the
kernel `splice()` transfer of the data stage — lives in the explanation
section: [XTLS-Vision Mechanism](../../docs/explanation/xtls-vision.md).

Here it matters twice: it removes the nested-TLS fingerprint from the tunnel,
and it requires `streamSettings.network: tcp`, which is why this scheme is
`VLESS + TCP`.

## 4. When to Choose This Over REALITY

1. **You already own a domain** and want standard, auditable TLS
   infrastructure rather than a borrowed identity.
2. **Corporate or academic firewalls** that correlate SNI with IP ASN
   registries. A borrowed Apple name on a generic cloud IP raises an anomaly
   score; your own domain matches its DNS records exactly.
3. **Dual-use hosting** — the same IP and port can serve a blog, an API, or
   static documentation to the public while proxying invisibly. The fallback
   site makes that the natural configuration rather than a trick.

## 5. Deploying This Scheme

### Step 1: Tuning and the fallback site (server)

```sh
sudo cp host/server/99-xray-tuning.conf /etc/sysctl.d/
sudo sysctl --system

sudo mkdir -p /var/www/fallback
sudo cp host/server/fallback/nginx/www/index.html /var/www/fallback/index.html
sudo cp host/server/fallback/nginx/nginx.conf /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl restart nginx
```

The fallback site should look like a site you would plausibly host: the
shipped `index.html` is a placeholder, not a disguise. A Caddy variant lives
in `host/server/fallback/caddy/`.

### Step 2: Issue the certificate

Follow [Certificate Management Guide](cert-guide.md). The `xray` service
account must be able to read the issued files; Certbot creates them under a
`0700 root:root` hierarchy, so the guide grants access with `setfacl` rather
than by loosening the directory.

### Step 3: Server config

```sh
S=./schemes/vless-xtls-vision-tls
cp $S/server.json $S/server.local.json
$EDITOR $S/server.local.json      # <UUID:...>, <SERVER_DOMAIN:...>, cert paths
xray run -test -config $S/server.local.json
sudo install -Dm600 $S/server.local.json /etc/xray/config.json
sudo systemctl restart xray-server.service
```

### Step 4: Client config

```sh
S=./schemes/vless-xtls-vision-tls
cp $S/client.json $S/client.local.json
$EDITOR $S/client.local.json      # same UUID, plus <SERVER_IP:...> and <SERVER_DOMAIN:...>
xray run -test -config $S/client.local.json
sudo install -Dm600 $S/client.local.json /etc/xray/config.json
sudo systemctl restart xray-tproxy.service
```

## 6. Verification

1. **The disguise holds**: `curl -I https://<SERVER_DOMAIN>` answers
   `HTTP/2 200` with the site's content, from a machine that is not a client.
2. **A wrong SNI is rejected**: `curl -k --resolve wrong.example.com:443:<IP>`
   fails the handshake rather than reaching the fallback.
3. **The tunnel works**: `curl -I https://www.google.com` from the client
   succeeds, and `journalctl -u xray-server` shows the inbound receiving it.

## 7. Configuration Files

- `client.json` — the complete client config: TProxy datapath plus this
  scheme's outbound. Deploys to `/etc/xray/config.json` on the client host.
- `server.json` — the complete server config, including the `fallbacks` rule
  and the certificate paths. Deploys to `/etc/xray/config.json` on the server
  host.

Both come from this one directory, so the values that must agree (`id`,
`serverNames`, the certificate hostname) have a single source. Copy a config to
a sibling `client.local.json` / `server.local.json`, fill in every
`<PLACEHOLDER:...>`, and validate with `xray run -test` before installing.
That suffix is git-ignored, so credentials never reach the repository.
