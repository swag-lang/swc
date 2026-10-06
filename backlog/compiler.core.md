# Compiler Backlog

This backlog covers the compiler front end, back end, workspace build engine, and editor-facing compiler services. Documentation, formatting, and language-design work have their own domain files. Only unfinished work belongs here; completed investigations and implementations remain discoverable through Git history.

Items are ordered from the most recently updated down. Every completion condition is intended to be testable. Measurements below are a dated baseline, not permanent product claims.

As of 2026-09-04, excluding the vendored `src/Support/Memory/mimalloc` tree, `src/` contains 266,719 physical lines in 685 `.cpp` and `.h` files. `src/Compiler/Sema` accounts for 85,710 lines in 154 files. The compiler diagnostic catalog contains 561 ids carrying 643 message variants, and `swc format --dump-config` exposes 133 options. Recompute these figures when using them to prioritize work.

### compiler.core.021 — JIT code leaks one thread-local index per compiler instance

- Recorded: 2026-08-12 18:01
- Updated: 2026-10-06 16:12 — Destroyed instances are now poisoned and release their fiber-local slots; thread-local indexes remain.
- Area: compiler, JIT runtime hosting
- Found while: tracking an intermittent JIT '#test' failure in `swc test -w bin/apps -m swagcapture
  --rebuild`: imported native modules kept `Swag.processInfos().args` slices into the storage of a
  destroyed dependency-build instance. That storage is interned for the process since.
- Done (2026-10-06): a DevMode `~CompilerInstance` fills its global zero, initialized and compiler
  segments with `0xCD`, so a stale reference into a destroyed instance reads the pattern instead
  of plausible old bytes. The first thing it caught was `retireAllocatorThreadHeap`, the cleanup
  callback the JIT-compiled runtime allocator registers through `FlsAlloc`: Windows ran it at
  thread exit, after the instance was gone, and it read `Swag.g_AllocatorThreadHeapTlsId` from the
  dead segment (`import_core_without_using.swgs` exited with a failure code after reporting
  `clean`). JIT calls to `FlsAlloc` and `FlsFree` now resolve to host wrappers that record each
  slot and its callback, and an instance frees the slots whose callback is its own JIT code before
  it is destroyed; `FlsFree` runs the callbacks while their code and data are still valid.
- What remains: JIT code also takes plain thread-local indexes through `TlsAlloc` (the allocator's
  fast heap slot, for example). They have no callback, so nothing reads them after the instance
  dies, but each instance that ran its allocator keeps one index allocated for the rest of the
  process, and Windows has 1,088 of them.
- Next: count the indexes a long workspace run (`tools/std.swgs dm test`) leaves allocated, and if
  the count grows with the number of instances, record the `TlsAlloc` indexes per instance the
  same way and free them at destruction.
- Complete when: a process that creates and destroys many compiler instances keeps a bounded
  number of thread-local indexes, with the workspace suite green under the poisoning.

### compiler.core.056 — A library still lowers the equality operators of its public structs

- Recorded: 2026-09-23 14:11
- Updated: 2026-10-06 15:26 — Libraries now lower only what they export and what that reaches.
- Area: compiler/codegen, module publication, compilation time
- Evidence: `Sema.Struct.cpp` gives every struct that `shouldGenerateEqualityOperator` selects
  (one holding a `string`, for example) a member-wise `opEquals` when the struct completes,
  whether or not anything compares it. On 2026-09-23 a hello world lowered 31 of them (19.4% of
  its lowering) and `gui` 1 901 (4.57 s, 6.2% of its lowering).
- Done (2026-10-06): `NativeBackendBuilder::prepare` used to seed lowering with the whole code
  segment. An executable now seeds it with its roots, and a static or shared library with the
  functions it exports under their API name plus the executable roots (test, init, drop, runtime
  and global-initialization targets). A hello world lowers none of those operators. Functions
  lowered by a DevMode `gui` chain rebuild: `core` 5 212 to 3 915, `ogl` 1 845 to 1 585,
  `truetype` 1 275 to 934, `pixel` 5 250 to 4 477, `gui` 9 274 to 8 238. Wall time at six workers
  stayed within the machine's noise. The `std` tests in both configurations, every application
  and example build, the script smokes and a `swagscope` smoke pass.
- What remains: a public struct's generated `opEquals` is public, so a library still exports and
  lowers it even when neither the library nor any importer compares the struct. An importer that
  compares it generates its own operator from the published struct source.
- Next: check whether an importer ever calls a library's generated operator. If it never does,
  stop exporting generated equality, and the remaining ones fall out of the library's closure.
- Complete when: a library lowers no generated `opEquals` that neither its own code nor an
  importer calls, with the workspace suite and `std` release green.
- Related: compiler.core.030, compiler.core.006.

### compiler.core.053 — Confirm that a linked PDB keeps one definition per structure

- Recorded: 2026-09-17 08:42
- Updated: 2026-10-06 14:55 — One type table no longer repeats a record; a linked program remains to be measured.
- Area: compiler/backend, `DebugInfoCodeView` type table, integrated PDB writer
- Evidence: `swc tools/apps.swgs dm build swagscope --debug` (build 847) wrote a 12.2 MB PDB
  whose TPI stream held 38,154 records, 5,178 of them `LF_STRUCTURE`, with `Surface` defined 28
  times, `interface` 26, `Wnd` 24 and `Application` 22.
- Done (2026-10-06): `TypeTableBuilder` now hash-conses every record it emits, so a record
  identical to an earlier one returns the earlier index, and a pointer to a structure names its
  forward declaration, as MSVC does, so a structure's records no longer depend on whether its
  definition was complete when they were emitted. On a 60-structure probe compiled with
  `--debug`, the TPI stream went from 1,253 to 913 records (procedures 296 to 200, argument
  lists 296 to 154), `interface` from five structure records to one and `string` from four to
  one; each structure keeps one forward declaration and one definition. The `DebugInfo_*` and
  `Pdb_*` tests pass.
- What remains: `LinkDebugMerger` already keeps one copy of each record once remapped, so the
  copies archive members brought came from records that differed only by which index a pointer
  named. With pointers now naming forward declarations those records should coincide, but no
  linked `--debug` program with debug archives has been measured yet.
- Next: build swagscope with `--debug` before and after this change and compare the PDB size,
  the TPI record count and the number of `LF_STRUCTURE` records per name.
- Complete when: every structure has one definition per distinct layout in a linked PDB, the
  `DebugInfo_*` and `Pdb_*` tests pass, and the swagscope `--debug` PDB shrinks accordingly.

### compiler.core.046 — A `!` buried in a `Swag.assert` argument proves a path the guard may not check

- Recorded: 2026-09-15 12:47
- Updated: 2026-10-06 09:49 — Measured what recording nothing from an assertion argument would touch.
- Found while: the same change, on `bin/unittests/sanity/self_borrow_move.swg`.
- Evidence: `Swag.assert(target.cursor![] == 13)` records the non-null proof for the rest of the
  block, but `Swag.Safety(.Assert, false)` and the `release` preset drop the whole assertion,
  including the `!` inside its argument. The proof survives compilation; the runtime guard does
  not. `Swag.assert(p != null)` has the same property and the reference documents it as the
  precondition form, which is why it reads as deliberate there; a `!` inside an argument does not
  read as a precondition at all.
