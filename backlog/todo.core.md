# Core Roadmap

This file is the roadmap for `std/core`, measured against the standard libraries it competes with:
the Go standard library, the .NET base class library, Rust's `std` plus its de-facto crates, the
Python standard library, and Zig's `std`.

It is not the repository's discovery backlog. Defects and leads about other subsystems belong in
the `findings.*` files, which hold evidence; compiler intent belongs in
[todo.compiler.md](todo.compiler.md) and language intent in [todo.language.md](todo.language.md).
This file holds intent about `bin/std/modules/core`. [README.md](README.md) has the whole layout.

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

## Tier A — Structural

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

### T-028 — Process services have no second-platform backend

Add process creation, waiting, termination, pipes, exit status, and resource semantics for the
chosen second platform. The common-policy extraction is tracked separately in T-106 and T-277.

- Related: T-103, T-106, T-277, T-280

### T-132 — Filesystem services have no second-platform backend

Implement directory, file, stream, metadata, path-state, and mutation primitives for the chosen
second platform behind the contract prepared by T-107, T-282, and T-283.

- Related: T-107, T-282, T-283

### T-133 — Threads have no second-platform backend

Implement thread creation, start, join, yield, sleep, identity, and priority for the chosen second
platform without copying common lifecycle policy into the native leaf.

- Related: T-300, T-312

### T-312 — Synchronization primitives have no second-platform backend

Implement mutexes, read-write locks, and events for the chosen second platform behind the existing
portable contracts.

- Related: T-133, T-161

### T-134 — Clocks have no second-platform backend

Implement wall-clock fields and monotonic ticks for the chosen second platform.

- Related: T-302, T-313

### T-313 — Timers have no second-platform backend

Implement native timer wait/wake mechanisms for the chosen second platform behind the common
scheduler in T-301.

- Related: T-134, T-301

### T-135 — Environment services have no second-platform backend

Implement environment variables, arguments, locale, special directories, and generic desktop
actions for the chosen second platform.

- Related: T-271, T-278, T-279, T-288

### T-136 — Native errors have no second-platform mapping

Map the second platform's error domain into the portable `core` failure contract, preserving native
detail without leaking native codes into portable callers.

- Related: T-103

### T-137 — The sandbox has no second-platform backend

Implement the sandbox's platform enforcement and early-startup behavior for the chosen second
platform independently of general environment services.

- Related: T-135, T-279

### T-138 — Hardware discovery has no second-platform backend

Implement the portable CPU, memory, display-adjacent, and machine capability queries currently
provided only by Windows.

- Related: T-103

### T-139 — Console I/O has no second-platform backend

Implement terminal encoding, capability, color, prompt, and byte output for the chosen second
platform behind the common formatting work in T-303.

- Related: T-303

### T-140 — Stack capture has no second-platform backend

Provide address capture and current-image discovery for the chosen second platform behind the
runtime host boundary.

- Related: T-104, T-314, T-342

### T-342 — Debug-symbol access has no second-platform backend

Locate and read the target's debug information for captured addresses, leaving parsing and
presentation common under T-328.

- Related: T-140, T-328

### T-314 — Debugger integration has no second-platform backend

Implement debugger detection, break/attach behavior, and any debugger-facing host operations
independently of stack-symbol presentation.

- Related: T-104, T-140

### T-141 — Input devices have no second-platform backend

Implement keyboard and gamepad acquisition for the chosen second platform while keeping normalized
state and policy in common code.

- Related: T-112

---

## Tier B — Present but too thin to use

### T-029 — No JSON

- Problem: `serialization` provides `ByteStream` and the reflection-driven `TagBin` binary format.
  There is no JSON, and no XML, TOML or YAML either.
- Consequence: no configuration file another tool can read or write, no web API interoperability,
  no exchange with anything outside Swag. `TagBin` is a good internal format and a useless
  interchange one.
