# Compiler Roadmap

This file is the roadmap for `swc` itself — the frontend, the backend, and what sits around them —
measured against what it competes with: rustc and cargo, the Go toolchain, Zig, Clang, D, and the
self-hosted tier of Jai and Odin. The two commands the compiler also ships have their own files,
[todo.doc.md](todo.doc.md) and [todo.format.md](todo.format.md), and the language itself is
[todo.language.md](todo.language.md).

It is not the repository's discovery backlog. Defects, suspicious behavior, and leads found while
doing something else belong in the `findings.*` files, which hold evidence; this file holds intent.
[README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

Every number below was measured on the current tree with the Release `swc.exe`, on a 22-worker
machine, and is reproducible with the command quoted next to it. Re-measure before acting: an
entry justified by a number nobody re-checked is a guess.

## Where the compiler already stands

About 243 500 lines of project-owned C++ in 667 files, and almost none of it is borrowed.

- **No LLVM, and no external toolchain on the hot path.** The backend owns its own SSA IR
  (`Backend/Micro`, 31 746 lines, 23 passes), its own x64 encoder (`Backend/Encoder`, 4 614
  lines), its own PE linker (`Backend/Linker`, 5 509 lines), its own CodeView/PDB emitter
  (`Backend/Debug`), and its own JIT (`Backend/JIT`). Nothing in this tier is a wrapper. Very few
  languages at this age own their whole path to machine code.
- **The JIT is the same code generator as the native path**, which is why `#run` executes real
  compiled code and why compile-time execution is not a second, weaker interpreter. This is the
  single largest structural advantage the compiler has, and the language is built on it.
- **The frontend is demand-driven and concurrent.** Semantic jobs park on the exact symbol state
  they need and are woken by the producer (`JobManager::wake`, with a lock-free presence filter
  over wait keys), rather than running as ordered phases. Ordering constraints that other
  compilers resolve with declaration order or forward declarations dissolve here.
- **538 diagnostics** with source snippets, notes, and help lines, driven by a message table
  (`Support/Report/Msg`) rather than scattered string literals. Each one is named, and a warning's
  name is what the three policy layers address it by.
- **A `format` command with 130 options** and a cascading `.swc-format`, and a `doc`
  command that renders a full documentation site with no script and no server.
- Throughput today: `std/core` — 291 files, 50 690 lines — rebuilds in **2.1 s** in fast-debug
  (`swc build --workspace bin/std --workspace-module core --rebuild --stats`). A hello-world
  script runs end to end in **~90 ms**.

The gaps are not in capability. They are in the module boundary, in what the compiler keeps in
memory, and in everything an editor would want to ask it.

---

## Tier A — Architecture

These three shape every other entry. Nothing below Tier A gets structurally easier until they land.

### T-001 — The module boundary is re-parsed Swag source

- Problem: a module's public API is emitted as generated Swag source and consumed as generated
  Swag source. `core` publishes **16 files and 12 328 lines** per configuration
  (`bin/std/.output/core/shared-library/release/x86_64/*.swg`), and every dependent module lexes,
  parses and re-analyzes all of it. There is no serialized module interface.
- Consequence: the cost of depending on a module scales with the *text of its whole public
  surface*, not with what the consumer uses. It also means no symbol-level identity survives a
  module boundary — no fingerprints, no per-symbol invalidation — which is precisely what
  T-002, T-006 and T-008 need to exist.
- Fix: a binary module interface written at the end of a successful build — symbols, types,
  constants, attribute payloads, and the bodies that must stay inlinable — loaded lazily by name
  rather than parsed wholesale. Keep the generated `.swg` as a *product* (`--export-api-dir` is a
  real deliverable for interop and for reading), not as the internal channel.
- Sequence it deliberately: the interface format is also what makes a language server affordable,
  so design it with T-008 in the room rather than retrofitting.

### T-002 — Incrementality stops at the module

- Problem: up-to-date detection compares the module manifest's write time against its inputs
  ([CompilerInstance.Module.cpp:1060-1064](../src/Main/CompilerInstance.Module.cpp#L1060-L1064)). The unit of
  work is the module. Editing one line of one file rebuilds all 291 files of `core`.
- Consequence: the inner loop of anyone working in `bin/std` or `bin/apps` is a full module
  rebuild — 2.1 s for `core`, more for `gui` — for a one-character change. rustc caches at query
  granularity, Zig is incremental at function granularity, and even C++ is incremental per
  translation unit. Swag is the coarsest of the four.
- Fix the frontend boundary first: cache analysis per file, keyed on content hash plus the
  interface version of everything it imports.
- Measure before and after with T-007, on a real edit-one-file-in-`core` loop, not on a clean
  build.
- Related: T-001, T-122

### T-122 — Code generation is not incremental per function

Cache code generation per function, keyed on the semantic fingerprint of its body and everything
it reaches. This is independently measurable after T-001 and T-002 establish persistent symbol and
frontend identities.

- Related: T-001, T-002, T-004

### T-003 — Overload ranking has no focused unit tests

- Problem: `Compiler/Sema` is 81 189 lines across 150 files — a third of the compiler. Its entire
  C++ test surface is `src/Unittest/Sema`, a single 116-line purity test. Everything else is
  covered end to end through the `.swg` suites.
- Consequence: the suites prove that programs compile; they cannot address one decision procedure.
  Overload ranking ([Match.Func.cpp](../src/Compiler/Sema/Match/Match.Func.cpp), 3 232 lines) is a
  deterministic, table-shaped function with no focused unit tests.
- Add table-driven C++ rows for inputs and expected ranking, following the focused suite shape in
  `src/Unittest/Format` and `src/Unittest/Micro`.
- This is the cheapest entry in Tier A and the one that makes the other two safe.
- Related: T-335, T-336

### T-335 — Cast legality has no focused unit tests

Add table-driven C++ coverage around `Sema/Cast` so conversion rules can be changed without relying
only on compiled source suites.

- Related: T-003, T-336

### T-336 — Generic deduction has no focused unit tests

Add table-driven C++ coverage for
[SemaGeneric.Deduce.cpp](../src/Compiler/Sema/Generic/SemaGeneric.Deduce.cpp), independently of
overload-ranking and cast tests.

- Related: T-003, T-335

---

## Tier B — Speed and memory

### T-004 — Nothing tracks compile speed except one four-line program

This entry is first in the tier because the three below cannot be judged without it.

- Problem: `bench/` measures the *generated code* against fourteen runtimes, thoroughly. The only
  compiler-side numbers in `bench/history.json` are `hello_build_ms` and `hello_build_peak_mb` —
  one four-line program. Nothing measures a real module, a warm rebuild, or the edit-one-file loop.
- Consequence: across eleven campaigns since 2026-07-31, hello-world build time reads 92, 61, 74,
  68, 74, 64, 66, 85, 81, 95, 67 ms and peak memory sits flat at 96–98 MB. That is noise around a
  flat line, on a workload too small to contain what actually costs. A campaign cannot currently
  tell whether the compiler got faster.
- Fix: add compiler-side workloads to the campaign — a full `core` rebuild, a warm no-op build, and
  a one-file-touched rebuild — recording wall time and peak working set for each. Then decide
  explicit regression gates from those stable workloads.
- Related: T-123

### T-123 — Release builds hide per-stage compiler profiling

`Stats` already carries lexer, parser, sema, codegen and Micro timings plus AST, type, symbol and
instruction counts ([Stats.h:20-59](../src/Main/Stats.h#L20-L59)), but `SWC_HAS_STATS` restricts them
to the separate `Stats` configuration ([pch.h:77-81](../src/pch.h#L77-L81)). Make the useful
counters available on demand in the shipped binary with measured disabled-mode overhead.

- Related: T-004, T-005

### T-005 — Peak memory is 672 MB for one module

- Problem: rebuilding `core` — 50 690 lines — peaks at **671.9 MB** of working set in fast-debug
  and about 490 MB in release. That is roughly 13 KB of resident memory per source line. Hello
  world peaks at **81.6 MB**.
- Consequence: it bounds how many modules can ever be compiled concurrently (T-007 multiplies
  this number), and it is felt directly on any machine that is not this one. A language that wants
  to be run as a script cannot ask for 80 MB to print one line.
- Fix: measure first — there is no per-subsystem memory accounting today, only an OS peak, so the
  split between AST, types, symbols, constants and Micro is currently unknown. `MemoryProfile`
  exists but is behind the same `SWC_HAS_STATS` gate as everything else in T-004. Then attack
  what the measurement shows. Two suspects worth checking early: nothing is released between
  stages, so post-codegen the whole AST and every Micro function are still resident; and
  per-function Micro state is retained for the whole module rather than freed as each function
  finishes.

### T-006 — Every invocation re-analyzes the prelude

- Problem: before touching a single line of user code, a build analyzes **8 files, 19 494 tokens
  and 237 functions** — the runtime prelude. Measured on an empty module: `checked 8 files •
  19_494 tokens`, and on hello world the frontend alone is 28–39 ms of a ~90 ms run.
- Consequence: that is the floor under every `swc` invocation, including every script run, every
  editor save if T-008 ever lands, and every one of the thousands of test compilations in the
  suites.
- Fix: this is T-001 applied to the prelude — serialize the analyzed prelude once and map it in,
  instead of re-deriving it. Do it after T-001 rather than as a special case, or the compiler
  ends up with two module-loading mechanisms.

### T-007 — Modules build one at a time

- Problem: the job system parallelizes aggressively *within* a module — files, functions, jobs
  parked on symbol states — but the workspace scheduler runs modules serially. A `core` build
  prints `win32 139 ms`, `xinput 76 ms`, `core 2 s 075 ms` inside a 2 s 539 ms workspace build:
  the three module times run back to back and account for nearly all of it.
- Consequence: in a real workspace the independent modules are the big ones — `pixel`, `gui`,
  `audio` and `truetype` all depend on `core` and on nothing else — and they are compiled one
  after another on a machine with 22 workers.
- Fix: schedule modules on the dependency DAG instead of in sequence, sharing one job manager so
  the worker pool is not oversubscribed. The `compile-speed` branch already prototypes this;
  finish it against T-005's memory number, because N concurrent modules multiply peak memory
  by N.

---

## Tier C — What sits around the compiler

### T-008 — There is no language server

- Problem: the VSCode extension contributes a TextMate grammar, themes, a task provider and a
  problem matcher, but no persistent protocol server or diagnostics while typing.
- Consequence: the compiler already computes everything an editor wants — types, symbols,
  overload resolution, source ranges — and throws it away at process exit. The gap is not
  knowledge, it is that nothing can ask.
- Fix: LSP is a consumer of T-001 and T-002, not a parallel project. A server that must re-analyze
  every dependency's 12 000 lines of generated source on each keystroke is not viable, and one
  with a serialized interface and per-file caching mostly falls out. Sequence it accordingly, and
  keep the protocol surface independent of the VSCode client.
- Related: T-001, T-002, T-124, T-337, T-338, T-339, T-340

### T-337 — No editor completion service

Expose scope- and type-aware completion through the language server after T-008 establishes the
persistent analysis session.

- Related: T-008

### T-338 — No go-to-definition service

Resolve an identifier at a source position to its declaration across files and serialized module
interfaces.

- Related: T-001, T-008

### T-339 — No editor hover service

Return the resolved symbol's type, signature, and documentation without making hover part of
completion.

- Related: T-008, T-015

### T-340 — No semantic rename service

Compute and validate workspace edits for one symbol identity, respecting scopes, generated code,
and cross-module references.

- Related: T-001, T-008

### T-124 — The VSCode task provider invokes a nonexistent compiler interface

The extension shells out to `swag` with `-w:` and `-f:` arguments
([providers.js:23-25](../vscode/src/providers.js#L23-L25)); the binary is `swc` and its parser rejects
that syntax. Update the task provider to the current command-line contract independently of any
language-server work.

- Related: T-008

---

### T-102 — A script's bare name is not a shell command

`setup.swgs` claims `.swgs` for the current user, so double-click works, but
`tools\tests.swgs dm` is not directly executable from `cmd` or PowerShell 5.1. Define a reliable
installation and relocation contract for the association, including elevated machine-wide setup,
`PATHEXT`, and a clear report when the shell integration cannot be installed.

- Related: T-125

### T-125 — Every script invocation recompiles unchanged inputs

`swc tools/tests.swgs plan <file>` and `-h` each take about 650 ms warm because every run rechecks
the same 46 files and roughly 148,000 tokens. Cache a script compilation from the complete loaded
input set that module setup already collects, and invalidate it by content and compiler inputs.

- Related: T-002, T-006, T-102

## Out of scope

**Adopting LLVM.** The self-contained path to machine code — encoder, linker, debug info, JIT — is
what makes `#run` execute real compiled code and what keeps the compiler a single binary with no
toolchain to install. Every entry above is compatible with keeping it; none of them is a reason to
give it up.

**A package registry.** Dependency resolution is path-based today and that is a tooling question,
not a compiler one. [todo.core.md](todo.core.md) already places the client side outside the
standard library; the registry itself is a separate product, and it is gated on T-027
anyway.

**A second frontend.** The demand-driven job model in sema is the compiler's other structural
advantage, and it is not compatible with a conventional phase-ordered rewrite. Improve it in place.
