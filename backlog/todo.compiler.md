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

About 241 000 lines of C++ in 653 files, and almost none of it is borrowed.

- **No LLVM, and no external toolchain on the hot path.** The backend owns its own SSA IR
  (`Backend/Micro`, 27 300 lines, 20 passes), its own x64 encoder (`Backend/Encoder`, 4 550
  lines), its own PE linker (`Backend/Linker`, 5 500 lines), its own CodeView/PDB emitter
  (`Backend/Debug`), and its own JIT (`Backend/JIT`). Nothing in this tier is a wrapper. Very few
  languages at this age own their whole path to machine code.
- **The JIT is the same code generator as the native path**, which is why `#run` executes real
  compiled code and why compile-time execution is not a second, weaker interpreter. This is the
  single largest structural advantage the compiler has, and the language is built on it.
- **The frontend is demand-driven and concurrent.** Semantic jobs park on the exact symbol state
  they need and are woken by the producer (`JobManager::wake`, with a lock-free presence filter
  over wait keys), rather than running as ordered phases. Ordering constraints that other
  compilers resolve with declaration order or forward declarations dissolve here.
- **535 diagnostics** with source snippets, notes, and help lines, driven by a message table
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

### 1. The module boundary is re-parsed Swag source

- Problem: a module's public API is emitted as generated Swag source and consumed as generated
  Swag source. `core` publishes **16 files and 12 328 lines** per configuration
  (`bin/std/.output/core/shared-library/release/x86_64/*.swg`), and every dependent module lexes,
  parses and re-analyzes all of it. There is no serialized module interface.
- Consequence: the cost of depending on a module scales with the *text of its whole public
  surface*, not with what the consumer uses. It also means no symbol-level identity survives a
  module boundary — no fingerprints, no per-symbol invalidation — which is precisely what entries
  2, 6 and 8 need to exist.
- Fix: a binary module interface written at the end of a successful build — symbols, types,
  constants, attribute payloads, and the bodies that must stay inlinable — loaded lazily by name
  rather than parsed wholesale. Keep the generated `.swg` as a *product* (`--export-api-dir` is a
  real deliverable for interop and for reading), not as the internal channel.
- Sequence it deliberately: the interface format is also what makes a language server affordable,
  so design it with entry 8 in the room rather than retrofitting.

### 2. Incrementality stops at the module

