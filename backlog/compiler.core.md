# Compiler Backlog

This backlog covers the compiler front end, back end, and workspace build engine. Documentation, formatting, and language-design work have their own domain files. Only unfinished work belongs here; completed investigations and implementations remain discoverable through Git history.

Entries stay in one flat list. Keep only measurements that affect the next action; refresh them before relying on them.


### compiler.core.082 — Hot-path node containers that need more than a container swap

- Evidence: several remaining node maps are iterated in ways that affect diagnostics or output:
  sanitizer sparse facts, mem2reg `slots`, SLP `locations`, and web-renaming `loads`. A
  worker-kept `FlatKeyMap` also clears its largest previously used capacity on each rebuild.
- Next: choose one remaining node map, establish its traversal order, and design an order-preserving
  flat representation; leave the kept-table reset tradeoff for measurement.
- Done when: each remaining map has an equivalent replacement, or code evidence shows that no
  lower-work representation preserves its traversal contract.

### compiler.core.074 — Repeated native rebuilds choose different prologues

- Evidence: two consecutive six-worker DevMode rebuilds of `core` on 2026-10-13 differ in every
  section but `.idata` and `.rsrc`: `.text` by 64 bytes, `.rdata` by 160, `.data` by 3,056,
  `.bss` by 8, and the unwind, export, and relocation sections follow. Global offsets in `.data`
  and `.bss` vary because semantic jobs assign them concurrently, and type-info string
  deduplication can shift `.rdata` by one empty-string allocation; the `.text` difference shows
  that function or constant placement varies as well, so the comparison has to start from the
  normalized sections rather than from unwind records.
- Next: assign globals at emission using a stable key such as module, file, and declaration order,
  while keeping JIT addresses valid. Then repeat the normalized section and unwind comparison.
- Done when: output differences are explained and corrected at their owning boundary, normalized
  sections are stable across repeated builds, and affected native tests pass.

### compiler.core.081 — An imported generic method once lost its own parameter

- Evidence: at 2026-10-08 23:56 the first `tools/help.swgs dm` after the formatting commit
  33f2aa0f3 stopped in the `brand.swgs` dependency build (gdi32, ogl, truetype, then pixel, all
  rebuilt against a just-republished core API) with `unknown symbol 'arr'` at
  `bin/std/.output/core/shared-library/devmode/x86_64/array.swg:135`, inside
  `Array.opSet(arr: const [..] T) where Reflection.canCopy(T)`, noted "while checking generic
  struct 'Array' with T = u8" from `core.swg:1410` (`ICodec.encode`). The generated file was
  intact and the parameter is declared on the line above; the next run passed unchanged.
- Reduction attempts, all green: 40 pixel-only rebuilds; 40 rebuilds of the same four modules
  in one process; 60 `--randomize` seeds of that build; 30 two-process rounds (core rebuilt, then
  its dependents); 12 replays of the exact core-then-`brand.swgs` sequence in the checkout. API
  reads are captured under the publication lock, and the editor extension only runs `sema`, so
  a torn file from a concurrent writer is unlikely: the race looks internal to sema of a
  generic method instantiated from an imported API while several modules share it.
- Next: the DevMode compiler now stops at the wait itself when a body waits on the name of a
  parameter of the function it belongs to (`Sema::waitIdentifier`), naming the function. When
  it reappears, keep the failing process's full log and rerun that exact command under
  `--randomize --seed` sweeps with that report.
- Done when: the ordering is proved safe by construction or the race is reproduced and
  fixed with a regression case in the `workspace` suite.

### compiler.core.047 — Imported generic bodies intermittently lose or duplicate bindings

- Found while: validating the dynamic type-pattern migration with DevMode 0.1.675 and six workers.
- Evidence: `bin/swc.dm.exe --num-cores 6 tools/scripts.swgs dm smoke --num-cores 6`
  ran `2048.swgs`, then stopped while checking `asciiart.swgs`. The generated core API's
  `hashtable.swg:521` reported that local `mask` was already defined; the previous-definition
  note pointed to the same declaration. The specialization was
  `HashTable(string, ConcatBufferPosition)`, requested by generated `core.swg:5311`.
  Application tests and example builds were running concurrently in the same checkout.
- Reduction status: an immediate isolated `tools/scripts.swgs dm smoke asciiart` rerun with
  the same compiler, sources, cache, and six workers passed. A complete rerun of all 21
  script smokes also passed. The cause and any relationship
  to the type-pattern change are unestablished; no concurrency fix is included in that migration.
