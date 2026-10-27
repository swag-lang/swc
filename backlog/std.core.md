# Core Backlog

This backlog covers `std/core`, measured against the standard libraries it competes with:
the Go standard library, the .NET base class library, Rust's `std` plus its de-facto crates, the
Python standard library, and Zig's `std`.

Compiler work belongs in [compiler.core.md](compiler.core.md) and language work in
[language.design.md](language.design.md). This file keeps the evidence, investigations, and intended outcomes
owned by `bin/std/modules/core` together. [README.md](README.md) has the whole layout.


Read [design-swag-bin-modules](../.agents/skills/design-swag-bin-modules/SKILL.md) before
acting on any entry that proposes a boundary change. Several entries below deliberately argue for a
new module rather than growth inside `core`.

## Entries

### std.core.018 — Rebaseline and reduce Deflate match-search cost

- Evidence: match search dominates `Compress.Deflate` level 6 on filtered PNG data, which also
  sets the cost of `TagBin` and future containers. Level 6 walks up to 132 candidates per
  position for matches three to six bytes long, while level 1 compresses the same input about 4x
  faster for about 5% more bytes. The two untried levers are zlib's `nice_match` (stop the chain
  once a match is long enough, 128 at level 6) and tuning the lazy-match rule inherited from
  miniz. Both change which matches are chosen, so each must report compressed size beside time.
  Older timings predate a compiler spill fix, so they are not a baseline. Any remaining backend
  cause belongs in [compiler.optimization.md](compiler.optimization.md).
- Next: remeasure the current compiler and match finder on the same PNG and `.scc` corpus,
  then compare each search-policy change against that recorded baseline.
- Done when: level 6 on the PNG and `.scc` fixtures is at least 1.5x faster than that
  baseline with no more than 1% growth in compressed size, and every `core` compression test
  still round-trips.
- Related: std.core.021, std.core.022

### std.core.001 — Blocking TCP needs portable address coverage

- Evidence: `net` provides blocking TCP connections and listeners over IPv4 on Windows. IPv6,
  portable address handling and other host backends remain absent; name resolution belongs to
  std.core.003. Platform leaves are owned by platform.portability.088.
- Next: extend the address and transport contract to IPv6 and the next host backend, retaining
  loopback and failure coverage without putting networking in the module every program links.
- Done when: a separate net module opens, listens for, accepts, reads, writes, and closes
  blocking TCP connections by portable address, with loopback tests for EOF, partial transfer,
  and connection failure.
- Related: std.core.003, std.core.004, std.core.005, std.core.006, std.core.007, std.core.008,
  std.core.002, platform.portability.088

### std.core.004 — No non-blocking socket readiness API

- Next: add non-blocking sockets and readiness notification after the concurrency decision in
  language.parallelism.001. Keep the readiness mechanism separate from the blocking socket
  foundation.
- Done when: non-blocking sockets expose a documented readiness and cancellation contract that
  serves multiple connections without busy waiting, with tests for readable, writable, closed,
  and failed peers.
- Related: std.core.001, language.parallelism.001, std.core.028

### std.core.013 — No BLAKE2s implementation

- Evidence: `Hash.Blake2b` already implements incremental and one-shot keyed and unkeyed
  hashing, with variable digest lengths and tests in `src/tests/crypto/blake2b.test.swg`. There
  is no BLAKE2s.
- Next: add BLAKE2s with the same operation family and published vectors; BLAKE3 remains
  independent.
- Done when: BLAKE2s supports incremental and one-shot keyed and unkeyed hashing with variable
  digest lengths, and published vectors match across chunk boundaries and invalid parameters.
- Related: std.core.014

### std.core.002 — No UDP sockets

- Next: add datagram sockets, endpoints, size/error behavior, and broadcast/multicast decisions
  independently of TCP connection semantics.
- Done when: UDP sockets send and receive complete datagrams with portable endpoints, report
  size and truncation behavior explicitly, and pass loopback and error tests; broadcast and
  multicast support are decided and documented.
- Related: std.core.001, std.core.003, std.core.004

### std.core.003 — No DNS resolver

- Next: add host/service resolution to the `net` module over the platform resolver, with
  explicit address ordering, cancellation, and failure semantics.
- Done when: the net module resolves host and service names to portable addresses with
  documented ordering, cancellation, and failure behavior, tested against local and invalid
  names.
- Related: std.core.001

### std.core.005 — No TLS transport

- Next: provide client and server TLS over the socket contract. Decide explicitly whether each
  platform binds its native provider or the project owns a portable implementation.
