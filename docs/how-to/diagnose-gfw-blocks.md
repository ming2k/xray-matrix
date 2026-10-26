# How to Diagnose GFW Blocks and Network Anomalies

A systematic troubleshooting runbook for diagnosing connection failures between
a domestic client and an overseas proxy server. This guide covers how to detect
GFW IP and port blocks, avoid diagnostic false positives (such as SSH connection
reuse and ICMP illusions), and verify server health from multiple global vantages.

---

## 1. Threat Model and Failure Modes

The Great Firewall (GFW) employs layered passive traffic analysis, heuristic
flow profiling, and active probing. When diagnosing connectivity failure, first
identify which failure mode has occurred:

| Failure Mode | Symptoms | Root Cause |
| :--- | :--- | :--- |
| **Port-Level Block** | A specific port (e.g. 10443) drops TCP SYN packets; other ports (e.g. SSH 22) work normally. | High sustained throughput on a non-standard port triggers heuristic classification; Xray warns against non-443 REALITY for this reason. |
| **Full-IP TCP Blackhole** | All TCP connections to the server IP time out (ports 22, 25, 80, 443, 993); ICMP ping continues to respond normally. | The destination IP is placed on the edge routing blackhole table for TCP SYN packets. |
| **Active Probe Flagging** | A previously working REALITY port abruptly dies after scanning activity. | The borrowed SNI/`dest` returned an anomaly (e.g., HTTP 403 Forbidden, CDN error, redirect, or cross-ocean latency $\Delta T > 15\text{ms}$). |
| **Carrier SYN Drop for one `(IP, port)` pair** | A single port (often 443) to one IP loses 10–50 % of *new* connections, in bursts that last minutes to hours; the same routing on a spare port is clean; other Chinese networks are clean. | The access network probabilistically drops SYNs to a flagged `(destination, port)` tuple. The server never sees the packets, so nothing is logged anywhere. |
| **Local TProxy Routing Loop** | Client machine experiences 100% CPU, DNS failure, or immediate connection resets. | Packet mark collision (`mark: 2`), missing firewall exemptions, or loopback routing errors on the client host. |

---

## 2. Common Diagnostic Illusions (False Positives)

When diagnosing network blocks, three common mechanisms frequently mislead
operators into believing a connection is healthy when it is broken, or vice versa:

### 2.1 The ICMP Echo Illusion

```text
[ Client (China) ] ── ICMP Echo Request ──> [ Edge Router / Gateway ]
                   <── ICMP Echo Reply ──── (Responds directly, ~130ms)
                                             |
                                   (VPS IP: 203.0.113.10)
                                             |
[ Client (China) ] ── TCP SYN (Port 443) ──> [ GFW Filter: Silently Dropped ]
                   (No response, timeout)
```

- **The Illusion**: Running `ping <SERVER_IP>` shows `0% packet loss` with stable
  latency (e.g., 130 ms). Operators assume "the server is up and reachable".
- **The Reality**: Modern cloud providers and upstream internet exchanges often
  terminate or respond to ICMP Echo requests at edge border routers or hypervisor
  gateways before packets reach the VPS. The GFW selectively drops **TCP SYN**
  packets for flagged destination IPs while passing ICMP unaffected.
- **Rule**: Never use `ping` alone to assess proxy reachability. Always test layer-4
  TCP handshake behavior.

### 2.2 The SSH ControlMaster / Connection Reuse Illusion

- **The Illusion**: An operator thinks direct connectivity to the VPS is still
  working because running `ssh my-vps` instantly opens a shell prompt, even after
  commenting out proxy settings or shutting down the proxy daemon.
- **The Reality**: OpenSSH `ControlMaster` and `ControlPersist` keep an existing
  authenticated master socket alive in the background (typically at
  `~/.ssh/cm-<user>@<host>:<port>`). If that master connection was originally
  established through a jump host (e.g. `ProxyJump jump-box`) or a previous proxy
  session, subsequent `ssh` commands reuse the live UNIX domain socket without
  initiating a new TCP connection.
- **Rule**: When diagnosing connectivity, always bypass OpenSSH connection reuse:
  ```sh
  ssh -o ControlMaster=no -o ControlPath=none -o ProxyJump=none root@<SERVER_IP>
  ```

### 2.3 The TProxy Local Interception Trap

