# Scheme: VLESS + TCP + XTLS-Vision + TLS (with Web Fallback)

This scheme pairs a self-owned domain and valid CA certificate with XTLS-Vision and active probe deflection via local Web Fallback (Nginx/Caddy).

---

## 1. Architectural Overview

```text
[Client / Browser]
        |
        | TLS 1.3 Handshake (SNI: node.example.com)
        v
[Xray Server :443] (Terminates TLS with valid CA certificate)
        |
        +---> Valid VLESS UUID + Vision Flow?
        |         |-- YES --> [XTLS-Vision Engine] --> Direct Kernel Splice --> Internet
        |
        +---> Standard HTTPS / Active Probe / Scanner GET?
                  |-- NO  --> [Fallback via PROXY Protocol v1]
                                  |
                                  v
                      [Nginx / Caddy :8080] --> Returns authentic 200 OK Website
```

---

## 2. Key Mechanisms

### 2.1 100% Compliant TLS 1.3 Handshake
Unlike REALITY (which synthesizes handshake parameters to match a stolen destination identity), this scheme executes a standard, RFC 8446-compliant TLS 1.3 handshake using a genuine certificate issued by a trusted CA (Let's Encrypt / ZeroSSL).
- **Enterprise Firewall Friendly**: In strict corporate or university networks that inspect SNI-to-IP matching and certificate validity chains, standard TLS avoids alarms triggered by REALITY IP-to-ASN discrepancies.
- **ALPN Negotiation**: Advertises `h2` and `http/1.1`, matching modern web browsers.

### 2.2 Active Probing Deflection via Fallbacks
If a censor's active scanner connects to port 443:
1. The scanner successfully completes the TLS handshake (verifying the genuine certificate).
2. The scanner sends an HTTP probe (`GET / HTTP/1.1`, invalid handshake data, or randomized bytes).
3. Xray inspects the decrypted stream: because the payload does not begin with a valid VLESS header and matching UUID, Xray triggers the `fallbacks` handler.
4. Xray prepends a PROXY protocol header (`xver: 1`, preserving the scanner's real IP) and pipes the socket directly to local Nginx on `127.0.0.1:8080`.
5. Nginx parses the request and returns a standard `200 OK` response with a realistic static website (`server/fallback/nginx/www/index.html`).
6. To the scanner, the endpoint behaves identically to an ordinary HTTPS web server hosting documentation or a portfolio.

### 2.3 XTLS-Vision Protection
When an authenticated client connects:
1. **Vision Handshake Obfuscation**: The client and server exchange Vision control frames with randomized padding, defeating TLS-in-TLS record length correlation classifiers.
2. **Zero-Copy Splice**: When inner HTTPS traffic is detected, Xray initiates Linux `splice()` system calls, passing encrypted packets directly between network sockets without double encryption or user-space buffer overhead.

---

## 3. Quick Start

### Step 1: Deploy Web Fallback & Tuning (Server)
```sh
# 1. Apply kernel tuning
sudo cp server/99-xray-tuning.conf /etc/sysctl.d/
sudo sysctl --system

# 2. Deploy Nginx fallback site
sudo cp server/fallback/nginx/nginx.conf /etc/nginx/nginx.conf
sudo mkdir -p /var/www/fallback
sudo cp server/fallback/nginx/www/index.html /var/www/fallback/
sudo systemctl restart nginx
```

### Step 2: Issue Certificate
Follow [Certificate Management Guide](cert-guide.md) to acquire Let's Encrypt certificates for `<SERVER_DOMAIN:node.example.com>`.

### Step 3: Deploy Server Config
```sh
S=./schemes/vless-xtls-vision-tls
cp $S/server.json $S/server.local.json
$EDITOR $S/server.local.json      # fill in <UUID:...>, <SERVER_DOMAIN:...>, cert paths
xray run -test -config $S/server.local.json
sudo install -Dm600 $S/server.local.json /etc/xray/config.json
sudo systemctl restart xray-server.service
```

### Step 4: Deploy Client Config
```sh
S=./schemes/vless-xtls-vision-tls
cp $S/client.json $S/client.local.json
$EDITOR $S/client.local.json      # fill in the same UUID, plus <SERVER_IP:...> and <SERVER_DOMAIN:...>
xray run -test -config $S/client.local.json
sudo install -Dm600 $S/client.local.json /etc/xray/config.json
sudo systemctl restart xray-tproxy.service
```