- Cost: no unsoundness in `release`, where every guard is already off. In `devmode` with an
  explicit safety override, a path can be used unguarded because of an assertion that was
  compiled out.
- Blast radius (2026-10-06): recording nothing from inside a `Swag.assert` argument is a
  one-line change to `notNullRunsUnconditionally` (an `AstIntrinsicCallExpr` parent with
  `IntrinsicAssert` returns false). `bin/` holds 89 assertions with a postfix `!` in an
  argument, most of them in application and module tests, so any code after them that relies on
  the proof would stop compiling; that needs every `bin/` test source compiled before it lands.
  Recording the proof only where `Assert` safety is on would make the same source compile in one
  configuration and not in another, which is worse.
- Next: decide whether a proof recorded inside an argument of a removable intrinsic should be
  kept. Either record nothing from inside a `Swag.assert` argument and compile every `bin/` test
  source, or state the rule in `bin/reference/modules/language/src/004_007_pointers.swg` next to
  the existing `Swag.assert` paragraph.
- Complete when: the chosen rule is implemented or documented, with a case showing what
  `Swag.Safety(.Assert, false)` does to the proof.

### compiler.core.072 — Link preparation resolves and places the native image on one thread

- Recorded: 2026-10-01 14:25
- Updated: 2026-10-06 09:49 — Description sections are now built in parallel; placement and resolution remain serial.
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
- Complete when: `link prepare` no longer shows as serial time in the scheduler report, with the
  linker and PDB C++ tests, the native suite, and a linked consumer green under both executables.
- Related: compiler.core.069

### compiler.core.039 — One module analysis resolves four and a half million substitutions

- Recorded: 2026-09-09 17:44
- Updated: 2026-10-06 08:06 — Removed repeated code-generation queries at their callers.

**Evidence.** Instrumented on 2026-09-09 (Release 0.1.426): analyzing one snippet module that imports `core` — 52 files, 155 000 tokens — enters `NodePayload::followSubstituteChain` **4 554 160 times**, walking 9 121 151 links. The same walk over a 22 800-line file with no import enters it 269 675 times. A chain is short: two links on average, three at most, so the traffic is not depth but the sheer number of times the pass asks what a node now stands for. A profile of that analysis puts the walk at 2.8 % of the compiler's own code and `SemaNodeView::computeInner`, which begins with that question, at 3.2 %.

Handing the walk the payload state its caller had just read — so a two-link chain reads one node instead of two — was written and measured. Paired A/B on the 22 800-line file moved nothing either way, and the imported-module workload, which cannot be measured by alternating runs because two build numbers invalidate the standard library's artifacts between them, gave 92 %, 101 % and 110 % of the processor time across three block measurements. It was reverted: the walk is not where the time goes.

**Taken (2026-10-06, build 1173).** Comparison lowering carries the result type already read
by its dispatcher through the scalar, string, slice, type-info, aggregate, three-way and vector
paths. Payload metadata merging receives the resolved node reference already held by all four
call sites. These remove a result view per ordinary comparison and a substitute-chain query per
metadata merge without retaining new state or changing substitution rules. The comparison change
with concurrent SSA work passed 3,620 native Release tests; the metadata change passed 66 native inline tests and four JIT
`defer.catch` tests. These are structural savings, with no timing or memory measurements.

Do not merge separate type and constant views mechanically: a combined view can suppress a null
constant when flow analysis narrows the type, while a constant-only view does not perform that
narrowing. Such a rewrite requires a separate semantic proof.

**Next.** Find out why a view is rebuilt so often, rather than making each rebuild cheaper. Count how many of those 4.5 million resolutions ask about a node another resolution already answered for in the same pass, and whether a resolved reference can be remembered on the node instead of re-derived. The answer decides whether this is a memoization or a call-site problem.

**Related:** compiler.core.001, compiler.core.038.

### compiler.core.060 — A compile-time call still pays per-call plumbing its call graph does not need

- Recorded: 2026-09-30 08:32
- Updated: 2026-10-03 19:05 — Narrowed to uncached constant walks and pending release edges.
- Area: compiler/JIT, compile-time execution, compilation time
- Evidence: the remaining repeated work is visible in the current call paths:
  - `patchConstantFunctionRelocationsRec` walks the whole constant closure of each constant a
    patched function names, once per function, taking the allocation lock and the relocation lock
    and filling a fresh relocation vector for every allocation it visits. The semantic walk over
    the same graph remembers an allocation per relocation version; this one remembers nothing
    between functions.
  - `SemaEscape::propagateCompletedFreesSummaries` runs twice per prepared compile-time call. Its
    memo keys on the count of semantically completed symbols, which moves while sema runs. The
    unguarded path retains applied forwardings and appends only new edges, but each new signature
    still scans the pending edges; an edge whose callee never frees its parameter stays pending.
    The guarded path also reconstructs its closure-local return-summary table. A worklist keyed by
    callee could revisit an edge only when its callee's mask or either end's completion changes.
- Next: measure these remaining walks on a `gui` release rebuild. Before remembering patched
  allocations across functions, preserve deferred-function registration and the `Pause` path;
  a memo must account for both. Preserve the guarded return proofs and late completion when
  replacing the release scan with a worklist.
- Complete when: each item is either removed with compile-time execution and safety tests, or
  recorded as measured and not worth its risk.
- Related: compiler.core.056, compiler.core.030.

### compiler.core.074 — Repeated native rebuilds choose different prologues

- Recorded: 2026-10-01 17:08
- Updated: 2026-10-03 18:10 — Fixed a third cause, location constants sharded by pointer; global layout still varies.
- Evidence: two consecutive full `native -bc release --rebuild` suite runs with the same
  Release compiler (build 1173, prompt-4 working revision based on `656356844`) both pass
  3,545 tests, but `dumpbin /unwindinfo` reports 6,713 and 6,712 function records. Comparing
  records without addresses finds eleven changed groups, including one removed leaf record,
  different saved registers, and stack allocations changing from `0x700` to `0xAF0`.
  Both commands cap the outer script and inner compiler at six workers and use isolated
  temporary caches. No compiler rebuild occurs between them.
- Scope: this was observed while removing the redundant sort in `X64UnwindWindows::buildInfo`.
  That routine serializes already generated prologue operations; the record differences also
  occur between runs of the same changed binary. This does not establish when the variation
  was introduced, nor whether its cause is semantic ordering, automatic inlining, or allocation.
