# Getting Started: Deploying Your First Xray Transparent Proxy

This tutorial guides you through deploying a complete, production-grade transparent proxy network from scratch. By the end of this tutorial, you will have a hardened VPS egress server and a fully transparent Linux workstation client routing traffic seamlessly through **VLESS + XTLS-Vision + REALITY**.

---

## What You Will Build

You will set up two machines:
1. **Server (VPS Egress Node)**: An internet-facing Linux host running the REALITY inbound, deflecting scanners to an authentic website.
2. **Client (Workstation or Gateway)**: A modern Linux machine running transparent proxying (TProxy) via nftables and policy routing.

```text
[ Browser / App ] ──► (Original Dest IP) ──► [ nftables TProxy ]
                                                     │
                                                     ▼ (table 110)
                                            [ Local Xray Client ]
                                                     │
                                              VLESS + REALITY
                                                     │
                                                     ▼
                                            [ Remote VPS Server ] ──► [ Authentic Web ]
```

---

## Prerequisites

- **One Linux VPS** (Debian, Ubuntu, or Arch Linux) with a public IPv4 address and root access.
- **One Linux Workstation or Gateway** (systemd + nftables enabled).
- **`xray` binary installed** on both machines (e.g., `/usr/bin/xray`).

---

## Step 1: Deploy the Server (VPS)

We will use the **REALITY** scheme because it requires zero domain names and zero CA certificate issuance.

### 1.1 Generate REALITY Cryptographic Keys
On your server (or client), run the Xray key generator:
```sh
xray x25519
```
This outputs a Private Key and a Public Key:
```text
PrivateKey: <YOUR_PRIVATE_KEY>
PublicKey:  <YOUR_PUBLIC_KEY>
```
Also generate a unique user ID:
```sh
xray uuid
```

### 1.2 Install the Server OS Layer
Clone this repository on your VPS and install the systemd integration and firewall:
```sh
# 1. Install kernel tuning and service account
sudo install -Dm644 ./host/server/99-xray-tuning.conf /etc/sysctl.d/
sudo sysctl --system
sudo install -Dm644 ./host/server/xray-server.sysusers.conf /usr/lib/sysusers.d/xray.conf
sudo systemd-sysusers

# 2. Install systemd service and firewall
sudo install -Dm644 ./host/server/xray-server.service /etc/systemd/system/
sudo install -Dm644 ./host/server/xray-server.nft /etc/nftables.conf
sudo systemctl enable --now nftables.service
```

### 1.3 Configure and Start the Server
Copy the template configuration and fill in your generated keys:
```sh
SCHEME=./schemes/vless-xtls-vision-reality
cp $SCHEME/server.json $SCHEME/server.local.json

# Edit $SCHEME/server.local.json with your editor:
# Replace <PLACEHOLDER:UUID> with your generated UUID
# Replace <PLACEHOLDER:REALITY_PRIVATE_KEY> with your generated PrivateKey
$EDITOR $SCHEME/server.local.json

# Validate syntax
xray run -test -config $SCHEME/server.local.json

# Deploy and start
sudo install -Dm600 $SCHEME/server.local.json /etc/xray/config.json
sudo systemctl daemon-reload
sudo systemctl enable --now xray-server.service
```
Check server status:
```sh
sudo systemctl status xray-server.service
```

---

## Step 2: Deploy the Client (Workstation)

Now switch to your local Linux workstation.

### 2.1 Install the Client OS Integration
The client uses Linux Netfilter TProxy to intercept traffic at wire speed:
```sh
# 1. Install systemd service, nftables rules, and service account
sudo install -Dm644 ./host/client/xray-tproxy.service /etc/systemd/system/
sudo install -Dm644 ./host/client/xray-tproxy.nft /etc/nftables/xray-tproxy.nft
sudo install -Dm644 ./host/client/xray-tproxy.sysusers.conf /usr/lib/sysusers.d/xray.conf
sudo systemd-sysusers

# 2. Attach policy routing to your physical network interface
# Identify your active uplink (e.g., 20-wireless or 10-ethernet in /etc/systemd/network/)
UPLINK="20-wireless"
sudo install -Dm644 ./host/client/xray-policy.conf \
  /etc/systemd/network/${UPLINK}.network.d/xray-policy.conf

sudo networkctl reconfigure ${UPLINK}
```

### 2.2 Configure the Client Scheme
Copy the client template and configure it to point to your VPS:
```sh
SCHEME=./schemes/vless-xtls-vision-reality
cp $SCHEME/client.json $SCHEME/client.local.json

# Edit $SCHEME/client.local.json:
# Fill in:
# - <PLACEHOLDER:SERVER_IP>: Your VPS IP address
# - <PLACEHOLDER:UUID>: Same UUID configured on the server
# - <PLACEHOLDER:REALITY_PUBLIC_KEY>: PublicKey from Step 1.1
$EDITOR $SCHEME/client.local.json

# Test configuration
xray run -test -config $SCHEME/client.local.json

# Deploy and start
sudo install -Dm600 $SCHEME/client.local.json /etc/xray/config.json
sudo systemctl daemon-reload
sudo systemctl enable --now xray-tproxy.service
```

---

## Step 3: Verify Your Connection

1. **Verify Outbound IP**:
   Run `curl` from your client terminal without specifying any proxy flags:
   ```sh
   curl https://api.ipify.org
   ```
   The output should match your VPS IP address.

2. **Verify Leak Prevention**:
   Check that domestic sites or direct connections remain unhindered, and DNS queries resolve securely via DoH.

---

## Next Steps

Congratulations! You now have a working, hardened transparent proxy.
- Learn more specific workflows in [How-To Guides](../how-to/index.md).
- Understand why this architecture is immune to DNS pollution in [DNS Explanation](../explanation/dns.md).
- Inspect nftables firewall and routing internals in [Traffic Selection Reference](../reference/traffic-selection.md).
