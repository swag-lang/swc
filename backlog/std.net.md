# Network Backlog

This backlog covers `bin/std/modules/net`, measured against the networking libraries in the Go
standard library, .NET, Rust's standard library and de-facto crates, Python, and Zig.

Platform-specific operating-system bindings belong in [platform.portability.md](platform.portability.md).
Core cryptographic primitives remain in [std.core.md](std.core.md). [README.md](README.md) has the
whole layout.

## Entries

### std.net.002 — Complete UDP broadcast and multicast host coverage

- Evidence: `DatagramSocket` enables IPv4 broadcast and joins or leaves IPv4/IPv6 multicast groups
  on Linux and Windows. IPv4 membership selects a local interface address; IPv6 membership selects
  an interface index. Runtime tests cover broadcast configuration and IPv4/IPv6 join/leave on Linux;
  Windows runtime coverage remains part of platform.portability.088.
- Next: run the multicast and broadcast tests on Windows, including IPv6 membership on a local
  interface selected by its Windows interface index.
- Done when: broadcast and IPv4/IPv6 membership behavior pass runtime tests on both supported hosts,
  including interface selection and invalid group handling.
- Related: std.net.003, std.net.004

### std.net.003 — DNS cancellation and resolution policy

- Evidence: `Dns.resolve` uses the platform resolver on Linux and Windows, preserves resolver
  ordering, supports address-family filters, resolves numeric ports and named services, and
  returns portable endpoints. Resolution is synchronous and cannot be cancelled; callers that
  need responsiveness must run it on a worker.
- Next: add an asynchronous resolver only with a cancellable platform contract; retain the
  synchronous API as the simple blocking option.
- Done when: tests cover resolver ordering, family filtering, named services, and failure, while
  the synchronous API documents that platform lookup blocks and cannot be cancelled.
- Related: platform.portability.088

### std.net.004 — No non-blocking socket readiness API

- Next: add non-blocking sockets and readiness notification after the concurrency decision in
  language.parallelism.001. Keep the readiness mechanism separate from the blocking socket
  foundation.
- Done when: non-blocking sockets expose a documented readiness and cancellation contract that
  serves multiple connections without busy waiting, with tests for readable, writable, closed,
  and failed peers.
- Related: language.parallelism.001, std.core.028, platform.portability.088

### std.net.005 — No TLS transport

- Next: provide client and server TLS over the socket contract. Decide explicitly whether each
  platform binds its native provider or the project owns a portable implementation.
- Done when: client and server TLS operate over the socket contract with certificate
  validation, handshake and shutdown failures, and stream ownership stated, with local-peer
  tests for accepted and rejected credentials.
- Related: std.core.010, std.core.015, std.core.016, platform.portability.088

### std.net.006 — HTTP client needs streaming and portable transports

- Evidence: `Net.Http.get` streams response chunks and `Net.Http.post` reads request chunks on
  Linux and Windows. Both bound the buffered response body when no handler is supplied and use
  platform certificate validation. Active cancellation, a bounded redirect policy, and identical
  end-to-end deadline semantics remain open.
- Next: define bounded redirect behavior, then align active cancellation and whole-transfer
  deadlines across both backends.
- Done when: local-server tests cover streamed requests and responses, bounded redirects,
  cancellation, deadlines, and rejection of oversized or malformed headers.
- Related: std.net.005, platform.portability.088

### std.net.008 — Secure WebSocket transport and interoperability

- Evidence: `WebSocket.connect` and `Http.ServerConnection.upgradeWebSocket` implement RFC 6455
  over plain TCP, including masking, fragmentation, control frames, size limits, UTF-8 validation,
  and the close handshake. TLS streams and secure `wss://` connections remain absent.
- Next: add verified TLS transport to the WebSocket client and server after std.net.005.
- Done when: secure client and server peers pass local tests for credential validation, masked
  and fragmented frames, control frames, limits, and close handshakes.
- Related: std.net.005, std.net.006
