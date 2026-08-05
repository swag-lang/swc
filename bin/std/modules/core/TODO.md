# Core Roadmap

This file is the roadmap for `std/core`, measured against the standard libraries it competes with:
the Go standard library, the .NET base class library, Rust's `std` plus its de-facto crates, the
Python standard library, and Zig's `std`.

It is not the repository's discovery backlog. Defects and leads about other subsystems belong in
[FINDINGS.md](../../../../FINDINGS.md); compiler and language intent belongs in the root
[TODO.md](../../../../TODO.md). This file holds intent about this module.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

Read [design-swag-bin-modules](../../../../.agents/skills/design-swag-bin-modules/SKILL.md) before
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

### 1. No networking of any kind

- Problem: there are no sockets. No TCP, no UDP, no DNS resolution, no HTTP client or server, no
  TLS, no WebSocket. A Swag program cannot open a connection to anything.
- Consequence: this rules out servers, clients, tooling that talks to a registry or an API, package
  management, telemetry, and every application whose value involves a network. It is the single
  largest capability gap in the language, larger than anything in the compiler.
- Fix, and a boundary recommendation: **do not put this in `core`.** A `net` module importing
  `core` matches how `audio`, `pixel` and `gui` are already separated, and keeps a TLS stack and an
  HTTP parser out of the module every program links. Staged:
  1. Sockets — TCP and UDP, blocking, with addresses and DNS resolution. Winsock on Windows, BSD
     sockets elsewhere. This is the layer everything else sits on.
  2. Non-blocking and readiness notification. This is where the async design question in entry 11
     becomes unavoidable, so decide that first rather than around it.
  3. TLS. Depends on entry 6 for AES and the signature primitives. Consider binding the platform
     provider — Schannel, Secure Transport, OpenSSL — before writing one.
  4. HTTP/1.1 client, then server.

### 2. The standard library is Windows-only

- Problem: twenty-six `.win32.swg` files and zero POSIX, Linux or macOS implementations. Every
  `#os` check outside those files tests for Windows. `std/core` does not exist on another platform,
  and therefore neither does anything above it.
- What needs a peer implementation: process, filesystem (directory, file, stream, info, attributes,
  path, drives), threading (thread, mutex, rwlock, event), time (datetime, time, timer, timestamp),
  environment, errors, sandbox, hardware, console, debugger, and the input devices.
- The good news: the boundary already exists and is applied consistently. The `.win32.` suffix
  convention means the split points are already chosen and visible, so this is implementation work
  rather than a redesign. That is not a small distinction — most libraries in this position have to
  invent the abstraction first.
- The honest news: it is still the largest single body of work on this list, and it is a marathon.
  Sequence it so it does not gate the rest — a Linux port that lands one area at a time is worth
  more than one that lands all at once in a year.
- Pick the second platform deliberately. Linux is the larger audience; macOS shares more of its
  shape with what already exists through BSD sockets and Mach.

---

## Tier B — Present but too thin to use

### 3. No JSON

- Problem: `serialization` provides `ByteStream` and the reflection-driven `TagBin` binary format.
  There is no JSON, and no XML, TOML or YAML either.
- Consequence: no configuration file another tool can read or write, no web API interoperability,
  no exchange with anything outside Swag. `TagBin` is a good internal format and a useless
  interchange one.
- Fix: a JSON codec in `serialization`, declaration-driven the way `TagBin` already is. The
  reflection layer means this can be *better* than most standard libraries here rather than merely
  present — encoding a struct should need no schema and no annotations.
- This is the highest value-to-effort entry in the module. Do it before anything in Tier C.

### 4. Process control is two functions

- Problem: `system/process.swg` offers `startProcess`, `doSyncProcess` and `waitForExit`. There is
  no standard output or standard error capture, no standard input, no exit code, no kill, no
  working directory, and no environment override.
- Consequence: nothing can drive another program and read its result. Every build tool, test
  runner, formatter integration and script that shells out is blocked, which is why this
  repository's own tooling lives in `.bat` files.