- Further evidence: on 2026-10-07, `tools/help.swgs dm --num-cores 6` with the cast-call
  compiler stopped during the forced standard-library rebuild: generated `array.swg:134`
  reported unknown symbol `arr` inside `Array(u8).opSet(arr: const [..] T)`, while checking
  the Pixel dependency. The parameter declaration remained present in the published source.
  A direct doc retry passed, as did a complete forced tool rerun; a separate forced doc run
  with baseline `ca107d2a9` and its compiler also passed. No other command in this checkout
  was compiling when the first failure occurred. These observations do not establish a cause
  or a relationship to the cast syntax change or the earlier duplicate-local report.
- Next: the DevMode compiler now stops when a conflict names two symbols of one declaration
  node (`SemaError::raiseSymbolConflict`), and when a body waits on a parameter of its own
  function, each with the function named. When either reappears, replay the cached script
  import alongside module builds from that report, capture generic-instance ownership,
  parameter-scope restoration, and semantic restarts around the affected bindings, and
  compare with the parent compiler before attributing the failure to parsing, publication,
  or scheduling.
- Done when: a bounded reproducer identifies the duplicate visitation or publication,
  the root cause is fixed, and the script passes repeated parallel imports with six workers.

### compiler.core.030 — Reuse lowered runtime code across executables

- Evidence: executable lowering starts from reachable roots, but runtime functions reached through relocations are lowered for every executable. The existing function cache skips functions with code relocations.
- Next: profile a current `hello_build`, identify the runtime functions repeatedly lowered, and determine whether their relocations can be represented in a reusable artifact keyed by compiler build, runtime sources, configuration, and target.
- Done when: a fresh and reused runtime artifact produce identical executables and the cache invalidates on every relevant input change; delete the entry if no safe reusable subset remains.
- Related: compiler.core.003, compiler.core.004, compiler.core.006.
### compiler.core.072 — Link preparation resolves and places the native image on one thread

- Evidence: `PELinker::prepareImageLinkParallel` loads archives and builds the symbol table as
  jobs. On 2026-10-01, probed phases in a 16-worker DevMode `gui` rebuild gave image lowering
  about 0.6 s and resolution 0.2 s of wall time over the five native modules. Since 2026-10-06,
  `buildNativeImage` builds each object description's text bytes, code relocations and unwind
  sections as an indexed parallel loop, then places them in description order on the driver; an
  in-process comparison against the sequential order produced identical sections, relocations
  and symbols for `core`, `ogl`, `truetype`, `pixel`, `gui` and `gui2`. A module has only six
  descriptions, so that loop is at most six-way. Placement (`placeNativeSection`, the symbol and
  relocation tables), `resolveSymbols`, `appendSymbolTable`, and `finishImage` are still serial.
- Next: measure `link prepare` in a 16-worker `gui` rebuild with `--dev-sched-stats` and decide
  whether the remaining serial time justifies splitting descriptions further or resolving
  archive members in parallel.
- Done when: `link prepare` no longer shows as serial time in the scheduler report, with the
  linker and PDB C++ tests, the native suite, and a linked consumer green under both executables.
- Related: compiler.core.069

### compiler.core.075 — Aligned node references collapse semantic metadata partitions

- Evidence: `NodePayload` selects each of its 16 shards with `nodeRef.get() % 16`.
  The reference contains an AST byte offset aligned to at least eight bytes, so only
  two shards can receive payload storage or side-table entries. Readers of a sparse
  side table also lose most of the intended empty-shard early exits.
- Experiment: replacing all 22 selectors with `Math::hash(nodeRef.get()) % 16`
  passed concurrent publication/readback coverage, both JIT suites, and semantic
  tests; all 116 benchmark functions retained identical normalized pre-emit code.
  Five paired six-worker Release rebuilds increased peak committed memory by a
  median 17% on `core` and 3% on `gui`. Wall-time medians moved by +3% and -6%,
  respectively, on a machine with substantial background-load variation. A quieter
  single-worker pair also made `core` about 6% slower. The change was not retained:
  distributing every file's small payloads over more 16 KiB pages has a definite
  cost, without a sufficiently clear overall compilation-time win.
- Next: separate sparse side-table distribution from payload-page allocation, or
  reduce initial storage without reducing the supported contiguous symbol-list
  size. Compare one-worker and parallel rebuilds on both modules under stable load.
- Done when: the partitioning improvement has concurrent read/write coverage
  and a measured compilation-time benefit with its memory cost explicitly bounded.