- Done when: client and server TLS operate over the socket contract with certificate
  validation, handshake and shutdown failures, and stream ownership stated, with local-peer
  tests for accepted and rejected credentials.
- Related: std.core.001, std.core.010, std.core.015, std.core.016

### std.core.006 — HTTP client needs streaming and portable transports

- Evidence: `Net.Http.get` provides bounded synchronous HTTP/HTTPS GET on Windows through
  WinHTTP, with system certificate validation, phase timeout settings, explicit redirect responses and
  local-server tests. URL component encoding and a restricted HTTP URL parser are available.
  The host can enforce timeouts coarsely; streaming, active cancellation, strict deadlines and
  other host backends remain open.
- Next: add streaming request and response bodies, bounded redirect policy and cancellation,
  with a portable contract over std.core.001 and std.core.005 or an explicit backend decision.
- Done when: an HTTP/1.1 client streams requests and responses, follows bounded redirect
  policy, cancels active transfers, and rejects oversized or malformed headers in local-server
  tests.
- Related: std.core.001, std.core.005

### std.core.007 — No HTTP server

- Next: implement HTTP/1.1 server parsing, response streaming, connection lifetime, and limits
  independently of the client API.
- Done when: an HTTP/1.1 server parses bounded requests and streams responses over multiple
  connection lifetimes, with tests for malformed framing, cancellation, and graceful shutdown.
- Related: std.core.001, std.core.004, std.core.005, std.core.006

### std.core.008 — No WebSocket protocol

- Next: add WebSocket handshake and frame processing above HTTP without making it part of the
  HTTP client's completion criteria.
- Done when: a WebSocket peer completes the HTTP upgrade and exchanges masked and fragmented
  frames, control frames, and close handshakes within declared size limits, with client and
  server tests.
- Related: std.core.006, std.core.007

### std.core.010 — No AES implementation

- Evidence: `core/src/crypto` has Adler-32, CRC-32, CRC-64, MD5, SHA-1, SHA-256, HMAC-SHA-256,
  PBKDF2, BLAKE2b, Argon2id, ChaCha20, Poly1305, ChaCha20-Poly1305, and several
  non-cryptographic hashes, but no block cipher.
- Next: add AES with hardware acceleration where available and constant-time fallback
  behavior, then add separately numbered modes only when their contracts are chosen.
- Done when: AES-128, AES-192, and AES-256 block operations match published vectors in
  hardware and fallback paths, the fallback has a documented constant-time contract, and cipher
  modes retain separate backlog IDs.
- Related: std.core.005, std.core.011, std.core.012, std.core.013, std.core.014, std.core.015,
  std.core.016, std.core.017

### std.core.011 — No SHA-512 family

- Next: implement SHA-384/SHA-512 and HMAC variants with standard vectors and streaming parity
  with the existing SHA-256 API.
- Done when: SHA-384 and SHA-512 digests and their HMAC variants match published vectors for
  one-shot and chunked input, including empty input and boundary block lengths.
- Related: std.core.010

### std.core.012 — No SHA-3 family

- Next: implement the SHA-3 digest family and SHAKE extendable-output functions as a distinct
  sponge-based API.
- Done when: the supported SHA-3 digest sizes and SHAKE output lengths match published vectors
  across one-shot and incremental input, including empty and multi-block messages.
- Related: std.core.010

### std.core.014 — No BLAKE3 implementation

- Next: add BLAKE3 hashing, keyed hashing, key derivation, and parallel tree processing as one
  algorithm contract.
- Done when: BLAKE3 unkeyed, keyed, and key-derivation modes match published vectors across
  chunk and tree boundaries, and parallel and serial processing return identical outputs.
- Related: std.core.013

### std.core.015 — No Ed25519 signatures

- Next: add key generation, signing, verification, strict input validation, and published
  vectors for Ed25519.
- Done when: key generation, signing, and verification match published vectors, while
  malformed encodings, wrong messages, and invalid keys are rejected with an explicit failure
  contract.
- Related: std.core.005, std.core.016

### std.core.016 — No X25519 key agreement

- Next: add X25519 key generation and shared-secret derivation with low-order input handling
  stated and tested.
- Done when: key generation and shared-secret derivation match published vectors for both
  peers, and low-order or invalid inputs follow the documented rejection policy.
- Related: std.core.005, std.core.015

### std.core.017 — No RSA interoperability

- Next: provide only the RSA operations and padding schemes justified by external
  interoperability, with unsafe legacy modes excluded from the default surface.