- Fix: pipe redirection for the three standard streams, exit code, termination, working directory,
  and an environment block. Bounded work with immediate payoff for the repository itself.

### 5. Globalization is a stub that implies more than it delivers

- Problem: the whole area is twenty-nine lines. `CultureInfo` holds one `NumberFormatInfo`, which
  holds a negative sign, a positive sign and a decimal separator.
- Missing: thousands separators and grouping, currency formatting, per-culture date and time
  patterns, collation and locale-aware comparison, plural rules, and locale-aware case mapping.
- The concern is not the absence but the shape. A type named `CultureInfo` with a
  `currentCulture()` accessor promises a localization system and delivers three characters. Either
  grow it toward what .NET and ICU provide, or narrow the names to what it actually does.
- Related: `bin/apps` and `std/gui` now have localization work in flight on the `gui-resources`
  branch. Coordinate rather than building a second vocabulary.

### 6. Cryptography has hashes but almost no ciphers

- Present: Adler-32, CRC-32, CRC-64, MD5, SHA-1, SHA-256, HMAC-SHA-256, PBKDF2, ChaCha20, and
  several non-cryptographic hashes.
- Missing: AES — so no hardware-accelerated bulk encryption and no interoperability with the large
  amount of the world that speaks AES. Also missing: SHA-512, SHA-3, BLAKE2 and BLAKE3, Ed25519 and
  X25519 signatures and key agreement, and RSA.
- Two entries elsewhere depend on this. Entry 1 needs AES and the signature primitives before TLS
  is possible. The sCrypt roadmap asks for Argon2id and a single-pass AEAD in this same folder —
  see `bin/apps/modules/sCrypt/TODO.md` entries 4 and 5. Do them as one campaign, not three.

---

## Tier C — Coverage

### 7. Archive formats

`compress` has raw deflate, inflate and a zlib wrapper, so the hard part is done. Missing: the
gzip container, ZIP, and TAR. Reading a `.zip` is among the most common I/O tasks there is, and it
is a thin layer over what already exists. Modern codecs — Zstandard, LZ4 — are a separate and
lower-priority question.

### 8. Time zones

`time` handles UTC and local. There is no IANA zone database, no historical offsets, and no DST
rules for an arbitrary zone. Any application that schedules or displays times across regions is
stuck at the boundary.

### 9. Missing collections

Present: `Array`, `ArrayPtr`, `BitArray`, `ConcatBuffer`, `HashSet`, `HashTable`, `List`,
`StaticArray`. Missing, in order of how often they are wanted:

- An ordered map and set, so iteration is sorted and range queries are possible. Rust has
  `BTreeMap`, C++ has `std::map`; a hash table cannot substitute.
- A deque or ring buffer.
- A priority queue.

### 10. Memory-mapped files and filesystem watching

Neither exists. Memory mapping matters for any large file read — the sCrypt container is one
example already in the repository. Watching matters for any tool that reacts to edits, which
includes anything this repository would want to build around the formatter or the compiler.

### 11. Concurrency beyond parallel fan-out

`Jobs` gives parallel visiting and parallel loops, and there are atomics, mutexes, read-write locks
and events. There is no future or task type, no channels, and no condition variable. There is no
asynchronous I/O.

This is as much a language question as a library one — Go answered it with goroutines and channels,
Rust with `async` and a futures machinery that reaches into the type system, .NET with `Task`. It
should be decided deliberately and early, because entry 1 will force the question the moment
non-blocking sockets arrive, and answering it under that pressure is how libraries end up with two
concurrency models.

The language-design half is entry 4 of the language section in the root [TODO.md](../../../../TODO.md).
Record decisions there, not here.

---

## Out of scope

**A package registry client.** That belongs to the tooling around the compiler, not to the standard
library, even after entry 1 makes it possible.

**Bundling ICU.** Entry 5 should grow toward what applications need from the platform's own locale
data. Vendoring a multi-megabyte dependency into the module every program links is the wrong shape
for that need.
