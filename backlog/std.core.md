# Core Backlog

This backlog covers `std/core`, measured against the standard libraries it competes with:
the Go standard library, the .NET base class library, Rust's `std` plus its de-facto crates, the
Python standard library, and Zig's `std`.

Compiler work belongs in [compiler.core.md](compiler.core.md) and language work in
[language.design.md](language.design.md). This file keeps the evidence, investigations, and intended outcomes
owned by `bin/std/modules/core` together. [README.md](README.md) has the whole layout.

Entries are ordered from the most recently updated down. An entry disappears when it
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

## Entries

The network stack starts with the blocking transport contract; datagrams and higher-level protocols have separate
acceptance conditions of their own.

All concurrency types and their generic implementations belong to `bin/runtime`, as specified by
language.parallelism.001. The concurrency entries own Core integration, algorithms, and consumer
migration against that native surface; they do not introduce Core-owned task or synchronization
types.

### std.core.032 — The recovered inflate rewrite fails a real-document golden

- Recorded: 2026-09-08 22:17
- Updated: 2026-09-10 19:39 — Distinguish the observed rendering failure from the pending decoded-byte comparison.
- Evidence: the block decoder refills once per outer iteration, and the fast loop then drains the
  bit buffer to wherever its last symbol ended. The careful path that takes over decodes a length
  code and then a distance code with nothing between them to reload, so it subtracts a width the
  buffer no longer holds. Swag Scope's InDesign document stopped there with `integer overflow`:
  thirty bits when the group started, fourteen left when the distance needed fifteen, with the
  input cursor at 31 083 of 46 021 and the destination a megabyte from its bound, so neither end
  was near and the fast loop had bailed mid-stream on a code longer than its table covers.
- Evidence: `643900899` gives that group a refill of its own and fails a truncated tail instead of
  wrapping around. The crash goes away and the same document then decodes to an image the golden
  rejects, so the recovered branch still has a correctness failure beyond the fixed crash. The
  mismatch has not yet been attributed to specific decoded bytes. `bin/std` keeps master's
  inflate until that failure is explained and fixed; a rendering mismatch is not acceptable
  evidence for adopting the rewrite.
- Evidence: the crash has no synthetic reduction. The fast loop hands a match to the careful path
  only when a literal or length code exceeds the twelve bits of its table, and the repository's
  own deflate did not emit one for any of four shapes: a drifting four-kilobyte block, text from a
  heavily skewed vocabulary, forty byte values occurring twice each, and a thirty-kilobyte block
  repeated at the far end of the window with one rare short match per copy. All four entered the
  careful path with a nearly full buffer, and the widest distance group seen there was fourteen
  bits against forty-six available. The measurements came from a temporary probe on the careful
  path's distance decode; `bin/apps/modules/swagscope/src/tests/viewer.indesign.test.swg` is what
  exercises the real shape.
- Next: find the wrong bytes before anything else. Decode the document's streams with both
  decoders and compare the output, rather than comparing rendered images, so the divergence is a
  byte offset instead of a pixel. Only then decide whether the rewrite is repairable, and settle
  its grain against master's inflate, because the whole point of it was speed and none of that was
  ever measured here.
- Complete when: the rewrite decodes every stream byte-for-byte as master's inflate does, a `core`
  test fails without the careful path's refill, and a measurement says what the rewrite buys.
- Related area: [image decoding](std.pixel.image.md).

### std.core.018 — Rebaseline and reduce Deflate match-search cost

- Recorded: 2026-08-23 22:36
- Updated: 2026-09-10 19:32 — Separate the historical compression profile from the next baseline.
- Intent: close the rest of the gap between `Compress.Deflate` and the compressors it competes
  with. The 2026-08-23 profile attributed 97% of PNG encoding to Deflate; it is also what
  `TagBin` and every future container pay.
