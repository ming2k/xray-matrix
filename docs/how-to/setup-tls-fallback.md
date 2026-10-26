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

## Step 3: Deploy Xray Server Configuration

Deploy the server template from the scheme directory:

```sh
# 1. Copy the scheme template to a git-ignored local copy
S=./schemes/vless-xtls-vision-tls
cp $S/server.json $S/server.local.json

# 2. Edit configuration
$EDITOR $S/server.local.json
# Replace:
#   <UUID:...> with your UUID (generate with `xray uuid`)
#   <SERVER_DOMAIN:...> with your actual domain (e.g., node.example.com)

# 3. Test and install
xray run -test -config $S/server.local.json
sudo install -Dm600 $S/server.local.json /etc/xray/config.json
sudo systemctl restart xray-server.service
```

---

## Step 4: Configure Client Side

On the client machine (workstation or router):

```sh
# 1. Copy the scheme template to a git-ignored local copy
S=./schemes/vless-xtls-vision-tls
cp $S/client.json $S/client.local.json

# 2. Edit configuration
$EDITOR $S/client.local.json
# Replace:
#   <SERVER_DOMAIN:...> with node.example.com
#   <UUID:...> with matching server UUID
#   <SERVER_IP:...> with VPS public IP (for routing bypass)

# 3. Validate and install
xray run -test -config $S/client.local.json
sudo install -Dm600 $S/client.local.json /etc/xray/config.json
sudo systemctl restart xray-tproxy.service
```

---

## Step 5: Verification

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