- October 3: three causes found and fixed. A by-value aggregate argument that folds to a
  constant (`#curlocation` in every `Swag.panic` call) had its call-argument storage detached
  by the folding cast and registered again on every sema rerun, each copy keeping a frame
  slot: `allocatorCorruptedFreeList` in the runtime got a 0x40 to 0x130-byte frame from one
  build of the same benchmark to the next. `.rdata` was laid out by constant shard and
  creation offset, which follow job scheduling; it now follows the order the code reaches
  each constant. And a source-location constant chose its shard from the function's address
  and the source view's load index, so two locations in one file shared their file-name
  string in some builds and not in others, shifting the whole section; the shard now comes
  from the file and function names. Over five pairs each of `sort`, `wordfreq` and `nbody`
  builds, the code (ignoring addresses), `.pdata` and `.xdata` no longer vary, and `.rdata`
  differed in one pair only, by 41 bytes, next to a `.data` difference.
- What still varies: the offsets of globals in `.data` and `.bss`. They are assigned while
  sema runs in parallel, so the addresses that code and relocations use differ from one
  build to the next (48 to 5,800 bytes per pair).
- Next: give globals a layout decided at emission from a stable key (module, file, declaration
  order) instead of first-come offsets, keeping the JIT's addresses valid; then repeat the
  unwind record comparison to see whether another prologue cause remains.
- Complete when: the source of the different prologues is explained and corrected at its
  owning boundary, with stable normalized output and the affected native tests green.

### compiler.core.075 — Aligned node references collapse semantic metadata partitions

- Recorded: 2026-10-03 16:28
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
- Complete when: the partitioning improvement has concurrent read/write coverage
  and a measured compilation-time benefit with its memory cost explicitly bounded.


### compiler.core.073 — A dependent module waits for its dependency's whole link before starting

- Recorded: 2026-10-01 14:25
- Evidence: `CompilerInstance::runWorkspace` keeps one deferred link in flight, but joins it before
  compiling any module that depends on the linked one. The `std` chain is nearly linear
  (`core` → `ogl`/`truetype` → `pixel` → `gui`), so most links become a wait: in 16-worker DevMode
  `gui` rebuilds, `--dev-sched-stats` charges 2.8–4.8% of worker time to the
  `workspace link wait` phase, nearly all of it starvation while the single `NativeLink` job
  (0.4–1.2 s per module) runs.
- Next: list what a dependent actually needs from its dependency before code generation (the
  module API and setup files, the DLL only for compile-time calls into it) and join the link at
  the first use that needs the binary instead of before the module starts.
- Complete when: a dependent's semantic analysis overlaps its dependency's link in a `gui`
  rebuild, with the workspace suite and `std` tests green under both compiler executables.
- Related: compiler.core.069, compiler.core.007

### compiler.core.071 — WebP's macroblock reconstruction takes seconds to generate and holds back `pixel`

- Recorded: 2026-10-01 13:08
- Updated: 2026-10-01 13:40 — traced to inlining and unrolling; code generation now starts the largest functions first
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
- Complete when: no single function's code generation in `bin/std` takes more than a tenth of its
  module's wall time at 16 workers, without a measurable loss in WebP decoding speed.
- Related: compiler.core.069

### compiler.core.069 — Measure where a module build loses its workers beyond six cores

- Recorded: 2026-10-01 07:35
- Updated: 2026-10-01 13:40 — break the losses down by driver phase
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
- Complete when: each share above has an owning entry.
- Related: compiler.core.071, compiler.core.072, compiler.core.073, compiler.core.065, compiler.core.068, compiler.core.007

### compiler.core.068 — The job scheduler serializes every transition on one mutex

- Recorded: 2026-10-01 07:35
- Updated: 2026-10-01 13:08 — measured: lock waits cost under 1% of worker time at 16 workers
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
- Complete when: a std module build at 16 workers spends no measurable time waiting on the
  scheduler lock (VTune or ETW contention view), with the scheduler unit tests and both compiler
  executables green.
- Related: compiler.core.069

### compiler.core.065 — Remaining barrier rounds still drain the whole module

- Recorded: 2026-10-01 07:35
- Updated: 2026-10-01 09:53 — add paused lazy bodies as a barrier source
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
- Complete when: a std module build needs no barrier round to resolve forward identifier and
  type-completion dependencies, with the sema suite, the C++ scheduler tests, and std release
  green under both compiler executables.
- Related: compiler.core.069, compiler.core.007

### compiler.core.064 — A compiler-held dependency DLL blocks child rebuilds

- Recorded: 2026-09-30 15:28
- Evidence: a serial native Swag Prism test with the DevMode compiler and program configuration
  `release` loads `bin/std/.output/core/shared-library/release/x86_64/core.dll` in its parent
  compiler. The test's child compiler requests `build --build-cfg release --optim-level 0` for a
  temporary Core importer and tries to republish that DLL. The write fails with access denied;
  the diagnostic identifies the parent `swc.dm.exe` as its owner. Six workers and serial execution
  reproduce it. Running a script concurrently can hold the same source artifact and expose the
  same failure, but concurrency between campaigns is not required.
- Boundary: scripts use immutable dependency-cache copies, and external workspace dependencies
  are mirrored into `.dep`; workspace-local dependencies can still be loaded from their mutable
  `.output` directories. `ExternalModuleManager` retains loaded libraries for the process.
  Prism's retired probe helper exposed this by forwarding snippet optimization levels to all
  dependencies; its current `BuildArtifact` path sets the level on the snippet's module instead.
- Next: reduce the parent compile-time DLL call followed by a child's forced dependency rebuild
  to a workspace-suite fixture. Audit shared-library resolution during dependency builds and
  separate compiler-loaded library lifetime from the mutable publication path, while preserving
  native linking, publication, cache invalidation, and runtime-instance ownership.
- Complete when: the fixture rebuilds the dependency while its parent compiler remains alive,
  with both compiler executables, and workspace reuse and publication checks still pass.

### compiler.core.063 — Reduce the PDF spill-slot regression to a standalone language test

- Recorded: 2026-09-30 11:15
- Updated: 2026-09-30 14:18 — retain only the standalone regression coverage still missing
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
- Complete when: `bin/unittests/native` reproduces this stack-depth aliasing independently of GUI,
  alongside the existing C++ regression and PDF consumer tests.

### compiler.core.061 — Type-info graph publication uses one serialization domain

- Recorded: 2026-09-30 08:34
- Updated: 2026-09-30 13:48 — narrow the remaining boundary to canonical graph ownership
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
- Complete when: independent components can progress on different workers, mutually recursive
  graphs publish no partial data, and identity, interface, and reflection tests pass under
  repeated parallel cold compilation.
- Related: compiler.core.020, compiler.core.007.

### compiler.core.007 — Workspace front ends and code generation run serially

- Recorded: 2026-08-09 20:16
- Updated: 2026-09-30 07:58 — Located the shared state that must be isolated before scheduling module front ends concurrently.

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

**Complete when.**

- Independent sibling modules overlap front-end and code-generation work, while consumers wait for the required interface or link artifact.
- Compiler and linker work share a bounded concurrency policy and do not oversubscribe the host.
- Logs, manifests, diagnostics, and emitted artifacts remain deterministic.
- The concurrency cap accounts for the memory measurements and budget from compiler.core.005.
- Workspace tests cover a diamond graph, concurrent failures, cancellation, and deterministic repeated builds.

