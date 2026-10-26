# Technical Reference

Authoritative technical specifications, configuration parameters, systemd unit definitions, and kernel table allocations.

---

## Configuration & Scheme Reference

| Reference Page | Details |
| :--- | :--- |
| **[Client Configuration Reference](client-configuration.md)** | Client Xray JSON keys, placeholders, routing rule priorities, and DNS settings. |
| **[Server Configuration Reference](server-configuration.md)** | Server Xray JSON keys, inbound fallbacks, PROXY protocol, and transport parameters. |

---

## Operating System & Network Reference

| Reference Page | Details |
| :--- | :--- |
| **[Traffic Selection Reference](traffic-selection.md)** | Exact nftables table rulesets (`xray_v4`, `xray_v6`), bypass CIDRs, and port policies. |
| **[Host Artifacts Reference](host-artifacts.md)** | Service accounts, systemd unit lifecycles, sandbox security flags, and sysctl BBR tunings. |

---

## Related Documentation

- For practical tasks using these artifacts, see [How-To Guides](../how-to/index.md).
- For the cryptographic and architectural principles behind these choices, consult [Explanation](../explanation/index.md).
