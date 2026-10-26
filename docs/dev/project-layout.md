# Project Layout

Repository tree map and ownership boundaries. User-facing behavior is
documented from the [Documentation Index](../index.md).

## Two Layers

The top level names two *layers*, not two roles, because a layer answers a
different question than a role does:

- **`schemes/`** — *what you run*. Everything that changes when the transport
  changes. A scheme directory is self-contained and deployable: it carries the
  complete Xray config for *both* ends plus its own documentation.
- **`host/`** — *where it runs*. The OS artifacts, split by `client` and
  `server` role. nftables rulesets, unit files, sysusers entries, kernel
  tuning, and the fallback web server are identical whichever scheme runs, so
  they exist exactly once.

Naming the directory after its role (`client/`, `server/`) would collide with
the scheme-side names `client.json` / `server.json` and suggest it holds
configuration; it holds system integration. A scheme switch therefore touches
one directory under `schemes/` and leaves `host/` alone.

## Tree Map

| Path | Purpose |
|------|---------|
| `schemes/<scheme>/client.json` | Complete client Xray config: TProxy datapath plus the scheme's outbound |
| `schemes/<scheme>/server.json` | Complete server Xray config: the scheme's inbound plus `freedom` / `blackhole` |
| `schemes/<scheme>/README.md` | Scheme mechanism, threat model, key generation |
| `schemes/<scheme>/*.local.json` | Operator copy with real credentials; git-ignored, never committed |
| `schemes/README.md` | Scheme comparison matrix, decision tree, threat models |
| `host/client/xray-tproxy.nft` | nftables tables `xray_v4` / `xray_v6`; deployed to `/etc/nftables/` |
| `host/client/xray-tproxy.service` | systemd unit for the client transparent proxy |
| `host/client/xray-tproxy.sysusers.conf` | Service account allocation; deployed to `/usr/lib/sysusers.d/xray.conf` |
| `host/client/xray-policy.conf` | networkd drop-in template; copied under each uplink `<profile>.network.d/` |
| `host/server/xray-server.service` | Hardened, unprivileged systemd unit for the proxy server |
| `host/server/xray-server.sysusers.conf` | Server service account definition |
| `host/server/99-xray-tuning.conf` | Linux kernel tuning (BBR, TCP Fast Open, 64MB buffers) |
| `host/server/xray-server.nft` | Minimal stateful server firewall |
| `host/server/fallback/nginx/` | Fallback web server configuration and disguise site |
| `host/server/fallback/caddy/` | Alternative Caddy reverse proxy fallback configuration |
| `.githooks/pre-commit` | Refuses to commit host-specific values; activate with `git config core.hooksPath .githooks` |
| `.githooks/test-pre-commit.sh` | Cases for that guard; run it after editing the hook |
| `docs/` | Documentation; governance in `docs/dev/documentation/` |

## Packaging

Two local `wright` plans ship the OS layer, and their copies must stay
identical to the repository copies:

| Plan | Contents |
|------|----------|
| `xray` | upstream only: `/usr/bin/xray` |
| `xray-tproxy` | the four `host/client/` files, `runtime_deps = ['xray', 'v2ray-rules-dat']`: unit, `/etc/nftables/xray-tproxy.nft`, sysusers entry, networkd template |

The plan directory is flat (`/var/lib/wright/plans/xray-tproxy/`), so the unit
files are installed from `host/client/` by name; the repository does not mirror them
at the root.

The split follows one rule: a package may only contain values that do not
differ per host. Credentials, domain names, and the uplink profile name are per
host, so they stay operator steps — held in a git-ignored `*.local.json` copy
next to the scheme template.

## Design References

| Component | Primary reference |
|-----------|-------------------|
| Transport Schemes | [Schemes Matrix](../../schemes/README.md) |
| Client nftables rules | [Traffic Selection Reference](../reference/traffic-selection.md) |
| Client config template | [Client Configuration Reference](../reference/client-configuration.md) |
| Server config template | [Server Configuration Reference](../reference/server-configuration.md) |
| System Architecture | [Architecture](../explanation/architecture.md) |

## Where New Files Go

- New documentation: route it with [Routing](documentation/routing.md); never add files to `docs/dev/documentation/` itself.
- New transport schemes: add a subfolder under `schemes/<scheme-name>/` containing `client.json`, `server.json`, and `README.md` — nothing else, unless the scheme needs its own extra artifact (for example `vless-xtls-vision-tls/cert-guide.md`).
- New OS artifacts: keep them under `host/client/` or `host/server/`, never inside a scheme.
- Operator copies with credentials: name them `*.local.json` beside the template they came from; they are git-ignored, and the commit guard refuses them if they are staged anyway.
- A new class of secret to guard against: add a case to `.githooks/test-pre-commit.sh` first, then teach `.githooks/pre-commit` about it.
- Diagnostic output (`xray-tproxy-diagnose-*.txt`): never committed; covered by `.gitignore`.