**Related:** compiler.core.004, compiler.core.005.

### compiler.core.005 — Compiler memory has no attributed, enforced budget

- Recorded: 2026-08-06 20:18
- Updated: 2026-09-29 16:26 — commit-on-demand allocator pages, live-only sanitizer states, lighter symbols; per-worker fragmentation attributed

**Evidence (2026-09-29, Release `swc.exe`, peak committed memory of the job, order-alternated A/B against master `d748642a5`).** Four changes landed on `perf/memory-footprint-20260929`: mimalloc small pages commit in 16 KiB steps instead of whole 64 KiB pages; the sanitizer keeps only registers live on entry to a chain head in its stored states (chain liveness computed once per function); per-symbol `std::mutex` become `std::shared_mutex` and the symbol map's big hash map is created only past eight keys; a function's `MicroBuilder` is created at code generation and deleted once lowered. Bench JIT tasks at the default worker count: hello 97 -> 65 MB, wordfreq 131 -> 96, chacha release 132 -> 95, chacha devmode 216 -> 99 (0.62x wall: the sanitizer copies far smaller states), raytrace 107 -> 74, dijkstra 157 -> 123; hello build 112 -> 78 MB; core devmode rebuild (`--num-cores 6`) 579 -> 389 MB with wall min 3.30 -> 2.86 s. Wall-time median ratios stay 0.92-1.00 on every workload. The native programs themselves were already at parity with C++ and are unchanged.

**Attribution after these changes (hello JIT, mimalloc statistics).** Live allocated bytes peak at 16-17 MiB whatever the worker count, but committed memory is 25 MiB with one worker, 42 MiB with six and 61 MiB with 22 (164 -> 238 -> 418 pages): the rest of the JIT overhead is fragmentation across the per-thread heaps, each holding the high-water mark of its own transient allocations. About 10 MiB of it follows the Micro pipeline's `thread_local` scratch (`-O 0` 54 MiB vs `-O 2` 64 MiB at 22 workers), the rest the semantic analysis of the runtime prelude spread over the workers. Measured and rejected: a 4 KiB commit step (-5 MiB, but about +11% median wall on hello JIT); mimalloc purge delay, page retention and reclaim options (no effect). A function's JIT code occupies at least one 4 KiB page because protection is flipped per allocation. `PagedStore::publishPages` copies the whole page table, and keeps every earlier copy for lock-free readers, each time a page is added: 81 KB on hello and 5.3 MB on the core devmode rebuild (61,329 snapshots, largest store 83 pages).

**Evidence (2026-09-05, Release `swc.exe`, `--num-cores 6`, peak working set).** Before: core devmode rebuild 731 MB, core release rebuild 638 MB, hello 73 MB, bench tasks 74-83 MB. After finished jobs release their Sema and CodeGen state, 64 KiB arena blocks, and the api-export index dropped after export: 517 MB, 360 MB, 60 MB, 58-66 MB, with wall time at 0.86x, 0.95x, 1.0x, 0.97x (order-alternated A/B). Attribution by mimalloc statistics and a throwaway sampling probe on the DevMode core rebuild: the largest block still resident at peak is the static sanitizer's flow state (`SanitizerState` copies, ~150 MiB of ~100-byte map nodes, 17M allocations per core rebuild), then paged AST/payload/type stores (~110 MiB), per-thread arenas (~95 MiB, dominated by 2 KB `SymbolFunction` and 1.3 KB `SemaInlinePayload`), the CodeGen objects of sleeping codegen jobs (~23 MiB), and link-time archive buffers (~23 MiB). The compile-time runtime allocator is not a factor.

**Intent.** Use external profiling and the compiler.core.004 workloads to reduce retained AST, semantic, Micro, and temporary state, then turn the agreed memory targets into regression checks.

**Next.** Reduce per-worker high-water marks without reducing parallelism: shrink or share the Micro pipeline's retained `thread_local` scratch, and find which transient semantic allocations a prelude job makes (the 20 KiB and 5 KiB bins hold in-flight `CodeGen` (10.5 KB, 5.6 KB of it an inline 32-entry defer-scope vector) and `Sema` (5 KB, 3.5 KB of it `AstVisit`'s inline stack)). Pack JIT functions into shared pages once the patcher no longer relies on page-sized allocations.

**Complete when.**

- A full core DevMode build peaks below 250 MiB and a hello-world build below 40 MiB on the campaign host.
- Every campaign workload stays within twice the best comparable compiled-language implementation measured by the same harness, or records a reviewed exception.
- Thresholds, host normalization, and variance policy are stored with the campaign.
- External profiling attributes the remaining peak well enough that a regression report names the responsible subsystem.

**Related:** compiler.core.004, compiler.core.007, runtime.allocator.017.

### compiler.core.057 — The lazy-body completion race has no deterministic regression

- Recorded: 2026-09-24 14:07
- Updated: 2026-09-29 14:26 — Root cause fixed; only the regression seam remains.
- Area: compiler/semantic analysis, lazy bodies of generic-instance, imported and runtime functions.
- Evidence: `Core.HashTable.find` (`hashtable.swg:594`, `.tryFind(key)`) intermittently reached
  `resolveSelectedCallFunction` with no bound function symbol, once in a six-worker
  `std/core --rebuild` comparison on 2026-09-24 and once in
  `tools/std.swgs dm test core -bc release` on 2026-09-29. The declaration walk that hands a
  body to the lazy runner could still complete the function in `AstFunctionDecl::semaPostNode`:
  it read `LazyBodyRunning` twice, and a runner starting between the two reads made the walk
  publish the function and schedule its code generation while the runner was still resolving
  the body. `semaPostNode` now leaves a delegated body to its runner. A temporary 3 ms delay
  between the two reads made one core release test report six premature completions
  (`Core.Array.grow`, `Swag.panic`, `Core.HashTable.tablePtr`, `__ftoa`) and stop on a missing
  identifier symbol in code generation; with the fix, three delayed runs and ten undelayed runs
  passed with none.
- Why no suite test: the failure needs another task to start the lazy run inside a window of a
  few instructions in the declaration walk. No suite source or C++ test can place a thread there.
- Next: add a DevMode scheduling-stress option that delays the declaration walk's post-node
  when its function has a lazy body, and run `tools/std.swgs dm test core -bc release` with it
  from the `cpp` or `workspace` campaign. Check whether `compiler.core.047` (a generic local
  defined twice in `HashTable`) reproduces under the same stress before attributing it here.
- Complete when: a repeatable test fails without the post-node ownership check and passes with it.

### compiler.core.030 — Every executable lowers the runtime's functions again

- Recorded: 2026-09-05 22:13
- Updated: 2026-09-23 09:29 — Measured how far this cost has grown with the runtime, and what the benchmark saw.

