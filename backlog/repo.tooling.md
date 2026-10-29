# Tooling Backlog

The build, the sandbox, and the test harness — everything that surrounds the compiler rather than
being compiled by it.

[README.md](README.md) defines the shared backlog conventions.

### repo.tooling.011 — No validation step compiles the Swag benchmark modules

- Evidence: `tools/build.bat` covers std, examples, apps, and the reference. Nothing in the
  build or test launchers compiles the eleven
  `bench/*/module.swg` modules, so a language or std change can break them unnoticed.
  `argon2`, `chacha20`, and `resize` are test-only modules meant for
  `test --no-test-jit -bc release`. Their JIT run trips the `Swag.workerCount()` assertion,
  so a compile check must not execute them.
- Next: give `build.bat` a benchmark step: `sema --module` for program modules, and a compile
  of the test-only modules that runs none of their timed `#test` bodies (a compiler option to
  build a test executable without running it, or a dedicated tag), in each configuration.
- Done when: breaking any `bench/*/module.swg` source fails `tools/build.bat`.

### repo.tooling.002 — A video differential harness must line pictures up by time, not by rank

- Evidence: FFmpeg numbers the pictures it emits densely, while `std/video` numbers them as the
  container does. The two diverge wherever a sample produces no picture: a plane that codes
  nothing, a skipped leading picture, or an access unit before the first one that can be
  reconstructed. Pairing by ordinal reported defects that vanished when pictures were paired
  by presentation time. No differential harness against an external decoder is checked in;
  the video tests only compare against reference planes such as
  `bin/std/modules/video/src/tests/datas/ffmpeg-h264-baseline.yuv`.
- Next: check in an opt-in differential harness that decodes a media file with an external
  reference decoder, records each reference picture's presentation time, and asks this reader
  for the rank carrying that time before comparing decoded pixels.
- Done when: the checked-in harness pairs decoded pictures by presentation time rather than
  ordinal, a reproducible case with a non-picture sample compares without manual alignment,
  and a mismatched decoded picture still fails the comparison.

### repo.tooling.010 — Separate cross-language build scenarios from compiler throughput

- Evidence: since protocol 3 every toolchain is timed in one recorded state, a warm toolchain
  and a clean project (Go's standard library and Zig's global cache warm, Swag's runtime
  machine code warm), with intervals. C++ still reparses headers, including unused `<cmath>`
  through `src/cpp/common.h`, Swag collects its runtime sources even for hello, and the report
  combines native executable builds with Java and C# bytecode generation: valid recipe timings,
  not equal compiler workloads.
- Next: define versioned scenarios for application rebuilds with prepared dependencies,
  dependency rebuilds, and a real source edit. Keep bytecode and native outputs distinct.
  Add a separate generated-code workload at several sizes, with equivalent operations and
  minimal imports, and time semantic checking, object generation, and linking where supported.
  Record cache policy, flags, worker counts, repetitions and dispersion with every scenario;
  retain old campaigns under their original protocol rather than reinterpreting them.
