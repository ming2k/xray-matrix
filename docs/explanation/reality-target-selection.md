# REALITY Target Selection and Traffic Camouflage

This document details the selection criteria, physical constraints, traffic volume profiling, and regional catalogs for choosing borrowed destination targets (`dest` and `serverNames`) in the **VLESS + REALITY** scheme.

---

## 1. Core Principles & Threat Model

In the REALITY transport scheme, the server holds no TLS certificate and registers no domain name. Instead, it impersonates a high-reputation, legitimate third-party website:

1. **Authenticated Users**: The client embeds ephemeral ECDH credentials inside the legacy TLS 1.3 `Session ID` field. The server intercepts the handshake, establishes the VLESS tunnel, and enables XTLS-Vision flow control.
2. **Unauthenticated Probes & Scanners**: The server acts as a transparent L4 relay, forwarding raw TCP bytes to the configured destination (`dest`). The prober completes an authentic TLS 1.3 handshake directly with the genuine third-party site, receiving a valid CA-signed certificate.

```text
Incoming Connection (Port 443)
           |
           v
  [ Xray REALITY Inbound ]
           |
     +-----+-----+
     |           |
 (Session ID   (Unauthenticated
  Validated)    Probe/Scanner)
     |           |
     v           v
 [ VLESS +     [ Transparent TCP Relay ]
   Vision ]              |
     |                   v
 [ Internet ]      [ Remote Target (dest:443) ]
                         |
                   Genuine TLS 1.3 Handshake & Cert
```

If the target domain is chosen carelessly, the disguise fails at the network perimeter before probe deflection can even occur.

### 1.1 Visibility Model: What REALITY Hides and What It Cannot

REALITY hides the *identity* of the service, not the *existence* of the endpoint.
The distinction decides which countermeasures are worth anything.

| Observable | Visible to the censor? | What REALITY can do about it |
| :--- | :--- | :--- |
| Destination IP, port, packet sizes, timings | **Always.** Every IP header carries the address; no protocol can hide it | Nothing. Rotating addresses is the only mitigation |
| SNI in the `ClientHello` | **Yes**, in plaintext (no ECH) | Present a third party's name, so a name-based block costs collateral damage |
| Certificate and handshake bytes | Yes, to a prober | Relay to the real site: the prober gets the genuine certificate chain |
| Inner destinations (which sites the user visits) | **No** — inside the tunnel | The core privacy guarantee of any tunnel |
| DNS lookups of the borrowed name | **No lookup happens**: the client dials the IP directly | — |
| Flow shape (duration, volume, packet cadence) | **Yes**, statistically | Only camouflage by choosing a target whose normal traffic looks like a tunnel |

Consequences, in order of importance:

1. **Blocking by IP is the default lever, and REALITY does not stop it.** A borrowed
   SNI only removes *targeted* blocking on cheap discriminators (SNI blacklist,
   certificate inspection, protocol fingerprint). It does not make the IP less
   blockable; it raises the *cost* of the cheapest alternative.
2. **The real shield is collateral damage, not concealment.** The borrowed name
   works because blocking it would break legitimate traffic to a large third party.
   That is why a high-traffic CDN name is chosen over a low-traffic one — and why
   borrowing a neighbour's small site provides no protection at all.
3. **Being *identified* and being *blocked* are different failures.** Detection
   works on flow shape plus consistency checks (for example: does this address
   belong to the ASN the SNI claims?). REALITY does not defeat detection of the
   endpoint; it defeats detection of the *protocol*.
4. **Expect the address to be burned eventually.** A deployment that cannot
   cheaply change addresses is one bad week away from being unusable, regardless
   of how good the camouflage is.

---

## 2. The Four Mandatory Technical Constraints

Every candidate domain must meet four non-negotiable criteria:

1. **Dual Reachability**: The target must be accessible without blocking or DNS poisoning from inside Mainland China, and simultaneously accessible from your foreign VPS. If a domain is already flagged on the GFW SNI blacklist (e.g., `google.com`, `twitter.com`), border gateways issue immediate **TCP RST** packets upon seeing the plaintext SNI in `ClientHello`.
2. **Native TLS 1.3 & HTTP/2 Support**: REALITY and XTLS-Vision require TLS 1.3 cipher suites and ALPN (`h2`, `http/1.1`). Targets restricted to TLS 1.2 will fail handshake synthesis.
3. **Clean, Non-Redirecting Port 443**: Avoid bare domains that unconditionally return `301 Moved Permanently` or `302 Found` to redirect visitors to `www.` subdomains. Such redirects introduce extra round-trips and irregular probe responses.
4. **No Hostile WAF or Datacenter IP Blocking**: Avoid websites using aggressive bot detection (e.g., Cloudflare Under-Attack Mode or Turnstile challenges against datacenter ASNs). If the target rejects connections from your VPS IP with `403 Forbidden`, the deflection probe reveals an anomaly.