- **The Illusion**: Running a Python socket test or `curl` on the local machine
  shows `TCP connected in 0 ms`, but application data hangs and times out during
  TLS or banner exchange.
- **The Reality**: The local transparent proxy (`xray-tproxy`) intercepts all
  outbound TCP traffic via Netfilter `TPROXY` and policy routing table 110,
  completing the kernel TCP handshake locally with the `dokodemo-door` listener
  (`127.0.0.1:12345`). The timeout occurs only when Xray attempts to dial the
  remote server out-of-band using mark 2.
- **Rule**: To test raw destination reachability, temporarily test with a process
  marked for bypass, or stop the client proxy unit before testing raw sockets:
  ```sh
  sudo systemctl stop xray-tproxy.service
  ```

### 2.4 The Silent-Server Illusion

- **The Illusion**: The web server's error log and the daemon log contain nothing
  about the failed requests, so the fault must be in the request path *inside*
  the server (bad demultiplexer, wrong backend, broken certificate).
- **The Reality**: An empty log is *positive evidence* that the packets never
  arrived. A TLS terminator records every handshake it aborts, and the kernel
  counts every connection it refuses. Nothing logged plus no counter movement
  means the loss is upstream of the host.
- **Rule**: Treat "server logs are silent" as a measurement, not as an absence of
  evidence. Pair it with the counter check in
  [Step 4](#step-4-confirm-whether-the-packet-reached-the-server).

### 2.5 The Small-Sample Illusion

- **The Illusion**: Ten successful requests prove the path is healthy, so a later
  report of "the site does not open" is attributed to the browser or to the
  server.
- **The Reality**: The failure modes above are bursty: the same `(IP, 443)` pair
  measured `0/20`, then `12/50`, then `1/40` within one hour. A ten-request
  sample cannot distinguish a 0 % path from a 20 % path.
- **Rule**: Before declaring a path healthy, take at least 40 samples, and take
  the comparison sample (another port, another network) in the same minute, so
  the network's own drift cannot masquerade as a difference.

---

## 3. Step-by-Step Diagnostic Runbook

Execute these diagnostic steps in sequence to isolate the exact point of failure.

### Step 1: Isolate the Local Client Environment

Before testing remote connectivity, verify that the local host's datapath is
operating correctly:

```sh
# 1. Verify the client proxy unit status
sudo systemctl status xray-tproxy.service

# 2. Check if local interception ports are listening
ss -tlpn | grep -E ':(1080|12345|10085)'

# 3. Check for routing table 110 and policy rule
ip rule show | grep 'fwmark 0x1 lookup'
ip route show table 110
```

If the client service is failing, consult
[How to Troubleshoot Common Problems](troubleshoot-common-problems.md).

### Step 2: Raw Layer-4 TCP Port Sweep

Bypass all proxies and test multiple distinct TCP ports to distinguish a
single-port block from a full-IP blackhole.

Run this test script directly on the client machine:

```sh
python3 - << 'EOF'
import socket, time

SERVER_IP = "203.0.113.10"  # Replace with your server IP
PORTS = [22, 25, 80, 443, 993, 10443]

print(f"--- Testing TCP reachability to {SERVER_IP} ---")
for port in PORTS:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    start = time.time()
    try:
        s.connect((SERVER_IP, port))
        elapsed = (time.time() - start) * 1000
        print(f"Port {port:5d}: [OPEN] Connected in {elapsed:.1f} ms")
    except socket.timeout:
        print(f"Port {port:5d}: [BLOCKED] Handshake timed out (> 5.0s)")
    except ConnectionRefusedError:
        print(f"Port {port:5d}: [REJECT] Connection refused (host reachable, port closed)")
    except Exception as e:
        print(f"Port {port:5d}: [ERROR] {e}")
    finally:
        s.close()
EOF
```

**Interpretation**:
- **All ports time out**: Destination IP is experiencing full TCP blackholing
  by border routers.
- **Port 443 (or 10443) times out, but port 22 connects**: Single-port block.
  The server IP is intact; only the proxy listening port is blocked.
- **Port returns `Connection refused`**: The network path is clear, but the
  daemon is not listening on that port or the server-side firewall rejected it.

### Step 3: Multi-Vantage Global Probing

Determine whether the blockage is local to your domestic ISP or effective
nationwide across China, and verify if the server is healthy internationally.

#### A. International Reachability Check (From an Overseas Node or Jump Host)

From an overseas VPS or third-party probe node (e.g. `check-host.net` API):

```sh
# Test if the REALITY port answers with the genuine borrowed certificate
curl -Iv --tlsv1.3 --http2 --resolve <SERVER_NAME>:443:<SERVER_IP> https://<SERVER_NAME>/
```

- If this returns `HTTP/2 200 OK` with the target domain's legitimate certificate,
  the server daemon, firewall, and REALITY relay are functioning perfectly.

#### B. Domestic Multi-City Probing (From Mainland China)

Use distributed testing tools (e.g., the Globalping API) to check TCP
connectivity across China Telecom, China Unicom, and China Mobile:

```sh
# Submit a multi-probe TCP check across Chinese cities
curl -s -X POST https://api.globalping.io/v1/measurements \
  -H "Content-Type: application/json" \
  -d '{
    "type": "http",
    "target": "http://<SERVER_IP>",
    "locations": [{"country": "CN"}],
    "limit": 5,
    "measurementOptions": {
      "protocol": "HTTP",
      "port": 443,
      "request": {"method": "HEAD", "path": "/"}
    }
  }'
```

- **All Chinese nodes time out**: Nationwide GFW IP or port block.
- **Some provinces/ISPs connect while yours times out**: Regional routing fault
  or provincial edge firewall filtering.

---

### Step 4: Confirm Whether the Packet Reached the Server

This step decides between "the server is misconfigured" and "the network ate the
connection", and it needs numbers rather than logs alone.

```sh
# 1. Count your attempts, then count what the server logged.
fails=0; for i in $(seq 40); do
  curl -s -o /dev/null --max-time 6 https://<YOUR_HOST>/ || fails=$((fails+1))
done; echo "client failures: $fails/40"

ssh root@<SERVER_IP> 'wc -l < /var/log/nginx/stream.log'   # or the daemon access log
```

Interpretation, in order of what the numbers mean:

| Client result | Server-side evidence | Verdict |
| :--- | :--- | :--- |
| Some attempts fail | The log holds **fewer** connections than you attempted, and they all read `status=200` | The dropped attempts never arrived: on-path SYN loss |
| Some attempts fail | The log holds **every** attempt, with `status=400`/`502` | The demultiplexer or backend accepted and then failed: server-side |
| Everything fails | No connections logged at all | Full blackhole, or the port is closed upstream |

Confirm the kernel agrees — a SYN that arrives but is refused moves one of these,
and a SYN that never arrives moves none:

```sh
ssh root@<SERVER_IP> 'nstat -az | grep -E "ListenOverflows|ListenDrops|SyncookiesSent"'
# take the reading, repeat the client loop, read again, then diff
```

Then prove the loss is tied to the `(IP, port)` pair, not to the host or the
service, by putting an identical listener on a spare port and interleaving the
two loops **in the same minute**:

```sh
for i in $(seq 20); do
  curl -s  -o /dev/null --max-time 6 https://<YOUR_HOST>/                       ; echo "443  -> $?"
  curl -sk -o /dev/null --max-time 6 --resolve <YOUR_HOST>:8446:<SERVER_IP> \
       https://<YOUR_HOST>:8446/                                                ; echo "8446 -> $?"
done
```

- `443` fails while `8446` is clean → the access network is penalising `(IP, 443)`.
  Nothing on the server needs changing; wait out the window, and only consider a
  CDN in front if the loss persists (see
  [Strategy 4](#strategy-4-put-a-cdn-in-front-evaluated-deliberately-not-adopted)).
- Both fail in the same proportion → the path or the host is degraded, not the port.

---

## 4. Remediation and Recovery Strategies

When a block is confirmed, select the appropriate recovery path:

### Strategy 1: Migrate to Port 443 and a Clean Borrowed Domain

If only the high-numbered port (e.g. 10443) was blocked and port 22 is reachable:

1. Reconfigure the server inbound to `port: 443`.
2. Replace the borrowed target with a verified local CDN edge
   (see [REALITY Target Selection](../explanation/reality-target-selection.md)).
3. Verify that active probes to `https://<SERVER_NAME>/` return `HTTP/2 200 OK`
   rather than `403 Forbidden`.

### Strategy 2: Two-Hop Transit Relay (`dialerProxy`)

If the target server IP (`VPS-B`) is completely blocked from Mainland China, but
you operate a second, unblocked overseas server (`VPS-A`):

You can establish a chained tunnel where traffic from China connects to `VPS-A`,
which then relays the encrypted session to `VPS-B`:

```text
[ Client (China) ]
       │
       ▼ (VLESS + REALITY to Unblocked Node)
[ VPS-A: US Egress (e.g., 198.51.100.10:443) ]
       │
       ▼ (Chained dialerProxy relay)
[ VPS-B: Blocked Node (e.g., 203.0.113.10:443) ]
       │
       ▼
  [ Internet ]
```

In the client `outbounds` configuration:

```json
{
  "outbounds": [
    {
      "protocol": "vless",
      "tag": "proxy-exit",
      "settings": {
        "vnext": [
          {
            "address": "203.0.113.10",
            "port": 443,
            "users": [
              {
                "id": "<UUID_JP>",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "cdn.softbank.jp",
          "publicKey": "<PUBLIC_KEY_JP>",
          "shortId": "<SHORT_ID_JP>"
        },
        "sockopt": {
          "dialerProxy": "proxy-transit"
        }
      }
    },
    {
      "protocol": "vless",
      "tag": "proxy-transit",
      "settings": {
        "vnext": [
          {
            "address": "198.51.100.10",
            "port": 443,
            "users": [
              {
                "id": "<UUID_US>",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "download.nvidia.com",
          "publicKey": "<PUBLIC_KEY_US>",
          "shortId": "<SHORT_ID_US>"
        },
        "sockopt": {
          "mark": 2
        }
      }
    }
  ]
}
```

This immediately restores access using the Japanese exit node without waiting
for IP replacement, at the cost of additional transit latency.

### Strategy 3: Request an IP Address Replacement

If full-IP TCP blackholing is persistent:

1. Contact your VPS provider to allocate a new public IPv4 address.
2. Ensure that before routing production proxy traffic to the new IP:
   - Port 443 is selected from day one.
   - The borrowed target domain is verified locally ($\text{RTT} < 15\text{ms}$).
   - Linux kernel tuning (`BBR` + socket buffers) is applied.
3. Update `address` in `client.json` and deploy.

### Strategy 4: Put a CDN in Front (evaluated, deliberately not adopted)

The obvious escape from "nobody can reach `(my-ip, 443)`" is to move the *website*
behind Cloudflare and let the proxy keep the bare IP. It works, and it is the
right answer when the origin IP is durably unusable for a population you care
about. It is the *wrong* answer for the case in this guide, for these reasons:

| Cost | Detail |
| :--- | :--- |
| It does not protect the proxy | An Xray client still dials `(your-ip, 443)` directly, so the REALITY inbound stays as reachable — and as blockable — as before. Only the website moves. |
| Chinese latency | The free plan hands mainland visitors an edge outside the mainland; measure `%{time_connect}` before and after, because it can be slower than the direct path it replaces. |
| 100-second idle cut | Any origin response that stays idle for 100 s is closed. Server-sent-event endpoints must emit a keep-alive comment on the application side; nginx cannot inject one into an existing stream. |
| Certificate workflow | HTTP-01 renewals break as soon as a redirect rule sits in front of the challenge path, so issuance has to move to DNS-01. |
| Trust surface | The CDN terminates visitor TLS and sees request and response bodies in plaintext. |

Decision rule: a **transient** burst of SYN loss that clears within an hour does
not justify any of the above — confirm with
[Step 4](#step-4-confirm-whether-the-packet-reached-the-server), wait, and keep the
direct path. Deploy a CDN when access is *persistently* broken for real visitors,
or when the origin IP itself has to change.

Two hard rules if it is ever deployed:

- Keep one DNS-only (grey-cloud) name pointing at the origin. It is how you test
  the origin, and it is the only way in if the CDN's own addresses become
  unreachable from a given network.
- Never point the REALITY `serverName` at a CDN-proxied name of your own: probes
  would be answered by your site's identity instead of the borrowed third party's.

---

## Related Documentation

- [How to Deploy an Xray Proxy Server on a VPS](deploy-server.md)
- [How to Troubleshoot Common Problems](troubleshoot-common-problems.md)
- [REALITY Target Selection & Camouflage](../explanation/reality-target-selection.md)
