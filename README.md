# Xray Architecture & Modern Deployment Guidebook

A production-grade, end-to-end proxy architecture for modern Linux workstations, routers, and server hosts. Designed for zero-compromise anti-censorship performance, complete leak prevention, and modular transport scheme management.

---

## What It Is

Two layers, and they never overlap:

1. **`schemes/` — what you run.** Ready-to-deploy transport schemes. Each
   directory carries the complete Xray configuration for *both* ends plus its
   own documentation, and picking one is copying a file:
   - **VLESS + TCP + XTLS-Vision + REALITY**: zero domain required. The server
     borrows the TLS identity of a high-reputation foreign site and deflects
     active scanners to that real site.
   - **VLESS + TCP + XTLS-Vision + TLS (Web Fallback)**: a domain you own with
     an authentic CA certificate, deflecting active probes to a real local
     website (Nginx/Caddy) via the PROXY protocol.
2. **`host/` — where it runs.** The OS integration, identical whichever scheme
   you pick. `host/client/` is a transparent proxy (TProxy) for Linux
   workstations and routers: Xray, nftables and policy routing, with zero
   per-application configuration. `host/server/` is a hardened egress node on a
   Linux VPS: unprivileged systemd sandboxing, a stateful nftables firewall,
   BBR kernel tuning, and the web-fallback infrastructure the TLS scheme uses.

### Core Architectural Guarantees
- **Real-IP Smart DNS Split**: DNS resolves via DoH; applications receive authentic, unpolluted IP addresses without FakeIP subnet anomalies or DNS pollution.
- **XTLS-Vision Traffic Steer**: Injects randomized padding during handshakes to destroy TLS-in-TLS machine learning signatures, followed by Linux `splice()` zero-copy kernel transfers for native wire speed.
- **Fail-Closed Reliability**: Crashes preserve kernel tables and routes so failed units fail closed instead of leaking unproxied traffic.
- **Captive Portal Compatibility**: Portal probes dynamically resolve via local DHCP DNS and route direct for public Wi-Fi popups.
- **Active Probing Deflection**: Scanners attempting active probing are either proxied to genuine destination targets (REALITY) or served authentic website content from local Nginx/Caddy (TLS Fallback).

---

## Directory Overview

```text
├── schemes/                        # What you run: transport schemes, both ends together
│   ├── vless-xtls-vision-reality/  #   client.json + server.json + README.md
│   │                               #   VLESS + Vision + REALITY (zero domain)
│   └── vless-xtls-vision-tls/      #   VLESS + Vision + TLS (domain & web fallback)
│                                   #   (+ cert-guide.md)
│
├── host/                           # Where it runs: OS artifacts, identical for every scheme
│   ├── client/                     #   Generic Linux TProxy (workstation / gateway)
│   │   ├── xray-tproxy.service
│   │   ├── xray-tproxy.sysusers.conf
│   │   ├── xray-tproxy.nft
│   │   └── xray-policy.conf
│   └── server/                     #   VPS egress node
│       ├── xray-server.service
│       ├── xray-server.sysusers.conf
│       ├── xray-server.nft
│       ├── 99-xray-tuning.conf
│       └── fallback/{nginx,caddy}/ #   Disguise website, used by the TLS scheme only
│
└── docs/                           # Comprehensive Diátaxis Documentation
    ├── how-to/                     # Task-oriented guides (Client & Server)
    ├── reference/                  # Technical reference (Configs, Traffic)
    └── explanation/                # Architectural & cryptographic deep dives
```

Two layers, and they never overlap:

- **`schemes/`** — *what you run*. A scheme is picked, not composed: its
  directory carries the whole Xray configuration for both ends (`client.json`,
  `server.json`) plus its own documentation, so adding a transport means adding
  one directory.
- **`host/`** — *where it runs*. nftables rules, unit files, sysusers entries,
  kernel tuning, the fallback site: identical whichever scheme runs, so they
  exist once. `host/client/` is the generic Linux TProxy; `host/server/` is the
  VPS egress node.

