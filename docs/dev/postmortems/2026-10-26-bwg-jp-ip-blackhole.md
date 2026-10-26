# Postmortem: 2026-10-26 Unreachable Egress Node (IP-Level TCP Blackhole)

## Executive Summary
An egress node in Osaka (`212.50.249.175`, AS25820) was reported as "port 10443
looks blocked". The port was not the problem: the whole address was a **TCP
blackhole from mainland China on every port** (22, 25, 443, 993 measured), while
ICMP kept answering and every vantage outside China reached it normally. Three
diagnostic artefacts hid that conclusion for most of the session — a working SSH
session that was in fact reusing a multiplexed connection through another node,
ICMP echo replies that come from the provider's edge, and local `connect()` calls
that "succeeded" in 0 ms because the workstation's transparent proxy answered them
itself. The node was rebuilt on 443 with a better borrowed identity anyway, which
means the "port" hypothesis was fixed without being the cause. A two-hop chain
through the US node was validated as a stopgap, and the diagnosis became a
step-by-step procedure in the public how-to.

---

## Timeline of Events (UTC, approximate)

- **12:47** ($T_0$): Operator reports that REALITY on `10443` "seems blocked", and
  asks for a rebuild on 443 with a stronger borrow target. The existing inbound
  borrowed `www.lovelive-anime.jp`, which returns `403` from CloudFront to a
  datacenter probe — a probe-visible anomaly independent of any block.
- **12:50–13:05**: `ssh bwg-jp` is attempted directly and fails at
  "banner exchange". A `ProxyJump` through the US node is added to make the
  host reachable; from then on `ssh bwg-jp` works and is mistaken for evidence
  that the address is reachable. `ControlMaster`/`ControlPersist` is enabled in
  the same edit.
- **13:05–13:30**: Node rebuilt: Xray upgraded `26.3.27 → 26.10.21`, inbound moved
  to `0.0.0.0:443`, borrow target replaced with `cdn.softbank.jp` (`0.6 ms` RTT,
  TLS 1.3, HTTP/2, `200`), BBR/64 MB socket buffers applied, `ExecStartPre`
  preflight and log rotation added. Server-side verification from the node itself
  and from the US node both pass (`HTTP/2 200`, genuine SoftBank certificate).
- **13:30–14:10** ($T_{\text{detect}}$): Client in China cannot connect. Measurements
  accumulate: ICMP `0%` loss at `130 ms`; every TCP port to the address times out;
  the US node reaches `443` fine; `check-host.net` reports 50/50 foreign nodes
  successful; Globalping reports 5/5 Chinese ASes unable to establish TCP on
  `:25`, later 6/6 on the mail server's port.
- **14:10–14:40**: The false positives are each dismantled: the SSH session is
  found to carry `sshd`'s view `45.62.102.129` (the US node) as its source; a
  direct `ssh -o ProxyJump=none -o ControlPath=none` fails at connect; a local
  `python` `connect()` returning `0 ms` is traced to TProxy answering on
  `127.0.0.1:12345`. Conclusion: evidence of an IP-level block.
- **14:40**: Stopgap validated: client → US node `:443` → Japan node `:443` via
  `dialerProxy` exits in Japan at `14.8 MB/s` (single hop: `17.0 MB/s`).
- **15:10**: Root-cause knowledge written into the public how-to as a
  four-step procedure, including the "did the packet arrive at all" test that
  would have short-circuited the session.

---

## Detection Gaps

1. **SSH success was treated as reachability.** With `ProxyJump` + `ControlMaster`
   in place, `ssh <host>` opens a shell over a previously established multiplexed
   socket. It proves nothing about the direct path, and it silently survives the
   removal of the very `ProxyJump` line that created it (`ControlPersist 10m`).
   Detection: `ssh -O check <host>` reports a live master; `sshd` on the remote
   side reports the *jump host's* address as the peer.
2. **ICMP echo replies were treated as reachability.** The replies came back at
   `130 ms` with `0%` loss while every TCP SYN was dropped, because providers and
   upstream routers answer ICMP at the edge. Detection: a TCP handshake, never a
   ping.
3. **A local `connect()` returning in 0 ms was treated as the server accepting.**
   It was the workstation's own TProxy listener. Detection: stop the client unit,
   or compare against a second host.
4. **The "blocked port" framing survived because 10443 was the only port anyone
   had tested.** Testing the address on four unrelated ports took one minute and
   settled it.

---

## Trigger & Underlying Root Cause

The address is unusable from mainland China at the IP layer: TCP SYNs are dropped
for all ports while ICMP passes. What caused the address to be selected for that
treatment is not observable from the outside; the plausible contributors are the
node's long service as a proxy endpoint (the previous REALITY inbound had run for
months on a non-standard port), and a borrowed identity that answered probes with
`403`. Neither is provable from evidence available to the operator, and neither
changes the response.

Two secondary defects were confirmed and fixed in the same window:

- the previous borrow target was probe-hostile (`www.lovelive-anime.jp` behind
  CloudFront answers datacenter probes with `403`), which is a self-inflicted
  detection signal;
- the node had no `ExecStartPre` config preflight and no log rotation, so a bad
  edit could replace a working process and logs grew without bound.

---

## Action Items & Defense-in-Depth

| Item | Status |
| :--- | :--- |
| Diagnose with TCP on multiple ports before believing a port-specific report | Done — [How to Diagnose GFW Blocks](../../how-to/diagnose-gfw-blocks.md) failure-mode table |
| Prove whether the packet reached the server (backend log count + kernel counters + spare-port A/B) | Done — same guide, "Confirm Whether the Packet Reached the Server" |
| Treat SSH/ICMP/TProxy success as non-evidence; three named illusions documented | Done — same guide, "Common Diagnostic Illusions" |
| Keep a documented two-hop chain available for any node that becomes unreachable | Done — [Client Configuration Reference](../../reference/client-configuration.md), "Two-Hop Chaining" |
| Replace probe-hostile borrow targets with targets that answer `200` from a datacenter | Done — target rebuilt on `cdn.softbank.jp` |
| Request an IP replacement for the mail-serving host, or separate mail from proxy duty | **Open** — the same address serves `mail.hihusky.com`; SMTP/IMAP from China measured 0/6 reachable |
| Add a per-node smoke test that runs from inside China before a node is declared production | **Open** — currently manual |
