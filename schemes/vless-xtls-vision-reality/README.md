# Scheme: VLESS + TCP + XTLS-Vision + REALITY

The zero-domain scheme. Instead of presenting a certificate of its own, the
server borrows the TLS identity of a real, high-reputation website and
forwards anyone who fails authentication to that same real website — so an
active probe gets genuine Apple or Google TLS, not a refusal.

- **Needs**: a VPS with a free port 443. No domain, no certificate, no web
  server, no renewal.
- **If port 443 is already taken** by a website on the same host, this scheme
  still applies but the port is owned by nginx as a layer-4 SNI demultiplexer and
  the REALITY inbound moves to `127.0.0.1:10443`; follow
  [How to Share Port 443 with an Existing Website](../../docs/how-to/share-port-443-with-a-website.md).
  Note that `sockopt.acceptProxyProtocol` must stay off on a REALITY inbound — it
  cannot parse the header and every handshake fails if it is enabled.
- **Config**: [`client.json`](client.json) and [`server.json`](server.json)
  are complete and deployable; see [Key Generation](#5-key-generation) and
  [Configuration Files](#6-configuration-files).

---

## 1. The Certificate Paradox

Two conventional options are both weak:

- **A self-signed certificate** cannot be flagged by decryption — the censor
  cannot read it either — but it is trivially flagged by *inspection*: no
  public root CA signed it, so a scanner sees a certificate that no real site
  would present.
- **A certificate for your own domain** requires buying the domain, running
  DNS, and renewing the certificate, and it makes the domain itself the
  target: SNI filtering, DNS poisoning, and domain blacklisting all become
  available to the censor.

REALITY removes the choice: the server holds **no certificate at all** and
borrows the identity of an existing third-party site. There is no private key
to steal and nothing to renew.

## 2. Mechanism: The Session ID Channel

### 2.1 ClientHello construction

In TLS 1.3 the `Session ID` field is legacy data retained for middlebox
compatibility (RFC 8446 §4.1.2) and is normally 32 random bytes. REALITY
repurposes it as a covert authentication channel:

1. The client generates a fresh Curve25519 key pair for the session.
2. It packs its ephemeral public key and an HMAC authentication tag into the
   32 bytes of `Session ID`. The HMAC is derived from the server's `publicKey`
   and the agreed `shortId`.
3. The `ClientHello` carries the **borrowed** site's SNI (say
   `gateway.icloud.com`), so the visible handshake matches the site being
   imitated.

Because the key pair is ephemeral, the scheme has perfect forward secrecy:
knowing the server's public key does not expose past sessions.

### 2.2 Server verification and the two branches

On receiving a `ClientHello`, the server reads the `Session ID`, performs ECDH
with its X25519 `privateKey`, and recomputes the expected tag.

**Authenticated — the client.** The tag matches. The server synthesises a
`ServerHello` that mimics the target site's cipher suites, extensions and
certificate parameters, completes the handshake, and the connection becomes a
VLESS tunnel.

**Unauthenticated — a probe.** The tag does not match, and the server does the
opposite of what a detector expects: it neither closes the connection nor
returns an error. It opens a TCP connection to the configured `dest` and
relays the prober's raw bytes both ways.

The outcome is that a scanner finishes a cryptographically valid TLS 1.3
handshake with the real site, receives a certificate genuinely signed by that
site's CA, and classifies the host as a CDN edge or reverse proxy. There is no
response that distinguishes this server from the site it imitates, because for
an unauthenticated client it *is* a relay to that site.

> The comparison against the TLS-fallback scheme's behavior for each probe
> type is in [Transport Schemes](../README.md#3-how-each-defense-answers-a-probe).

## 3. Mechanism: XTLS-Vision

Vision is shared with the TLS-fallback scheme, so its full mechanism — the
TLS-in-TLS length signature it destroys, the randomized padding of the
handshake stage, and the kernel `splice()` transfer of the data stage — lives
in the explanation section: [XTLS-Vision Mechanism](../../docs/explanation/xtls-vision.md).

What it means for this scheme: the traffic inside the REALITY tunnel no longer
shows the deterministic record-size correlation that machine-learning DPI
uses to spot a nested TLS handshake, and the data stage adds no second
encryption. It also constrains the transport: Vision requires
`streamSettings.network: tcp`, which is why this scheme is `VLESS + TCP`.

## 4. Operational Limits

1. **`dest` must be a plausible neighbour.** The imitated site should support
   TLS 1.3 and HTTP/2, be geographically near the server's datacentre, and
   return valid OCSP responses. A `dest` whose edge is far away, or which
   fails ALPN negotiation, is visible in the handshake.
2. **SNI-to-IP mismatch.** Corporate DPI may check whether the IP belongs to
   the ASN that owns the SNI. An Apple name on a generic VPS IP is an anomaly
   for such a firewall. If that is your environment, use
   [VLESS + Vision + TLS](../vless-xtls-vision-tls/README.md) with a domain
   you own instead; that is the one case where REALITY is the wrong choice.
3. **No certificate rotation to hide behind.** Borrowing an identity means the
   server's observable behaviour is tied to the borrowed site's; if that site
   changes its TLS profile, `dest` should be revisited.

## 5. Key Generation

Run on either machine, with `xray` installed:

```sh
xray x25519        # -> PrivateKey (server) + Password/PublicKey (client)
xray uuid          # -> the client UUID, used on both ends
openssl rand -hex 8  # -> one shortId (8 hex bytes); the server takes a list
```

The server holds the private key and a list of accepted `shortIds`; the client
holds the public key and one `shortId`. The UUID appears in both configs — copy
it, do not regenerate it per host.

## 6. Configuration Files

- `client.json` — the complete client config: TProxy datapath plus this
  scheme's outbound. Deploys to `/etc/xray/config.json` on the client host.
- `server.json` — the complete server config. Deploys to
  `/etc/xray/config.json` on the server host.

Both come from this one directory, so the values that must agree (`id`,
`serverName`, `shortIds`) have a single source. Copy a config to a sibling
`client.local.json` / `server.local.json`, fill in every `<PLACEHOLDER:...>`,
and validate with `xray run -test` before installing. That suffix is
git-ignored, so credentials never reach the repository.

## 7. Choosing `dest`

1. **Must support TLS 1.3 and HTTP/2** — verify with `curl -Iv https://<domain>`.
2. **Geographically near the server**, ideally served by a CDN with an edge in
   the server's region (RTT < 15ms).
3. **Clean OCSP stapling.**
4. **Traffic volume profile match** — choose domains naturally associated with
   bulk downloads (OS mirrors, package repositories, driver distribution).
5. Sites that are stable and appropriate for the server's region.

For in-depth selection criteria, traffic volume profiling, timing defense against active probes, and curated candidate lists across Japan, the United States, Singapore, and Hong Kong, see [REALITY Target Selection and Traffic Camouflage](../../docs/explanation/reality-target-selection.md).

Record the choice in the local copy: `dest` on the server and `serverName` on
the client must name the same site, or the handshake fails closed.