- Historical measurement (2026-08-23): the match finder used to hash the three bytes miniz hashes, and on filtered
  image data one three-byte sequence repeats about twenty-six times inside a window, so the chain
  was a list of genuine duplicates walked to the end. It now hashes four bytes multiplicatively
  with a one-slot three-byte table beside it for the matches four bytes cannot hold. Search work
  per byte fell 1.6-1.8x, level 6 measured 1.27-1.67x faster on image data with the compressed
  size unchanged, and PNG encoding 1.31-1.52x faster with files 2-11% smaller.
- Remaining lead: search accounted for about 85% of that profile. Level 6 walks up to 132 candidates per
  position and comes back with a match three to six bytes long on filtered data, and level 1
  compresses the same input 4x faster for 5% more bytes, which is the size of the prize.
  The two untried levers are zlib's `nice_match` — stop the chain once a match is long enough,
  128 at level 6 — and tuning the lazy-match rule miniz inherited. Both change which matches are
  chosen, so each has to report compressed size beside time.
- The other half is not in this file: the block loop spends its time in stack slots rather than
  registers, which [compiler.optimization.006](compiler.optimization.md) measured at 1.6x against clang for the
  matching Inflate loop and is a backend problem, not a library one.
- Next: remeasure the current compiler and match finder on the same PNG and `.scc` corpus, then compare each search-policy change against that recorded baseline.
- Complete when: level 6 on the PNG and `.scc` fixtures is at least 1.5x faster than that
  baseline with no more than 1% growth in compressed size, and every `core` compression test still
  round-trips.
- Related: std.core.021, std.core.022

### std.core.022 — No reusable ZIP reader and writer

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-10 19:32 — Account for the bounded ZIP reader already shipped in Swag Scope.

- Evidence: Core exposes no ZIP container API. Swag Scope already owns a bounded reader in
  `src/viewers/archive/ziparchive.swg`, including ZIP64 directory metadata, stored/Deflate
  extraction, CRC checks, and a 250,000-entry limit.
- Next: review and extract that reader into a reusable container boundary, migrate Scope to it,
  and add the missing writer with explicit supported formats and resource limits.
- Complete when: owning round-trip and malformed-container tests cover the shared reader/writer
  and Scope uses that contract without a private ZIP parser.

- Related: std.core.021

### std.core.031 — Two atomic families, one of them Core's

- Recorded: 2026-09-07 16:02
- Updated: 2026-09-08 12:52 — the directory watcher's private cancellation state now uses the runtime atomic type
- Found while: adding `Swag.AtomicValue` to `bin/runtime` for the scheduler and the task states.
- Evidence: `Core.Atomic` is a namespace of `#[Swag.Inline]` wrappers over the `Swag.atom*`
  intrinsics, originally found at 227 call sites across `bin/`. `Swag.AtomicValue'T` owns
  atomic storage and exposes the same operations as methods. The concurrency contract says one
  owner for each concurrency type family; there are two, and the runtime one had to be named
  `AtomicValue` because `Atomic` is already taken by the Core namespace in every file that writes
  `using Threading`.
- Evidence: `Directory.Watcher` now stores its private cancellation field as `Swag.AtomicValue'u32`;
  all four operations use the field's methods. The immediate and cross-thread cancellation tests
  cover this migration without changing the watcher's public lifetime contract.
- Next: decide which one the language keeps. Storage that only its own operations reach is the
  stronger contract -- it is what makes "no ordinary access beside an atomic one" checkable -- so
  the likely answer is the runtime type, with `Core.Atomic` migrating to it and the runtime type
  taking the name `Atomic` once the namespace is gone. Count the call sites that atomically access
  a field of a larger structure, because those need the field itself to become an
  `AtomicValue` rather than a wrapper call on its address.
- Complete when: one atomic family remains, its name is not a workaround, and no consumer reaches
  atomic storage through an ordinary pointer.
- Related: language.parallelism.001, language.parallelism.005

### std.core.025 — No task combinators over the runtime tasks

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-07 15:56 — cut down to what the runtime types do not answer, now that
  `Core.Jobs` is gone and every consumer uses `Swag.Task` and `Swag.TaskGroup`