Host-specific values (server address, UUID, keys, uplink name) are never
committed: copy a scheme config to a sibling `*.local.json` and fill it in —
`.gitignore` covers that suffix.

---

## Quick Start

### 1. Client Setup (Workstation / Gateway)

```sh
# 1. Install the OS layer (scheme-independent, from host/client/)
sudo install -Dm644 ./host/client/xray-tproxy.service /etc/systemd/system/
sudo install -Dm644 ./host/client/xray-tproxy.nft /etc/nftables/xray-tproxy.nft
sudo install -Dm644 ./host/client/xray-tproxy.sysusers.conf /usr/lib/sysusers.d/xray.conf
sudo systemd-sysusers

# 2. Deploy a scheme: copy the template, fill in the local values
SCHEME=./schemes/vless-xtls-vision-reality     # or ./schemes/vless-xtls-vision-tls
cp $SCHEME/client.json $SCHEME/client.local.json
$EDITOR $SCHEME/client.local.json              # fill in every <PLACEHOLDER:...>
xray run -test -config $SCHEME/client.local.json
sudo install -Dm600 $SCHEME/client.local.json /etc/xray/config.json

# 3. Configure networkd policy routing drop-in
sudo install -Dm644 ./host/client/xray-policy.conf \
  /etc/systemd/network/<uplink>.network.d/xray-policy.conf

# 4. Reconfigure network and start
sudo networkctl reconfigure <uplink>
sudo systemctl daemon-reload
sudo systemctl enable --now xray-tproxy.service
```

### 2. Server Setup (VPS Egress Node)

```sh
# 1. Apply BBR kernel tuning and buffer optimization
sudo install -Dm644 ./host/server/99-xray-tuning.conf /etc/sysctl.d/
sudo sysctl --system

# 2. Install unprivileged service account & hardened systemd unit
sudo install -Dm644 ./host/server/xray-server.sysusers.conf /usr/lib/sysusers.d/xray.conf
sudo systemd-sysusers
sudo install -Dm644 ./host/server/xray-server.service /etc/systemd/system/

# 3. Apply stateful firewall
sudo install -Dm644 ./host/server/xray-server.nft /etc/nftables.conf
sudo systemctl enable --now nftables.service

# 4. Deploy the server half of the same scheme
SCHEME=./schemes/vless-xtls-vision-reality     # must match the client's scheme
cp $SCHEME/server.json $SCHEME/server.local.json
$EDITOR $SCHEME/server.local.json              # fill in UUID, privateKey, serverNames
xray run -test -config $SCHEME/server.local.json
sudo install -Dm600 $SCHEME/server.local.json /etc/xray/config.json

# 5. Start
sudo systemctl daemon-reload
sudo systemctl enable --now xray-server.service
```

For setting up the `vless-xtls-vision-tls` scheme with Let's Encrypt and Nginx fallback, see [How to Set Up VLESS + Vision + TLS with Web Fallback](docs/how-to/setup-tls-fallback.md).

---

## Documentation

See the [Documentation Index](docs/index.md):

### Guides
- [How to Install and Start the Transparent Proxy](docs/how-to/install-and-start.md)
- [How to Deploy an Xray Proxy Server on a VPS](docs/how-to/deploy-server.md)
- [How to Set Up VLESS + Vision + TLS with Web Fallback](docs/how-to/setup-tls-fallback.md)
- [How to Verify the Setup](docs/how-to/verify-the-setup.md)
- [How to Troubleshoot Common Problems](docs/how-to/troubleshoot-common-problems.md)

### Reference & Mechanism Deep Dives
- [Transport Schemes Matrix](schemes/README.md)
- [XTLS-Vision Mechanism](docs/explanation/mechanisms/xtls-vision.md)
- [REALITY Scheme](schemes/vless-xtls-vision-reality/README.md)
- [TLS + Fallback Scheme](schemes/vless-xtls-vision-tls/README.md)
- [Architecture](docs/explanation/architecture.md)
- [Data Packet Lifecycle](docs/explanation/packet-lifecycle.md)