- Done when: a named interoperability case fixes the required RSA operations and safe padding
  schemes; accepted cases pass external vectors and unsafe legacy forms are rejected, or the
  entry is retired with a recorded decision that no use case justifies it.
- Related: std.core.005

### std.core.021 — No gzip container support

- Next: add the gzip container over the existing deflate/inflate and zlib support, including
  headers, trailers, checksums, and concatenated members.
- Done when: gzip reading and writing validate headers, trailers, checksums, and concatenated
  members over existing Deflate, with round-trip, truncation, and corruption tests.
- Related: std.core.022, std.core.023

### std.core.023 — No TAR container support

- Next: add streaming TAR reading and writing, with the supported metadata and extension
  variants stated.
- Done when: a streaming TAR reader and writer round-trip regular files, directories, and the
  declared metadata and extension variants, while malformed sizes and unsafe paths fail under
  explicit limits.
- Related: std.core.021

### std.core.024 — Time zones

- Evidence: `time` handles UTC and local. There is no IANA zone database, no historical
  offsets, and no DST rules for an arbitrary zone, so any application that schedules or displays
  times across regions is stuck at the boundary.
- Next: choose the zone-data source (platform database or embedded tzdata) and add a zone type
  that converts UTC to and from civil time for a named zone.
- Done when: a named IANA zone converts UTC and local civil times using historical offsets and
  daylight-saving rules, and tests cover transitions, ambiguous times, missing times, and
  unknown zones.

### std.core.019 — Unambiguous regular-expression captures replay the search

- Evidence: `src/text/regexp` finds the matching span with its automata, then uses the
  iterative backtracking engine for short-span capture recovery, with the Pike VM handling
  longer spans or exhausted backtracking budgets. Capture extraction therefore walks the
  pattern a second time.
- Next: identify patterns whose capture transitions are unambiguous and prototype capture
  extraction during one forward pass. Keep the bounded fallback for patterns outside that subset.
- Done when: the capture corpus returns identical groups and spans, ambiguous patterns retain
  the existing fallback, and interleaved measurements show the cost of the second walk removed.
- Related: std.core.020, std.core.030

### std.core.032 — The recovered inflate rewrite fails a real-document golden

- Evidence: the rewrite, with a refill of its own for the careful path's length/distance group,
  is preserved in commit `643900899`; `bin/std` keeps master's inflate. The rewrite decoded the
  native InDesign fixture `publicdomain.indd` (removed from Swag Scope with its viewer; still in the
  history of `bin/apps/modules/swagscope/src/tests/datas/`) to an image the golden rejected, and the
  mismatch has not been attributed to specific decoded bytes. No synthetic Deflate stream from the
  repository's own compressor reaches the careful path with a drained bit buffer, so that file is
  what exercises the real shape.
- Next: decode the document's streams with both decoders and compare the output, rather than
  rendered images, so the divergence is a byte offset instead of a pixel. Only then decide
  whether the rewrite is repairable, and measure what it buys over master's inflate.
- Done when: the rewrite decodes every stream byte-for-byte as master's inflate does, a `core`
  test fails without the careful path's refill, and a measurement says what the rewrite buys;
  or the rewrite is abandoned and this entry deleted.

### std.core.022 — No reusable ZIP reader and writer


- Evidence: Core exposes no ZIP container API. Swag Scope already owns a bounded reader in
  `bin/apps/modules/swagscope/src/viewers/archive/zip.swg`, including ZIP64 directory metadata, stored/Deflate
  extraction, CRC checks, and a 250,000-entry limit.
- Next: review and extract that reader into a reusable container boundary, migrate Scope to it,
  and add the missing writer with explicit supported formats and resource limits.
- Done when: owning round-trip and malformed-container tests cover the shared reader/writer
  and Scope uses that contract without a private ZIP parser.

- Related: std.core.021

### std.core.031 — Two atomic families, one of them Core's

- Evidence: `Core.Atomic` (`thread/atomic.swg`) is a namespace of `#[Swag.Inline]` wrappers
  over the `Swag.atom*` intrinsics, with about 220 uses in 26 files under `bin/`.
  `Swag.AtomicValue'T` (`bin/runtime/atomic.swg`) owns atomic storage and exposes the same
  operations as methods. The concurrency contract says one owner for each concurrency type
  family; there are two, and the runtime one is named `AtomicValue` because `Atomic` is already
  taken by the Core namespace in every file that writes `using Threading`.