**Evidence.** Profiled on 2026-09-05 (Release 0.1.367 with a PDB, six worker cores, a user-mode sampling profiler): a hello world build spends 38 % of its thread samples in `CodeGenJob::exec`, 31 % of them in `MicroPassManager::run`, against 8 to 11 % in semantic analysis. The stage log says why — `tuned 172 functions`, `forged 320 functions`, for a four-line program: the runtime's own functions are lowered and optimized again for every executable, at the `release` preset's `O2`. `swc sema` on an empty file shows the same shape at 19 %: the prelude's `const __buildCfg = #run Swag.compiler().getBuildCfg()![]` (bin/runtime/core.swg) JIT-lowers about a hundred runtime functions so that the build configuration, which the compiler already holds in C++, can be read back through compile-time execution. On a quiet machine the same run measured `swc help` at 34 ms, the prelude's syntax at 35 ms, its sema at 165 ms and the hello world build at 197 ms (0.1.369, six cores); the campaign's `hello_build` target is 50 ms.

**Evidence (2026-09-09, Release 0.1.422, twelve workers, minimum of ten interleaved runs).** The JIT half of this entry no longer costs a native build anything: replacing `const __buildCfg = #run …` with a plain variable in the prelude leaves a snippet build at 91 ms either way, with the same 448 tuned and 441 forged functions, because a native artifact lowers the runtime regardless. The lowering half is what remains, and it is now the largest term of a Swag Prism snippet compilation: the same probe takes 116 ms as a static library and 68 ms with `--artifact-kind export`, so lowering and linking the runtime is 48 ms of it, against 52 ms for the prelude's own semantic pass (compiler.core.006) and 16 ms of process start.

**Evidence (2026-09-23, Release 0.1.1046).** This cost grew with the runtime, not with the compiler. `bin/runtime` went from 8 files and 5 260 lines on 2026-08-07 to 19 files and 8 629 lines on 2026-09-21 — +64 %, as the scheduler, tasks, parallelism, sync, TLS, atomics and symbol families landed — and the benchmark followed it: the Swag build series reads 106 ms on 2026-08-07 against 172 ms on 2026-09-20, and the campaign headline `build_edge`, how many times faster `swc` compiles than the other toolchains, fell from 4.08 to 2.65 over those eight campaigns. A hello world release rebuild now reports `checked 20 files • 42 719 tokens • 43 ms`, `tuned 176 functions • 76 ms`, `forged 314 functions • 91 ms`, for 153 ms of process time: the prelude and the runtime are the entire measurement, and every family added to `bin/runtime` is lowered again by every executable anyone compiles. None of it is a compiler regression; it is this entry and compiler.core.006 scaling with the runtime's surface.

**Intent.** Keep the runtime's lowered code between builds — per compiler build, configuration and architecture, like the module setup cache keeps a setup. Prelude-state reuse belongs to compiler.core.006; this entry owns lowered runtime artifacts.

The 2026-09-28 prompt-4 continuation removed one Micro instruction lookup per emitted instruction:
`MicroBuilder` now records its source on the pointer returned by allocation. This keeps the same
source information for sanity diagnostics and debug tables. The Release `location` selection
passed 18 native tests; timing and peak memory were not measured.

**Complete when.**

- A build whose sources contain no compile-time execution lowers nothing of the runtime and runs no JIT code.
- The cached runtime code is invalidated by the compiler build, the runtime sources, the configuration and the target, and a workspace test proves a fresh and a reused runtime produce identical executables.
- `hello_build` in the compiler.core.004 campaign reads under 50 ms on the campaign host.

**Related:** compiler.core.001, compiler.core.004, compiler.core.006, compiler.optimization.029.

### compiler.core.003 — Code-generation invalidation is module-wide

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-19 12:32 — make every safe native cache part of the default build path

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

**Complete when.**

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

- Recorded: 2026-09-16 19:54
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
  cache reuse from shared code-generation state when cloning the macro's closure.
- Complete when: a stable reproducer identifies the cause, the correction passes
  that reproducer repeatedly, and the full native suite remains green.

### compiler.core.051 — Isolate a silent CodeGen failure observed in a discarded JIT prototype

- Recorded: 2026-09-16 18:31
- Found while: comparing Release compilation of `bin/std` with six pinned performance workers.
- Evidence: an unmerged build-710 prototype based on `277804c1c` returned exit 5 on the third
  candidate rebuild of `swc.exe build -w bin/std -m gui -bc release --num-cores 6 --rebuild`.
  Seven dependency modules completed; gui stopped with
  `internal compiler error: job 'CodeGen' returned an error without a diagnostic`.
- Scope: the prototype transferred the existing shared JIT-order lock to its reader and reused
  local dependency/completion vectors. It was discarded. The same gui command passed once in
  DevMode; three further runs with unchanged Release build 702 passed. Neither a production
  regression nor a causal connection to either prototype change has been established.
- Evidence location: `bench/results/compilation/20260916-bin-release/README.md` and its sample
  CSV retain the command context, compiler hashes and failed run. The session's external
  `jit-order-lock-buffers-710.patch` and `jit-order-control` compilers retain the exact prototype.
- Next: capture the function, waited symbol and failing return path at `abortCodeGen`, replay
  candidate and baseline, and isolate lock transfer from vector reuse before reviving either
  optimization. Do not classify this as compiler.core.047 without a matching generic-local witness.
- Complete when: a bounded reproducer identifies the responsible path, or evidence confines the
  failure to an invalid discarded prototype; remove this entry once that question is settled.

### compiler.core.048 — Offer semantic cleanup edits with explicit preservation checks

- Recorded: 2026-09-16 16:06
- Evidence: the bin/ cleanup changed 53 direct-return bodies, five declaration/with pairs and
  two relay locals. Candidate searches also found deliberate language-test syntax, owning locals
  and typed temporaries which cannot safely be removed by a textual rewrite. The formatter
  normalizes source shape; it cannot decide ownership, overload selection or evaluation effects.
  Existing LSP entries cover diagnostics, navigation, completion and rename, not these rewrites.
- Proposed contract: a compiler-backed suggestion produces a previewable, versioned source edit
  only after proving the specific transformation preserves meaning. Start with expression bodies,
  declaration-bound with and copyable relay returns. Preserve evaluation count/order, receiver
  binding, contextual type, selected overload, lexical scope and destruction timing.
  A single-use variable is a candidate, not proof of redundancy.
- Boundaries: distinguish semantics-preserving cleanup from a diagnostic explaining a costly copy
  and from a breaking language migration. Never turn a copy into a move, a required receiver into
  an optional call, or a named owner into a temporary borrow automatically. Preserve comments and
  do not rewrite intentional syntax fixtures as part of an unfiltered bulk operation.
- Next: implement a semantic rewrite query on an ordinary compiler snapshot with a dry-run diff.
  Prove positive and negative examples for each of the three initial transformations; expose the
  same edits as editor code actions once compiler.core.008 provides the session layer. Wider
  API-family renames use compiler.core.014 plus an explicit migration, not a cleanup heuristic.
- Complete when: suggested edits apply only to the analyzed document version, are idempotent,
  compile with the same relevant contracts, and regression tests reject transformations that
  alter effects, ownership, overload resolution or scope. A CLI preview works independently of LSP.
