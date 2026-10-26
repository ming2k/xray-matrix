# How-To Guides

Task-oriented recipes for operators and system administrators. Each guide assumes you have basic familiarity with Linux networking and provides step-by-step solutions to specific operational tasks.

---

## Client Setup & Administration

| Guide | Solves |
| :--- | :--- |
| **[Install and Start the Transparent Proxy](install-and-start.md)** | Step-by-step client installation on a bare Linux workstation or router. |
| **[Verify the Setup](verify-the-setup.md)** | Verify transparent packet interception, DNS leak prevention, and egress routing. |
| **[Use Captive Portal Networks](use-captive-portal-networks.md)** | Authenticate through public Wi-Fi login popups while the transparent proxy is active. |
| **[Troubleshoot Common Problems](troubleshoot-common-problems.md)** | Symptom-driven diagnoses and fixes for routing, firewall, and permission issues. |
| **[Diagnose GFW Blocks and Network Anomalies](diagnose-gfw-blocks.md)** | Methodical diagnosis for GFW IP/port blocks, connection reuse illusions, and multi-vantage probing. |

---

## Server Deployment & Hardening

| Guide | Solves |
| :--- | :--- |
| **[Deploy an Xray Proxy Server on a VPS](deploy-server.md)** | VPS egress node provisioning, unprivileged sandboxing, BBR tuning, and nftables firewall. |
| **[Share Port 443 with an Existing Website](share-port-443-with-a-website.md)** | Layer-4 SNI demultiplexer for hosts that already terminate TLS for real sites on 443. |
| **[Set Up VLESS + Vision + TLS with Web Fallback](setup-tls-fallback.md)** | Automated ACME Let's Encrypt certificates and Nginx/Caddy reverse proxy disguise site. |

---

## Related Documentation

- For theoretical background on traffic steering and packet paths, see [Explanation](../explanation/index.md).
- For exact JSON schemas and nftables parameters, consult [Reference](../reference/index.md).