---

## 3. Physics & Side-Channel Defense: RTT Timing Constraints

Active probing engines employ timing analysis to detect proxy relays. 

When a probe initiates a connection, it measures two intervals:
- **$T_{\text{TCP}}$**: Time to complete the TCP 3-way handshake with the VPS.
- **$T_{\text{TLS}}$**: Time from sending `ClientHello` to receiving `ServerHello`.

$$\Delta T = T_{\text{TLS}} - T_{\text{TCP}} \approx \text{RTT}_{\text{VPS}\leftrightarrow\text{Target}} + \text{Processing Time}$$

```text
Probe ──(TCP: 30ms)──> Tokyo VPS ──(Relay RTT: 160ms)──> New York Target
[ Probe receives ServerHello after 190ms: anomaly detected (cross-ocean delay) ]

Probe ──(TCP: 30ms)──> Tokyo VPS ──(Relay RTT: 2ms)────> Tokyo Local Target
[ Probe receives ServerHello after 32ms: authentic local server behavior ]
```

- **The Cross-Continent Failure**: If your VPS is in Tokyo but your `dest` points to a server in Ashburn, Virginia, $\Delta T$ spikes by ~160ms. A domestic probe expects a Japanese web server to answer within local latency bounds. An unexplained multi-hundred-millisecond delay reveals that the host is proxying the TLS handshake across the globe.
- **The Proximity Rule**: The target server **must be geographically and topologically adjacent to the VPS**. Target an RTT between VPS and `dest` of **< 15ms** (ideally < 5ms within the same metropolitan exchange or datacenter ASN).

---

## 4. Flow Profiling: Why Targets Must Match High-Volume Traffic

Deep Packet Inspection systems use NetFlow/IPFIX flow collectors to profile network behavior over time:

- **The Behavioral Mismatch**: If you choose a weather API endpoint (`api.weather.example`), municipal notice board, or static blog as your target, normal traffic consists of intermittent, sub-second connections exchanging a few tens of kilobytes. Streaming 40 GB of 4K video over a single 3-hour TCP session to that SNI produces a glaring statistical anomaly in machine-learning flow classifiers.
- **The Bulk-Data Disguise**: Targets should naturally host **large-volume, continuous data streams**:
  - Operating system distribution mirrors (ISO images, package archives).
  - Developer package registries and runtime installers.
  - Large hardware vendor driver and firmware update repositories.
  - High-traffic static content delivery networks (CDNs) and media asset edges.

When high-throughput proxy tunnels carry large downloads over these domains, the session duration and packet MTU distribution match the expected business profile of the target.

---

## 5. Curated Regional Target Catalogs

All domains below have been verified for **TLS 1.3**, **HTTP/2**, clean non-redirecting HTTPS behavior, and natural compatibility with bulk data transfer.

### 5.1 Japan (Tokyo & Osaka)

Japan hosts dense interconnection hubs (BBIX, JPNAP) and major Asian CDN edge nodes.

| Domain (`serverNames`) | Destination (`dest:443`) | Category | Operational Profile |
| :--- | :--- | :--- | :--- |
| `ftp.jaist.ac.jp` | `ftp.jaist.ac.jp:443` | OS & Software Mirror | JAIST official mirror. High bandwidth, bulk Linux ISO downloads. |
| `s.yimg.jp` | `s.yimg.jp:443` | CDN Static Network | Yahoo Japan CDN. Massive nationwide media throughput. |
| `cdn.softbank.jp` | `cdn.softbank.jp:443` | Telecom CDN | SoftBank official CDN edge. Outstanding domestic routing to China. |
| `swdist.apple.com` | `swdist.apple.com:443` | OS Update Distribution | Apple software updates. Low RTT via local Tokyo Akamai edge. |
| `www.sony.jp` | `www.sony.jp:443` | Enterprise / Tech | Sony Japan portal. Native TLS 1.3 with X25519-MLKEM hybrid. |
| `www.nintendo.co.jp` | `www.nintendo.co.jp:443` | Gaming / Media | Nintendo corporate and update edge. |

### 5.2 United States