- Related: compiler.core.008, compiler.core.009, compiler.core.014;
  language.design.024 in [language.design.md](language.design.md).

### compiler.core.047 — A script import intermittently defines a generic local twice

- Recorded: 2026-09-16 09:28
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
- Next: replay the cached script import alongside module builds, capture generic-instance
  ownership and semantic restarts around the duplicate local, and compare with the parent
  compiler before attributing the failure to parsing, publication, or scheduling.
- Complete when: a bounded reproducer identifies the duplicate visitation or publication,
  the root cause is fixed, and the script passes repeated parallel imports with six workers.

### compiler.core.045 — A conditionally evaluated `!` cannot record the proof it makes

- Recorded: 2026-09-15 12:47
- Found while: making the postfix `!` prove its own path so a second one on that path is
  rejected (`sema_err_notnull_already_proven`).
- Evidence: a proof is recorded by mutating live frames in place, because pushing a frame with
  an ancestor-anchored pop from the middle of a statement breaks the LIFO discipline of the
  deferred pops. The right operand of `and`/`or`, a branch of `?:`, the fallback of `orelse` and
  the tail of a `?.` chain are each evaluated on a decision taken to their left, and none of them
  carries a frame of its own: `AstLogicalExpr::semaPostNodeChild` pushes one only when the left
  side yielded facts, and the other three push none. A fact recorded inside one would therefore
  outlive the region that justifies it, so `notNullRunsUnconditionally` in
  `Sema.Function.Flow.cpp` refuses to record anything there.
- Cost: `p!` written in those positions teaches the compiler nothing, so a later `!` on the same
  path is not reported and its runtime guard is still emitted. Measured on the 2026-09-15 sweep:
  246 assertions were removed across `bin/`, and the paths left untouched are dominated by
  sibling `case` bodies (which are correctly out of scope) and by these conditional operands.
- Next: give each conditionally evaluated operand its own frame unconditionally — the `and`/`or`
  right side whatever the left side yielded, both branches of `?:`, the `orelse` fallback, and
  the `?.` chain tail — then drop the `notNullRunsUnconditionally` guard and let the frame pop
  scope the fact. Measure sema time on `bin/std` before and after: this adds a frame push per
  logical expression.
- Complete when: `p!` in an `and` right side proves the path for the rest of that operand and
  for nothing beyond it, with a JIT case for each of the four forms in
  `bin/unittests/jit/flow/nullable_narrow.swg` and the negative controls in
  `bin/unittests/errors/sema/sema_err_notnull_already_proven.swg` still passing.

### compiler.core.020 — Concurrent type generation can corrupt declared-method traversal

- Recorded: 2026-08-10 12:35
- Updated: 2026-09-14 10:43 — repeated the affected module builds after the publication fixes; the historical corruption remains unattributed
- Area: compiler
- Found while: rerunning `tools/tests.swgs dm --all-cfg` after an unrelated intermittent
  semantic-completion assertion had passed on immediate focused rerun.
- Observation: a later multi-configuration pass ended with a mimalloc corrupted-free-list report
  and a hardware exception while type generation traversed a struct's declared methods. The same
  compiler and sources had completed the full Release campaign immediately beforehand, and the
  equality suites had already passed in all three build configurations, so the failure appears
  scheduling-dependent rather than tied to one deterministic source construct.
- Evidence: mimalloc reported a corrupted 32-byte free-list entry. The stack ran through
  `appendImplFunctions` and `SymbolStruct::declaredMethods` in `Symbol.Struct.cpp`,
  `findGeneratedImplicitMethod`, `findGeneratedLifecycleWrapper`, `initStruct`,
  `TypeGen::processTypeInfo`, and then function-candidate implicit-conversion probing. The isolated
  command is `swc tools/tests.swgs dm --all-cfg`; it failed only in a downstream standard-library
  leg after lexer, parser, sema, JIT, safety, sanity, native, and workspace suites had passed in all
  three configurations.
- Current validation (2026-09-14): 100 Release 0.1.571 rebuilds of `core` completed with
  byte-identical sets of 24 published API files. Another 20 Release and 20 DevMode rebuilds
  of `ogl` completed without a crash. The current declared-method traversal copies impl and
  interface lists under shared locks, and `SymbolMap::getAllSymbols` snapshots each map under
  its corresponding lock. This session also fixed mutable attribute snapshots and lifecycle
  pointer publication, with regression tests. These results establish non-recurrence under
  those workloads; they do not identify the writer that caused the original free-list damage.
- Next step: re-evaluate on the next occurrence only. The 2026-08-12 sanification pass eliminated
  three writers able to corrupt or misread memory underneath a stack like this one: a struct
  layout republished through transient zero and partially accumulated sizes on every post-node
  resume (`SymbolStruct::computeLayout`, now computed into locals and published once, atomically);
  imported native modules keeping `Swag.processInfos().args` slices into a destroyed compiler instance's
  storage (`ensureProcessInfosRunArgs`, now interning into process-lifetime storage); and the call
  matcher reading the signature type of a selected candidate before that type was published
  (`Match::resolveFunctionCandidates`, which now parks until the winner is typed — caught live as
  a `typeRef.isValid()` assertion under `finalizeAutoEnumArgs` while building the generated `ogl`
  wrappers, one run in ~20; in Release that read returned an out-of-bounds `TypeInfo`). A mimalloc
  report now appends the reporting thread's stack (`Allocator.cpp`), so a recurrence preserves its
  detection stack; if one does recur, persist the failing module and stress parallel type
  generation as originally planned.

### compiler.core.038 — Measure the remaining semantic frame construction cost

- Recorded: 2026-09-09 15:04
- Updated: 2026-09-14 06:24 — narrowed the investigation after conditional frame copies and compact safety state landed
- Historical evidence: Release 0.1.425 pushed 41,573 frames for a 22,800-line file and
  259,030 for a snippet importing `core`; `SemaFrame` then occupied 1,376 bytes. Removing
  one copy at 42 push sites was tried and reverted after three paired runs measured
  100.0%, 102.6%, and 103.8% of baseline processor time. The earlier attribute-list shrink
  had removed non-trivial string-vector construction and destruction, not just copy bytes.
  Those counts and sizes describe that build, not the current implementation.
- Current evidence: `Sema::preNode` now copies a frame only when a node introduces syntax,
  compiler-evaluation, or generated-top-level context, directly into the scoped destination.
  `AttributeList` now summarizes sanity and runtime-safety overrides with masks instead of
  copying override histories (`ab595100b`, `55a30fbbf`). `SemaFrame` still owns non-trivial
  collections for namespaces, bindings, iteration borrows, hidden symbols, and narrowing
  facts, and `AttributeList::attributes` still stores attribute instances. The
  [September 13 report](../bench/results/compilation/20260913-sema-codegen/README.md)
  records the implemented reductions and their validation; it does not establish how much
  these remaining members cost or attribute a timing gain to this entry alone.
- Next: remeasure frame-push counts, populated-member frequency, and constructor/destructor
  samples on the current compiler for both original workload shapes. Only select a member
  for deferred storage or a call site for reuse if that measurement shows a material cost;
  the reverted copy-only experiment is not evidence that the current cost is zero.
