# How to Set Up VLESS + Vision + TLS with Web Fallback

This guide walks through deploying the `vless-xtls-vision-tls` scheme, issuing a valid TLS certificate with Let's Encrypt, and configuring local Nginx to handle active probe deflection.

---

## Prerequisites

- Server host prepared with [How to Deploy an Xray Proxy Server on a VPS](deploy-server.md).
- A domain name (e.g., `node.example.com`) whose `A` record points to your VPS public IPv4 address.
- Nginx and Certbot installed:
  ```sh
  sudo apt update && sudo apt install -y nginx certbot acl
  ```

---

## Step 1: Deploy Disguise Website and Nginx Fallback

Deploy the local Nginx fallback server listening on `127.0.0.1:8080` with PROXY protocol support:

```sh
# 1. Install website files
sudo mkdir -p /var/www/fallback
sudo cp ./host/server/fallback/nginx/www/index.html /var/www/fallback/index.html

# 2. Deploy Nginx configuration
sudo cp ./host/server/fallback/nginx/nginx.conf /etc/nginx/nginx.conf

# 3. Test and restart Nginx
sudo nginx -t
sudo systemctl restart nginx
```

---

## Step 2: Issue Certificate via Certbot

Issue a valid CA certificate for your domain:

```sh
# Issue certificate in standalone mode
sudo certbot certonly --standalone \
  -d node.example.com \
  --agree-tos \
  --register-unsafely-without-email
```

### Grant Permissions to the Xray Service Account
Certbot creates certificate directories with `0700 root:root`. Grant the unprivileged `xray` service user read permissions:

```sh
sudo setfacl -R -m u:xray:rx /etc/letsencrypt/live/
sudo setfacl -R -m u:xray:rx /etc/letsencrypt/archive/
sudo setfacl -R -d -m u:xray:rx /etc/letsencrypt/live/
sudo setfacl -R -d -m u:xray:rx /etc/letsencrypt/archive/
```

---

## Step 3: Deploy the Xray Configs

With the web server and the certificate in place, the Xray side is the scheme's
own deployment: copy `server.json` on this host — and `client.json` on the
client — to a sibling `*.local.json`, fill in `<UUID:...>` and
`<SERVER_DOMAIN:...>`, validate, and install. The commands and the placeholder
list are in
[Deploying This Scheme](../../schemes/vless-xtls-vision-tls/README.md#5-deploying-this-scheme).

Two values must agree across the two hosts, and both come from this one scheme
directory: the UUID, and the domain name (`serverNames` on the server,
`serverName` on the client). The certificate must be issued for that same
domain, or the client fails the handshake.

---

## Step 4: Verification

1. **Verify Web Fallback**: Open `https://node.example.com` in a browser or run:
   ```sh
   curl -I https://node.example.com
   ```
   You should see `HTTP/2 200` with the disguise site content.
2. **Verify Proxy Connectivity**: On the client machine, run:
   ```sh
   curl -I https://www.google.com
   ```
   Traffic should flow through the VLESS tunnel smoothly.
