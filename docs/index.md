# Documentation

Entry point for the project documentation.

## Where things live

The repository has two layers, and each keeps its documentation beside it:

| Layer | Documentation |
|-------|---------------|
| `schemes/` — *what you run* | [Transport Schemes](../schemes/README.md) compares them and links each scheme's own page. Mechanism, threat model, key generation and operational limits live with the scheme, in `schemes/<scheme>/README.md`. |
| `host/` — *where it runs* | The client and server OS integration, documented below. Nothing here changes when you switch schemes. |

The guides below are split by which host you are setting up.

## How-To Guides

### Client Setup
| Page | Task |
|------|------|
| [How to Install and Start the Transparent Proxy](how-to/install-and-start.md) | Full client installation from a bare system |
| [How to Verify the Setup](how-to/verify-the-setup.md) | Confirm traffic flows through Xray |
| [How to Use Captive Portal Networks](how-to/use-captive-portal-networks.md) | Public Wi-Fi login with the proxy running |
| [How to Troubleshoot Common Problems](how-to/troubleshoot-common-problems.md) | Symptom-driven fixes and diagnostics |

### Server Setup
| Page | Task |
|------|------|
| [How to Deploy an Xray Proxy Server on a VPS](how-to/deploy-server.md) | Server hardening, BBR tuning, firewall, and service setup |
| [How to Set Up VLESS + Vision + TLS with Web Fallback](how-to/setup-tls-fallback.md) | Automated ACME certificates and Nginx fallback site |

## Reference

| Page | Lookup target |
|------|---------------|
| [Transport Schemes](../schemes/README.md) | Scheme comparison, selection, probe-response behaviour, switching |
| [REALITY Scheme](../schemes/vless-xtls-vision-reality/README.md) | The Session ID channel, probe deflection, key generation |
| [TLS + Fallback Scheme](../schemes/vless-xtls-vision-tls/README.md) | One port, two behaviours, PROXY protocol, certificate setup |
| [Client Configuration Reference](reference/client-configuration.md) | Client Xray keys, placeholders, and routing rules |
| [Server Configuration Reference](reference/server-configuration.md) | Server Xray keys, fallbacks, and stream settings |
| [Traffic Selection Reference](reference/traffic-selection.md) | What nftables intercepts and what it bypasses |

## Explanation

### Architecture & Networking
| Page | Topic |
|------|-------|
| [Architecture](explanation/architecture.md) | End-to-end architecture, component ownership, suspend/resume |
| [Data Packet Lifecycle](explanation/packet-lifecycle.md) | Round-trip packet journey and 3-tier traffic steering model |
| [DNS](explanation/dns.md) | System DNS vs. Xray DNS, and why port 53 stays direct |
| [Captive Portals](explanation/captive-portals.md) | Why portals break under TProxy and how the design avoids it |
| [Policy Decisions](explanation/policy-decisions.md) | QUIC, torrents, IPv6, DNS filtering and BBR: choices and trade-offs |

### Cryptographic & Anti-Censorship Mechanisms
| Page | Topic |
|------|-------|
| [XTLS-Vision Mechanism](explanation/mechanisms/xtls-vision.md) | TLS-in-TLS padding obfuscation and Linux kernel zero-copy splice (shared by both schemes) |

## Contributor

- [Contributor Documentation](dev/index.md)