- Evidence: the runtime provides one task, one group, and one partitioned loop. A caller that
  wants bounded map, first completion, first success, all-results, or progress writes the fan-out
  and the join by hand, as `H264.Decoder.scheduleParsedRows` and `Hevc` wavefront scheduling both
  do with their own arrays and their own failure flag.
- Next: review that family as one operation set rather than adding members one at a time, and
  settle what each does with a losing branch: cancel it, join it, and only then release anything it
  borrows. Combinators that select one result need
  [language.parallelism.002](language.parallelism.md) to land first, because a task carries no
  typed result yet. Keep scheduling below Core; these are algorithms over the runtime types, not a
  second scheduler.
- Complete when: the operations preserve result and error ownership, join losing work before
  releasing its borrows, and the manual fan-outs in `std/video` are written with them instead.
- Related: language.parallelism.002, language.parallelism.011, std.core.028

### std.core.028 — No asynchronous I/O contract

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-07 15:56 — waits on language.parallelism.002 rather than on the whole model
- Evidence: there is no shared asynchronous I/O contract for completion, cancellation, borrowed
  buffers, or scheduler integration.
- Next: implement awaitable I/O against language.parallelism.002's completion and task-lifetime rules,
  using runtime-owned operation, completion, and cancellation types. Keep the common operation
  contract independent of its first socket or file backend. Model
  immediate completion, failed registration, cancellation racing completion, partial transfer,
  late callbacks, and shutdown. A stop request or expired deadline is not native completion.
- Complete when: a fake backend and one real backend demonstrate exactly one terminal completion
  and retain buffers, request records, and callbacks until the backend is finished with them;
  owning I/O consumers use the common runtime without private task or cancellation machinery.
- Related: language.parallelism.002, std.core.025, std.core.004

### std.core.019 — Unambiguous regular-expression captures replay the search

- Recorded: 2026-09-06 17:42
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

- Recorded: 2026-08-29 16:36
- Updated: 2026-09-06 17:42 — git: Add unit tests for float to u64 conversion safety checks
- Evidence: the 2026-08-29 small-pattern measurement fell from about 27 to 8 microseconds after
  byte-set accounting and lazy automaton construction. The remaining allocation count was left
  as a lead; it has not been isolated from parsing and program construction in a current profile.
- Next: count allocations and bytes per compiled pattern, then test whether co-locating the
  immutable program data improves compilation without retaining unused automata or excess memory.
- Complete when: that attribution is reproducible and the allocation design is either improved
  with equal matching behavior or retained for a measured reason.
- Related: std.core.019

### std.core.001 — No blocking TCP sockets

- Recorded: 2026-08-05 07:43
- Updated: 2026-09-06 07:51 — git: prompt 6
- Problem: there are no TCP sockets. A Swag program cannot open even a blocking connection.
- Consequence: this rules out servers, clients, tooling that talks to a registry or an API, package
  management, telemetry, and every application whose value involves a network. It is the single
  largest capability gap in the language, larger than anything in the compiler.
- Put the blocking TCP and address foundation in a `net` module importing `core`; do not put a
  network stack in the module every program links. Platform leaves are owned by
  platform.portability.088.
- Related: std.core.003, std.core.004, std.core.005, std.core.006, std.core.007, std.core.008, std.core.002, platform.portability.088

### std.core.004 — No non-blocking socket readiness API

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-06 07:51 — git: prompt 6

Add non-blocking sockets and readiness notification after the concurrency decision in language.parallelism.001. Keep
the readiness mechanism separate from the blocking socket foundation.

- Related: std.core.001, language.parallelism.001, std.core.028

### std.core.020 — Unicode scripts and most derived properties are missing

- Recorded: 2026-08-29 16:36
- Updated: 2026-09-06 07:51 — git: prompt 6
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

### std.core.013 — No BLAKE2s implementation

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-05 16:27 — git: Add unit tests for TaskProvider in providers.test.js

`Hash.Blake2b` already implements incremental and one-shot keyed and unkeyed hashing, with
variable digest lengths and tests in `src/tests/crypto/blake2b.test.swg`. Add BLAKE2s with the
same operation family and published vectors; BLAKE3 remains independent.

