# Explanation & Architectural Deep Dives

Discursive documentation explaining how and why `xray-matrix` is built the way it is. Read these to understand networking models, cryptographic guarantees, and trade-offs.

---

## Architecture & Kernel Networking

| Article | Explains |
| :--- | :--- |
| **[System Architecture](architecture.md)** | End-to-end architecture, the Two-Layer model, component boundaries, and suspend/resume lifecycle. |
| **[Data Packet Lifecycle](packet-lifecycle.md)** | Round-trip packet journey through Netfilter hooks, policy routing table 110, and zero-copy transfer. |
| **[DNS Architecture & Real-IP Split](dns.md)** | Why port 53 stays direct, DoH encrypted resolution, and why FakeIP was rejected. |
| **[Captive Portal Compatibility](captive-portals.md)** | How public Wi-Fi captive portals operate and how the TProxy design permits native login. |
| **[Policy & Routing Decisions](policy-decisions.md)** | Trade-offs concerning QUIC interception, BitTorrent blocking, IPv6 dual-stack, and DNS filtering. |

---

## Cryptography & Camouflage Mechanisms

| Article | Explains |
| :--- | :--- |
| **[XTLS-Vision Mechanism](xtls-vision.md)** | TLS-in-TLS signature elimination via dynamic handshake padding and Linux `splice()` zero-copy acceleration. |
| **[REALITY Target Selection & Camouflage](reality-target-selection.md)** | Threat model, physical constraints, traffic volume profiling, and regional catalogs for borrowed TLS targets. |

---

## Related Documentation

- For practical application of these principles, see [How-To Guides](../how-to/index.md).
- For exact parameter values, consult [Reference](../reference/index.md).