- Problem: up-to-date detection compares the module manifest's write time against its inputs
  ([CompilerInstance.Module.cpp:1060-1064](../src/Main/CompilerInstance.Module.cpp#L1060-L1064)). The unit of
  work is the module. Editing one line of one file rebuilds all 291 files of `core`.
- Consequence: the inner loop of anyone working in `bin/std` or `bin/apps` is a full module
  rebuild — 2.1 s for `core`, more for `gui` — for a one-character change. rustc caches at query
  granularity, Zig is incremental at function granularity, and even C++ is incremental per
  translation unit. Swag is the coarsest of the four.
- Fix, staged: (1) cache the frontend per file, keyed on content hash plus the interface version
  of everything it imports; (2) cache codegen per function, keyed on the sema fingerprint of its
  body and of everything it reaches. Step 2 is where the win is, and it is unreachable without
  entry 1.
- Measure before and after with entry 7, on a real edit-one-file-in-`core` loop, not on a clean
  build.

### 3. The semantic analyzer is 80 000 lines with one unit test

- Problem: `Compiler/Sema` is 80 812 lines across 150 files — a third of the compiler. Its entire
  C++ test surface is `src/Unittest/Sema`, a single 116-line purity test. Everything else is
  covered end to end through the `.swg` suites.
- Consequence: the suites prove that programs compile; they cannot address one decision procedure.
  Overload ranking ([Match.Func.cpp](../src/Compiler/Sema/Match/Match.Func.cpp), 3 232 lines), cast
  legality (`Sema/Cast`), and generic deduction
  ([SemaGeneric.Deduce.cpp](../src/Compiler/Sema/Generic/SemaGeneric.Deduce.cpp), 1 778 lines) are
  pure, deterministic, table-shaped functions with no unit tests at all. That is the reason
  refactoring sema feels dangerous, and "ultra-clean architecture" is not reachable through code
  nobody dares to move.
- Fix: those three first, as table-driven C++ suites — a list of (inputs, expected ranking) rows,
  not compiled programs. `src/Unittest/Format` (5 225 lines) and `src/Unittest/Micro` (4 874
  lines) already show the shape and already carry the subsystems that get refactored most freely.
- This is the cheapest entry in Tier A and the one that makes the other two safe.

---

## Tier B — Speed and memory

### 4. Nothing tracks compile speed except one four-line program

This entry is first in the tier because the three below cannot be judged without it.

- Problem: `bench/` measures the *generated code* against fourteen runtimes, thoroughly. The only
  compiler-side numbers in `bench/history.json` are `hello_build_ms` and `hello_build_peak_mb` —
  one four-line program. Nothing measures a real module, a warm rebuild, or the edit-one-file loop.
- Consequence: across eleven campaigns since 2026-07-31, hello-world build time reads 92, 61, 74,
  68, 74, 64, 66, 85, 81, 95, 67 ms and peak memory sits flat at 96–98 MB. That is noise around a
  flat line, on a workload too small to contain what actually costs. A campaign cannot currently
  tell whether the compiler got faster.
- Also: the per-stage instrumentation exists but is compiled out. `Stats` carries lexer, parser,
  sema, codegen and Micro timings plus AST, type, symbol and instruction counts
  ([Stats.h:20-59](../src/Main/Stats.h#L20-L59)), all behind `SWC_HAS_STATS`, which only the separate
  `Stats` build configuration defines ([pch.h:77-81](../src/pch.h#L77-L81)). In the shipped binary
  `--stats` prints four lines: workers, total time, peak memory.
- Fix: add compiler-side workloads to the campaign — a full `core` rebuild, a warm no-op build, and
  a one-file-touched rebuild — recording wall time and peak working set for each. Then decide
  whether the per-stage counters should be available in the Release binary behind a flag, since a
  profile nobody can take on the shipping build is a profile nobody takes.

### 5. Peak memory is 672 MB for one module

- Problem: rebuilding `core` — 50 690 lines — peaks at **671.9 MB** of working set in fast-debug
  and about 490 MB in release. That is roughly 13 KB of resident memory per source line. Hello
  world peaks at **81.6 MB**.
- Consequence: it bounds how many modules can ever be compiled concurrently (entry 7 multiplies
  this number), and it is felt directly on any machine that is not this one. A language that wants
  to be run as a script cannot ask for 80 MB to print one line.
- Fix: measure first — there is no per-subsystem memory accounting today, only an OS peak, so the
  split between AST, types, symbols, constants and Micro is currently unknown. `MemoryProfile`
  exists but is behind the same `SWC_HAS_STATS` gate as everything else in entry 4. Then attack
  what the measurement shows. Two suspects worth checking early: nothing is released between
  stages, so post-codegen the whole AST and every Micro function are still resident; and
  per-function Micro state is retained for the whole module rather than freed as each function
  finishes.

### 6. Every invocation re-analyzes the prelude

- Problem: before touching a single line of user code, a build analyzes **8 files, 19 494 tokens
  and 237 functions** — the runtime prelude. Measured on an empty module: `checked 8 files •
  19_494 tokens`, and on hello world the frontend alone is 28–39 ms of a ~90 ms run.
- Consequence: that is the floor under every `swc` invocation, including every script run, every
  editor save if entry 8 ever lands, and every one of the thousands of test compilations in the
  suites.
- Fix: this is entry 1 applied to the prelude — serialize the analyzed prelude once and map it in,
  instead of re-deriving it. Do it after entry 1 rather than as a special case, or the compiler
  ends up with two module-loading mechanisms.

### 7. Modules build one at a time

- Problem: the job system parallelizes aggressively *within* a module — files, functions, jobs
  parked on symbol states — but the workspace scheduler runs modules serially. A `core` build
  prints `win32 139 ms`, `xinput 76 ms`, `core 2 s 075 ms` inside a 2 s 539 ms workspace build:
  the three module times run back to back and account for nearly all of it.
- Consequence: in a real workspace the independent modules are the big ones — `pixel`, `gui`,
  `audio` and `truetype` all depend on `core` and on nothing else — and they are compiled one
  after another on a machine with 22 workers.
- Fix: schedule modules on the dependency DAG instead of in sequence, sharing one job manager so
  the worker pool is not oversubscribed. The `compile-speed` branch already prototypes this;
  finish it against entry 5's memory number, because N concurrent modules multiply peak memory
  by N.

---

## Tier C — What sits around the compiler

### 8. There is no language server

- Problem: the VSCode extension contributes a TextMate grammar, themes, a task provider and a
  problem matcher — 90 lines of JavaScript. No completion, no go-to-definition, no hover, no
  rename, no diagnostics while typing. Every other language in the comparison set has one
  (rust-analyzer, gopls, ZLS, clangd).
- Consequence: the compiler already computes everything an editor wants — types, symbols,
  overload resolution, source ranges — and throws it away at process exit. The gap is not
  knowledge, it is that nothing can ask.
- Evidence that the editor path is currently unowned: the extension's own tasks shell out to a
  binary named `swag` with `-w:` and `-f:` argument syntax
  ([providers.js:23-25](../vscode/src/providers.js#L23-L25)); the binary is `swc` and the current
  parser rejects that syntax outright (`unknown command-line argument '-f:...'`).
- Fix: LSP is a consumer of entries 1 and 2, not a parallel project. A server that must re-analyze
  every dependency's 12 000 lines of generated source on each keystroke is not viable, and one
  with a serialized interface and per-file caching mostly falls out. Sequence it accordingly, and
  fix the extension's task commands now regardless.

---

### 9. A script is not yet a full substitute for a shell script

A `.swgs` should replace a `.bat`, a `.ps1` or a `.py` outright: as simple to run, and more
capable. It is close. Three gaps are left, and `tools/` is the proof either way — it is the
repository's own scripting, and it still carries batch launchers because of them.

- **A missing `swag@std` stops everything.** `resolveSwagStdOutputRoot` resolves
  `<SWAG_PATH>/std/.output` and fails when it is absent, so a fresh clone runs no script at all
  until the library is built by hand. Build the dependency on demand instead of refusing: it is
  the difference between `python script.py` and a script that first asks for an install step.
- **A script cannot say which files it is made of, once.** `#load` does not nest — a file
  reached by `#load` cannot `#load` another, and the paths resolve against the entry script. A
  script spread over several sources therefore repeats the whole list in every entry point,
  where a Python script says `import` once. Either make `#load` nest and resolve relative to the
  loading file, or give a script a module file of its own.
- **Nothing associates `.swgs` with the compiler.** Double-clicking one should run it.
  `Env.associateFileExtension` already exists; what is missing is the registration step and a
  rule for which compiler answers. The one worth having: in script mode, a `swc.exe` sitting
  beside the script wins over the one on the path, so dropping a known-good compiler next to a
  set of scripts pins them with no ceremony at all.

Two pieces already landed and are what makes the rest worth finishing: a script takes its own
command line, and the compiler recognizes it wherever it sits.

## Out of scope

**Adopting LLVM.** The self-contained path to machine code — encoder, linker, debug info, JIT — is
what makes `#run` execute real compiled code and what keeps the compiler a single binary with no
toolchain to install. Every entry above is compatible with keeping it; none of them is a reason to
give it up.

**A package registry.** Dependency resolution is path-based today and that is a tooling question,
not a compiler one. [todo.core.md](todo.core.md) already places the client side outside the
standard library; the registry itself is a separate product, and it is gated on that file's entry 1
anyway.

**A second frontend.** The demand-driven job model in sema is the compiler's other structural
advantage, and it is not compatible with a conventional phase-ordered rewrite. Improve it in place.