- Next: decide which one the language keeps. Storage that only its own operations reach is the
  stronger contract, since it makes "no ordinary access beside an atomic one" checkable, so the
  likely answer is the runtime type, with `Core.Atomic` migrating to it and the runtime type
  taking the name `Atomic` once the namespace is gone. Count the call sites that atomically
  access a field of a larger structure, because those need the field itself to become an
  `AtomicValue` rather than a wrapper call on its address.
- Done when: one atomic family remains, its name is not a workaround, and no consumer reaches
  atomic storage through an ordinary pointer.
- Related: language.parallelism.001, language.parallelism.005

### std.core.025 — A dependency graph of tasks is written by hand

- Evidence: the runtime joins a group whose children can fail (the first error asks the others to
  stop), and waits for all or any of several typed tasks (`Swag.whenAll`, `Swag.whenAny`);
  H.264 reconstruction bands use such a group. What remains hand-made is a dependency between
  tasks: HEVC wavefront rows each wait for the row above to be two coding tree blocks ahead,
  through an array of `Sync.Event`s, a progress array and a shared failure flag. Nothing bounds
  how many children a group runs at once either.
- Next: decide whether a row that waits on its neighbour's progress is a task-graph edge, with
  cycle rejection, or a progress counter a task can wait on without occupying its worker; settle
  it against the dependency-graph workload in language.parallelism.001.
- Done when: HEVC wavefront decoding has no hand-made event array or failure flag, and its
  speed is measured against what it does today.
- Related: language.parallelism.002, language.parallelism.011, std.core.028

### std.core.028 — No asynchronous I/O contract

- Evidence: there is no shared asynchronous I/O contract for completion, cancellation, borrowed
  buffers, or scheduler integration.
- Next: implement awaitable I/O against language.parallelism.002's completion and task-lifetime rules,
  using runtime-owned operation, completion, and cancellation types. Keep the common operation
  contract independent of its first socket or file backend. Model
  immediate completion, failed registration, cancellation racing completion, partial transfer,
  late callbacks, and shutdown. A stop request or expired deadline is not native completion.
- Done when: a fake backend and one real backend demonstrate exactly one terminal completion
  and retain buffers, request records, and callbacks until the backend is finished with them;
  owning I/O consumers use the common runtime without private task or cancellation machinery.
- Related: language.parallelism.002, std.core.025, std.core.004

### std.core.030 — Compiling a regular expression makes many separate allocations

- Evidence: after byte-set accounting and lazy automaton construction, the remaining cost of
  compiling a small pattern is suspected to be allocation count, but it has not been isolated
  from parsing and program construction in a current profile.
- Next: count allocations and bytes per compiled pattern, then test whether co-locating the
  immutable program data improves compilation without retaining unused automata or excess memory.
- Done when: that attribution is reproducible and the allocation design is either improved
  with equal matching behavior or retained for a measured reason.
- Related: std.core.019

### std.core.020 — Unicode scripts and most derived properties are missing

- Intent: `\p{...}` should name the scripts and the common derived properties, not only the
  handful of general categories the Unicode tables in `core` happen to carry.
- Where it stands: `\p{L}`, `\p{Ll}`, `\p{Lu}`, `\p{Lt}`, `\p{N}`, `\p{Nd}`, `\p{S}`,
  `\p{Sm}` and `\p{Z}` work, negated by `\P`. `\p{Greek}`, `\p{Han}`, `\p{Alphabetic}` and
  the rest fail to compile; `White_Space` is already supported. The engine itself needs nothing new: a property is a set of scalar
  intervals, and the compiler already turns any such set into a UTF-8 automaton.
- Next: the interval tables. `Unicode` ships general-category tables ported from Go;
  scripts would be another table of the same shape, generated the same way, and the property
  lookup in `RuneClass.unicodeProperty` is one more `switch` arm per table.
- Done when: the script names of UAX #24 resolve, a test matches text in two scripts, and the
  tables are generated rather than hand-written.
- Related: std.core.019
### std.core.036 — Move the regex program and syntax nodes to tagged unions after measuring

- Evidence: `Regex.Inst` ([program.swg](../bin/std/modules/core/src/text/regexp/program.swg))
  shares `next` across kinds and keeps `lo`, `hi`, `assertion`, `alt` and `slot` meaningful for one
  kind each; `Regex.Node` and `Regex.Prefilter` are wide structs commented form by form. They sit
  on the hot paths of every regex engine.
- Next: prototype `Inst` as `next` beside a union tagged by `InstKind`, compare the generated
  loops of the regex benchmark tasks, and migrate only if layout and loops do not regress.
- Done when: the regex types state their forms as tagged unions without a benchmark regression,
  or the measurement rejects the change and this entry is removed.
- Related: language.design.002.

---
