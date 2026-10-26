# Xray TProxy Guidebook

## What It Is

This project provides a transparent proxy client setup for a single-host
Linux machine using Xray, nftables, and policy routing. Once installed,
all application traffic is routed through Xray according to your rules —
no per-application proxy configuration needed.

It is tuned for a workstation or laptop running `systemd-networkd` and a
local resolver such as `systemd-resolved`:

- **Real-IP Smart DNS Split**: All DNS is handled via Xray DoH; applications receive authentic, unpolluted IP addresses without FakeIP subnet anomalies
- **Full TProxy Protection**: Both HTTP (port 80) and HTTPS (port 443) for overseas destinations travel through the proxy tunnel, protecting against ISP hijacking and GFW blocks
- **Captive Portal Compatible**: Portal probes dynamically resolve via local DHCP DNS and route direct for automatic Wi-Fi login popups
- **Root Process Proxying**: `sudo apt update`, `docker pull`, and admin processes are transparently proxied according to Xray routing rules
- **Resilient Policy Routing**: `systemd-networkd` owns the fwmark policy rule, so it survives sleep/wake and interface switching; the unit repairs it and logs when it is gone
- **Fail-Closed Restarts**: a crash keeps the tables and the policy route, so the restart window drops traffic instead of leaking it
- **Observable**: per-outbound byte counters on a loopback gRPC API
- **Validated on Start**: the unit refuses a config that fails `xray run -test` and asserts the datapath after start


## Quick Start

Run from the repository root:

```sh
# 1. the solution: unit, ruleset, service account, networkd template
#    (upstream xray and the geo data come in as dependencies)
sudo install -Dm644 ./xray-tproxy.service /var/lib/wright/plans/xray-tproxy/
sudo install -Dm644 ./xray-tproxy.nft /var/lib/wright/plans/xray-tproxy/
sudo install -Dm644 ./xray-tproxy.sysusers.conf /var/lib/wright/plans/xray-tproxy/
sudo install -Dm644 ./xray-policy.conf /var/lib/wright/plans/xray-tproxy/
sudo wright install xray-tproxy

# 2. operator-owned configuration: only what differs per host
cp ./xray-config/client/config-example.json ./xray-config/client/config-jp.json
$EDITOR ./xray-config/client/config-jp.json      # fill in every <PLACEHOLDER:...>
sudo install -Dm600 ./xray-config/client/config-jp.json /etc/xray/config.json
sudo install -Dm644 /usr/share/xray-tproxy/xray-policy.conf \
  /etc/systemd/network/<uplink>.network.d/xray-policy.conf

# 3. validate, then start
sudo xray run -test -config /etc/xray/config.json    # must print: Configuration OK
sudo networkctl reconfigure <uplink>
sudo systemctl daemon-reload
sudo systemctl enable --now xray-tproxy.service
```

Replace `<uplink>` with the `.network` file that manages your connection
(such as `20-wireless.network`); every uplink profile you use needs the
policy drop-in. Step 2 holds the only host-specific values (credentials and
the uplink name) — see
[How to Install and Start the Transparent Proxy](docs/how-to/install-and-start.md)
for prerequisites and per-step explanations.



## Documentation

See the [Documentation Index](docs/index.md). Frequently used pages:

- [How to Verify the Setup](docs/how-to/verify-the-setup.md)
- [How to Use Captive Portal Networks](docs/how-to/use-captive-portal-networks.md)
- [Client Configuration Reference](docs/reference/client-configuration.md)
- [Architecture](docs/explanation/architecture.md)
- [Data Packet Lifecycle](docs/explanation/packet-lifecycle.md)
