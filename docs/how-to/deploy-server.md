# How to Deploy an Xray Proxy Server on a VPS

This guide walks through setting up a hardened, production-grade Xray server on a clean Linux VPS (Ubuntu/Debian) using modern best practices.

---

## Prerequisites

- A Linux VPS with a public IPv4 (and optional IPv6) address running Ubuntu 22.04+ or Debian 12+.
- Root access to the server.
- The `xray` binary installed on the system (e.g. via [Xray-install](https://github.com/XTLS/Xray-install) or manual extraction to `/usr/bin/xray`).

---

## Step 1: Apply Kernel Tuning (BBR & TCP Buffers)

Deploy the modern kernel parameters to enable BBR congestion control and high-BDP buffer sizing:

```sh
# 1. Copy the tuning configuration
sudo install -Dm644 ./server/99-xray-tuning.conf /etc/sysctl.d/99-xray-tuning.conf

# 2. Apply parameters immediately
sudo sysctl --system

# 3. Verify BBR is active
sysctl net.ipv4.tcp_congestion_control
# Expected output: net.ipv4.tcp_congestion_control = bbr
```

---

## Step 2: Install Service Account and Systemd Unit

Deploy the unprivileged `xray` service account and the hardened systemd unit:

```sh
# 1. Create the dedicated xray service account
sudo install -Dm644 ./server/xray-server.sysusers.conf /usr/lib/sysusers.d/xray.conf
sudo systemd-sysusers

# 2. Install the hardened server unit
sudo install -Dm644 ./server/xray-server.service /etc/systemd/system/xray-server.service
sudo systemctl daemon-reload
```

---

## Step 3: Configure Server Firewall

Deploy the stateful nftables firewall to protect the host while keeping ports 22, 80, and 443 open:

```sh
sudo install -Dm644 ./server/xray-server.nft /etc/nftables.conf
sudo systemctl enable --now nftables.service
```

---

## Step 4: Choose and Deploy a Transport Scheme

Select a scheme from `schemes/` according to your requirements:

### Option A: VLESS + Vision + REALITY (Zero Domain Setup)
```sh
# 1. Copy full template
S=./schemes/vless-xtls-vision-reality
cp $S/server.json $S/server.local.json

# 2. Fill in UUID, serverNames, privateKey, and shortId
$EDITOR $S/server.local.json
xray run -test -config $S/server.local.json
sudo install -Dm600 $S/server.local.json /etc/xray/config.json
```
See [REALITY Scheme Guide](../../schemes/vless-xtls-vision-reality/README.md) for key generation.

### Option B: VLESS + Vision + TLS (Domain & Web Fallback)
```sh
# Follow the dedicated guide:
# docs/how-to/setup-tls-fallback.md
```

---

## Step 5: Validate and Start

Always test configuration syntax before starting:

```sh
# Validate configuration
sudo xray run -test -config /etc/xray/config.json
# Must output: Configuration OK.

# Enable and start service
sudo systemctl enable --now xray-server.service

# Check health and status
sudo systemctl status xray-server.service
sudo ss -tlpn | grep xray
```