- Fix: a JSON codec in `serialization`, declaration-driven the way `TagBin` already is. The
  reflection layer means this can be *better* than most standard libraries here rather than merely
  present — encoding a struct should need no schema and no annotations.
- This is the highest value-to-effort entry in the module. Do it before anything in Tier C.

### T-030 — Number formatting has no grouping rules

- Problem: the whole area is twenty-nine lines. `CultureInfo` holds one `NumberFormatInfo`, which
  holds a negative sign, a positive sign and a decimal separator.
- Add per-culture group separators, group sizes, and grouped numeric formatting to the existing
  sign and decimal-separator data.
- Related: `bin/apps` and `std/gui` now have localization work in flight on the `gui-resources`
  branch. Coordinate rather than building a second vocabulary. See T-142 through T-145 for the
  other independent globalization capabilities.

### T-146 — No per-culture currency formatting

Add currency symbols, placement, grouping, decimal rules, and negative patterns independently of
general number formatting.

- Related: T-030

### T-142 — No per-culture date patterns

Add localized date patterns plus month and day names to `core` so applications and GUI resources
do not maintain their own culture tables.

- Related: T-030, T-218, T-315

### T-315 — No per-culture time patterns

Add localized clock patterns, separators, and 12/24-hour conventions independently of date
formatting.

- Related: T-030, T-142

### T-143 — No locale-aware collation

Provide locale-aware comparison and sort keys independently of Unicode normalization and ordinal
string comparison.

- Related: T-030

### T-144 — No plural-rule evaluation

Expose cardinal and ordinal plural categories for a locale so resource selection can represent
more than singular versus plural.

- Related: T-030, T-218

### T-145 — No locale-aware case mapping

Add culture-sensitive upper, lower, and case-fold operations without changing the existing ordinal
and Unicode-default operations.

- Related: T-030

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

## Tier C — Coverage

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

### T-034 — No ordered map

Present: `Array`, `ArrayPtr`, `BitArray`, `ConcatBuffer`, `HashSet`, `HashTable`, `List`,
`StaticArray`. Add an ordered map so iteration is sorted and range queries are possible; a hash
table cannot substitute.

- Related: T-156, T-157, T-158

### T-156 — No ordered set

Add an ordered set with the same ordering, lookup, range, ownership, and iterator conventions as
T-034's ordered map.

- Related: T-034

### T-157 — No deque

Add a double-ended queue or ring-buffer collection with bounded amortized operations at both ends.

- Related: T-158

### T-158 — No priority queue

Add a heap-backed priority queue with explicit comparator and ownership behavior.

- Related: T-157

### T-035 — No memory-mapped files

Add portable mapped-file and mapped-region APIs with flush, resize interaction, lifetime, and
failure contracts suitable for large files such as an sCrypt container.

- Related: T-159

### T-159 — No filesystem watching

Add a filesystem change stream for tools that react to edits, with overflow, rename pairing,
recursive scope, and cancellation behavior stated per platform.

- Related: T-035, T-008

### T-036 — No future or task abstraction

`Jobs` gives parallel visiting and loops, but no value-bearing or failing asynchronous task that a
caller can await, combine, cancel, or observe.

This is as much a language question as a library one — Go answered it with goroutines and channels,
Rust with `async` and a futures machinery that reaches into the type system, .NET with `Task`. It
should be decided deliberately and early, because T-027 will force the question the moment
non-blocking sockets arrive, and answering it under that pressure is how libraries end up with two
concurrency models.

The language-design half is [T-012](todo.language.md#t-012--the-concurrency-model-is-undecided).
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

---

## Out of scope

**A package registry client.** That belongs to the tooling around the compiler, not to the standard
library, even after T-027 makes it possible.

**Bundling ICU.** T-030 should grow toward what applications need from the platform's own locale
data. Vendoring a multi-megabyte dependency into the module every program links is the wrong shape
for that need.