#### A. US West (Silicon Valley, San Jose, Los Angeles, Seattle)
| Domain (`serverNames`) | Destination (`dest:443`) | Category | Operational Profile |
| :--- | :--- | :--- | :--- |
| `download.nvidia.com` | `download.nvidia.com:443` | Hardware Drivers | NVIDIA driver downloads. Regular multi-gigabyte continuous flows. |
| `releases.ubuntu.com` | `releases.ubuntu.com:443` | OS Distribution | Canonical Ubuntu release server. High-capacity ISO distribution. |
| `download.docker.com` | `download.docker.com:443` | Container Runtimes | Official Docker engine and repository distribution edge. |
| `dl.k8s.io` | `dl.k8s.io:443` | Developer Tooling | Kubernetes binary release repository. |
| `static.rust-lang.org` | `static.rust-lang.org:443` | Language Toolchains | Rust toolchain and binary package archive. |
| `developer.apple.com` | `developer.apple.com:443` | Developer Distribution | Apple developer portal and SDK distribution infrastructure. |

#### B. US East & Central (Virginia / Ashburn, New York, Dallas, Chicago)
| Domain (`serverNames`) | Destination (`dest:443`) | Category | Operational Profile |
| :--- | :--- | :--- | :--- |
| `mirrors.kernel.org` | `mirrors.kernel.org:443` | Kernel / OS Archives | Linux Kernel Archive mirror network. Massive transfer capacity. |
| `repo.anaconda.com` | `repo.anaconda.com:443` | Data Science Repos | Anaconda distribution packages. High sustained multi-GB transfers. |
| `pypi.org` | `pypi.org:443` | Language Packages | Python Package Index repository edge. |
| `cdn.jsdelivr.net` | `cdn.jsdelivr.net:443` | Global Public CDN | High-throughput open-source CDN edge. |
| `media.steampowered.com` | `media.steampowered.com:443` | Gaming Assets | Valve Steam content and media distribution. |
| `speed.cloudflare.com` | `speed.cloudflare.com:443` | Network Benchmarking | Cloudflare speed test asset distribution. Designed for saturated throughput. |

### 5.3 Singapore

Singapore serves as the principal routing and cloud gateway for Southeast Asia.

| Domain (`serverNames`) | Destination (`dest:443`) | Category | Operational Profile |
| :--- | :--- | :--- | :--- |
| `mirror.sg.gs` | `mirror.sg.gs:443` | Regional OS Mirror | SG.GS open-source mirror node. Direct peering with SGIX. |
| `www.singtel.com` | `www.singtel.com:443` | Tier-1 Telecom Portal | Singtel primary portal. High trust score in international firewall rules. |
| `www.starhub.com` | `www.starhub.com:443` | Major ISP Edge | StarHub infrastructure portal. Local low-latency TLS 1.3 endpoint. |
| `www.ntu.edu.sg` | `www.ntu.edu.sg:443` | Academic Institution | Nanyang Technological University portal and research assets. |
| `shopee.sg` | `shopee.sg:443` | E-Commerce Platform | Shopee regional platform. Extremely high daily transaction volume. |

### 5.4 Hong Kong

Hong Kong connections have the lowest physical RTT to Mainland China (< 35ms). Handshake latency anomalies are scrutinized aggressively by edge firewalls. Targets must terminate in local HK datacenters.

| Domain (`serverNames`) | Destination (`dest:443`) | Category | Operational Profile |
| :--- | :--- | :--- | :--- |
| `mirror.xtom.com.hk` | `mirror.xtom.com.hk:443` | OS Mirror / Hosting | xTom Hong Kong local mirror. Directly peered at HKIX. |
| `images.hktvmall.com` | `images.hktvmall.com:443` | Retail Media CDN | HKTVmall high-volume image and media delivery network. |
| `tvb.com` | `tvb.com:443` | Broadcast Media | Television Broadcasts Limited (TVB) digital web endpoint. |
| `cdn.hk01.com` | `cdn.hk01.com:443` | News / Media CDN | HK01 digital media streaming and asset distribution network. |
| `www.hkix.net` | `www.hkix.net:443` | Internet Exchange | Hong Kong Internet eXchange official infrastructure portal. |
| `www.hku.hk` | `www.hku.hk:443` | Academic Institution | University of Hong Kong main web assets. |
| `hk.yahoo.com` | `hk.yahoo.com:443` | Regional Portal | Yahoo Hong Kong regional media and search portal. |

---

## 6. Target Verification & Neighbor Discovery

Public lists are susceptible to clustering if thousands of operators adopt identical targets from online guides. The most resilient REALITY configuration uses **locally discovered neighbor targets within your VPS provider's autonomous system (ASN)**.

### 6.1 Testing Candidate Domains (From VPS)

Run this verification pipeline on your server:

```sh
TARGET="download.nvidia.com"

# 1. Measure RTT (must be < 15ms, ideally < 5ms)
ping -c 4 "$TARGET" | tail -1 | awk -F '/' '{print "Average RTT: " $5 " ms"}'

# 2. Verify TLS 1.3 and HTTP/2 negotiation
curl -Iv --tlsv1.3 --http2 -s -m 5 "https://$TARGET" 2>&1 | \
  grep -E "(SSL connection using TLSv1.3|using HTTP/2|HTTP/2 [0-9]{3})"
```

