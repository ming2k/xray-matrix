---
id: ADR-0002
title: "TProxy and Policy Routing over TUN/Redirect"
status: accepted
date: 2026-10-26
scope: [host/client]
superseded_by: null
invariants: ["[INV-FAIL-CLOSED]"]
---

# ADR-0002: TProxy and Policy Routing over TUN/Redirect

## Context & Problem Statement
On Linux client workstations and gateway routers, transparent traffic interception can be achieved through multiple kernel mechanisms: Linux TUN virtual network devices (e.g., `tun0` with a userspace tun2socks daemon), iptables/nftables `REDIRECT`/`DNAT`, or Linux Netfilter `TPROXY` combined with policy routing.

We must choose an interception topology that delivers wire-speed zero-copy forwarding, preserves original socket destination metadata, supports both TCP and UDP natively, and guarantees fail-closed security.

## Decision Drivers
- High throughput and low latency via Linux kernel zero-copy transfer (`splice()`).
- Unified, native handling of both TCP and UDP without synthetic connection translators.
- Zero per-application proxy configuration.
- Preservation of authentic original destination IP and port without NAT table bloat.

## Considered Options
1. **Userspace TUN Interface (tun2socks / tun-inbound)**: Intercept all IP packets via a virtual TUN adapter.
2. **NAT / REDIRECT**: Use Netfilter `REDIRECT` or `DNAT` targets to capture traffic.
3. **Netfilter TPROXY with Policy Routing (Table 110 & fwmark)**: Intercept packets using `tproxy ip to 127.0.0.1:12345` with IP rule marking.

## Decision Outcome
Chosen option: **Option 3: Netfilter TPROXY with Policy Routing**.

- **Datapath**: Local outbound traffic (or forwarded LAN traffic) is marked with `mark 1` in the nftables `output` / `prerouting` hooks.
- **Routing**: Policy routing rule `ip rule add fwmark 1 lookup 110` steers marked packets to routing table `110`, which directs them to `local default dev lo table 110`.
- **Socket Delivery**: The kernel delivers transparent proxy connections directly to Xray's listening socket (`127.0.0.1:12345`) with `IP_TRANSPARENT`.
- **Zero-Copy Splice**: For TCP streams, XTLS-Vision leverages Linux `splice()` to pipe data directly between sockets in kernel space without userspace buffer copying.

### Ratified Invariants
- `[INV-FAIL-CLOSED]`: Intercepted traffic is strictly routed to the loopback TProxy socket. If the user-space daemon stops, table 110 drops traffic rather than falling back to unencrypted egress.

## Negative Knowledge & Discarded Alternatives
- **Why not TUN devices?** TUN adapters force all packets across the kernel-userspace boundary twice per transfer, preventing the use of `splice()` zero-copy kernel transfers and causing high CPU overhead during gigabit saturations.
- **Why not REDIRECT / DNAT?** Netfilter `REDIRECT` only works for TCP (not UDP), alters the packet headers destructively, bloats the conntrack table, and fails to handle modern QUIC/UDP proxying seamlessly.
