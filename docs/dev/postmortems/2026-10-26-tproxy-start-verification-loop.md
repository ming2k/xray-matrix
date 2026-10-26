# Postmortem: 2026-10-26 Transparent Proxy Restart Loop

## Executive Summary
A workstation running the transparent proxy entered an endless restart loop:
every two seconds the unit killed a healthy Xray process and reported `no TProxy
listener on 12345`. Three independent defects aligned behind that one symptom —
a start assertion that assumed the process is ready the moment it is forked, a
preflight that ran as `root` while the real start ran as `xray`, and a deployed
unit file that no longer matched the repository. Operator traffic kept flowing
unproxied instead of being lost, because the IPv4 policy rule had separately
been deleted by hand; had it been intact, the fail-closed datapath would have
taken the host offline. No credentials were exposed and no traffic leaked
through a broken tunnel — the tunnel never came up.

---

## Timeline of Events (UTC)

- **10:14** ($T_0$): `wright` seals and installs the `xray-tproxy` plan. The
  sealed unit asserts the `12345` listener with a single `ss` probe.
- **10:14–10:30**: The unit fails repeatedly with
  `open /etc/xray/config.json: permission denied` — `ExecStartPre … xray run -test`
  carries `+` and runs as `root`, so it passes while `ExecStart` fails as
  `User=xray`. The config is re-owned; the masking defect itself is not fixed.
- **10:32** ($T_{\text{impact}}$): A start succeeds and runs for 2 h 50 min.
  `ExecStartPost` happened to execute ~490 ms after the fork, so the single
  probe found the listener. The race is now invisible in the record.
- **10:42–11:06**: The plan and `host/client/xray-tproxy.service` gain the
  polling check (plan `release = 2`).
- **10:49**: Upstream `xray` is upgraded. The merge re-deploys the unit recorded
  at 10:14, so `/usr/lib/systemd/system/xray-tproxy.service` is byte-identical
  to `/var/lib/wright/sources/xray-tproxy-xray-tproxy.service` — the
  single-probe revision — and differs from the repository in exactly that line.
- **13:22**: The operator rewrites `/etc/xray/config.json` (enabling
  `/var/log/xray/access.log`) and restarts. Xray 26.10.21 needs ~470 ms to load
  geodata and bind; the probe fires ~30 ms after the fork.
- **13:22–13:23** ($T_{\text{detect}}$): Seven consecutive failed starts. Each
  cycle: `ExecStartPost` → `no TProxy listener on 12345` → systemd `TERM`s a
  process that had not yet printed its banner → `RestartSec=2`.
- **13:23**: The operator deletes the IPv4 policy rule (`ip rule del pref
  32765`) while reproducing, which is why the host kept network access: the
  marked packets were no longer routed into table 110. IPv6 is a separate rule
  set, so only IPv4 was affected.
- **13:29**: The deployed unit is patched in place with the polling check.
  Every start then fails with `no TProxy listener on 12345 after 15s` — proving
  the listener never appears because Xray is exiting, not because it is slow.
- **13:31**: The masked defect surfaces: `Failed to start: main: failed to
  create server > app/log: failed to initialize access logger > open
  /var/log/xray/access.log: permission denied`, `status=23`.
  `/var/log/xray/{access,error}.log` are `root:root 0600`: `LogsDirectory=`
  owns the directory, not files created by a root-run `xray`.
- **13:44** ($T_{\text{resolve}}$): `release = 3` — the unit re-owns both log
  files before start, and the config preflight drops `+` so it runs as `xray`.

---

## Detection Gaps

1. **Nothing compared the deployed unit with the shipped one.** Every route
   (repository `install`, `wright merge`) reports success without checking the
   bytes that landed in `/usr/lib/systemd/system/`. The package manager goes
   further and reports `Building … Staging … Sealing … Deploying` while
   rebuilding from a cached source copy, so an edit to the plan directory can
   be re-deployed as the previous revision. Three hours of "it is fixed in the
   repo" coexisted with a host running the older revision — twice.
