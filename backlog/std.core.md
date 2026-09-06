# Core Backlog

This backlog covers `std/core`, measured against the standard libraries it competes with:
the Go standard library, the .NET base class library, Rust's `std` plus its de-facto crates, the
Python standard library, and Zig's `std`.

Compiler work belongs in [compiler.core.md](compiler.core.md) and language work in
[language.design.md](language.design.md). This file keeps the evidence, investigations, and intended outcomes
owned by `bin/std/modules/core` together. [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

Read [design-swag-bin-modules](../.agents/skills/design-swag-bin-modules/SKILL.md) before
acting on any entry that proposes a boundary change. Several entries below deliberately argue for a
new module rather than growth inside `core`.

## Where the module already stands

- **Text** includes strings, a builder,
  formatting, parsing, a regular-expression engine, Unicode and Latin-1 tables, UTF-8 and UTF-16,
  correctly-rounded `atod`/`dtoa`, decimals, and tokenizing.
- **Math** has vectors, matrices, 2D geometry and transforms, curves, 128-bit integers, bit
  manipulation and angles.
- **Reflection** over structs, enums, attributes and arrays supports the `TagBin` serializer and
  reflected property editors.
- **Random** includes reproducible generators and procedural noise.
- Collections, filesystem, time, threading and the job system all cover their basics.

The remaining work includes networking, cryptography, compression, text, and concurrency.

---

## Tier A — Network stack

Start with the blocking transport contract; datagrams and higher-level protocols have separate
acceptance conditions below.

### std.core.001 — No blocking TCP sockets

- Problem: there are no TCP sockets. A Swag program cannot open even a blocking connection.
- Consequence: this rules out servers, clients, tooling that talks to a registry or an API, package
  management, telemetry, and every application whose value involves a network. It is the single
  largest capability gap in the language, larger than anything in the compiler.
- Put the blocking TCP and address foundation in a `net` module importing `core`; do not put a
  network stack in the module every program links. Platform leaves are owned by
  platform.portability.088.
- Related: std.core.003, std.core.004, std.core.005, std.core.006, std.core.007, std.core.008, std.core.002, platform.portability.088

### std.core.002 — No UDP sockets

Add datagram sockets, endpoints, size/error behavior, and broadcast/multicast decisions
independently of TCP connection semantics.

- Related: std.core.001, std.core.003, std.core.004

### std.core.003 — No DNS resolver

Add host/service resolution to the `net` module over the platform resolver, with explicit address
ordering, cancellation, and failure semantics.

- Related: std.core.001

### std.core.004 — No non-blocking socket readiness API

Add non-blocking sockets and readiness notification after the concurrency decision in language.parallelism.001. Keep
the readiness mechanism separate from the blocking socket foundation.

- Related: std.core.001, language.parallelism.001, std.core.028

### std.core.005 — No TLS transport

Provide client and server TLS over the socket contract. Decide explicitly whether each platform
binds its native provider or the project owns a portable implementation.

- Related: std.core.001, std.core.010, std.core.015, std.core.016

### std.core.006 — No HTTP client

Implement an HTTP/1.1 client over std.core.001 and std.core.005, with streaming bodies, redirects, cancellation,
and bounded parsing as its own public contract.

- Related: std.core.001, std.core.005

### std.core.007 — No HTTP server

Implement HTTP/1.1 server parsing, response streaming, connection lifetime, and limits independently
of the client API.

- Related: std.core.001, std.core.004, std.core.005, std.core.006

### std.core.008 — No WebSocket protocol

Add WebSocket handshake and frame processing above HTTP without making it part of the HTTP client's
completion criteria.

- Related: std.core.006, std.core.007

---

## Tier B — Cryptography

### std.core.009 — Independent Argon2 lanes run serially

- Intent: run independent lanes within each legal slice through `Jobs`, respecting Argon2's
  synchronization points and the configured `parallelism` contract.
- Complete when: multi-lane published vectors still agree, the requested lane count executes in
  parallel, and a benchmark separates the lane-parallel gain from the packed permutation work.
- Related: cpu.simd.018 in [cpu.simd.md](cpu.simd.md)

### std.core.010 — No AES implementation

- Present: Adler-32, CRC-32, CRC-64, MD5, SHA-1, SHA-256, HMAC-SHA-256, PBKDF2, ChaCha20, and
  several non-cryptographic hashes.
- Add AES with hardware acceleration where available and constant-time fallback behavior, then add
  separately numbered modes only when their contracts are chosen.
- Related: std.core.005, std.core.011, std.core.012, std.core.013, std.core.014, std.core.015, std.core.016, std.core.017

### std.core.011 — No SHA-512 family

Implement SHA-384/SHA-512 and HMAC variants with standard vectors and streaming parity with the
existing SHA-256 API.

- Related: std.core.010

### std.core.012 — No SHA-3 family

Implement the SHA-3 digest family and SHAKE extendable-output functions as a distinct sponge-based
API.

- Related: std.core.010

### std.core.013 — No BLAKE2s implementation

`Hash.Blake2b` already implements incremental and one-shot keyed and unkeyed hashing, with
variable digest lengths and tests in `src/tests/crypto/blake2b.test.swg`. Add BLAKE2s with the
same operation family and published vectors; BLAKE3 remains independent.

- Related: std.core.014

### std.core.014 — No BLAKE3 implementation

Add BLAKE3 hashing, keyed hashing, key derivation, and parallel tree processing as one algorithm
contract.

- Related: std.core.013

### std.core.015 — No Ed25519 signatures

Add key generation, signing, verification, strict input validation, and published vectors for
Ed25519.

- Related: std.core.005, std.core.016

### std.core.016 — No X25519 key agreement

Add X25519 key generation and shared-secret derivation with low-order input handling stated and
tested.

- Related: std.core.005, std.core.015

### std.core.017 — No RSA interoperability

Provide only the RSA operations and padding schemes justified by external interoperability, with
unsafe legacy modes excluded from the default surface.

- Related: std.core.005

---

## Tier B — Compression throughput

### std.core.018 — Deflate is still four-fifths match search

- Intent: close the rest of the gap between `Compress.Deflate` and the compressors it competes
  with. It is the whole cost of writing a PNG — 97% of an encode is Deflate — and it is also what
  `TagBin` and every future container pay.
- Where it stands: the match finder used to hash the three bytes miniz hashes, and on filtered
  image data one three-byte sequence repeats about twenty-six times inside a window, so the chain
  was a list of genuine duplicates walked to the end. It now hashes four bytes multiplicatively
  with a one-slot three-byte table beside it for the matches four bytes cannot hold. Search work
  per byte fell 1.6-1.8x, level 6 measured 1.27-1.67x faster on image data with the compressed
  size unchanged, and PNG encoding 1.31-1.52x faster with files 2-11% smaller.
- What is left: search is still about 85% of the time. Level 6 walks up to 132 candidates per
  position and comes back with a match three to six bytes long on filtered data, and level 1
  compresses the same input 4x faster for 5% more bytes, which is the size of the prize.
  The two untried levers are zlib's `nice_match` — stop the chain once a match is long enough,
  128 at level 6 — and tuning the lazy-match rule miniz inherited. Both change which matches are
  chosen, so each has to report compressed size beside time.
- The other half is not in this file: the block loop spends its time in stack slots rather than
  registers, which [compiler.optimization.006](compiler.optimization.md) measured at 1.6x against clang for the
  matching Inflate loop and is a backend problem, not a library one.
- Complete when: level 6 on the PNG and `.scc` fixtures is at least 1.5x faster than it is
  now with no more than 1% growth in compressed size, and every `core` compression test still
  round-trips.
- Related: std.core.021, std.core.022

---

## Tier B — Regular expression throughput

### std.core.019 — Unambiguous regular-expression captures replay the search

- Evidence: `src/text/regexp` finds the matching span with its automata, then uses the iterative
  backtracking engine to recover groups. The 2026-08-29 date-pattern measurement reduced that
  replay from 360 ns to 90 ns, but capture extraction still walks the pattern a second time.
  Anchored backtracking and lazy automaton construction are already implemented.
- Next: identify patterns whose capture transitions are unambiguous and prototype capture
  extraction during one forward pass. Keep the bounded fallback for patterns outside that subset.
- Complete when: the capture corpus returns identical groups and spans, ambiguous patterns retain
  the existing fallback, and interleaved measurements show the cost of the second walk removed.
- Related: std.core.020, std.core.030

### std.core.030 — Compiling a regular expression makes many separate allocations

- Evidence: the 2026-08-29 small-pattern measurement fell from about 27 to 8 microseconds after
  byte-set accounting and lazy automaton construction. The remaining allocation count was left
  as a lead; it has not been isolated from parsing and program construction in a current profile.
- Next: count allocations and bytes per compiled pattern, then test whether co-locating the
  immutable program data improves compilation without retaining unused automata or excess memory.
- Complete when: that attribution is reproducible and the allocation design is either improved
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
- Complete when: the script names of UAX #24 resolve, a test matches text in two scripts, and the
  tables are generated rather than hand-written.
- Related: std.core.019

---

## Tier C — Archives, calendars, and time zones

### std.core.021 — No gzip container support

Add the gzip container over the existing deflate/inflate and zlib support, including headers,
trailers, checksums, and concatenated members.

- Related: std.core.022, std.core.023

### std.core.022 — No ZIP container support

Add bounded ZIP reading and writing with central-directory validation and explicit support limits.

- Related: std.core.021

### std.core.023 — No TAR container support

Add streaming TAR reading and writing, with the supported metadata and extension variants stated.

- Related: std.core.021

### std.core.024 — Time zones

`time` handles UTC and local. There is no IANA zone database, no historical offsets, and no DST
rules for an arbitrary zone. Any application that schedules or displays times across regions is
stuck at the boundary.

## Tier C — Concurrency and asynchronous I/O

All new concurrency types and their generic implementations belong to `bin/runtime`, as specified
by language.parallelism.001. These entries own Core integration, algorithms, and consumer migration
against that native surface; they do not introduce Core-owned task or synchronization types.

### std.core.025 — No future or task abstraction

- Evidence: `Jobs` provides borrowed callbacks and parallel loops without typed results, owned
  captures, structured cancellation, or error propagation.
- Next: implement standard task combinators and migrate the Jobs family against the native
  task/runtime contract proposed in
  [language.parallelism.001](language.parallelism.md#languageparallelism001--specify-and-prototype-native-structured-concurrency),
  after its semantic gates and prototype settle the contract. Review bounded map, first completion,
  first success, all-results, supervision, progress, and shutdown as one operation family. Keep
  primitive task ownership and scheduling below Core; do not create a competing library scheduler.
  Any new reusable concurrency type needed by these operations is defined in `bin/runtime`.
- Complete when: those operations preserve result/error ownership and join losing work, and the
  caller inventory has migrated from the legacy Jobs API. Temporary callback adapters remain
  explicitly unchecked and are removed with their last consumers.
- Related: language.parallelism.001, std.core.026, std.core.027, std.core.028

### std.core.026 — No channel abstraction

- Evidence: no typed channel currently defines transfer, capacity, close, cancellation, and
  selection together.
- Next: integrate the runtime's bounded, rendezvous, and one-shot communication proposed in
  language.parallelism.001. Endpoint, selection, and rejected-message types remain in runtime.
  Settle endpoint clone/drop behavior, draining after close, ownership of rejected moved messages,
  and exactly one committed selection operation before choosing Core convenience functions.
- Complete when: focused channel and selection tests cover backpressure, closure, cancellation,
  simultaneous readiness, and withdrawal without lost messages or duplicate consumption.
- Related: language.parallelism.001, std.core.025

### std.core.027 — No condition variable

- Evidence: the synchronization family has no condition-variable predicate/wait contract.
- Next: integrate runtime condition and guard types with their explicit release/wait/reacquire
  contract under language.parallelism.001, including cancellation and lost/spurious wakeups. Review
  the existing mutex/event callers so a notification, permit count, and condition are not treated
  as interchangeable mechanisms. Keep native backend work in platform.portability.035.
- Complete when: guarded state remains valid across every wait outcome and focused tests prove
  notification registration, predicate rechecking, cancellation, and reacquisition behavior.
- Related: language.parallelism.001, std.core.025, platform.portability.035

### std.core.028 — No asynchronous I/O contract

- Evidence: there is no shared asynchronous I/O contract for completion, cancellation, borrowed
  buffers, or scheduler integration.
- Next: implement awaitable I/O against language.parallelism.001's completion and task-lifetime rules,
  using runtime-owned operation, completion, and cancellation types. Keep the common operation
  contract independent of its first socket or file backend. Model
  immediate completion, failed registration, cancellation racing completion, partial transfer,
  late callbacks, and shutdown. A stop request or expired deadline is not native completion.
- Complete when: a fake backend and one real backend demonstrate exactly one terminal completion
  and retain buffers, request records, and callbacks until the backend is finished with them;
  owning I/O consumers use the common runtime without private task or cancellation machinery.
- Related: language.parallelism.001, std.core.025, std.core.004

### std.core.029 — A buffered byte source over a file or memory is written once per module

- Problem: `Core.ByteStream` is a cursor over borrowed bytes and cannot read a file, and
  `File.FileStream` is an unbuffered handle, so every module that decodes a format larger than
  memory writes the missing half itself. `std/video` now owns `Video.Source` and `Video.Sink`,
  a buffered seekable reader and writer over a file or a memory buffer, and `Audio.SoundFile`
  solves the same problem differently by reopening its path on each payload read. `Pixel` avoids
  the question by decoding whole buffers, which is why an image codec there cannot stream.
- Consequence: three answers to one question, and the cheapest one wins by default: a decoder
  written against a slice is a decoder that cannot read a large file, which is exactly how a
  format ends up loading a whole document to show its first page.
- Promote the contract into Core — a buffered, seekable byte source and sink with file and memory
  backings — and move `std/video` and `std/audio` onto it. Read `Video.Source` first: it is the
  shape a codec actually needs, including a read that bypasses the window when it is larger
  than the window itself. Read `Video.Sink.patch` beside it: a container writer reserves the
  totals of its header and rewrites them once the last frame lands, and that operation is what
  keeps a writer at the cost of one frame instead of the cost of the file.
- Related: std.core.028

---

## Out of scope

**A package registry client.** That belongs to the tooling around the compiler, not to the standard
library, even after std.core.001 makes it possible.

**Bundling ICU.** Globalization should grow toward what applications need from compact locale
profiles or platform data. Vendoring a multi-megabyte dependency into the module every program
links is the wrong shape for that need.
