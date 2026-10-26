# How to Deploy an Xray Proxy Server on a VPS

The server half of a deployment: the OS layer first, then one scheme's server
config. The literal command sequence is in the
[Quick Start](../../README.md#quick-start); this guide covers prerequisites,
the choice of scheme, and how to confirm the result.

## Prerequisites

- A Linux VPS with a public IPv4 (and optional IPv6) address running Ubuntu
  22.04+ or Debian 12+.
- Root access to the server.
- The `xray` binary installed on the system (for example via
  [Xray-install](https://github.com/XTLS/Xray-install), or manually at
  `/usr/bin/xray`).
- `geoip.dat` / `geosite.dat` if the server config uses geo rules. The shipping
  server configs do not route by geo, so this is only needed when you add
  rules that do.

## What the OS Layer Does

Four artifacts, each with one job. What their settings actually are, and what
they own while running, is in the
[Host Artifacts Reference](../reference/host-artifacts.md); the reason to know
them individually is that a failure in any one produces the same symptom — a
service that starts and does not pass traffic.

| Artifact | Job |
|----------|-----|
| Kernel tuning | BBR congestion control and 64 MB socket buffers, so a single tunnel can saturate a long-haul path |
| Service account | An unprivileged `xray` user; the daemon never runs as root |
| Hardened unit | Sandbox, `CAP_NET_BIND_SERVICE` for port 443, and an `xray run -test` preflight so a bad config cannot replace a working process |
| Firewall | Stateful nftables: drop invalid packets, admit SSH, 80 and 443, allow established flows |

The unit is deliberately short on lifecycle: the server owns no kernel state
beyond its listening socket, so there are no tables to load and no routes to
repair. That is the main structural difference from the client.

## Choose the Scheme

The client and the server must run the **same** scheme directory. Pick by
whether you have a domain:

### Option A: VLESS + Vision + REALITY (zero domain)

Nothing to register and nothing to renew; the server borrows a third-party TLS
identity and relays unauthenticated probes to that real site. Generate the
keys, then fill in the server config:

```sh
xray x25519          # keep PrivateKey here; PublicKey goes to the client
xray uuid
openssl rand -hex 8  # one shortId
```

See [REALITY Scheme](../../schemes/vless-xtls-vision-reality/README.md) for
choosing `dest`, and for what the client must be given.

### Option B: VLESS + Vision + TLS with Web Fallback (domain required)

The server terminates standard TLS with your own certificate and hands
non-proxy traffic to a local web server. The certificate and the fallback site
are extra infrastructure, so they have their own guide:
[How to Set Up VLESS + Vision + TLS with Web Fallback](setup-tls-fallback.md).
Deploy that guide's web server and certificate first, then the config.

## Validate and Start

The preflight the unit runs is the check to run by hand first — a config that
fails it will fail the service, and doing it here keeps the error readable:

```sh
xray run -test -config /etc/xray/config.json     # must print: Configuration OK
sudo systemctl daemon-reload
sudo systemctl enable --now xray-server.service
```

## Confirm the Result

```sh
sudo systemctl status xray-server.service
sudo ss -tlpn | grep xray                       # must be listening on 443
sudo journalctl -u xray-server -n 50
```

Then check it from outside, which is the only test that matters:

- **REALITY**: the server is indistinguishable from the borrowed site, so the
  check is behavioural — connect as a client and confirm traffic flows, and
  connect as a stranger (`curl -I --resolve <serverName>:443:<IP>`) and confirm
  you get that site's genuine response.
- **TLS + fallback**: `curl -I https://<your-domain>` should answer `HTTP/2 200`
  with the fallback site's content.

If the service is up, listening, and still no client can connect, the fault is
almost always on the client side of the scheme — mismatched UUID, `shortId` or
`serverName`, or a blocked port. Compare the two configs' values directly.