### compiler.core.073 — A dependent module waits for its dependency's whole link before starting

- Evidence: `CompilerInstance::runWorkspace` keeps one deferred link in flight, but joins it before
  compiling any module that depends on the linked one. The `std` chain is nearly linear
  (`core` → `ogl`/`truetype` → `pixel` → `gui`), so most links become a wait: in 16-worker DevMode
  `gui` rebuilds, `--dev-sched-stats` charges 2.8–4.8% of worker time to the
  `workspace link wait` phase, nearly all of it starvation while the single `NativeLink` job
  (0.4–1.2 s per module) runs.
- Next: list what a dependent actually needs from its dependency before code generation (the
  module API and setup files, the DLL only for compile-time calls into it) and join the link at
  the first use that needs the binary instead of before the module starts.
- Done when: a dependent's semantic analysis overlaps its dependency's link in a `gui`
  rebuild, with the workspace suite and `std` tests green under both compiler executables.
- Related: compiler.core.069, compiler.core.007

### compiler.core.071 — WebP's macroblock reconstruction takes seconds to generate and holds back `pixel`

- Evidence: in 16-worker DevMode `gui` rebuilds, the longest code-generation job is one WebP
  function, `Pixel.Webp.decodeLossy` or `Pixel.Webp.vp8Reconstruct` depending on the run, 3–8 s in
  one slice. The `pixel` module's first code-generation round lasts exactly that long: the round is
  bounded by one job, not by when it starts. Per-pass timing on `decodeLossy` (DevMode, six
  workers) spreads about 4 s over the whole pipeline — register allocation 0.8–0.9 s in one run,
  branch-simplify 0.7 s, instcombine 0.5 s, const-fold 0.5 s, copy-elim 0.4 s, most pre-RA passes
  running eight or nine times — so no single pass misbehaves; the function is simply enormous.
  `vp8ReconstructMacroblock` runs two 4×4 loops that call `vp8Predict4` and `vp8InverseDct4`;
  single-call auto-inlining (`K_AUTO_INLINE_LAST_CALL_COST`, 4 096 tokens per callee, no cap on
  the caller's growth) folds the whole chain into its caller, and unrolling then repeats it sixteen
  times. Code generation now enqueues functions largest first, estimated from their own size plus
  what semantic analysis inlined into them, which removes late starts but not this length.
- Next: bound the growth a caller may receive from last-call auto-inlining and from unrolling
  loops whose bodies contain inlined calls, then compare WebP decoding speed and `pixel` build time
  before and after with the benchmark harness.
- Done when: no single function's code generation in `bin/std` takes more than a tenth of its
  module's wall time at 16 workers, without a measurable loss in WebP decoding speed.
- Related: compiler.core.069

### compiler.core.069 — Measure where a module build loses its workers beyond six cores

- Evidence: `--dev-sched-stats` (DevMode compiler) splits worker time into running jobs, serial
  phases (no job running), scheduler lock waits, and starvation (jobs run elsewhere, nothing is
  ready), and reports per job kind its work, its longest slice with what it worked on, and the
  starvation charged to it. `std.swgs dm build gui --rebuild`, 2026-10-01, DevMode compiler:
  - 6 workers, loaded machine: 70 s, 81% running, 11% serial, 0.3% lock, 7.5% starved.
  - 16 workers: 26–54 s depending on load, 58–66% running, 13–16% serial, 0.5–0.9% lock,
    20–25% starved. CodeGen alone causes 10–12% starvation: `Pixel.Webp.decodeLossy` is one job
    of 6.6–8.2 s. Sema's longest slice is 1–2.6 s; the five native links cost 4% together.
  - Barrier rounds no longer matter: 65 rounds moved about 500 sleepers, against 78 000–91 000
    dependency wakes.
- Per phase (the report now charges serial and starved time to driver phases): a quiet 16-worker
  run (26 s) loses 7.4% of worker time starved in semantic analysis, 7.0% starved and 2.2% serial
  in code generation, 3.3% serial and 2.4% starved in the rest of the native backend (collecting
  functions and dependencies before and after code generation), 3.2% starved waiting for deferred
  links, and 1.3% serial in module API export. Code generation runs two or three dependency
  rounds per module; only the first costs anything.
- Next: find what the backend does serially around code generation (`NativeBackendBuilder::prepare`
  and `rebuildFunctionInfos`) and what the semantic tail waits on (its longest job is 1.5–4 s);
  each becomes its own entry once named.
- Done when: each share above has an owning entry.
- Related: compiler.core.071, compiler.core.072, compiler.core.073, compiler.core.065, compiler.core.068, compiler.core.007

### compiler.core.068 — The job scheduler serializes every transition on one mutex

- Evidence: `JobManager` keeps one `mtx_` for the three ready deques, the client counters, the
  waiter map, and the worker list. Jobs are fine-grained (one per top-level declaration, one per
  function in code generation) and every enqueue, dequeue, park, and wake takes that lock.
  `growWorkersForLoadLocked` still creates threads while holding it. The queue is a global FIFO:
  a resumed job lands on any worker with a cold cache. The default worker count is
  `hardware_concurrency()`, which on a hybrid CPU includes efficiency cores and SMT siblings, so
  critical-path jobs can run on the slowest cores.
- Measured: `--dev-sched-stats` on a 16-worker DevMode `gui` rebuild charges 0.5–0.9% of worker
  time to waiting for this lock (compiler.core.069). It is not the ceiling today; revisit when
  starvation and serial phases shrink.
- Next: prototype per-worker deques with stealing behind the same `JobManager` interface, keeping
  the waiter map and client counters under their own lock, and spawn workers outside it.
- Done when: a std module build at 16 workers spends no measurable time waiting on the
  scheduler lock (VTune or ETW contention view), with the scheduler unit tests and both compiler
  executables green.
- Related: compiler.core.069

### compiler.core.065 — Remaining barrier rounds still drain the whole module

- Evidence: `SemaWaitIdentifier` and `SemaWaitImplRegistrations` now park on the name and are
  woken by symbol-map insertion and by the last impl registration; `SemaWaitTypeCompleted` parks
  on its blocking symbol and is woken by `setSemaCompleted`. Those producers have no flag to
  recheck at registration, so a publication racing the park still waits for the `wakeAll` in
  `Sema::waitDone`; so do `SemaWaitCompilerDefined`, a type completed by its concrete layout after
  `setSemaCompleted`, and a name made visible by a new `using` rather than an insertion. That
  barrier first drains the client: the tail of each wave runs on a few workers, then the driver
  does serial work before the next one. Any symbol transition still sets `changed_`, so most
  rounds end in a full `wakeAll`. The same barrier separates the declaration pass from the full
  pass and closes native code generation (`scheduleCodeGen`). A paused lazy function body is
  normally resumed by the job that paused it; when that job does not come back to it, its other
  callers stay parked on `SemaCompleted` until `hasPausedLazyBodyWait` wakes them in a barrier
  round so one can adopt the run. How often that fallback fires is unknown.
- Next: count rounds and re-parked sleepers per wait kind (compiler.core.069) on a std module, then
  give the dominant remaining kind a recheckable publication (a per-name generation counter for
  identifier waits closes the park race) so it no longer needs the barrier.
- Done when: a std module build needs no barrier round to resolve forward identifier and
  type-completion dependencies, with the sema suite, the C++ scheduler tests, and std release
  green under both compiler executables.
- Related: compiler.core.069, compiler.core.007

### compiler.core.063 — Reduce the PDF spill-slot regression to a standalone language test

- Evidence: `sinkFrameStoreIntoBranchTarget` compared raw stack displacements across outgoing-call
  stack adjustments. In `Pdf.parseContent`, a store at `[rsp + 0x1AA8]` under an eight-byte
  adjustment belonged to the slot later read at `[rsp + 0x1AA0]`. The pass mistook it for another
  loop's store at the first displacement and erased it. Comparing entry-relative addresses fixes
  the three PDF failures; all eleven selected corpus/stroke tests pass in release JIT and native
  execution. `PostRAPeephole_SpillStoreSinkingTracksStackDepth` fails before the fix and covers both
  distinct slots with equal displacements and one slot with different displacements.
- Remaining boundary: that regression is a C++ Micro test, not a standalone source under
  `bin/unittests`. Extracting the parser and dash loop into a Core-only script passes even without
  the fix. Forty-eight standalone two-loop variants, varying call arity from one to twelve and
  live accumulator pressure, also pass without it. Those reductions change register allocation
  and no longer place the two loops' spills at the conflicting adjusted displacements; retaining
  the full GUI decoder would violate the standalone suite boundary.
- Next: reduce the interacting loops and their register pressure while checking the pre-fix
  post-allocation instruction stream, then keep a native suite case that fails without the fix.
- Done when: `bin/unittests/native` reproduces this stack-depth aliasing independently of GUI,
  alongside the existing C++ regression and PDF consumer tests.

### compiler.core.061 — Type-info graph publication uses one serialization domain

- Evidence: `ConstantManager::makeTypeInfo` deliberately sends all reflected types to constant
  shard zero, so shared dependencies have one canonical runtime identity. `TypeGen::makeTypeInfo`
  retains exclusive ownership of that segment across `processTypeInfo` and back-reference
  publication. Contention now records the exact storage and owner generation, and every ownership
  release wakes its registered jobs, including semantic pauses. Independent reflection roots still
  cannot generate their metadata concurrently. This is a static concurrency boundary, not an
  attribution of a measured fraction of cold-build time.
- Safety boundary: hashing roots into separate stores would duplicate common dependencies and
  break pointer identity. Publishing an entry before all required payloads and back references
  are ready would expose partial recursive metadata.
- Next: separate canonical graph registration from payload generation, identify independently
  publishable components, and define ownership and completion for recursive components before
  shortening or dividing the exclusive section. Preserve one address per reflected type.
- Done when: independent components can progress on different workers, mutually recursive
  graphs publish no partial data, and identity, interface, and reflection tests pass under
  repeated parallel cold compilation.
- Related: compiler.core.007.

### compiler.core.007 — Workspace front ends and code generation run serially


**Evidence.** The workspace computes dependency order, but module front-end and code-generation work is still consumed serially. The current depth-one pipeline can overlap one background link with compilation of the next module; it does not schedule independent ready modules concurrently.

**Architecture audit (2026-09-30).** `CompilerInstance::runWorkspace` still calls
`runWorkspaceModule` synchronously for each item in `buildOrder`; only one
`WorkspaceModuleLink` can remain in flight. Increasing `--num-cores` therefore cannot overlap
two independent module front ends. `Logger::ScopedStagesDetailed` and `Logger::ScopedStageMute`
change shared logger state, and command metrics live in the process-wide `Stats` singleton.
Dispatching the existing module loop as worker jobs would also let its blocking
`waitAll(clientId)` calls exhaust the same worker pool they need to finish.

**Next.** Give each in-flight module its own log/metric scope and drive module stages from a
coordinator that never blocks a compiler worker on its own pool. Preserve the lifetime of each
compiler through artifact publication and linking, then admit independent ready modules within
the shared memory budget.

**Intent.** Schedule ready modules concurrently on the dependency DAG through a shared worker pool with explicit memory and CPU limits.

**Done when.**

- Independent sibling modules overlap front-end and code-generation work, while consumers wait for the required interface or link artifact.
- Compiler and linker work share a bounded concurrency policy and do not oversubscribe the host.
- Logs, manifests, diagnostics, and emitted artifacts remain deterministic.
- The concurrency cap accounts for the memory measurements and budget from compiler.core.005.
- Workspace tests cover a diamond graph, concurrent failures, cancellation, and deterministic repeated builds.

**Related:** compiler.core.004, compiler.core.005.

### compiler.core.005 — Set and enforce a compiler memory budget

- Evidence: parallel compiler jobs retain high-water allocations across semantic analysis, code generation, and the Micro pipeline. The current peak and largest retained owners need a fresh measurement.
- Next: measure peak memory for a six-worker `core` DevMode rebuild and a representative hello build, then attribute the largest retained allocations before selecting one reduction.
- Done when: the campaign publishes host-normalized memory limits, every selected workload stays within them, and a regression report names the responsible subsystem.
- Related: compiler.core.004, compiler.core.007.
### compiler.core.003 — Code-generation invalidation is module-wide


**Current boundary.** Workspace manifests keep a completed module when its own inputs and the
dependency API generations it consumed are unchanged. The default build keeps an executable image
when only an interface-compatible dynamically linked implementation changed; the fresh DLL is
republished before a run. It also persists one deterministic COFF object containing a non-debug
executable's module-owned code and data. When only a static native dependency generation changes,
the workspace reloads that object, resolves the fresh archives, and writes a new PE without running
the consumer's front end or code generation. Imported native code executed at compile time remains
a strict invalidation boundary. Cache publication is atomic and best-effort, and a missing or
modified object falls back to a normal compilation.

The next cache layer now fingerprints raw per-function microcode before optimization. For a
non-debug executable, an unchanged function with at least 64 micro-instructions and no
code relocation reuses its COFF archive member, including unwind metadata, and skips the micro
passes and encoder. The cache remains one archive plus a compact index rather than one persistent
file per function. Entries carry the compiler build and backend configuration identity; malformed,
missing, renamed, or fingerprint-mismatched entries fall back to ordinary emission. The workspace
regression changes one large leaf while observing another reported as reused, then verifies that
`--rebuild` bypasses the cache.

**Evidence for the next layer.** The first function slice deliberately excludes calls, referenced
constants, debug information, and small functions: those need a canonical dependency fingerprint
or cost more to serialize than they save. `NativeObjFileWriter` already serializes one function per
archive member, and the integrated linker resolves those members lazily, so broader coverage should
extend the fingerprint and admission policy rather than create another storage format.

Do not content-hash the source tree in a separate warm-build pass. Reuse the manifest's read
boundaries for the cheap eligibility decision; when content fingerprints are later needed, compute
them while bytes are already being read. Do not write capsules for non-native outputs or failed
builds, and allow the write to be skipped below a measured code-generation cost threshold. Record
cache decision time, bytes read/written, and saved code-generation/link time so a hit that costs
more than it saves is visible.

**Next — broaden function-level code generation.** Admit functions with relocations by fingerprinting
their referenced symbol identities, constant payloads, reachable ABI, and inlinable bodies. Add
debug records only after their source identity and line mapping are deterministic. Measure an
adaptive size/cost threshold so small functions never pay more hashing and archive work than their
micro passes cost. Front-end state and binary module interfaces remain compiler.core.002 and
compiler.core.001 respectively; this entry consumes their semantic fingerprints rather than
inventing a second dependency graph.

**Performance gate.** Compare clean, no-op, private-body edit, static-dependency edit, and public-API
edit workloads with compiler.core.004. A clean build may not regress outside the established noise
band, a no-op cache decision must stay cheaper than launching code generation, and cache writes may
not extend the reported critical path. `--rebuild` remains the clean-build oracle while every safe
cache is part of the normal DevMode and Release paths.

**Done when.**

- A static-dependency implementation edit relinks a consumer without re-running its front end or
  code generation. Done for non-debug executable build/run/smoke commands.
- A body-only edit regenerates the changed function and any function whose generated code depends
  on it, while unrelated functions are reused. Done for sufficiently large relocation-free leaf
  functions in non-debug executables.
- Reuse works for native and JIT builds, including debug and unwind metadata.
- Clean and warm builds produce byte-identical deterministic cache entries and observably identical
  programs, and reject compiler, target, configuration, ABI, API, and optimization changes.
- The compiler.core.004 edit-build workloads demonstrate a material win with no measurable clean
  build regression.

**Related:** compiler.core.001, compiler.core.002, compiler.core.004, compiler.core.030.

### compiler.core.052 — Isolate a transient null-capture diagnosis in a macro binding

- Area: compiler/codegen, captured variables, static sanity
- Evidence: a Release `swc.exe` 728 full native test (`-bc release --num-cores 6`)
  diagnosed twelve null dereferences at `total += seed` in
  `bin/unittests/native/inline/binding_visit_growth.swg`. The source is already a
  permanent regression test and is unchanged during this investigation.
- Reduction: standalone builds 712 and 714 passed; build 718 failed using the
  original session output/work roots, then passed with new output/work roots.
  An identical source copied outside the checkout passed with the same 718 binary.
  Build 730 with temporary pre-sanity tracing passed. Tracing was removed; integrated
  build 731 passes all 3,277 native tests and the expected-failure recovery probes.
  These observations do not distinguish cache/work-directory state from scheduling
  or another input. They do not prove that a particular optimization introduced or
  fixed the failure. The diagnostic is emitted before the micro optimization loops.
- Evidence artifact: [generated-code session](../bench/results/generated-code/20260916/README.md).
- Next: repeat the unchanged standalone source with controlled work directories and
  six workers, preserve the failing pre-sanity capture lowering, and distinguish
  cache reuse from shared code-generation state when cloning the macro's closure. Twenty
  consecutive Release-compiler runs of the native suite filtered to that source, release
  configuration, six workers, the suite's own output and work roots, passed on 2026-10-13.
- Done when: a stable reproducer identifies the cause, the correction passes
  that reproducer repeatedly, and the full native suite remains green.

### compiler.core.041 — Reduce parallel dependency registration to a workspace-suite witness

- Evidence: the 2026-09-11 workspace build stopped inside `std::set::insert` reached from
  `semaCompilerInclude`. `NativeArtifact_ConcurrentCompilerInputsKeepEveryDependency` now forces
  six simultaneous writers and checks all included files, loaded files, and deduplicated imports;
  registration and snapshots share a mutex. That C++ boundary is covered, but the language suites
  cannot yet force the failing interleaving. A reduction with 256 independent source files and
  16,384 `#include` expressions over 256 byte fixtures passed both standalone semantic analysis
  and a workspace build with the unfixed Release 0.1.477 compiler; its manifest retained every
  fixture. Keeping that reduction as a regression would not distinguish the defect.
- Next: find a bounded source-level ordering or a workspace-test scheduling hook that exposes
  missing or corrupted dependency registration without depending on a large GUI module build.
  Keep the existing C++ concurrency test as the precise internal guard. A DevMode option that
  slept one millisecond before each registration, over a twelve-file module whose files each
  include sixteen fixtures of their own, did not expose the unsynchronized insertion in three
  six-worker rebuilds: the sleep aligns the arrivals, not the insertions, so the hook has to
  hold the registration open inside the mutation itself.
- Done when: a `bin/unittests/workspace` case fails with unsynchronized registration, passes
  with synchronized registration under both compiler executables with six workers, and verifies
  dependency retention and subsequent invalidation without an intermittent timeout as its oracle.

### compiler.core.004 — The benchmark campaign has no regression threshold on the edit-build loop

**Evidence.** The benchmark harness records `core_rebuild`, `core_noop`, `core_touch`,
`hello_build`, `doc_std`, and `format_tree` with samples and compilation context. The
[20260906-143159 record](../bench/results/20260906-143159.json) covers these workloads but is not
sufficient to establish the five-campaign baseline band. The harness now records timed-process peak
working set separately from process-tree commit; the formatter input-opening bias remains in
repo.tooling.007.

**Intent.** Establish each workload's noise band, then report regressions without silently moving
its baseline.

**Done when.**

- Five clean baseline campaigns establish a resolution band for each edit-build workload.
- A campaign reports a workload that moves beyond its band without rewriting the baseline.
- Release and DevMode are measured where their behavior differs, and every result names its mode.

**Related:** compiler.core.002, compiler.core.005, compiler.core.007.

### compiler.core.006 — Reuse analyzed prelude state

- Evidence: each fresh compiler process analyzes the unchanged runtime prelude before compiling a module or script.
- Next: serialize the prelude through the ordinary module-interface mechanism and include source, compiler, target, and relevant configuration in its cache key.
- Done when: warm module builds and script launches skip prelude lexing, parsing, and semantic analysis, while fresh and reused paths produce identical diagnostics and artifacts.
- Related: compiler.core.001, compiler.core.004, compiler.core.016.
### compiler.core.001 — Replace generated dependency source with a reusable module interface

- Evidence: every workspace import currently adds generated API source to the dependent compiler front end, repeating lexing, parsing, and semantic analysis for unchanged dependencies.
- Next: define a versioned binary interface that preserves exported symbols, types, constants, attributes, ABI data, and bodies needed by downstream optimization; keep readable `.swg` export for inspection.
- Done when: workspace imports no longer parse generated API source, cache invalidation covers every exported input, and fresh and reused interfaces produce identical diagnostics and artifacts.
- Related: compiler.core.002, compiler.core.006, compiler.language.service.001, compiler.language.service.003, compiler.core.030.
### compiler.core.002 — Front-end invalidation is module-wide


**Intent.** Persist lexical, parsed, and semantic state per source file. Cache keys must include the source content, relevant build configuration, and fingerprints of imported public symbols actually observed by the file.

**Implementation constraint.** The current AST is not an immutable parse cache: semantic analysis can
replace source expressions with substitutions and append generated nodes to the same per-file AST.
`SourceFile::setContent` rejects changing a file after its AST owns a source view; editor revisions
retain the old source buffer and node payload while activating a fresh pair. The editor session now
records symbols by source revision and derives conservative file-to-file dependencies from resolved
and folded node symbols. It can therefore reuse unaffected files, but invalidation does not compare
the public interfaces actually observed: changing a private body still reanalyzes every file that
references the source. Semantic symbol maps remain append-only, so retired declaration ASTs cannot
yet be reclaimed safely. Persisted `using` maps carry a source revision and stale entries are
excluded from lookup.

**Done when.**

- Editing a private body reanalyzes only the changed file and its semantic dependents.
- Changing a public signature invalidates every consumer that observed it.
- Adding, removing, or renaming a file, changing relevant configuration, and changing compiler versions invalidate the correct state.
- The compiler.core.004 `core_touch` workload lands far below `core_rebuild`, which today it does not: one saved file rebuilds every file of the module.
- Clean and incremental workspace builds are covered by equivalent-result tests.

**Related:** compiler.core.001, compiler.core.004, compiler.core.003, compiler.core.016.

### compiler.core.016 — Tool scripts recompile on every invocation


**Intent.** Persist compiled script artifacts using a dependency-complete key over loaded source files, imported public interfaces, compiler version, target, and relevant build configuration.

**Done when.**

- A second unchanged invocation skips script lexing, parsing, semantic analysis, and code generation before launching the cached artifact.
- Changes in the main script, `#load` inputs, imported public APIs, compiler version, target, or relevant configuration invalidate the artifact.
- Cached and fresh paths preserve diagnostics, forwarded arguments, environment handling, output, and exit code.
- Tests cover direct source changes, transitive loads, imports, configuration changes, corrupt entries, and concurrent cache population.

**Related:** compiler.core.001, compiler.core.002, compiler.core.006, platform.portability.080.

### compiler.core.027 — A run-time loaded shared library cannot share the host's runtime

- Area: compiler
- Found while: making an executable link its dependencies' code in by default, so it ships as one
  file (`bin/unittests/workspace/modules/standalone_exe`).
- Observation: an executable links its whole import closure in, which gives the process one copy of
  each module and one runtime state. A shared library it loads at run time through
  `Core.NativeLibrary.load` was built against the shared libraries instead, so it brings a second
  `core` with it: two allocators, two runtime contexts, and memory that cannot cross between them.
  Nothing the compiler sees says the load will happen — the library is named by a path the program
  computes while it runs.
- Evidence: `runtime_context_dynamic_consumer` faulted with `0xC0000005` after its `#test` passed,
  at shutdown, once its `core` import resolved to the archive. Pinning that import with
  `link: "shared-library"` — which the all-or-nothing rule then propagates to the whole closure —
  makes it pass again, and is now what the module states.
- Next: decide whether a loaded module can adopt its host's runtime instead. The
  `__swc_rt_stage` hook already hands an imported module the host's TLS slot and context, and
  `NativeLibrary.load` could call it the same way; that leaves the loaded module's own `core.dll`
  allocator as the remaining split, so the question is whether the hook can also install the host's
  allocator. Until then the rule is the pin, and it is documented on the reference's dependency
  page.
- Done when: either a loaded shared library provably shares the host's allocator and context in
  a workspace test that links its dependencies in, or the backlog records why it cannot and the
  compiler diagnoses the combination it can see.

---

### compiler.core.083 — Define an embeddable compiler driver boundary

- Evidence: `src/main.cpp` owns process setup and cleanup: allocator configuration, the Windows
  host exception hook, stdio flushing, and the PID-scoped sandbox. CLI parsing and command
  dispatch live in `src/Main/CompilerCli.cpp`; the persistent stdio transport lives in
  `src/Main/EditorService.cpp`. `CompilerInstance` remains the internal compilation entry point.
  `Global` still stores process-static services, `CommandLine` is coupled to CLI configuration,
  and `swc.vcxproj` still builds one executable rather than a reusable library target.
- Next: define a host-facing configuration and lifetime contract for diagnostics, cancellation,
  worker shutdown, and repeated compiler instances; build a core library without the CLI and
  process entry; prove a non-CLI consumer can initialize, analyze, and shut down the compiler.
- Done when: the executable entry point and process-only setup are absent from a reusable compiler
  library target, and a host can use that target without parsing command-line arguments or
  exchanging requests over process stdio.

## Deliberately out of scope

- **An LLVM back end.** The native and Micro back ends are the supported architecture. Reconsider only if a concrete platform or optimization requirement cannot be met within them.
- **A second language front end.** The compiler architecture is optimized for Swag; a second parser and semantic model would dilute the persisted-state and tooling work above.
- **A package registry inside the compiler backlog.** Path and workspace dependencies remain compiler responsibilities. Registry identity, trust, lockfiles, acquisition, and publishing need a separate product backlog once their scope and owner are defined.

Frontend, semantic analysis, and code generation defects: something observed in `swc` itself, with
a reproduction and a next investigation step. Optimization passes and generated-code performance
are [compiler.optimization.md](compiler.optimization.md); the borrow, lifetime and sanity analyses
are [compiler.safety.md](compiler.safety.md); the `doc` and `format` commands have their own files,
[compiler.command.doc.md](compiler.command.doc.md) and [compiler.command.format.md](compiler.command.format.md).
