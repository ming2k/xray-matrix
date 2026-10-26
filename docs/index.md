# Documentation

Welcome to the **xray-matrix** documentation.

`xray-matrix` provides a hardened, transparent proxy architecture for modern Linux workstations, routers, and server egress nodes. The documentation is organized according to the **Diátaxis** framework across four distinct quadrants.

---

## The Four Quadrants

```text
               PRACTICAL                   THEORETICAL
          ┌─────────────────────────┬─────────────────────────┐
          │  Tutorials              │  How-To Guides          │
LEARNING  │  (Learning-Oriented)    │  (Task-Oriented)        │
          │  `docs/tutorials/`      │  `docs/how-to/`         │
          ├─────────────────────────┼─────────────────────────┤
          │  Reference              │  Explanation            │
WORKING   │  (Information-Oriented) │  (Understanding-Orient) │
          │  `docs/reference/`      │  `docs/explanation/`    │
          └─────────────────────────┴─────────────────────────┘
```

---

## 1. [Tutorials](tutorials/index.md)
Learning-oriented guides for new operators. Follow step-by-step to achieve your first working setup:
- **[Getting Started: Deploying Your First Xray Transparent Proxy](tutorials/getting-started.md)**: From a clean machine to a running VPS egress node and Linux client transparent proxy.

---

## 2. [How-To Guides](how-to/index.md)
Task-oriented recipes for specific administration and operational needs:

### Client Workstation & Gateway
- **[How to Install and Start the Transparent Proxy](how-to/install-and-start.md)**
- **[How to Verify the Setup](how-to/verify-the-setup.md)**
- **[How to Use Captive Portal Networks](how-to/use-captive-portal-networks.md)**
- **[How to Troubleshoot Common Problems](how-to/troubleshoot-common-problems.md)**
- **[How to Diagnose GFW Blocks and Network Anomalies](how-to/diagnose-gfw-blocks.md)**

### Server VPS Node
- **[How to Deploy an Xray Proxy Server on a VPS](how-to/deploy-server.md)**
- **[How to Share Port 443 with an Existing Website](how-to/share-port-443-with-a-website.md)**
- **[How to Set Up VLESS + Vision + TLS with Web Fallback](how-to/setup-tls-fallback.md)**: (Legacy / Corporate Profile; requires self-owned domain and CA certificate).

---

## 3. [Reference](reference/index.md)
Formal technical specifications, configuration keys, and kernel artifacts:
- **[Client Configuration Reference](reference/client-configuration.md)**: Keys, placeholders, and routing rule order.
- **[Server Configuration Reference](reference/server-configuration.md)**: Inbound parameters and PROXY protocol fallback.
- **[Traffic Selection Reference](reference/traffic-selection.md)**: nftables rules, bypass sets, and port handling.
- **[Host Artifacts Reference](reference/host-artifacts.md)**: Service units, sandboxing, and kernel tuning parameters.

---

## 4. [Explanation](explanation/index.md)
Architectural deep dives, cryptographic guarantees, and networking rationale:
- **[System Architecture](explanation/architecture.md)**: The Two-Layer model and datapath isolation.
- **[Data Packet Lifecycle](explanation/packet-lifecycle.md)**: TProxy steering, table 110, and round-trip journey.
- **[DNS Architecture & Real-IP Split](explanation/dns.md)**: Why port 53 stays direct and DoH eliminates pollution.
- **[Captive Portal Compatibility](explanation/captive-portals.md)**: Transparent network escape mechanism.
- **[Policy Decisions](explanation/policy-decisions.md)**: QUIC, BitTorrent, IPv6, and filtering trade-offs.
- **[XTLS-Vision Mechanism](explanation/xtls-vision.md)**: TLS-in-TLS padding and zero-copy splice.
- **[REALITY Target Selection & Camouflage](explanation/reality-target-selection.md)**: Threat model and target domains.
