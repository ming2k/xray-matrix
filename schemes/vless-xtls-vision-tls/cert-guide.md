# Automated Certificate Management for VLESS + TLS

The `vless-xtls-vision-tls` scheme requires a valid TLS certificate issued by a trusted CA (such as Let's Encrypt or ZeroSSL).

---

## 1. Prerequisites

- A domain name with an `A` (or `AAAA`) record pointing to your server's public IP address (e.g., `node.example.com`).
- Port 80 and 443 accessible on the server firewall.

---

## 2. Issuance Methods

### Method A: Standalone Issuance (Before Starting Xray)

If Xray is not running yet, Certbot can bind port 80 directly:

```sh
# 1. Install certbot
sudo apt update && sudo apt install -y certbot

# 2. Issue certificate via standalone HTTP-01 challenge
sudo certbot certonly --standalone \
  -d node.example.com \
  --agree-tos \
  --register-unsafely-without-email
```

### Method B: DNS-01 API Issuance (Zero Port Conflict, Recommended)

DNS-01 does not require port 80 to be open and never conflicts with web servers or Xray:

```sh
# Using acme.sh with Cloudflare API
curl https://get.acme.sh | sh -s email=admin@example.com
export CF_Token="your_cloudflare_api_token"
export CF_Zone_ID="your_zone_id"

~/.acme.sh/acme.sh --issue --dns dns_cf -d node.example.com \
  --key-file /etc/xray/privkey.pem \
  --fullchain-file /etc/xray/fullchain.pem \
  --reloadcmd "systemctl restart xray-server.service"
```

---

## 3. Service Account Permissions

By default, `/etc/letsencrypt/live/` and `/etc/letsencrypt/archive/` are restricted to `root:root` with `0700` permissions. The unprivileged `xray` service user must be granted read access:

```sh
# Grant the xray user read access using POSIX ACLs
sudo setfacl -R -m u:xray:rx /etc/letsencrypt/live/
sudo setfacl -R -m u:xray:rx /etc/letsencrypt/archive/

# Ensure new certificates automatically inherit read permissions
sudo setfacl -R -d -m u:xray:rx /etc/letsencrypt/live/
sudo setfacl -R -d -m u:xray:rx /etc/letsencrypt/archive/
```

---

## 4. Automated Renewal with Reload Hook

Certbot renews automatically via systemd timer (`certbot.timer`). Configure a renewal hook to restart Xray and re-assert permissions when a certificate updates:

Create `/etc/letsencrypt/renewal-hooks/deploy/xray-reload.sh`:

```sh
#!/bin/bash
setfacl -R -m u:xray:rx /etc/letsencrypt/live/
setfacl -R -m u:xray:rx /etc/letsencrypt/archive/
systemctl reload-or-restart xray-server.service
```

Make it executable:

```sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/xray-reload.sh
```

---

## 5. Security & Censorship Hazard: Certificate Transparency (CT) Logs

When obtaining a certificate from public authorities (Let's Encrypt, ZeroSSL), the issuance is automatically logged in public **Certificate Transparency (CT)** logs (RFC 6962).

### The Threat
1. **Automated Discovery**: Active censors and crawler bots continuously monitor CT log streams. A newly registered domain or subdomain pointing to an IP range of a foreign VPS provider (e.g., Bandwagon, Vultr, DigitalOcean) immediately flags your server.
2. **Predictable Naming**: Subdomains containing words like `vpn`, `node`, `proxy`, or `xray` invite immediate targeted probing.

### Mitigations
- **Use generic subdomain names**: Use plausible names (e.g., `api`, `static`, `doc`, `assets`) rather than proxy-related keywords.
- **Wildcard certificates**: Issuing a wildcard certificate (`*.example.com`) via DNS-01 challenge hides individual subdomains in CT log entries.
- **Evaluate REALITY**: If domain exposure or CT log scraping presents an unacceptable risk, use [VLESS + Vision + REALITY](../vless-xtls-vision-reality/README.md) instead, which borrows third-party certificates and requires no domain registration.