- Complete when: current measurements either identify a bounded, worthwhile change with a
  reproducible A/B comparison, or show that the residual cost does not justify further work.
- Related: compiler.core.001, compiler.core.005, compiler.core.006.

### compiler.core.041 — Reduce parallel dependency registration to a workspace-suite witness

- Recorded: 2026-09-11 23:34
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
  Keep the existing C++ concurrency test as the precise internal guard.
- Complete when: a `bin/unittests/workspace` case fails with unsynchronized registration, passes
  with synchronized registration under both compiler executables with six workers, and verifies
  dependency retention and subsequent invalidation without an intermittent timeout as its oracle.

### compiler.core.004 — The benchmark campaign has no regression threshold on the edit-build loop

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-10 19:43 — Account for the September 6 campaign that already records edit-build workloads.

**Evidence.** Since 2026-09-05 the campaign measures the edit-build loop beside the seven tasks: `core_rebuild`, `core_noop`, `core_touch`, `hello_build`, `doc_std` and `format_tree` (`bench/toolchains.py`, `make_compiler_workloads` and `make_hello_builds`), each recorded with wall time, every sample and peak memory, corrected by the campaign's compilation context and indexed against the first clean campaign that measured it (`history.py`, `index_loop`). `bench/compile.py` answers the round-by-round A/B between two compilers. On 2026-09-05, Release 0.1.366, six worker cores, medians of five on a quiet machine: `core_rebuild` 3 485 ms, `core_noop` 334 ms, `core_touch` 3 214 ms, `format_tree` 5.6 s at one busy core, `doc_std` 142 s and 3.3 GiB peak, the standard-library publish pass included. The four August protocol-2 records predate these workloads. The later
[20260906-143159 record](../bench/results/20260906-143159.json) contains all five `loop`
workloads and the separate hello-world build result. One such record does not establish the
five-campaign baseline band required below.

**Intent.** Record enough clean campaigns to know the resolution of each workload, then make the campaign report a regression instead of only plotting it.

**Measurement caveat (2026-09-06).** The original benchmark memory field is process-tree peak
committed memory. The instrument now records the timed process's peak working set separately;
older samples have no resident-memory value and must not be used to set that threshold. Memory
is not normalized by timing context. Formatter source mirrors now preserve `.swc-format` and
the maintenance tool's complete input selection; the remaining input-opening bias is tracked
in repo.tooling.007. Establish the baseline band using these corrected inputs and explicit
compiler-worker counts.

**Complete when.**

- At least five clean baseline campaigns establish the resolution band of every edit-build workload, as the null indices already do for the tasks.
- The campaign reports a workload that moved past its band without silently rewriting the baseline.
- Release and DevMode are measured where their behavior differs, and the report says which one a number belongs to.

**Related:** compiler.core.002, compiler.core.005, compiler.core.007.

### compiler.core.006 — Every process rebuilds the prelude state

- Recorded: 2026-08-06 20:18
- Updated: 2026-09-09 12:34 — remeasured on 0.1.422 against the Swag Prism edit loop

**Evidence.** On 2026-09-05 (Release 0.1.369, six worker cores, quiet machine): `swc help` 34 ms, `swc syntax` on an empty file 35 ms, `swc sema` on the same 165 ms. The prelude is 14 files and 32 948 tokens; its semantic pass, including the JIT run compiler.core.030 describes, is what separates the last two numbers, and every module setup used to pay it once more until the setup cache of 0.1.367 kept the result.

**Evidence (2026-09-09, Release 0.1.422, twelve workers).** Measured against the Swag Prism edit loop, which compiles one snippet per keystroke: a snippet module that imports nothing takes 116 ms, of which 16 ms is process start and 48 ms is lowering the runtime (compiler.core.030). The remaining 52 ms is this entry — the prelude analyzed again for a snippet that never changes it.

**Intent.** Serialize and reuse the prelude through the same module-interface mechanism as ordinary dependencies, rather than maintaining a special prelude cache.

**Complete when.**

- A warm hello-world build and a warm script launch load the prelude interface without lexing, parsing, or semantically rebuilding the prelude.
- Prelude source, compiler version, target, and relevant configuration changes invalidate the interface.
- Fresh and reused prelude paths produce identical diagnostics and artifacts.
- The compiler.core.004 campaign demonstrates the reduced fixed startup floor.

**Related:** compiler.core.001, compiler.core.004, compiler.core.016.

### compiler.core.001 — Dependencies cross the module boundary as regenerated source

- Recorded: 2026-08-06 20:18
- Updated: 2026-09-09 12:21 — measured what the regenerated API costs an interactive consumer

**Evidence.** Swag Prism compiles one snippet per keystroke through a `swc build`, and on 2026-09-09 (Release 0.1.421, quiet machine, minimum of nine interleaved runs) that compilation cost 294 ms of which the user's code was 1 ms: a five-line snippet took 400 ms and a 1 400-line one 421 ms. The fixed cost decomposes into 17 ms of process start, 32 ms for the runtime prelude, 14 ms for the module setup, 60 ms to lower and link the runtime, and **172 ms to lex, parse, and analyze `core`'s generated API again** — 32 files and 115 000 tokens, on every keystroke. The heavier viewers pay the same cost scaled by their dependency: `pixel` 248 000 tokens and 672 ms, `gui` 365 000 tokens and 986 ms. A binary module interface is what removes that term; nothing else in the budget is large enough to reach a realtime edit loop.

**Intent.** Replace generated dependency API source with a versioned binary module interface. The interface must preserve exported symbols, types, constants, attributes, ABI information, and any bodies or metadata required by downstream optimization, while allowing lazy lookup by symbol.

**Complete when.**

- Workspace imports no longer add generated API `.swg` files to the lexer and parser.
- `--export-api-dir` still emits a human-readable `.swg` representation for inspection and tooling.
- Cache invalidation covers compiler version, build configuration, public declarations, exported constants, ABI-relevant attributes, and serialized inlinable bodies.
- Workspace tests prove that fresh and reused interfaces produce identical diagnostics and artifacts.
- One snippet compilation that imports `core` no longer spends its time in the front end of that import.

**Related:** compiler.core.002, compiler.core.006, compiler.core.008, compiler.core.011, compiler.core.030.

### compiler.core.011 — The editor has no semantic definition navigation

- Recorded: 2026-08-09 20:16
- Updated: 2026-09-06 07:51 — git: prompt 6

**Evidence.** The VSCode extension registers build, rebuild, and format tasks. It registers no
definition provider and does not consume resolved compiler symbols.

**Intent.** Resolve the symbol referenced at a source position and return its canonical declaration location, including declarations in dependencies represented by persisted interfaces.

**Complete when.**

- Navigation covers locals, parameters, members, overloads after resolution, generics, aliases, generated declarations with an available source origin, and imported symbols.
- Ambiguous or unresolved positions return no misleading location.
- Paths and ranges are valid for open snapshots and on-disk dependency sources.
- Protocol tests cover same-file, cross-file, cross-module, overload, and no-result cases.