- References: [compiler-benchmark](https://github.com/nordlow/compiler-benchmark) separates
  synthetic checking, compilation and linking;
  [rustc-perf](https://github.com/rust-lang/rustc-perf/blob/main/collector/README.md) separates
  profiles and full/incremental scenarios for the same compiler family.
- Done when: the report identifies each timing's artifact and dependency state, never mixes
  incompatible scenarios in one speedup, and compiler-throughput claims use controlled size
  scaling rather than small application build minima.

### repo.tooling.007 — Separate formatter input preparation from formatter cost

- Evidence: in the `format_tree` workload (`bench/toolchains.py`), formatting a fresh private
  copy spends most sampled worker time opening files (`SourceFile::loadContent`, mostly
  `NtCreateFile`). Formatting the original sources spends most of it in `Formatter::prepare`,
  with little in indentation. Sharing the indentation pass's two line-column computations
  gave no measurable gain and was removed. Do not retry it without a new profile.
- Next: measure fresh-copy and original-source formatting separately, attribute the opening
  delay externally, and profile the formatter's dominant passes before choosing another change.
- Done when: the campaign distinguishes input-opening cost from formatting CPU and a retained
  optimization has an order-alternated speed gain with identical output and measured memory.

### repo.tooling.005 — An incremental Release build can mix two versions of the diagnostic table

- Evidence: incremental Release builds have produced binaries that print the diagnostic
  adjacent to the expected one, while DevMode or `/t:Rebuild` binaries of the same sources were
  correct. Examples: `var v: MissingType` reported the message of the id after
  `sema_err_unknown_symbol`, and `sema_note_expansion_invoked_here` came out as
  `sema_note_generated_source_root` after an error id was inserted before the notes. In one
  case `SemaClone.obj` predated `Errors.Sema.inc`, and touching `SemaClone.cpp` alone fixed
  it: objects compiled against different `Errors.*.inc` enumerations were linked together.
  Identifiers reach code through `DiagnosticDef.h` from `Errors.inc`/`Notes.inc`, while
  message variants come from the `.msg` catalogs. The health-reset prompt uses `/t:Rebuild`
  to avoid the problem without fixing it.
- Next: reproduce a catalog edit over a warm Release object tree and inspect the MSBuild tracked
  reads for `DiagnosticDef.h`, its `.inc` catalogs, and the affected translation units. Distinguish
  an identifier insertion in `.inc` from a message-only edit in `.msg`, then fix the dependency
  that fails to invalidate.
- Done when: an incremental Release build after ids are added to an `.inc` catalog either
  recompiles what depends on them, or cannot produce a binary whose reported id and printed text
  disagree.

### repo.tooling.003 — Matroska timing and display-size cases lack reproducible fixtures

- Evidence: `bin/std/modules/video/src/tests/matroska.test.swg` covers the absent-display-size
  fallback. It covers neither a track whose `DefaultDuration` misstates its rate (the frame
  rate must come from timestamps) nor a display size that differs from the stored size. Both
  behaviors are verified only on private films. No EBML fixture producer is checked in. PyAV
  cannot write a chosen sample aspect into a rewritten stream, and hand-editing EBML means
  regrowing every parent size.
- Next: write a small Swag or Python producer that emits an EBML document element by element,
  so a test can request exactly the header a defect needs. This is test tooling: `std/video`
  writes no Matroska.
- Done when: a checked-in producer reproducibly creates both small header cases and tests
  verify timestamp-derived frame rate and non-square display geometry without private media.

### repo.tooling.009 — Measure Release LTO build cost and compiler throughput

- Evidence: Release currently disables whole-program optimization and link-time code
  generation (`swc.vcxproj`, also documented in `tools/README.md`). Earlier LTCG links took
  several minutes, including after a change to one semantic-analysis source; those observations
  are not a current comparison of compiler throughput, memory and incremental build cost.
- Next: measure compiler throughput, binary size, peak memory and incremental link time with
  and without LTO under comparable load; consider a separate fast-iteration build if the costs
  outweigh the measured compiler throughput benefit.
- Done when: comparable measurements support the Release policy and any fast-iteration option
  has an explicit place in the build workflow.

### repo.tooling.008 — Record module timings with load observed during each sample

- Evidence: `bench/compile.py` has no module-only GUI, Pixel, or OGL workload, and admission is
  checked only before a sample. A campaign starting during a sample therefore goes unrecorded;
  paired GUI samples of one compiler have varied more than fivefold. Two observations remain
  unexplained ([report](../bench/results/compilation/20260907/README.md)): a GUI resident and
  committed peak about 4–5% higher under fixed dependencies, and a roughly 2.5x `doc_std`
  slowdown with no proven load cause. Pinned (performance-core affinity) results must stay
  separate from ordinary unpinned builds.
- Next: add opt-in module-only workloads to the recorded compilation instrument and retain
  both preflight admission and system CPU deltas across the timed process. Distinguish warm
  dependencies, whole dependency rebuilds, pinned controls, and ordinary builds in the results.
  Repeat the GUI control under steady load and isolate each retained compiler change to explain
  the peak-memory difference, and investigate the `doc_std` slowdown under steady load, before
  setting a regression budget.
- Done when: GUI, Pixel, and OGL regressions can be assessed with repeatable paired module
  timings and memory peaks, and a sample disturbed after admission is identified in the record.
- Related: compiler.optimization.029

### repo.tooling.009 — Continue golden campaigns across empty workspaces

- Evidence: `tools/goldens.bat dm test` stops after the examples workspace reports that no
  test matches `--test-tag golden`; the application and reference stages are never reached.
  The reference workspace also has no matching test when run separately.
  Its early exits also prevent collection across failing workspaces.
- Next: distinguish an empty golden selection from a failed test, continue through all four
  workspaces, and aggregate genuine failures without accepting snapshots.
- Done when: an empty examples selection still reaches application and reference goldens,
  and a failing earlier workspace remains visible in the final exit status.