2. **The preflight validated a different identity than the service.** Because
   `ExecStartPre … run -test` carried `+`, it could read a `config.json` and
   write log files that the main process could not. Permission defects passed
   the gate twice in one day and only ever appeared as `status=23`.
3. **A start assertion treated "forked" as "ready".** `Type=simple` makes
   `ExecStartPost` concurrent with the child's own startup; probing a listener
   without a deadline asserts a property that does not exist yet.
4. **The race hid behind a single lucky pass.** The 10:32 start won the race on
   a loaded machine, which is why the failure looked like a regression of the
   13:22 config edit rather than a property of the check itself.
5. **`LogsDirectory=` was assumed to cover file ownership.** It creates and
   owns the directory only; the files inside inherit whoever opened them first.
6. **No guard rails on kernel-state commands.** `ip rule del pref 32765`
   silently removes the IPv4 rule the whole datapath depends on, while
   `ip -6 rule` is unaffected — a partial, invisible bypass.

---

## Trigger & Underlying Root Cause

The trigger was ordinary: a config edit at 13:22 that enabled the access log.

The underlying cause is a start path that verified the wrong things, in two
senses. It verified *too early* — the listener probe ran against a process with
30 ms of lifetime, while the process needs ~470 ms to load `geoip.dat` /
`geosite.dat` and bind, so the assertion could only pass if the host was slow
enough to delay the probe. And it verified *as the wrong identity* — the
preflight ran as `root`, so the failure it was supposed to catch (unreadable
config, unwritable log) was invisible until `ExecStart`, where the operator sees
only `status=23`.

The restart loop amplifies both: `Restart=always` with `RestartSec=2` means a
deterministic check failure produces a two-second kill cycle, and `fail-closed`
`ExecStopPost` deliberately leaves nftables and table 110 installed, so each
failed start is also a decision to keep intercepting traffic with no listener.

---

## Action Items & Defense-in-Depth

| Action Item | Type | Status | Verification |
| :--- | :--- | :--- | :--- |
| Poll the listener for up to 10 s instead of probing once (`release = 2`) | Preventative | Completed | Failure message changed from instant to `after 10s` |
| Re-own `/var/log/xray/{access,error}.log` in `ExecStartPre` (`release = 3`) | Mechanical Guard | Written, deploy pending | `sudo cmp` of deployed vs packaged unit |
| Drop `+` from the config preflight, so it runs as `User=xray` (`release = 3`) | Mechanical Guard | Written, deploy pending | Preflight fails on an unreadable config before `ExecStart` |
| Apply the same two fixes to `host/server/xray-server.service`, whose schemes log to `/var/log/xray/` as well | Mechanical Guard | Completed | `systemd-analyze verify`; guard line identical to the client unit |
| Document "run xray as `xray`, never as root" next to the log-directory step | Documentation | Completed | [How to Install and Start …](../../how-to/install-and-start.md#create-the-xray-client-config) |
| Add a deployed-vs-shipped comparison to the verification runbook | Mechanical Guard | Completed | [Check the Installed Unit](../../how-to/verify-the-setup.md#check-the-installed-unit) |
| Drop the package manager's cached source/forge before rebuilding, and treat `cmp` as the acceptance test | Mechanical Guard | Completed | [Install the OS Layer](../../how-to/install-and-start.md#install-the-os-layer) |
| Add symptom rows for `status=23`, the instant `no TProxy listener`, and the deleted IPv4 rule | Documentation | Completed | [How to Troubleshoot …](../../how-to/troubleshoot-common-problems.md) |
| Document the identity rule for the preflight in the artifact reference | Documentation | Completed | [Host Artifacts Reference](../../reference/host-artifacts.md#start-sequence) |
| Reject `ip rule del pref 32765` outside a teardown script | Process | Open | Needs a decision: a wrapper or a documented prohibition |