**Related:** compiler.core.001, compiler.core.008, compiler.core.012.

### compiler.core.002 — Front-end invalidation is module-wide

- Recorded: 2026-08-06 20:18
- Updated: 2026-09-05 22:11 — git: Measure the edit-build loop in the benchmark campaign

**Intent.** Persist lexical, parsed, and semantic state per source file. Cache keys must include the source content, relevant build configuration, and fingerprints of imported public symbols actually observed by the file.

**Complete when.**

- Editing a private body reanalyzes only the changed file and its semantic dependents.
- Changing a public signature invalidates every consumer that observed it.
- Adding, removing, or renaming a file, changing relevant configuration, and changing compiler versions invalidate the correct state.
- The compiler.core.004 `core_touch` workload lands far below `core_rebuild`, which today it does not: one saved file rebuilds every file of the module.
- Clean and incremental workspace builds are covered by equivalent-result tests.

**Related:** compiler.core.001, compiler.core.004, compiler.core.003, compiler.core.016.

### compiler.core.008 — There is no persistent language-server process

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Add a compiler-hosted LSP transport and session layer: initialization and shutdown, workspace discovery, document open/change/close notifications, versioned snapshots, request cancellation, and orderly teardown. Requests must call compiler-library services instead of launching a compiler process per operation.

**Complete when.**

- A standard LSP client can open a workspace, edit unsaved buffers, cancel obsolete requests, and shut down cleanly.
- Responses are computed from the requested document version and stale work cannot publish newer state.
- The session reuses persisted compiler state from compiler.core.001 and compiler.core.002 when available.
- Protocol integration tests run independently of the VSCode extension.

**Related:** compiler.core.001, compiler.core.002, compiler.core.010, compiler.core.011, compiler.core.013, compiler.core.014, compiler.core.009, compiler.core.012.

### compiler.core.009 — Open documents have no incremental diagnostics

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Publish parser and semantic diagnostics for the accepted version of every open document, including affected dependents, without requiring a workspace build.

**Complete when.**

- Opening a file with an error publishes diagnostics, correcting it clears them, and closing it restores the on-disk view.
- A stale analysis job never overwrites diagnostics for a newer document version.
- Diagnostic identifiers, severity, primary and related locations, source snippets, and normalized paths survive the protocol conversion.
- A multi-file protocol test covers an edit that introduces and then repairs a dependent-file error.

**Related:** compiler.core.002, compiler.core.008.

### compiler.core.010 — The editor has no semantic completion service

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Provide completion candidates from the semantic snapshot at a source position, including local scope, members, visible imports, generic parameters, and applicable language constructs.

**Complete when.**

- Completion operates on unsaved, syntactically incomplete buffers and honors shadowing and visibility.
- Items include stable kind, insertion text, signature/detail, and documentation fields where available.
- Results are deterministic and cancellable, and a stale request cannot populate a newer buffer.
- Protocol tests cover local, member, import, generic, incomplete-expression, and inaccessible-symbol cases.

**Related:** compiler.core.008, compiler.core.011, compiler.core.013.

### compiler.core.012 — The editor cannot find semantic references

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Enumerate references to the resolved declaration at a source position across the workspace, distinguishing declarations from uses and excluding textually identical but semantically different symbols.

**Complete when.**

- Results cover locals, members, overloads, generics, aliases, and cross-module references.
- The request supports including or excluding the declaration and uses versioned open-document snapshots.
- Shadowed names, comments, strings, and unrelated overloads do not appear.
- Results are deterministic, deduplicated, cancellable, and covered by same-file and cross-module protocol tests.

**Related:** compiler.core.008, compiler.core.011, compiler.core.014.

### compiler.core.013 — The editor has no semantic hover service

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Render concise semantic information for the resolved entity at a source position: declaration signature, inferred type or constant value, ownership and relevant attributes, and public documentation.

**Complete when.**

- Hover covers values, types, functions and selected overloads, generic parameters, fields, aliases, and literals with inferred types.
- Output uses stable Markdown escaping and does not expose internal compiler-only names.
- Unknown or ambiguous positions return no misleading result.
- Protocol tests cover imported documentation, inferred values, overload resolution, and no-result cases.

**Related:** compiler.core.008, compiler.core.010, compiler.core.011.

### compiler.core.014 — The editor cannot rename a symbol semantically

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Validate a requested identifier at a resolved declaration, reuse the semantic reference set, and produce a versioned workspace edit without changing unrelated text.

**Complete when.**

- Prepare-rename rejects keywords, compiler-generated or immutable declarations, ambiguous positions, and names that would create a known collision.
- Rename covers declarations and references across open and on-disk workspace files while preserving comments and strings.
- Edits are sorted, non-overlapping, versioned where required, and rejected when snapshots become stale.
- Protocol tests cover shadowing, members, overloads, aliases, cross-module use, collision, and cancellation.

**Related:** compiler.core.008, compiler.core.012.

### compiler.core.016 — Tool scripts recompile on every invocation

- Recorded: 2026-08-09 20:16
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity

**Intent.** Persist compiled script artifacts using a dependency-complete key over loaded source files, imported public interfaces, compiler version, target, and relevant build configuration.

**Complete when.**

- A second unchanged invocation skips script lexing, parsing, semantic analysis, and code generation before launching the cached artifact.
- Changes in the main script, `#load` inputs, imported public APIs, compiler version, target, or relevant configuration invalidate the artifact.
- Cached and fresh paths preserve diagnostics, forwarded arguments, environment handling, output, and exit code.
- Tests cover direct source changes, transitive loads, imports, configuration changes, corrupt entries, and concurrent cache population.

**Related:** compiler.core.001, compiler.core.002, compiler.core.006, platform.portability.080.

### compiler.core.027 — A run-time loaded shared library cannot share the host's runtime

- Recorded: 2026-08-30 12:06
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
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
- Complete when: either a loaded shared library provably shares the host's allocator and context in
  a workspace test that links its dependencies in, or the backlog records why it cannot and the
  compiler diagnoses the combination it can see.

---

## Deliberately out of scope

- **An LLVM back end.** The native and Micro back ends are the supported architecture. Reconsider only if a concrete platform or optimization requirement cannot be met within them.
- **A second language front end.** The compiler architecture is optimized for Swag; a second parser and semantic model would dilute the persisted-state and tooling work above.
- **A package registry inside the compiler backlog.** Path and workspace dependencies remain compiler responsibilities. Registry identity, trust, lockfiles, acquisition, and publishing need a separate product backlog once their scope and owner are defined.

Frontend, semantic analysis, and code generation defects: something observed in `swc` itself, with
a reproduction and a next investigation step. Optimization passes and generated-code performance
are [compiler.optimization.md](compiler.optimization.md); the borrow, lifetime and sanity analyses
are [compiler.safety.md](compiler.safety.md); the `doc` and `format` commands have their own files,
[compiler.command.doc.md](compiler.command.doc.md) and [compiler.command.format.md](compiler.command.format.md).