**Passing Criteria**:
- Output displays `SSL connection using TLSv1.3`.
- Output confirms `using HTTP/2`.
- Status code is `200`, `204`, or a non-looping standard response (not `403 Forbidden` or a captcha block).
- Average RTT is within the acceptable local latency threshold.

### 6.2 Autonomous Neighbor Discovery (BGP / ASN Method)

1. Look up your VPS public IP address on [https://bgp.tools/](https://bgp.tools/).
2. Identify the **Origin ASN** and allocated prefix (e.g., `AS20473` for Vultr, `AS14061` for DigitalOcean).
3. Open the **DNS** tab and select **Show Forward DNS**.
4. Review the domains resolving to IPs in your adjacent subnet.
5. Filter for corporate sites, software mirrors, or CDN endpoints hosted in that exact facility.
6. Verify candidates using the script above.

Borrowing a verified neighbor target yields an **$\text{RTT} \le 1\text{ms}$** between your VPS and the destination, providing the highest possible defense against timing-based active probing.

### 6.3 When the ASN Has No Usable Neighbor (Measured)

The neighbor method assumes the provider's address space hosts somebody else's
real business. On a budget hosting ASN it does not, and the discovery has to be
run before it can be relied on. The scan below answered the question with data
for `AS25820` (IT7 Networks), the ASN of two deployments in this repository.

```sh
# 1. The ASN's announced prefixes (RIPEstat; bgpview was unreachable)
curl -s "https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS25820" |
  python3 -c 'import sys,json; print([p["prefix"] for p in json.load(sys.stdin)["data"]["prefixes"] if ":" not in p["prefix"]])'

# 2. Reverse-DNS sweep: every PTR is a candidate name, and PTR names expose the
#    provider's own naming scheme. Sampling the first /24 of each prefix keeps the
#    scan under a few thousand lookups.
python3 - <<'PY'
import socket, concurrent.futures, ipaddress
socket.setdefaulttimeout(1.0)
prefixes = ["192.69.92.0/22", "23.83.228.0/22", "104.245.96.0/21", "212.50.236.0/22"]
targets = []
for p in prefixes:
    net = ipaddress.ip_network(p)
    targets += [str(h) for h in ipaddress.ip_network(f"{net.network_address}/24", strict=False).hosts()]
def ptr(ip):
    try: return ip, socket.gethostbyaddr(ip)[0]
    except Exception: return ip, None
names = dict(n for n in (ptr(i) for i in targets) if n[1])
print("PTR found:", len(names))
for ip, n in sorted(names.items())[:5]: print(" ", ip, n)
PY
```

**Observed result** on the host in Fremont (`45.62.102.0/22`, 1016 PTRs) and on
3302 sampled addresses across 13 prefixes:

- every sampled PTR is `*.16clouds.com` — the provider's own host naming, not a
  business domain;
- the only real names in the local `/22` are other tenants' mail hosts and small
  personal sites (`mail.*`, `www3.*`, `fmt.*`, a few `*.cc`/`*.pub` domains);
- **zero** names that look like a CDN edge, software mirror, or distribution
  endpoint.

So on this ASN the trade-off is forced, and the choice is between two documented
positions rather than three:

| Option | SNI ↔ IP ↔ ASN consistency | Collateral damage if the SNI is blocked | Verdict |
| :--- | :--- | :--- | :--- |
| Big-CDN target (`download.docker.com`, AS16509) | Inconsistent: a censor mapping the IP to its ASN sees a hosting prefix claiming a CDN name | **High**: blocking the SNI hurts every Docker user, so it is rarely blocked by name | Default choice; the mismatch is inherent to REALITY everywhere |
| Another tenant's domain in the same ASN | Consistent (same facility) | **None**: a small personal site nobody would miss; and the tenant can move its DNS, silently breaking `dest` | Rejected: no protection, unstable, and it impersonates a real third party's live site |
| Your own domain served from the same IP | Fully consistent: DNS, PTR-adjacent ASN, certificate and a genuine website all agree | **None**: the name can be blocked with zero side effects | Legitimate option when the concern is "being identified as a proxy" rather than "being blocked" |

The methodology to keep: run the sweep before assuming a neighbor exists, and
treat "no candidate" as a normal outcome, not as a reason to borrow a weaker
target. Consistency is one signal among several; the demultiplexer deployment in
this repository reduces the others by answering unknown SNIs with the borrowed
site's own `handshake failure` instead of a local certificate.
