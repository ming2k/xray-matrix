# Documentation

Entry point for the project documentation.

## How-To Guides

| Page | Task |
|------|------|
| [How to Install and Start the Transparent Proxy](how-to/install-and-start.md) | Full installation from a bare system |
| [How to Verify the Setup](how-to/verify-the-setup.md) | Confirm traffic flows through Xray |
| [How to Use Captive Portal Networks](how-to/use-captive-portal-networks.md) | Public Wi-Fi login with the proxy running |
| [How to Troubleshoot Common Problems](how-to/troubleshoot-common-problems.md) | Symptom-driven fixes and diagnostics |

## Reference

| Page | Lookup target |
|------|---------------|
| [Client Configuration Reference](reference/client-configuration.md) | Xray config keys, placeholders, routing rules |
| [Traffic Selection Reference](reference/traffic-selection.md) | What nftables intercepts and what it bypasses |

## Explanation

| Page | Topic |
|------|-------|
| [Architecture](explanation/architecture.md) | Mechanism, component ownership, suspend/resume |
| [Data Packet Lifecycle](explanation/packet-lifecycle.md) | Round-trip packet journey and 3-tier traffic steering model |
| [DNS](explanation/dns.md) | System DNS vs. Xray DNS, and why port 53 stays direct |
| [Captive Portals](explanation/captive-portals.md) | Why portals break under TProxy and how the design avoids it |
| [Policy Decisions](explanation/policy-decisions.md) | QUIC, torrents, IPv6, DNS filtering and BBR: what is a choice, and its cost |

## Contributor

- [Contributor Documentation](dev/index.md)
