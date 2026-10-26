# Project Layout

Repository tree map and ownership boundaries. User-facing behavior is
documented from the [Documentation Index](../index.md).

## Tree Map

| Path | Purpose |
|------|---------|
| `xray-tproxy.nft` | nftables tables `xray_v4` / `xray_v6`; configuration, deployed to `/etc/nftables/` |
| `xray-tproxy.service` | systemd unit; package artifact (`/usr/lib/systemd/system/`) |
| `xray-tproxy.sysusers.conf` | service account; package artifact (`/usr/lib/sysusers.d/xray.conf`) |
| `xray-policy.conf` | networkd drop-in; package artifact as a template (`/usr/share/xray-tproxy/`), copied by the operator under each uplink `<profile>.network.d/` |
| `xray-config/client/config-example.json` | Client config template; the deployed copy is `/etc/xray/config.json` |
| `xray-config/client/config-*.json` | Local per-server client configs (real credentials); gitignored |
| `xray-config/server/config-example.json` | Matching VLESS+Reality server config template; applied on the server host, not here |
| `xray-config/server/config-*.json` | Local server configs (real credentials); gitignored |
| `docs/` | Documentation; governance in `docs/dev/documentation/` |

Four files are duplicated in the local `wright` plans (outside the
repository, because the package manager owns that path) and must stay
identical to their repository copies:

| Plan | Contents |
|------|----------|
| `xray` | upstream only: `/usr/bin/xray` |
| `xray-tproxy` | the solution, `runtime_deps = ['xray', 'v2ray-rules-dat']`: unit, `/etc/nftables/xray-tproxy.nft`, sysusers entry, networkd template |

The split follows one rule: a package may only contain values that do not
differ per host. Credentials and the uplink profile name are per host, so
they stay operator steps.

## Design References

| Component | Primary reference |
|-----------|-------------------|
| nftables rules | [Traffic Selection Reference](../reference/traffic-selection.md) |
| Client config template | [Client Configuration Reference](../reference/client-configuration.md) |
| Service unit and policy rule | [Architecture](../explanation/architecture.md) |

## Where New Files Go

- New documentation: route it with
  [Routing](documentation/routing.md); never add files to
  `docs/dev/documentation/` itself.
- New config templates: `xray-config/<role>/config-example.json`, where
  `<role>` is `client` or `server`. Local per-server configs use
  `config-<name>.json` in the same directory and are gitignored.
- No new scripts, installers, timers or `/usr/libexec` helpers: unit
  behaviour goes into the unit, everything else is a documented command.
- Diagnostic output (`xray-tproxy-diagnose-*.txt`): never committed;
  covered by `.gitignore`.
