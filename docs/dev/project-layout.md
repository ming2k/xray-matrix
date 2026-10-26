# Project Layout

Repository tree map, physical asset boundaries, and file routing rules.

---

## 1. Two Fundamental Layers

The top level defines two decoupled layers, not two machine roles:

- **`schemes/`** — *What you run*. Everything that changes when the transport protocol changes. A scheme directory is completely self-contained: it carries the full Xray configuration for *both* ends (`client.json` and `server.json`) plus its own scheme documentation.
- **`host/`** — *Where it runs*. The operating system artifacts, partitioned by `client` (workstation/gateway) and `server` (VPS node) roles. nftables rulesets, systemd unit files, sysusers entries, sysctl kernel tuning, and fallback web configurations exist exactly once because they are identical across all schemes.

---

## 2. Tree Map

| Path | Purpose & Scope |
| :--- | :--- |
| **`schemes/<scheme>/client.json`** | Client Xray configuration template (TProxy datapath + scheme outbound). |
| **`schemes/<scheme>/server.json`** | Server Xray configuration template (scheme inbound + `freedom` / `blackhole`). |
| **`schemes/<scheme>/README.md`** | Transport mechanism, threat model, key generation, and operational limits. |
| **`schemes/<scheme>/*.local.json`** | Live deployment copy containing real secrets; git-ignored, never committed. |
| **`schemes/README.md`** | Transport scheme comparison matrix and selection guide. |
| **`host/client/README.md`** | Client TProxy datapath architecture and Xray configuration contract. |
| **`host/client/xray-tproxy.nft`** | nftables tables `xray_v4` and `xray_v6`; deployed to `/etc/nftables/`. |
| **`host/client/xray-tproxy.service`**| systemd unit for transparent proxying with fail-closed lifecycle. |
| **`host/client/xray-tproxy.sysusers.conf`** | Unprivileged service account allocation (`/usr/lib/sysusers.d/xray.conf`). |
| **`host/client/xray-policy.conf`** | networkd drop-in template; deployed under `/etc/systemd/network/<uplink>.network.d/`. |
| **`host/server/xray-server.service`** | Hardened, sandboxed systemd unit for the VPS proxy server. |
| **`host/server/xray-server.sysusers.conf`** | Server unprivileged service account definition. |
| **`host/server/99-xray-tuning.conf`** | Linux kernel TCP BBR tuning, TCP Fast Open, and 64MB buffer allocations. |
| **`host/server/xray-server.nft`** | Stateful ingress server firewall. |
| **`host/server/fallback/{nginx,caddy}/`** | Fallback web server configurations for the TLS scheme. |
| **`.githooks/pre-commit`** | Mechanical zero-leak commit guard. |
| **`.githooks/test-pre-commit.sh`** | Regression test cases for the pre-commit hook. |
| **`docs/tutorials/`** | Diátaxis Quadrant 1: Learning-oriented tutorials. |
| **`docs/how-to/`** | Diátaxis Quadrant 2: Task-oriented operator runbooks. |
| **`docs/reference/`** | Diátaxis Quadrant 3: Information-oriented technical specifications. |
| **`docs/explanation/`** | Diátaxis Quadrant 4: Understanding-oriented architectural deep dives. |
| **`docs/adr/`** | Authoritative Architectural Decision Records. |
| **`docs/dev/standards/`** | Engineering and governance standards (topology, invariants, taxonomy, style). |

---

## 3. Packaging Contracts

Two local `wright` package plans package the OS layer. Their copies must stay identical to repository copies:

| Plan | Contents |
| :--- | :--- |
| `xray` | Upstream binary only: `/usr/bin/xray` |
| `xray-tproxy` | The four `host/client/` files with `runtime_deps = ['xray', 'v2ray-rules-dat']`: unit, nftables config, sysusers config, and networkd drop-in template. |

---

## 4. Where New Files Go

- **New Documentation**: Categorize according to Diátaxis in `docs/` using [Taxonomy Standards](standards/taxonomy.md). Never create top-level directories in the repo root.
- **New Transport Scheme**: Create a directory under `schemes/<new-scheme>/` containing `client.json`, `server.json`, and `README.md`. Ensure shared datapath fields remain identical to sibling schemes (`[INV-SCHEME-ISOMORPHISM]`).
- **New Host Artifact**: Add under `host/client/` or `host/server/`. Never embed OS-specific scripts inside `schemes/`.
- **Architectural Boundary Decisions**: Record via an ADR under `docs/adr/` following the [ADR Standard](standards/adr.md).
- **Credentials & Local Configurations**: Always named `*.local.json` beside the template. Covered by `.gitignore` and enforced by `.githooks/pre-commit`.
