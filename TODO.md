# Compiler Roadmap

This file is the roadmap for `swc` — the compiler, its `doc` and `format` commands, and the Swag
language itself — measured against what it competes with: rustc and cargo, the Go toolchain, Zig,
Clang, D, and the self-hosted tier of Jai and Odin.

It is not the repository's discovery backlog. Defects, suspicious behavior, and leads found while
doing something else belong in [FINDINGS.md](FINDINGS.md), which holds evidence; this file holds
intent. Module-level intent under `bin` lives in `bin/std/modules/<module>/TODO.md` and
`bin/apps/modules/<app>/TODO.md`.

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
- **A `format` command with about 140 options** and a cascading `.swc-format`, and a `doc`
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
  ([CompilerInstance.Module.cpp:1060-1064](src/Main/CompilerInstance.Module.cpp#L1060-L1064)). The unit of
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
  Overload ranking ([Match.Func.cpp](src/Compiler/Sema/Match/Match.Func.cpp), 3 232 lines), cast
  legality (`Sema/Cast`), and generic deduction
  ([SemaGeneric.Deduce.cpp](src/Compiler/Sema/Generic/SemaGeneric.Deduce.cpp), 1 778 lines) are
  pure, deterministic, table-shaped functions with no unit tests at all. That is the reason
  refactoring sema feels dangerous, and "ultra-clean architecture" is not reachable through code
  nobody dares to move.
- Fix: those three first, as table-driven C++ suites — a list of (inputs, expected ranking) rows,
  not compiled programs. `src/Unittest/Format` (5 043 lines) and `src/Unittest/Micro` (4 874
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
  ([Stats.h:20-59](src/Main/Stats.h#L20-L59)), all behind `SWC_HAS_STATS`, which only the separate
  `Stats` build configuration defines ([pch.h:77-81](src/pch.h#L77-L81)). In the shipped binary
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
  ([providers.js:23-25](vscode/src/providers.js#L23-L25)); the binary is `swc` and the current
  parser rejects that syntax outright (`unknown command-line argument '-f:...'`).
- Fix: LSP is a consumer of entries 1 and 2, not a parallel project. A server that must re-analyze
  every dependency's 12 000 lines of generated source on each keystroke is not viable, and one
  with a serialized interface and per-file caching mostly falls out. Sequence it accordingly, and
  fix the extension's task commands now regardless.

---

## The `doc` command

Measured against rustdoc and docs.rs, godoc and pkg.go.dev, Doxygen, Sphinx, DocFX, and Zig's
autodoc.

Where it stands: 4 598 lines produce a complete static site — API pages collected from the
semantic model, guide pages from module comments, a symbol index, themes, brand and navigation
options, cross-module references, source links back to the repository, and a Markdown renderer
with headings, lists, tables, blockquote callouts and syntax-highlighted Swag code. It emits no
script and needs no server, deliberately
([DocPage.cpp:14](src/Doc/DocPage.cpp#L14)). The repository's own documentation is generated by it.

### 1. Code examples in documentation are rendered, never compiled

- Every ```` ```swag ```` fence goes through `DocMarkdown::renderCodeBlock`, which syntax-colors it
  and stops there. Nothing compiles it. The `truetype` module header carries a nine-line worked
  example ([module.swg](bin/std/modules/truetype/module.swg)) that no build checks.
- rustdoc compiles and runs every example as a test; Go compiles `Example` functions and checks
  their output. It is the reason their documentation does not rot.
- Swag is unusually well placed here: `#test` exists, and `#run` executes real compiled code, so a
  doc example is one synthesized test function away. This would turn every example in `bin/` from
  a liability into coverage.
- This is the highest value-to-effort entry in the command.

### 2. There is no search

- The symbol index is a static list. Finding a function means knowing its module or using the
  browser's find-in-page.
- rustdoc's fuzzy search is the single most-used feature of docs.rs, and it is a prebuilt static
  index plus a small script — no server. That directly contradicts the no-script rule, so the rule
  is the decision, not the implementation: either accept one self-contained script for search, or
  accept that the documentation is not navigable above a few hundred symbols.

### 3. There is no documentation model, only rendered HTML

- The pipeline collects `DocItem`/`DocOverload` ([DocTypes.h](src/Doc/DocTypes.h)) and renders
  straight to HTML. Nothing else can consume it.
- rustdoc emits JSON and Doxygen emits XML, which is how API-diffing, coverage reports, and
  third-party doc sites exist for those languages. Swag has a genuine half of this already —
  `--export-api-dir` publishes the public surface as Swag source — so what is missing is narrow:
  a stable serialization of *items plus their documentation and links*.
- Two things fall out of it immediately: a public-API diff between two revisions, and a
  documentation-coverage report, which today does not exist in any form — no warning names an
  undocumented public symbol.

---

## The `format` command

Measured against clang-format, rustfmt, gofmt, prettier, black and `zig fmt`.

Where it stands: 8 328 lines, about 140 options covering whitespace, indentation, wrapping,
braces, switch layout, alignment (including two-column declaration grids), spacing, attributes,
comments, `using` blocks and numeric literals; a cascading `.swc-format` resolved from the file's
directory upward with parent inheritance
([FormatOptionsLoader.cpp:289-317](src/Format/FormatOptionsLoader.cpp#L289-L317)); `swc-format
off`/`on` regions; nine passes over a token-and-AST model; and 5 043 lines of C++ tests, the
best-tested subsystem in the compiler. On option count it is already in clang-format's league.

### 1. It cannot be used in CI, and cannot be used by an editor

Three missing modes, all small, all blocking real use.

- **No check mode.** There is no `--check`, no `--list-different`, no diff output, and no exit-code
  contract for "this file was not formatted". clang-format has `--dry-run -Werror`, rustfmt
  `--check`, gofmt `-l` and `-d`, prettier `--check`. Without it, formatting cannot be enforced on
  a branch — which is exactly what a canonical style needs.
- **No stdin/stdout.** The command reads paths and writes files back in place. Every editor
  integration wants to format a buffer that may not be on disk, and to receive the result rather
  than have the file rewritten under it.
- **No range formatting.** clang-format has `--lines` and `--offset/--length`; rustfmt and
  prettier have equivalents. Format-selection is the interaction people actually use.

### 2. There is no canonical Swag style

- Every option defaults to `Preserve`. Out of the box the formatter normalizes almost nothing;
  the repository's own style lives in `bin/.swc-format`.
- gofmt, black and `zig fmt` owe their adoption to the opposite choice: one style, no options, no
  argument. Swag currently offers the configurability of clang-format without the default that
  makes a formatter a community norm.
- Fix: publish the repository's own profile as the built-in default (a named `--style` with the
  current `Preserve`-everything behavior kept as an explicit opt-out). This is a policy decision
  first and a small code change second, and it should be made before the option count grows again.

### 3. Wrapping is greedy, and files that do not parse are skipped

- There is no penalty model or layout solver anywhere in `src/Format` — `Pass.Wrap.cpp` decides
  per construct, locally. clang-format solves a penalty function over the whole unwrapped line and
  prettier searches a Wadler-style document for the best fit. On dense nested expressions that
  difference is visible.
- Separately, a file that fails to parse is counted and skipped
  ([FormatJob.cpp:40](src/Format/FormatJob.cpp#L40)). clang-format formats broken files because it
  works on tokens — which is what makes format-on-type possible.
- Neither is necessarily worth matching. Both should be a stated position rather than an
  unexamined limit: decide whether the formatter's contract is "valid files, locally good layout"
  and write that down, or invest in the solver.

---

## The language

Open compiler defects and language-rule inconsistencies with evidence — the folded `typeinfo ==`
that disagrees with the runtime comparison, nullability that does not survive a reference,
`#[Swag.Tls]` accepted and ignored — are in [FINDINGS.md](FINDINGS.md) and are not repeated here.
This section holds design questions that are open by choice rather than by accident.

### 1. Enum switches are silently non-exhaustive

- A `switch` over a three-value enum that handles two of them compiles with no error, no warning,
  and no `default`; the third value simply falls through to nothing. Exhaustiveness exists but is
  opt-in through `switch #complete`
  ([005_005_switch.swg:178](bin/reference/modules/language/src/005_005_switch.swg#L178)).
- Every language that made exhaustiveness the default — Rust, Swift, Kotlin, and Zig for tagged
  unions — did so because the failure is invisible at the time it is introduced and shows up when
  a value is *added* to the enum later, in code nobody re-read.
- The decision to make: whether `#complete` should be the default for enum switches, with an
  explicit `else` as the opt-out. That is a breaking change with a mechanical migration, and it
  depends on entry 9 above — without a warning policy, the only options are "error" and "silence".

### 2. There is no tagged union

- `union` is C-style and untagged: all fields share offset 0 and reading a field that was not the
  one written is legal and meaningless
  ([004_006_union.swg](bin/reference/modules/language/src/004_006_union.swg)). `any` covers the
  dynamic case. There is nothing in between — no discriminated union, no payload-carrying enum,
  no destructuring in `case`.
- Consequence: a sum type has to be hand-encoded as a tag next to an untagged union, and the
  invariant lives in a comment. `pixel`'s painter command is exactly that — `id: CommandId`
  followed by `using params: union`, documented as "Command-specific payload selected by `id`;
  inactive members must not be read"
  ([painter.swg:147-149](bin/std/modules/pixel/src/painter/painter.swg#L147-L149)). Nothing
  checks that sentence. Rust, Swift, Zig and modern C# all consider the checked version table
  stakes; it is arguably the single largest expressiveness gap in the language.
- It interacts with entry 1 (a tagged union is where exhaustive matching earns its keep) and with
  the error-handling design already shipped (`fail`/`try`/`catch`), which chose a different axis
  and should not be re-litigated by the same feature.

### 3. Generic constraints are predicates, and the instantiation chain omits the call site

- `where` is a compile-time boolean over generic parameters
  ([009_003_where_constraints.swg](bin/reference/modules/language/src/009_003_where_constraints.swg)).
  There is no way to state "T must provide `scaled`", so a body that uses a missing member fails
  at instantiation, C++-template style, rather than at the declaration that violates a contract.
- The diagnostic is already better than most: it reports the error inside the generic *and*
  attaches a note naming the specialization (`while checking generic function 'doubleIt' with
  T = Point`). What it does not do is name the call site that caused the instantiation — the one
  line the user has to change. Adding that frame to the instantiation chain is a small, immediate
  win, and it should be done before any decision on named constraints.
- The larger question — named contracts versus predicates — should be answered after the call-site
  frame lands, since a good instantiation trace removes most of the pain that motivates contracts.

### 4. The concurrency model is undecided

- There is no future or task type, no channels, and no condition variable; `Jobs` provides parallel
  fan-out and there is no asynchronous I/O. The library half of this is `std/core` roadmap entry
  11; the language half is here, and it is the half that must be decided first.
- Go answered with goroutines and channels, Rust with `async` and a futures machinery that reaches
  into the type system, .NET with `Task`. Each answer changed the language, not just the library.
- The forcing function is already scheduled: `std/core` roadmap entry 1 puts non-blocking sockets
  on the path, and deciding this *under* that pressure is how languages end up with two concurrency
  models. Decide it early and deliberately, and record the decision here.

### 5. Where the safety story ends is undecided

- Shipped and coherent: move semantics, `#move`/`#fwd`/`#relocate`, use-site nullability with
  narrowing and the postfix `!`, `= undefined` definite assignment, `#late` fields, and a static
  sanity layer that proves division by zero, overflow, null dereference and constant out-of-bounds
  indexing at compile time.
- Open: borrow-escape checking reports as errors, but through the sanity layer, which is togglable
  per module, per file and per function (`#[Swag.Sanity]`, `buildCfg.sanityGuards`). So whether a
  program is accepted depends on an attribute. That is the right shape for an analysis and the
  wrong shape for a language rule, and Swag has not said which one this is.
- The decision to make: name the subset of these checks that is part of the language — always on,
  not togglable, and specified in the reference — and leave the rest explicitly as tooling. Rust
  drew that line at the borrow checker and it is the reason its guarantee means something. The
  warning policy layer this needed now exists (`#[Swag.Warning]`, `cfg.warnings`, `--warn-*`), so
  the remaining work is the decision, not the mechanism.

---

## Out of scope

**Adopting LLVM.** The self-contained path to machine code — encoder, linker, debug info, JIT — is
what makes `#run` execute real compiled code and what keeps the compiler a single binary with no
toolchain to install. Every entry above is compatible with keeping it; none of them is a reason to
give it up.

**A package registry.** Dependency resolution is path-based today and that is a tooling question,
not a compiler one. `std/core`'s roadmap already places the client side outside the standard
library; the registry itself is a separate product, and it is gated on `core` entry 1 anyway.

**A second frontend.** The demand-driven job model in sema is the compiler's other structural
advantage, and it is not compatible with a conventional phase-ordered rewrite. Improve it in place.
