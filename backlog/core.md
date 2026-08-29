# Core Backlog

This backlog covers `std/core`, measured against the standard libraries it competes with:
the Go standard library, the .NET base class library, Rust's `std` plus its de-facto crates, the
Python standard library, and Zig's `std`.

Compiler work belongs in [compiler.md](compiler.md) and language work in
[language.md](language.md). This file keeps the evidence, investigations, and intended outcomes
owned by `bin/std/modules/core` together. [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

Read [design-swag-bin-modules](../.agents/skills/design-swag-bin-modules/SKILL.md) before
acting on any entry that proposes a boundary change. Several entries below deliberately argue for a
new module rather than growth inside `core`.

## Where the module already stands

Some areas are competitive or ahead.

- **Text**, at eleven thousand lines, is the largest area and it earns it: strings, a builder,
  formatting, parsing, a regular-expression engine, Unicode and Latin-1 tables, UTF-8 and UTF-16,
  correctly-rounded `atod`/`dtoa`, decimals, tokenizing. This is a peer of what Go and .NET ship.
- **Math** has vectors, matrices, 2D geometry and transforms, curves, 128-bit integers, bit
  manipulation and angles. Go, Rust and .NET ship none of this; the comparison here is a game
  engine, not a standard library.
- **Reflection** over structs, enums, attributes and arrays is a genuine advantage. C++ has
  nothing, Rust needs derive macros, Go's is runtime-only and awkward. The reflection-driven
  `TagBin` serializer is what that advantage buys.
- **Random** ships seven generators including noise, which is more than most.
- Collections, filesystem, time, threading and the job system all cover their basics.

The gaps are not about polish. Two of them are structural.

---

## Tier A — Network stack

These two entries are the difference between a standard library and a complete one. They are
independent: neither blocks the other, and neither should be allowed to block everything else.

### T-027 — No blocking TCP sockets

- Problem: there are no TCP sockets. A Swag program cannot open even a blocking connection.
- Consequence: this rules out servers, clients, tooling that talks to a registry or an API, package
  management, telemetry, and every application whose value involves a network. It is the single
  largest capability gap in the language, larger than anything in the compiler.
- Put the blocking TCP and address foundation in a `net` module importing `core`; do not put a
  network stack in the module every program links. Implement Winsock and BSD-socket leaves behind
  the same contract.
- Related: T-126, T-127, T-128, T-129, T-130, T-131, T-341

### T-341 — No UDP sockets

Add datagram sockets, endpoints, size/error behavior, and broadcast/multicast decisions
independently of TCP connection semantics.

- Related: T-027, T-126, T-127

### T-126 — No DNS resolver

Add host/service resolution to the `net` module over the platform resolver, with explicit address
ordering, cancellation, and failure semantics.

- Related: T-027

### T-127 — No non-blocking socket readiness API

Add non-blocking sockets and readiness notification after the concurrency decision in T-012. Keep
the readiness mechanism separate from the blocking socket foundation.

- Related: T-027, T-012, T-162

### T-128 — No TLS transport

Provide client and server TLS over the socket contract. Decide explicitly whether each platform
binds its native provider or the project owns a portable implementation.

- Related: T-027, T-031, T-151, T-152

### T-129 — No HTTP client

Implement an HTTP/1.1 client over T-027 and T-128, with streaming bodies, redirects, cancellation,
and bounded parsing as its own public contract.

- Related: T-027, T-128

### T-130 — No HTTP server

Implement HTTP/1.1 server parsing, response streaming, connection lifetime, and limits independently
of the client API.

- Related: T-027, T-127, T-128, T-129

### T-131 — No WebSocket protocol

Add WebSocket handshake and frame processing above HTTP without making it part of the HTTP client's
completion criteria.

- Related: T-129, T-130

## Tier A — Second-platform system services

### T-028 — Process services have no second-platform backend

Add process creation, waiting, termination, pipes, exit status, and resource semantics for the
chosen second platform. The common-policy extraction is tracked separately in T-106 and T-277.

- Related: T-106, T-277, T-280

### T-132 — Filesystem services have no second-platform backend

Implement directory, file, stream, metadata, path-state, and mutation primitives for the chosen
second platform behind the existing common orchestration and path contracts.

### T-133 — Threads have no second-platform backend

Implement thread creation, start, join, yield, sleep, identity, and priority for the chosen second
platform without copying common lifecycle policy into the native leaf.

- Related: T-312

### T-312 — Synchronization primitives have no second-platform backend

Implement mutexes, read-write locks, and events for the chosen second platform behind the existing
portable contracts.

- Related: T-133, T-161

### T-134 — Clocks have no second-platform backend

Implement wall-clock fields and monotonic ticks for the chosen second platform.

- Related: T-313

### T-313 — Timers have no second-platform backend

Implement native timer wait/wake mechanisms for the chosen second platform behind the common
scheduler in T-301.

- Related: T-134, T-301

### T-135 — Environment services have no second-platform backend

Implement environment variables, arguments, locale, special directories, and generic desktop
actions for the chosen second platform.

- Related: T-271, T-279, T-288

### T-136 — Native errors have no second-platform mapping

Map the second platform's error domain into the portable `core` failure contract, preserving native
detail without leaking native codes into portable callers.

### T-137 — The sandbox has no second-platform backend

Implement the sandbox's platform enforcement and early-startup behavior for the chosen second
platform independently of general environment services.

- Related: T-135, T-279

### T-138 — Hardware discovery has no second-platform backend

Implement the portable CPU, memory, display-adjacent, and machine capability queries currently
provided only by Windows.

### T-139 — Console I/O has no second-platform backend

Implement terminal encoding, capability, color, prompt, and byte output for the chosen second
platform behind the existing common formatting layer.

### T-140 — Stack capture has no second-platform backend

Provide address capture and current-image discovery for the chosen second platform behind the
runtime host boundary.

- Related: T-104, T-314, T-342

### T-342 — Debug-symbol access has no second-platform backend

Locate and read the target's debug information for captured addresses, leaving parsing and
presentation in the existing common layer.

- Related: T-140

### T-314 — Debugger integration has no second-platform backend

Implement debugger detection, break/attach behavior, and any debugger-facing host operations
independently of stack-symbol presentation.

- Related: T-104, T-140

### T-141 — Input devices have no second-platform backend

Implement keyboard and gamepad acquisition for the chosen second platform while keeping normalized
state and policy in common code.

---

## Tier B — Cryptography

### T-252 — Independent Argon2 lanes run serially

- Intent: run independent lanes within each legal slice through `Jobs`, respecting Argon2's
  synchronization points and the configured `parallelism` contract.
- Complete when: multi-lane published vectors still agree, the requested lane count executes in
  parallel, and a benchmark separates the lane-parallel gain from the packed permutation work.
- Related: T-251 in [simd.md](simd.md)

### T-031 — No AES implementation

- Present: Adler-32, CRC-32, CRC-64, MD5, SHA-1, SHA-256, HMAC-SHA-256, PBKDF2, ChaCha20, and
  several non-cryptographic hashes.
- Add AES with hardware acceleration where available and constant-time fallback behavior, then add
  separately numbered modes only when their contracts are chosen.
- Related: T-128, T-147, T-148, T-149, T-150, T-151, T-152, T-153

### T-147 — No SHA-512 family

Implement SHA-384/SHA-512 and HMAC variants with standard vectors and streaming parity with the
existing SHA-256 API.

- Related: T-031

### T-148 — No SHA-3 family

Implement the SHA-3 digest family and SHAKE extendable-output functions as a distinct sponge-based
API.

- Related: T-031

### T-149 — No BLAKE2 implementation

Add BLAKE2 variants with keyed and unkeyed modes independently of BLAKE3.

- Related: T-150

### T-150 — No BLAKE3 implementation

Add BLAKE3 hashing, keyed hashing, key derivation, and parallel tree processing as one algorithm
contract.

- Related: T-149

### T-151 — No Ed25519 signatures

Add key generation, signing, verification, strict input validation, and published vectors for
Ed25519.

- Related: T-128, T-152

### T-152 — No X25519 key agreement

Add X25519 key generation and shared-secret derivation with low-order input handling stated and
tested.

- Related: T-128, T-151

### T-153 — No RSA interoperability

Provide only the RSA operations and padding schemes justified by external interoperability, with
unsafe legacy modes excluded from the default surface.

- Related: T-128

---

## Tier B — Compression throughput

### T-561 — Deflate is still four-fifths match search

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
  registers, which [F-136](optimization.md) measured at 1.6x against clang for the
  matching Inflate loop and is a backend problem, not a library one.
- Complete when: level 6 on the PNG and `.scapture` fixtures is at least 1.5x faster than it is
  now with no more than 1% growth in compressed size, and every `core` compression test still
  round-trips.
- Related: T-032, T-154

---

## Tier B — Regular expression throughput

### B-154 — The last gaps between the regular-expression engine and the Rust crate

- Intent: keep `Parser.RegExp` at the speed of the fastest engine available, which is what the
  rewrite of 2026-08-29 set out to reach.
- Where it stands: measured against the Rust `regex` crate on the same ten-megabyte corpus,
  counting every match of the same pattern in memory, best of ten interleaved rounds. A plain
  literal 1.2x slower, an alternation of literals 2.4x *faster*, `\d{4}-\d{2}-\d{2}` 1.1x
  slower, `[a-z]+[0-9]+@[a-z.-]+` at parity, `(?i)sherlock` 1.6x *faster*, a date with capture
  groups 1.6x slower, `[a-z]+ing` 1.9x, and `\w+` 2x. Nothing is more than 2x, and what is
  behind is what matches often.
- What is left, in decreasing value:
  - **A search still costs more to start than to run**, against roughly thirty nanoseconds for
    the crate. Looking for every occurrence runs the engines from one loop rather than through
    the façade once per match, tries the pattern at the offset itself where no scan can skip
    ahead — a match found that way needs nothing read backwards — and collects its results in
    batches. That took `\w+` from 3.2x to 2x and `[a-z]+ing` from 2.4x to 1.9x. What is left
    is the prologue of an automaton call and the tuple it returns, both of which only the
    backend can remove.
  - **Captures replay the search.** The backtracking engine reads the groups back over the span
    the automata found — iteratively, without recursion, and reading the program through
    pointers, which took it from three hundred and sixty nanoseconds to ninety on a ten-byte
    date — but it still walks the pattern a second time. A pattern whose groups are unambiguous — most patterns
    that parse a line — can have them read by a single pass with no branch set at all, which is
    the crate's `onepass` engine and why its capture benchmark costs what its plain one costs.
  - **Vectors are 128 bits.** Every scan reads sixteen bytes per instruction where the crate
    reads thirty-two. That is a language matter, not a library one: see the `#simd` entries in
    [simd.md](simd.md).
- What is not worth trying again: the automaton step itself. One step is a byte read, a class
  read and a transition read, each depending on the one before it, and the loop measured four
  nanoseconds a byte both inside the engine and in a six-instruction function written for the
  experiment. That is the latency of three dependent loads on this machine.
- Complete when: no benchmark in that set is more than 1.5x the crate, and captures cost what a
  search without them costs.
- Related: B-155

### B-155 — Unicode properties are limited to the general categories

- Intent: `\p{...}` should name the scripts and the common derived properties, not only the
  handful of general categories the Unicode tables in `core` happen to carry.
- Where it stands: `\p{L}`, `\p{Ll}`, `\p{Lu}`, `\p{Lt}`, `\p{N}`, `\p{Nd}`, `\p{S}`,
  `\p{Sm}` and `\p{Z}` work, negated by `\P`. `\p{Greek}`, `\p{Han}`, `\p{Alphabetic}` and
  the rest fail to compile. The engine itself needs nothing new: a property is a set of scalar
  intervals, and the compiler already turns any such set into a UTF-8 automaton.
- What is left: the interval tables. `Unicode` ships general-category tables ported from Go;
  scripts would be another table of the same shape, generated the same way, and the property
  lookup in `RuneClass.unicodeProperty` is one more `switch` arm per table.
- Complete when: the script names of UAX #24 resolve, a test matches text in two scripts, and the
  tables are generated rather than hand-written.
- Related: B-154

---

## Tier C — Archives, calendars, and time zones

### T-032 — No gzip container support

Add the gzip container over the existing deflate/inflate and zlib support, including headers,
trailers, checksums, and concatenated members.

- Related: T-154, T-155

### T-154 — No ZIP container support

Add bounded ZIP reading and writing with central-directory validation and explicit support limits.

- Related: T-032

### T-155 — No TAR container support

Add streaming TAR reading and writing, with the supported metadata and extension variants stated.

- Related: T-032

### T-033 — Time zones

`time` handles UTC and local. There is no IANA zone database, no historical offsets, and no DST
rules for an arbitrary zone. Any application that schedules or displays times across regions is
stuck at the boundary.

## Tier C — Concurrency and asynchronous I/O

### T-036 — No future or task abstraction

`Jobs` gives parallel visiting and loops, but no value-bearing or failing asynchronous task that a
caller can await, combine, cancel, or observe.

This is as much a language question as a library one — Go answered it with goroutines and channels,
Rust with `async` and a futures machinery that reaches into the type system, .NET with `Task`. It
should be decided deliberately and early, because T-027 will force the question the moment
non-blocking sockets arrive, and answering it under that pressure is how libraries end up with two
concurrency models.

The language-design half is [T-012](language.md#t-012--the-concurrency-model-is-undecided).
Record decisions there, not here.

- Related: T-012, T-160, T-161, T-162

### T-160 — No channel abstraction

Add typed communication channels only after T-012 decides whether they are a language-level
coordination primitive or an ordinary library type.

- Related: T-012, T-036

### T-161 — No condition variable

Add condition variables with a predicate-loop usage contract and clear interaction with mutex
ownership and cancellation.

- Related: T-036

### T-162 — No asynchronous I/O contract

Define asynchronous I/O completion, cancellation, buffer lifetime, and scheduler integration
without coupling it to the first non-blocking socket backend.

- Related: T-012, T-036, T-127

### T-422 — A buffered byte source over a file or memory is written once per module

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
- Related: T-162

---

## Out of scope

**A package registry client.** That belongs to the tooling around the compiler, not to the standard
library, even after T-027 makes it possible.

**Bundling ICU.** Globalization should grow toward what applications need from compact locale
profiles or platform data. Vendoring a multi-megabyte dependency into the module every program
links is the wrong shape for that need.
