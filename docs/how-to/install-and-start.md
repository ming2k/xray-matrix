# How to Install and Start the Transparent Proxy

Install the full setup on a bare system. For the shortest command-only
path, follow the [Quick Start](../../README.md#quick-start); this guide
explains each step and covers the optional parts.

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

- a VLESS+Reality server. See
  [Server Config Template](../../xray-config/server/config-example.json)
  if you run your own.
- `systemd-resolved` (or another local resolver) and an uplink managed by
  `systemd-networkd`.

## Where Each File Goes

The project ships files; you place them. Values differ per host, so every
step is a command you adapt.

The split is by whether a value differs per host:

| Artifact | Layer | Installed by / to |
|---|---|---|
| `xray` (the binary) | upstream, unmodified | `wright install xray` |
| `xray-tproxy.service`, `xray-tproxy.nft`, `xray-tproxy.sysusers.conf`, `xray-policy.conf` (template) | solution | `wright install xray-tproxy` → unit, `/etc/nftables/xray-tproxy.nft`, `/usr/lib/sysusers.d/xray.conf`, `/usr/share/xray-tproxy/xray-policy.conf` |
| `xray-config/client/config-<profile>.json` | operator | `/etc/xray/config.json`, mode `600` — holds the user ID and the REALITY key |
| `xray-policy.conf` copied into an uplink profile | operator | `/etc/systemd/network/<uplink>.network.d/` — the profile name is host-specific |

## Install the Solution

```sh
sudo install -Dm644 ./xray-tproxy.service        /var/lib/wright/plans/xray-tproxy/xray-tproxy.service
sudo install -Dm644 ./xray-tproxy.nft            /var/lib/wright/plans/xray-tproxy/xray-tproxy.nft
sudo install -Dm644 ./xray-policy.conf           /var/lib/wright/plans/xray-tproxy/xray-policy.conf
sudo install -Dm644 ./xray-tproxy.sysusers.conf  /var/lib/wright/plans/xray-tproxy/xray-tproxy.sysusers.conf
sudo wright install xray-tproxy          # pulls xray and v2ray-rules-dat in
```

This places `/usr/bin/xray`, the unit, `/etc/nftables/xray-tproxy.nft` (an
`/etc` file the package owns, so upgrades keep your edits), the `xray`
service account via sysusers, and the networkd template. Installing by hand
instead works the same way — put each file at the destination in the table
above and run `systemd-sysusers`.

`/etc/nftables/xray-tproxy.nft` is loaded by the unit's `ExecStartPre` and
removed on an explicit stop, so `systemctl restart nftables` cannot leave a
half-broken state.

The unit sets `XRAY_LOCATION_ASSET=/usr/share/v2ray-rules-dat`; change that
line if your `geoip.dat` / `geosite.dat` live elsewhere. A unit in
`/etc/systemd/system/` shadows the packaged one; remove it.

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

Start from the annotated template, fill in every `<PLACEHOLDER:...>` (see
the [Client Configuration Reference](../reference/client-configuration.md#placeholders)),
keep the result as `xray-config/client/config-<profile>.json`, and validate
before installing:

```sh
xray run -test -config ./xray-config/client/config-jp.json   # Configuration OK
sudo install -Dm600 ./xray-config/client/config-jp.json /etc/xray/config.json
```

`xray run -test` is the check the unit runs before starting, so a bad config
never replaces a working process; `sudo nft -c -f ./xray-tproxy.nft` does the
same for the ruleset.

`LogsDirectory=xray` makes the unit create and own `/var/log/xray`.


## Point the System Resolver at the Local Stub

On a `systemd-resolved` host:

```sh
sudo ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
resolvectl status
```

## Start the Service

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now xray-tproxy.service
```

After start the unit asserts the policy rule, both tables and the `12345`
listener, and enters the failed state if one is missing — a green status
means proxying is wired. `journalctl -u xray-tproxy -n 50` names it.

Continue with [How to Verify the Setup](verify-the-setup.md).
