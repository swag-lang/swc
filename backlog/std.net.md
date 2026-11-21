# Network Backlog

This backlog covers `bin/std/modules/net`, measured against the networking libraries in the Go
standard library, .NET, Rust's standard library and de-facto crates, Python, and Zig.

Platform-specific operating-system bindings belong in [platform.portability.md](platform.portability.md).
Core cryptographic primitives remain in [std.core.md](std.core.md). [README.md](README.md) has the
whole layout.

## Entries

### std.net.001 — Blocking TCP needs portable address coverage

- Evidence: `net` provides blocking IPv4 and IPv6 TCP connections and listeners on Linux and
  Windows. Other host backends remain absent; name resolution belongs to std.net.003. Platform
  leaves are owned by platform.portability.088.
- Next: add the next host backend while retaining the portable endpoint contract and loopback
  and failure coverage without putting networking in the module every program links.
- Done when: the next host backend opens, listens for, accepts, reads, writes, and closes
  blocking TCP connections by portable address, with loopback tests for EOF, partial transfer,
  and connection failure.
- Related: std.net.003, std.net.004, std.net.005, std.net.006, std.net.007, std.net.008,
  std.net.002, platform.portability.088

### std.net.002 — Decide UDP broadcast and multicast support

- Evidence: `net` now sends and receives bounded UDP datagrams over portable IPv4 and IPv6
  endpoints on Linux and Windows. Broadcast and multicast are not part of the current API.
- Next: decide whether UDP broadcast and multicast belong in the portable datagram contract and
  document the platform behavior before adding either operation.
- Done when: the API either exposes tested broadcast and multicast operations on both hosts or
  explicitly documents why those operations are excluded.
- Related: std.net.001, std.net.003, std.net.004

### std.net.003 — DNS cancellation and resolution policy

- Evidence: `Dns.resolve` uses the platform resolver on Linux and Windows, preserves resolver
  ordering, supports address-family filters, resolves numeric ports and named services, and
  returns portable endpoints. Resolution is synchronous and cannot be cancelled; callers that
  need responsiveness must run it on a worker.
- Next: add an asynchronous resolver only with a cancellable platform contract; retain the
  synchronous API as the simple blocking option.
- Done when: tests cover resolver ordering, family filtering, named services, and failure, while
  the synchronous API documents that platform lookup blocks and cannot be cancelled.
- Related: std.net.001

### std.net.004 — No non-blocking socket readiness API

- Next: add non-blocking sockets and readiness notification after the concurrency decision in
  language.parallelism.001. Keep the readiness mechanism separate from the blocking socket
  foundation.
- Done when: non-blocking sockets expose a documented readiness and cancellation contract that
  serves multiple connections without busy waiting, with tests for readable, writable, closed,
  and failed peers.
- Related: std.net.001, language.parallelism.001, std.core.028

### std.net.005 — No TLS transport

- Next: provide client and server TLS over the socket contract. Decide explicitly whether each
  platform binds its native provider or the project owns a portable implementation.
- Done when: client and server TLS operate over the socket contract with certificate
  validation, handshake and shutdown failures, and stream ownership stated, with local-peer
  tests for accepted and rejected credentials.
- Related: std.net.001, std.core.010, std.core.015, std.core.016

### std.net.006 — HTTP client needs streaming and portable transports

- Evidence: `Net.Http.get` now streams response chunks on Linux and Windows and bounds the
  buffered body when no handler is supplied. Request-body streaming, active cancellation, strict
  deadlines, and a bounded redirect policy remain open. HTTPS still uses system certificate
  validation through each platform backend.
- Next: add streamed request bodies, then define redirect, cancellation, and deadline behavior
  across both backends.
- Done when: local-server tests cover streamed requests and responses, bounded redirects,
  cancellation, deadlines, and rejection of oversized or malformed headers.
- Related: std.net.001, std.net.005

### std.net.007 — HTTP server connection lifecycle and protocol coverage

- Evidence: `Http.Server` parses bounded HTTP/1.0 and HTTP/1.1 requests and writes fixed-length
  or chunked responses. Each connection handles one request and closes after one response;
  `Server.close` stops its listener without taking ownership of accepted connections.
- Next: add keep-alive only with a bounded request-count and timeout contract; blocking accept and
  reads otherwise remain uninterruptible.
- Done when: request framing, malformed framing, response streaming, one-request connection
  closure, and explicit listener closure have focused local-peer tests and documented behavior.
- Related: std.net.001, std.net.004, std.net.005, std.net.006

### std.net.008 — Secure WebSocket transport and interoperability

- Evidence: `WebSocket.connect` and `Http.ServerConnection.upgradeWebSocket` implement RFC 6455
  over plain TCP, including masking, fragmentation, control frames, size limits, UTF-8 validation,
  and the close handshake. TLS streams and secure `wss://` connections remain absent.
- Next: add verified TLS transport to the WebSocket client and server after std.net.005.
- Done when: secure client and server peers pass local tests for credential validation, masked
  and fragmented frames, control frames, limits, and close handshakes.
- Related: std.net.005, std.net.006, std.net.007
