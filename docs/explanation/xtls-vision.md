# XTLS-Vision Mechanism and Traffic Steer Design

This document details the inner workings of **XTLS-Vision** (`flow: xtls-rprx-vision`), how it defeats machine-learning traffic classifiers targeting TLS-in-TLS encapsulation, and why it achieves bare-metal throughput using Linux kernel zero-copy data paths.

---

## 1. The Threat: TLS-in-TLS Pattern Detection

When an application opens an encrypted HTTPS session through a TLS-based proxy tunnel (such as standard VLESS over TLS), two independent TLS layers exist:
1. **Inner TLS**: Between the client application (browser, curl) and the target website (e.g., `google.com`).
2. **Outer TLS**: Between the local proxy client and the remote proxy server.

```text
[Inner Application Data]
        |
        v  (Encrypted by browser with TLS 1.3)
[Inner TLS Record: 16-byte tag + ciphertext + header]
        |
        v  (Wrapped by proxy client)
[Outer TLS Record: Header + Inner TLS Record + MAC]
```

### Why Naive Encapsulation is Detected
Censors run Deep Packet Inspection (DPI) with machine learning classifiers trained on packet size distributions:
- **Handshake Determinism**: A `ClientHello` or `ServerHello` record has distinctive length characteristics. When wrapped verbatim inside an outer TLS record, the outer record size equals `InnerSize + Overhead`.
- **Timing and Sequence Correlation**: The outer session's record boundaries and packet inter-arrival times mirror an HTTPS handshake embedded inside another HTTPS connection. In genuine web browsing, nested TLS handshakes almost never occur on standard ports.

---

## 2. The XTLS-Vision Countermeasures

XTLS-Vision eliminates both the statistical fingerprint and the encryption overhead through a two-stage lifecycle:

```text
+-----------------------------------------------------------------------------+
| Stage 1: Handshake Obfuscation (Random Padding)                             |
| - Inspects client application handshake frames                              |
| - Injects random padding bytes to break record length correlation           |
| - Padding is negotiated and stripped transparently by proxy endpoints       |
+-------------------------------------+---------------------------------------+
                                      | Handshake completed & Inner TLS verified
                                      v
+-----------------------------------------------------------------------------+
| Stage 2: Kernel Direct Transfer (Linux splice zero-copy)                    |
| - Outer proxy TLS ceases re-encrypting the payload                          |
| - Linux splice() moves packets socket-to-socket in kernel ring buffers      |
| - Inner TLS flows natively; 0 double-encryption CPU overhead                |
+-----------------------------------------------------------------------------+
```

### Stage 1: Handshake Obfuscation (Vision Padding)
During the initial handshake:
1. The proxy client inspects the application's first few records.
2. If an inner TLS handshake (`ClientHello`) is detected, Vision injects **randomized padding blocks** before sending it across the outer tunnel.
3. The outer TLS record length becomes non-deterministic, completely breaking the length signature that ML classifiers match against.
4. The remote Xray server reads the Vision control header, strips the padding, and forwards the genuine `ClientHello` to the upstream destination.

### Stage 2: Kernel Splice Zero-Copy
Once the inner TLS handshake successfully completes:
1. The application's payload is *already* encrypted with end-to-end TLS 1.3 between the browser and the final destination.
2. Encrypting this data a second time in the outer proxy tunnel is both computationally wasteful and introduces protocol encapsulation artifacts.
3. XTLS-Vision transitions the connection to **Direct Mode**:
   - The outer TLS encryption context stops encrypting payload blocks.
   - On Linux systems, Xray invokes `splice(2)` to transfer data between the client socket and the tunnel socket entirely within kernel memory space.
   - **Zero User-Space Copying**: Data never moves back and forth between kernel buffers and user-space memory buffers.
   - **Wire Profile**: The wire traffic is indistinguishable from standard, single-layer TLS traffic flowing between a browser and a server.

---

## 3. Fallback for Non-TLS Traffic

What happens if an application connects to a plain HTTP or non-TLS TCP service through the tunnel?
- Vision inspects the payload signature.
- If the stream is **not** valid TLS, Vision automatically falls back to **Standard Proxy Encryption**:
  - The payload is encrypted by the outer proxy layer.
  - Plaintext data is never transmitted unencrypted across the network.

---

## 4. Fundamental Constraints: Why Vision Requires TCP

XTLS-Vision cannot operate over UDP, WebSocket, or gRPC transports:
1. **TCP Stream Semantics**: Vision relies on inspecting continuous byte streams to parse TLS record headers (`0x16 0x03 ...`).
2. **Splice Kernel Requirements**: The `splice()` system call operates on streaming file descriptors and socket pairs. It does not support datagram-oriented or framed application protocols (like WebSocket frame masking or gRPC HTTP/2 HEADERS/DATA framing).
3. **Transport Rule**: When using `flow: xtls-rprx-vision`, the underlying `streamSettings.network` must always be `tcp`.