- Related: std.core.014

### std.core.002 — No UDP sockets

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Add datagram sockets, endpoints, size/error behavior, and broadcast/multicast decisions
independently of TCP connection semantics.

- Related: std.core.001, std.core.003, std.core.004

### std.core.003 — No DNS resolver

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Add host/service resolution to the `net` module over the platform resolver, with explicit address
ordering, cancellation, and failure semantics.

- Related: std.core.001

### std.core.005 — No TLS transport

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Provide client and server TLS over the socket contract. Decide explicitly whether each platform
binds its native provider or the project owns a portable implementation.

- Related: std.core.001, std.core.010, std.core.015, std.core.016

### std.core.006 — No HTTP client

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement an HTTP/1.1 client over std.core.001 and std.core.005, with streaming bodies, redirects, cancellation,
and bounded parsing as its own public contract.

- Related: std.core.001, std.core.005

### std.core.007 — No HTTP server

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement HTTP/1.1 server parsing, response streaming, connection lifetime, and limits independently
of the client API.

- Related: std.core.001, std.core.004, std.core.005, std.core.006

### std.core.008 — No WebSocket protocol

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Add WebSocket handshake and frame processing above HTTP without making it part of the HTTP client's
completion criteria.

- Related: std.core.006, std.core.007

### std.core.010 — No AES implementation

- Recorded: 2026-08-05 07:43
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Present: Adler-32, CRC-32, CRC-64, MD5, SHA-1, SHA-256, HMAC-SHA-256, PBKDF2, ChaCha20, and
  several non-cryptographic hashes.
- Add AES with hardware acceleration where available and constant-time fallback behavior, then add
  separately numbered modes only when their contracts are chosen.
- Related: std.core.005, std.core.011, std.core.012, std.core.013, std.core.014, std.core.015, std.core.016, std.core.017

### std.core.011 — No SHA-512 family

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement SHA-384/SHA-512 and HMAC variants with standard vectors and streaming parity with the
existing SHA-256 API.

- Related: std.core.010

### std.core.012 — No SHA-3 family

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Implement the SHA-3 digest family and SHAKE extendable-output functions as a distinct sponge-based
API.

- Related: std.core.010

### std.core.014 — No BLAKE3 implementation

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Add BLAKE3 hashing, keyed hashing, key derivation, and parallel tree processing as one algorithm
contract.

- Related: std.core.013

### std.core.015 — No Ed25519 signatures

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Add key generation, signing, verification, strict input validation, and published vectors for
Ed25519.

- Related: std.core.005, std.core.016

### std.core.016 — No X25519 key agreement

- Recorded: 2026-08-09 11:30
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Add X25519 key generation and shared-secret derivation with low-order input handling stated and
tested.

- Related: std.core.005, std.core.015

### std.core.017 — No RSA interoperability

- Recorded: 2026-08-05 07:43
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Provide only the RSA operations and padding schemes justified by external interoperability, with
unsafe legacy modes excluded from the default surface.

- Related: std.core.005

### std.core.021 — No gzip container support

- Recorded: 2026-08-05 07:43
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Add the gzip container over the existing deflate/inflate and zlib support, including headers,
trailers, checksums, and concatenated members.

- Related: std.core.022, std.core.023

### std.core.023 — No TAR container support

- Recorded: 2026-08-05 07:43
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

Add streaming TAR reading and writing, with the supported metadata and extension variants stated.

- Related: std.core.021

### std.core.024 — Time zones

- Recorded: 2026-08-05 07:43
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

`time` handles UTC and local. There is no IANA zone database, no historical offsets, and no DST
rules for an arbitrary zone. Any application that schedules or displays times across regions is
stuck at the boundary.

---

## Out of scope

**A package registry client.** That belongs to the tooling around the compiler, not to the standard
library, even after std.core.001 makes it possible.

**Bundling ICU.** Globalization should grow toward what applications need from compact locale
profiles or platform data. Vendoring a multi-megabyte dependency into the module every program
links is the wrong shape for that need.
