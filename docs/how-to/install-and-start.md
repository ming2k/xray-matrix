# How to Install and Start the Transparent Proxy

Install the full setup on a bare system. The literal command sequence lives in
the [Quick Start](../../README.md#quick-start); this guide explains what each
step does, why the order matters, and covers the parts the Quick Start omits.

## Prerequisites

Install these packages: `xray`, `nftables`, `iproute2`, `systemd`,
`procps-ng`. The verification commands in
[How to Verify the Setup](verify-the-setup.md) use `jq`, `curl` and `getent`.

You also need:

- `geoip.dat` and `geosite.dat`, because the routing rules reference
  `geoip:cn`, `geosite:cn`, and related groups. The unit points Xray at
  `/usr/share/v2ray-rules-dat`; change `XRAY_LOCATION_ASSET` in
  `xray-tproxy.service` if your data files live elsewhere. A ruleset that
  references a tag the data files do not ship degrades to an empty rule,
  which is why the unit refuses to start on a config that fails
  `xray run -test`.

- a server running the **same scheme** you deploy on the client, or your own.
  The shipped server configs are
  [REALITY](../../schemes/vless-xtls-vision-reality/server.json) and
  [TLS](../../schemes/vless-xtls-vision-tls/server.json).
- `systemd-resolved` (or another local resolver) and an uplink managed by
  `systemd-networkd`.

## Where Each File Goes

The project ships files; you place them. Values differ per host, so every
step is a command you adapt.

The split is by whether a value differs per host:

| Artifact | Layer | Installed by / to |
|---|---|---|
| `xray` (the binary) | upstream, unmodified | `wright install xray` |
| `host/client/xray-tproxy.service`, `host/client/xray-tproxy.nft`, `host/client/xray-tproxy.sysusers.conf`, `host/client/xray-policy.conf` (template) | solution | `wright install xray-tproxy` → unit, `/etc/nftables/xray-tproxy.nft`, `/usr/lib/sysusers.d/xray.conf`, `/usr/share/xray-tproxy/xray-policy.conf` |
| `schemes/<scheme>/client.json` | operator | `/etc/xray/config.json`, mode `600` — holds the user ID and the scheme key |
| `host/client/xray-policy.conf` copied into an uplink profile | operator | `/etc/systemd/network/<uplink>.network.d/` — the profile name is host-specific |

## Install the OS Layer

The Quick Start installs the four `host/client/` files straight to their system
destinations. The alternative is the `wright` packaging, which performs the
same placement and pulls the upstream dependencies in with it:

```sh
sudo install -Dm644 ./host/client/xray-tproxy.service        /var/lib/wright/plans/xray-tproxy/xray-tproxy.service
sudo install -Dm644 ./host/client/xray-tproxy.nft            /var/lib/wright/plans/xray-tproxy/xray-tproxy.nft
sudo install -Dm644 ./host/client/xray-policy.conf           /var/lib/wright/plans/xray-tproxy/xray-policy.conf
sudo install -Dm644 ./host/client/xray-tproxy.sysusers.conf  /var/lib/wright/plans/xray-tproxy/xray-tproxy.sysusers.conf
sudo wright install xray-tproxy          # pulls xray and v2ray-rules-dat in
```

Either route leaves the same state: `/usr/bin/xray`, the unit, the `xray`
service account via sysusers, and the networkd template.

One consequence of the second route is easy to miss: `wright` caches both the
fetched source copy and the forge workspace, and neither is keyed on the
*content* of a `[[sources]] type = "local"` file. Editing a file in
`/var/lib/wright/plans/xray-tproxy/` and re-running `wright install` or
`wright upgrade` can print `Building … Staging … Sealing … Deploying` while
re-deploying the previous bytes. Drop the cache and verify what landed:

```sh
sudo wright clean xray-tproxy --sources          # re-fetched on the next build
sudo wright upgrade xray-tproxy --force --fresh  # --fresh wipes the forge workspace
sudo cmp /usr/lib/systemd/system/xray-tproxy.service ./host/client/xray-tproxy.service \
  && echo identical
```

`cmp` is the acceptance test, not the exit status of the package manager.

Two consequences of the unit owning the datapath, whichever route you take:

- **`/etc/nftables/xray-tproxy.nft` is an `/etc` file the unit owns.** It is
  loaded by `ExecStartPre` and removed on an explicit stop, so
  `systemctl restart nftables` cannot leave a half-broken state, and an upgrade
  will not overwrite your edits silently.
- **A unit in `/etc/systemd/system/` shadows the packaged one.** Older local
  copies set `User=root`, which breaks the `skuid "xray"` DNS-loop exemption
  in the ruleset. Remove the shadowing unit rather than editing it.

## Install the Policy-Rule Drop-In

The `fwmark 1 -> table 110` policy rule comes from the template the package
installs at `/usr/share/xray-tproxy/xray-policy.conf`, copied into the
`.network.d/` directory of **every** `.network` profile that manages an
uplink — a profile without it silently bypasses proxying:

```sh
sudo install -Dm644 /usr/share/xray-tproxy/xray-policy.conf \
  /etc/systemd/network/20-wireless.network.d/xray-policy.conf
```

Repeat for each profile (for example `10-eth.network`), then apply it:

```sh
sudo systemctl reload systemd-networkd
sudo networkctl reconfigure wlan0   # replace with your uplink
```

Optionally name routing table `110` for readability. The alias is
cosmetic: everything here uses the numeric id `110`, and the policy rule
displays as `lookup xray` once the alias exists.

```sh
echo '110 xray' | sudo tee -a /etc/iproute2/rt_tables
```

## Create the Xray Client Config

The commands are Quick Start step 2. Beyond running them, three things are
worth knowing:

- **Fill in every placeholder.** The template is not a working config until
  then; the full list is in the
  [Client Configuration Reference](../reference/client-configuration.md#placeholders).
- **Keep the filled-in copy as `client.local.json`, beside its template.** The
  suffix is git-ignored, so per-host credentials stay out of the repository,
  and the template stays clean for the next host.
- **`xray run -test` is the unit's own preflight**, so run it before installing:
  a config that fails never replaces a working one. `sudo nft -c -f
  ./host/client/xray-tproxy.nft` does the same for the ruleset.
- **Custom configurations must satisfy the TProxy contract.** If you write a
  configuration from scratch rather than starting from a scheme template, verify
  that it satisfies the [Client Datapath Contract](../reference/host-artifacts.md#3-client-datapath-contract-xray-interface-requirements):
  the `dokodemo-door` inbound on port 12345 with `sockopt.tproxy: "tproxy"`, and
  `sockopt.mark: 2` on all dialing outbounds to prevent infinite routing loops.

The service writes to `/var/log/xray`; `LogsDirectory=xray` makes the unit
create and own that directory, so nothing has to pre-create it. It does not own
the files inside: a root-run `xray` (`sudo xray run`, or any preflight that
carries `+`) leaves `access.log` and `error.log` as `root:root 0600`, and the
unprivileged main process then dies with `open /var/log/xray/access.log:
permission denied` (`status=23`). The unit re-owns both files on every start to
undo that, but the rule to follow is simpler: run xray as `xray`, never as
root.

## Point the System Resolver at the Local Stub

On a `systemd-resolved` host:

```sh
sudo ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
resolvectl status
```

The client config's `localhost` DNS entry queries this stub, which is how
portal probes reach the current network's DHCP resolver. Why that path needs
its own nftables exemption is explained in
[Real-IP DNS Architecture](../explanation/dns.md).

## Start the Service

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now xray-tproxy.service
```

After start the unit asserts the policy rule, both tables and the `12345`
listener, and enters the failed state if one is missing — a green status
means proxying is wired. `journalctl -u xray-tproxy -n 50` names it.

If it fails the way an earlier revision did, the file on the host is probably
not the file this repository ships — see
[Check the Installed Unit](verify-the-setup.md#check-the-installed-unit).

Continue with [How to Verify the Setup](verify-the-setup.md).
