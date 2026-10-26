# Captive Portals

Public Wi-Fi hotspots require a web login before they open access. This
page explains why such networks conflict with transparent proxying in
general, and why this setup does not.

## How Portals Redirect Clients

Before authentication, the hotspot gateway runs a **walled garden**: it
blocks all traffic except DNS and its own login server. To send the client
to the login page, the gateway abuses one of two cleartext channels:

- **DNS spoofing** — every DNS answer points at the login server,
  regardless of the queried name;
- **HTTP interception** — the gateway answers any plain HTTP request with
  a `302` redirect to the login page.

HTTPS cannot be hijacked either way: certificate validation rejects the
forged response, and HSTS prevents bypassing it. Phones therefore probe a
known plain-HTTP URL after connecting (Apple's `hotspot-detect`,
Android's `generate_204`, Firefox's `detectportal.firefox.com`) and open
whatever the hijack returns. A newer standard, RFC 8908/8910, advertises
the login API directly in DHCP and removes the need for hijacking, but
deployment is still rare.

## Why TProxy Breaks The Flow

A naive TProxy setup intercepts the probe traffic before it leaves the
host. The gateway then never sees a naked HTTP request to hijack, and the
proxy tunnel itself cannot help: the walled garden blocks the proxy server
too, so the probe hangs. Two independent hijackers fight over the same
traffic, and the local one wins while being the one that cannot work
pre-auth.

## How This Setup Avoids The Conflict

Instead of unencrypted global bypasses in nftables, traffic interception and captive portal compatibility are handled via Xray's DNS and routing engine:

- **Dynamic Local Resolver for Probes**: Xray's DNS config maps portal probe domains (`captive.apple.com`, `connectivitycheck.gstatic.com`, `detectportal.firefox.com`, `msftconnecttest.com`, `msftncsi.com`) to `localhost` (`skipFallback: true`, not `finalQuery` — see [DNS](dns.md)). This queries `systemd-resolved`, which dynamically forwards queries to whatever DHCP DNS server was assigned by the current Wi-Fi network. In a walled garden, the local gateway immediately spoof-resolves the probe to the portal login IP. The nftables `output`/`prerouting` exemptions for the `xray` and `systemd-resolve` users keep this path alive; without them the localhost query is re-intercepted and the probes time out (see the DNS Loop Hazard section in [DNS](dns.md)).
- **Probe Domain Direct Routing**: Xray routes probe domains and `geosite:private` / `geoip:private` to the **`direct`** outbound. The probe rule must precede every proxy rule: those names also belong to `geosite:google` and `geosite:geolocation-!cn`, so a later position makes the rule dead and the probe answers through the tunnel.
- **Unauthenticated Flow**: Before Wi-Fi login, remote proxy servers are unreachable. When OS probes initiate HTTP requests, Xray routes them via `direct` out the local wireless interface. The Wi-Fi gateway sees the naked HTTP probe, hijacks it with a `302 Redirect`, and opens the portal login page.
- **Authenticated Protection**: Once logged in, regular HTTP (port 80) and HTTPS (port 443) traffic to overseas destinations travel securely through the proxy tunnel, preventing ISP HTTP hijacking and allowing access to blocked HTTP sites.

## Edge Case Limitation

A few commercial portals host their login page on a public HTTPS domain. Pre-authentication, the walled garden blocks all external IPs, including proxy servers. If automatic detection does not trigger on a specific network, stop the service temporarily for login and restart it afterwards:

```sh
sudo systemctl stop xray-tproxy.service
# complete Wi-Fi login in browser
sudo systemctl start xray-tproxy.service
```

The unit's `ExecStopPost` teardown restores plain networking completely and safely; see [Architecture](architecture.md#component-ownership).

