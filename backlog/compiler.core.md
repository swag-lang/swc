# Compiler Backlog

This backlog covers the compiler front end, back end, and workspace build engine. Documentation, formatting, and language-design work have their own domain files. Only unfinished work belongs here; completed investigations and implementations remain discoverable through Git history.

Entries stay in one flat list. Keep only measurements that affect the next action; refresh them before relying on them.

### compiler.core.088 — Capture the intermittent standard-library documentation exception

- Evidence: `doc --workspace <private std> --rebuild --num-cores 6` exited with code 3 and a
  Windows exception report before producing HTML in a combined benchmark campaign. The old
  driver truncated the report before retaining the failing task and instruction. The same
  Release subject subsequently completed twice; the preserved pre-change compiler and the
  corrected DevMode and Release compilers also completed. No reduced case identifies the cause.
- Next: repeat the compiler workload with complete failure capture, preserving its compiler,
  runtime, module outputs and cache state. Use the first full exception report to distinguish
  host compilation from generated setup code and reduce that exact boundary. Do not attribute
  the fault to an optimization without a matching reproducer.
- Done when: a reduced regression fails before a root-cause repair and passes afterwards,
  with the complete documentation command green under both compiler executables.

### compiler.core.085 — Build shared libraries to identical bytes

- Evidence: executables, static libraries and the benchmark tasks rebuild identically with six
  workers; `core.dll`, `pixel.dll` and `gui.dll` still differ. Two sources remain. The set of
  generic instances varies: one build of `core.dll` emits one more `Core.Math.max` instance than
  the next, and a shared library emits every instance its analysis created. And `.rdata` holds a
  duplicated 16-byte string constant in some builds only: `Core.Env.showInFileExplorer` reaches
  three such constants in one build and two in the next. The machine-code cache keys ignore
  both string copies and global placement; the varying instance set alone still adds one or two
  records per six-worker `core` build.
- Next: log which call sites create `Core.Math.max` instances in two builds and find the
  speculative instantiation; then trace the `showInFileExplorer` string constants back to
  `materializeRuntimeStringConstant` and `materializeRuntimeBufferConstant` to see which cache
  lets one value materialize twice.
- Done when: rebuilding `core`, `pixel` and `gui` twice with six workers produces identical
  shared libraries apart from the image timestamp.

### compiler.core.084 — Stop native test recovery from reusing state abandoned by a panic

- Evidence: a safety panic in SVG parsing while `defaultThemeImages` holds its cache mutex
  skips the deferred unlock. The native test runner catches the panic and starts the next GUI
  test in the same process; that test waits on the abandoned mutex until the module timeout.
  The original failing test is reported, but subsequent tests cannot make progress.
- Next: define the recovery boundary for an uncaught test panic. Stop the affected process or
  isolate tests whose execution can abandon shared state; do not assume a caught panic ran
  deferred cleanup. Keep explicit `Swag.catchPanic` tests supported.
- Done when: a regression with a panic under a deferred mutex unlock reports the original
  failure promptly without hanging the next test, and the campaign can continue with other
  modules.

### compiler.core.082 — Hot-path node containers that need more than a container swap

- Evidence: several remaining node maps are iterated in ways that affect diagnostics or output:
  sanitizer sparse facts, mem2reg `slots`, and SLP `locations`. Web-renaming's repeated-load
  grouping now uses one composite-key first-index table and a source-ordered list of instruction refs,
  instead of nested maps and per-location vectors. A worker-kept `FlatKeyMap` also clears its
  largest previously used capacity on each rebuild.
- Next: choose one of the remaining node maps, establish its traversal order, and design an
  order-preserving flat representation; leave the kept-table reset tradeoff for measurement.
- Done when: each remaining map has an equivalent replacement, or code evidence shows that no
  lower-work representation preserves its traversal contract.

### compiler.core.081 — An imported generic method once lost its own parameter

- Evidence: a forced standard-library rebuild once stopped with `unknown symbol 'arr'` inside
  `Array.opSet(arr: const [..] T) where Reflection.canCopy(T)` of the generated core API
  (`array.swg`), while checking `Array` with `T = u8` for a dependent rebuilt against a
  just-republished core API. The parameter is declared on the line above, and an unchanged
  rerun passed. Isolated replays, `--randomize` seeds and multi-process rounds never
  reproduced it, so the race looks internal to sema of a generic method instantiated from an
  imported API that several modules share.
- Next: the DevMode compiler stops at the wait itself when a body waits on one of its own
  parameters (`Sema::waitIdentifier`), naming the function. When it fires, keep the failing
  process's full log and rerun that exact command under `--randomize --seed` sweeps.
- Done when: the ordering is proved safe by construction or the race is reproduced and fixed
  with a regression case in the `workspace` suite.
- Related: compiler.core.047

### compiler.core.047 — Imported generic bodies intermittently duplicate a binding

- Evidence: a six-worker DevMode script smoke (`tools/scripts.bat dm smoke`) once stopped
  while checking `asciiart.swgs`. The generated core API's `hashtable.swg` reported local
  `mask` as already defined, and the previous-definition note pointed at the same
  declaration, in specialization `HashTable(string, ConcatBufferPosition)`. Isolated and
  complete reruns passed, and the cause is unestablished.
- Next: the DevMode compiler stops when a conflict names two symbols of one declaration node
  (`SemaError::raiseSymbolConflict`), naming the function. When it fires, replay the cached
  script import alongside module builds from that report. Capture generic-instance
  ownership, parameter-scope restoration and semantic restarts around the binding, and
  compare with the parent compiler before attributing the failure to parsing, publication
  or scheduling.
- Done when: a bounded reproducer identifies the duplicate visitation or publication, the
  root cause is fixed, and the script passes repeated parallel imports with six workers.
- Related: compiler.core.081

### compiler.core.030 — Skip repeated runtime IR generation

- Evidence: automatic `MachineCodeCache` archives preserve runtime/API machine code,
  unwind data and relocations across executables, with consumer-owned reference fixups.
  Lookup still follows fresh semantic analysis and unoptimized IR generation. Conservative
  global-distance and source-context differences can also produce misses for unchanged sources.
- Next: move eligible lookup ahead of IR generation using stable body and semantic dependency
  identities, preserving configuration, target, ABI, constants, effects and source provenance.
- Done when: warm builds skip the corresponding runtime IR generation, fresh and reused paths
  preserve diagnostics and native/JIT behavior, and complete compilation remains faster after
  fingerprinting and reference fixups.
- Related: compiler.core.003, compiler.core.004, compiler.core.006.
### compiler.core.072 — Link preparation resolves and places the native image on one thread

- Evidence: `PELinker::prepareImageLinkParallel` loads archives and builds the symbol table as
  jobs, and `buildNativeImage` builds each object description's sections in an indexed
  parallel loop. A module has only six descriptions, so that loop is at most six-way.
  Placement (`placeNativeSection`, the symbol and relocation tables), `resolveSymbols`,
  `appendSymbolTable` and `finishImage` remain serial. In a 16-worker DevMode `gui` rebuild,
  image lowering took about 0.6 s and resolution about 0.2 s of wall time over the five
  native modules.
- Next: measure `link prepare` in a 16-worker `gui` rebuild with `--dev-sched-stats` and decide
  whether the remaining serial time justifies splitting descriptions further or resolving
  archive members in parallel.
- Done when: `link prepare` no longer shows as serial time in the scheduler report, with the
  linker and PDB C++ tests, the native suite, and a linked consumer green under both
  executables.
- Related: compiler.core.069

### compiler.core.075 — Aligned node references collapse semantic metadata partitions

- Evidence: `NodePayload` selects its shard with `nodeRef.get() % NODE_PAYLOAD_SHARD_NUM`
  (16 shards). The reference is an AST byte offset aligned
  to at least eight bytes, so only two shards receive payload storage or side-table entries.
  Side-table readers answer an absent entry from a per-node bit instead of their shard count
  (folded source symbols excepted). Payload storage writes (`storeMutex`, taken by every stored
  symbol, symbol list and substitute) and every side-table write still contend on those two
  shards.
- Failed attempt: hashing every selector kept generated code identical, but it raised peak
  committed memory (median +17% on `core`, +3% on `gui`) by spreading small payloads over more
  16 KiB pages, with no clear compile-time win.
- Next: separate payload-page allocation from the shard choice, or reduce initial storage
  without reducing the supported contiguous symbol-list size. Compare
  one-worker and parallel rebuilds on both modules under stable load.
- Done when: the partitioning improvement has concurrent read/write coverage and a measured
  compilation-time benefit with its memory cost explicitly bounded.

### compiler.core.073 — Overlap dependent semantic analysis with the producer link

- Evidence: the workspace pipeline now consumes the published API and parses a dependent while
  the producer links. It joins on the driving thread before semantic analysis, because compile-time
  calls and runtime hooks can load the dependency DLL. The `std` chain is nearly linear
  (`core` → `ogl`/`truetype` → `pixel` → `gui`), so that boundary can still leave workers idle.
- Next: introduce a dependency-ready continuation for compile-time native calls and runtime hooks.
  Keep semantic jobs runnable until they need the image, and resume suspended jobs after link
  publication. Do not block a worker waiting for a link queued on the same worker pool; one-worker
  builds must remain live. Keep manifest publication and retained-compiler destruction on the
  driving thread.
- Done when: a dependent's semantic analysis overlaps its dependency's link in a `gui`
  rebuild, with compile-time native calls, no-op reuse, link failures, the workspace suite and
  focused `std` tests green under both compiler executables.
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

- Evidence: `--dev-sched-stats` (DevMode) splits worker time into running jobs, serial phases,
  scheduler lock waits and starvation, and charges serial and starved time to driver phases.
  The earlier quiet 16-worker standard-library measurement found worker time lost to:
  - starvation in semantic analysis (7.4%)
  - code-generation starvation and serial time (7.0% and 2.2%, compiler.core.071)
  - native-backend work around code generation (3.3% serial and 2.4% starved)
  - deferred-link waits (3.2%, compiler.core.073)
  - module API export (1.3% serial)
  - the scheduler lock (0.5–0.9%, compiler.core.068)
- Next: find what the backend does serially around code generation
  (`NativeBackendBuilder::prepare` and `rebuildFunctionInfos`) and what the semantic tail
  waits on, which is its longest job at 1.5–4 s. Each becomes its own entry once named.
- Done when: each share above has an owning entry.
- Related: compiler.core.071, compiler.core.072, compiler.core.073, compiler.core.065,
  compiler.core.068, compiler.core.007

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

- Evidence: `sinkFrameStoreIntoBranchTarget` once compared raw stack displacements across
  outgoing-call stack adjustments and erased a live spill store in `Pdf.parseContent`.
  Comparing entry-relative addresses fixed it, and the C++ Micro test
  `PostRAPeephole_SpillStoreSinkingTracksStackDepth` fails without that fix. No source under
  `bin/unittests` does: Core-only and two-loop reductions change register allocation and no
  longer place the two loops' spills at the conflicting adjusted displacements.
- Next: reduce the interacting loops and their register pressure while checking the pre-fix
  post-allocation instruction stream, then keep a native suite case that fails without the
  fix.
- Done when: `bin/unittests/native` reproduces this stack-depth aliasing independently of
  GUI, alongside the existing C++ regression and PDF consumer tests.

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

- Evidence: `CompilerInstance::runWorkspace` calls `runWorkspaceModule` synchronously for
  each module in `buildOrder`, and only one `WorkspaceModuleLink` can be in flight, so
  independent ready modules never overlap. `Logger::ScopedStagesDetailed` and
  `Logger::ScopedStageMute` change shared logger state, and command metrics live in the
  process-wide `Stats` singleton. Dispatching the module loop as worker jobs would let its
  blocking `waitAll(clientId)` calls exhaust the pool they need.
- Next: give each in-flight module its own log and metric scope, and drive module stages from
  a coordinator that never blocks a compiler worker on its own pool. Preserve each
  compiler's lifetime through artifact publication and linking, then admit independent ready
  modules within the compiler.core.005 memory budget.
- Done when: independent sibling modules overlap front-end and code-generation work, and
  consumers wait only for the interface or link artifact they need. Compiler and linker
  work share a bounded concurrency policy. Logs, manifests, diagnostics and artifacts stay
  deterministic. Workspace tests cover a diamond graph, concurrent failures, cancellation
  and repeated deterministic builds.
- Related: compiler.core.004, compiler.core.005.

### compiler.core.005 — Set and enforce a compiler memory budget

- Evidence: a six-worker DevMode `core` rebuild measured 1008.9 MiB peak working set and 7360 ms median wall time before the SSA capacity change, and 957.4 MiB and 6338 ms after it (three alternating rounds, same source revision). A hello build measured 139.8 MiB and 259 ms before, and 138.1 MiB and 258 ms after. Both workloads remain above the 250 MiB and 50 MiB targets. An external sampled heap profile points to retained `MicroSsaState` buffers, but its instrumentation raised the observed peak to 1141 MiB and its sampled live-byte totals do not represent resident memory. A follow-up per-function CodeGen arena check measured 940.6 MiB baseline versus 933.7 MiB candidate peak working set and 965.8 versus 953.1 MiB peak commit on `core_rebuild`; the paired median ratios were 0.986 working set, 0.980 commit, and 0.837 wall time. This is incremental evidence on top of the SSA change, not a comparison to the original compiler. The ValueBorrow fast-path scratch now uses the same size-aware SSA release policy: three six-worker DevMode core_rebuild pairs measured 19.0 MiB lower working-set peak and 14.1 MiB lower commit peak, with a small unconfirmed timing cost.
- Next: attribute the remaining peak and measure Release and the benchmark-task workloads before making a campaign-wide memory claim.
- Done when: the campaign publishes host-normalized memory limits, every selected workload stays within them, and a regression report names the responsible subsystem.
- Related: compiler.core.004, compiler.core.007.
### compiler.core.003 — Code-generation invalidation is module-wide

- Evidence: the per-function code cache (`functionCacheFingerprint` in
  `NativeBackendBuilder.cpp`) admits only non-debug functions with at least 64
  micro-instructions and no code relocation. Ordinary functions outside that policy still
  regenerate; this per-function incremental cache has no JIT path. The separate automatic
  `MachineCodeCache` reuses supported non-debug module, runtime and imported-API machine code
  in native and JIT builds, including relocations (compiler.core.030). Lookup still follows
  fresh IR generation.
  `NativeObjFileWriter` already writes one function per archive member, and the integrated
  linker resolves members lazily. Broader coverage therefore extends the fingerprint and
  admission policy, not the storage format.
- Next: extend reuse to debug information, and move lookup ahead of IR generation using the
  compiler.core.001/002 fingerprints rather than a second dependency graph. Measure an
  adaptive size threshold so that hashing and archiving a small function never costs more
  than its micro passes.
- Done when: a body-only edit regenerates only the changed function and the functions whose
  code depends on it, for native and JIT builds, including debug and unwind metadata. Clean
  and warm builds produce byte-identical cache entries and reject compiler, target,
  configuration, ABI, API and optimization changes. The compiler.core.004 edit-build
  workloads show a material win with no measurable clean-build regression.
- Related: compiler.core.001, compiler.core.002, compiler.core.004, compiler.core.030.

### compiler.core.052 — Isolate a transient null-capture diagnosis in a macro binding

- Evidence: a Release native run once diagnosed twelve null dereferences at `total += seed`
  in `bin/unittests/native/inline/binding_visit_growth.swg`, a diagnostic emitted before the
  micro optimization loops. It failed once with the original session output and work roots,
  then passed with fresh roots and with the same source outside the checkout. Cache or
  work-directory state is therefore not yet separated from scheduling. Repeated filtered
  Release runs with six workers have not reproduced it. Artifact:
  [generated-code session](../bench/results/generated-code/20260916/README.md).
- Next: when it reappears, preserve the failing pre-sanity capture lowering and its output
  and work roots. Then separate cache reuse from shared code-generation state when the
  macro's closure is cloned.
- Done when: a stable reproducer identifies the cause, the correction passes that reproducer
  repeatedly, and the full native suite remains green.

### compiler.core.041 — Reduce parallel dependency registration to a workspace-suite witness

- Evidence: a workspace build once crashed inside `std::set::insert` reached from
  `semaCompilerInclude`. Registration and snapshots now share a mutex, and
  `NativeArtifact_ConcurrentCompilerInputsKeepEveryDependency` forces six concurrent writers.
  No language-suite case can force the interleaving. A 256-file, 16,384-`#include` reduction
  passed with the unfixed compiler, and a delay before registration aligns arrivals, not the
  insertions themselves.
- Next: add a workspace-test scheduling hook that holds one registration open inside the
  mutation, or find a bounded source-level ordering that exposes missing or corrupted
  registration without a large GUI module build.
- Done when: a `bin/unittests/workspace` case fails with unsynchronized registration, and
  passes with synchronized registration under both compiler executables with six workers.
  The case verifies dependency retention and later invalidation without an intermittent
  timeout as its oracle.

### compiler.core.004 — The benchmark campaign has no regression threshold on the edit-build loop

- Evidence: since benchmark protocol 3, every campaign measures `core_rebuild`, `core_noop`,
  `core_touch`, `doc_std` and `format_tree` beside the frozen reference compiler and reports
  each paired ratio with its 95 % interval and verdict. The `core` workloads build in DevMode
  only, so a Release-only edit-build regression stays invisible.
- Next: add Release variants of the three `core` workloads to `make_compiler_workloads`.
- Done when: the edit-build loop is measured in Release and DevMode against the reference, and
  every result names its mode.
- Related: compiler.core.002, compiler.core.005, compiler.core.007, repo.tooling.007.

### compiler.core.006 — Reuse analyzed prelude state

- Evidence: each fresh compiler process analyzes the unchanged runtime prelude before compiling
  a module or script. Machine-code archives amortize backend emission, but original runtime
  source loading, lexing, parsing and semantic analysis still repeat for each instance.
- Next: serialize the prelude through the ordinary module-interface mechanism and include source, compiler, target, and relevant configuration in its cache key.
- Done when: warm module builds and script launches skip prelude lexing, parsing, and semantic analysis, while fresh and reused paths produce identical diagnostics and artifacts.
- Related: compiler.core.001, compiler.core.004, compiler.core.016.
### compiler.core.001 — Replace generated dependency source with a reusable module interface

- Evidence: `CompilerInstance::appendImportedApiSnapshot` creates an `ImportedApi` source
  file for every published API source. `Command::sema` sends those files through
  `parseSourceFiles`, declaration sema, and full sema in each consumer. Dependency source
  snapshots and native artifact reuse do not preserve the resolved interface for a consumer
  that needs recompilation. `canDelayImportedFunctionBody` already defers eligible free
  function bodies, but excludes methods, interface implementations and other
  context-sensitive cases. Restoring methods' declaration contexts is insufficient by itself:
  delayed `ConcatBuffer.addBytes` and `reserveInPlace` can remain unresolved when native/JIT
  preparation waits on their semantic completion through allocation-failure reporting.
  Repeated closure application remains a local lead: a per-consumer capture set improves
  a 1,000-file shared dependency, but a standard eight-root graph was about 2.7% slower
  overall in Release despite neutral setup timing.
  Parse-image prototypes still required original source loading and a fresh semantic pass;
  their read and reconstruction costs did not establish a whole-command gain.
  `MachineCodeCache` preserves supported compiled bodies, while imported declaration and
  type resolution remain fresh.
- Next: measure imported API bytes, tokens, AST memory, parse time and declaration/body sema
  work separately from consumer sources on a small consumer, a large module graph, and a
  diamond dependency, including consumers of the core, pixel and gui API closures. Compare
  cold and warm imports with both compiler executables. Use
  that baseline to prototype a versioned binary interface for resolved non-generic
  declarations; retain the source import path for unsupported declarations while expanding
  coverage. Before widening lazy imported methods, close body materialization across cyclic
  method/free-function calls, then verify both compile-time execution and native presolve.
  Account for whole-command effects before adopting per-capture closure deduplication.
- Interface contract: preserve namespace and overload membership, exported and supporting
  symbols, canonical type identity, layouts, constants and default arguments, attributes
  including safety/borrow contracts, interface implementations, ABI/link identities, and
  source provenance. Index declarations for selective materialization without hiding
  overloads or implementations from lookup. Keep generic templates and required
  inline/macro/mixin bodies in separately indexed sections; instantiate or expand them in
  the consumer context when required. Resolved ordinary bodies can later use the typed-body
  representation from compiler.optimization.107. Importing metadata must not replay module
  setup or compile-time side effects; requested compile-time calls retain their execution
  behavior. Keep readable `.swg` export for inspection and compatibility.
- Ownership: compiler instances own their identifier, type and constant managers, and symbols
  point into mutable ASTs. Serialize stable interface-local identities and remap them into
  the consumer; do not persist raw pointers or share live semantic state across consumers.
  Reuse immutable interface bytes within a workspace invocation, with consumer-owned
  materialization and generic-instance state.
- Cache/publication: validate format and compiler identity, target/ABI, relevant configuration,
  exported content including required bodies, and transitive interface fingerprints. Publish
  the interface with the matching API/native artifact generation under the existing
  publication protocol. Reject partial, corrupt or incompatible entries; use a complete
  matching source API or rebuild rather than mixing generations.
- Done when: supported workspace imports skip API lexing, parsing and declaration sema;
  complete coverage removes the generated-source import path from ordinary builds. Warm
  imports show lower wall time and peak memory on the measured consumers. Fresh and reused
  paths preserve diagnostics, source locations, overload resolution, generic/inline/macro
  behavior, compile-time execution and native behavior. Workspace regressions cover diamond
  dependencies, configuration and transitive API/body changes, stale/corrupt entries and
  concurrent publication under both compiler executables with real parallelism.
- Related: compiler.core.002, compiler.core.006, compiler.language.service.001, compiler.language.service.003, compiler.core.030, compiler.optimization.107.
### compiler.core.002 — Front-end invalidation is module-wide

- Evidence: front-end state is not persisted, so the compiler.core.004 `core_touch` workload
  rebuilds every file of the module. The AST is not an immutable parse cache. Semantic
  analysis replaces expressions and appends generated nodes to the per-file AST, and
  `SourceFile::setContent` rejects a change once an AST owns the source view. The editor
  session reuses unaffected files through conservative file-to-file dependencies, but it
  does not compare the public interfaces each file observed. Append-only symbol maps also
  keep retired declaration ASTs alive.
- Next: separate an immutable per-file parse result from semantic substitutions. Then persist
  lexical, parsed and semantic state per file, keyed by source content, relevant
  configuration and fingerprints of the imported public symbols the file observed.
- Done when: a private-body edit reanalyzes only the changed file and its semantic
  dependents. A public-signature change invalidates every consumer that observed it.
  Adding, removing or renaming a file, or changing configuration or compiler version,
  invalidates the correct state. `core_touch` lands far below `core_rebuild`, and
  equivalent-result tests cover clean and incremental workspace builds.
- Related: compiler.core.001, compiler.core.004, compiler.core.003, compiler.core.016.

### compiler.core.016 — Tool scripts recompile on every invocation

- Evidence: every `.swgs` invocation lexes, parses, analyzes and generates code for the
  script and its `#load` closure before launching it. Only imported dependency builds are
  shared, under `<temp>/swag/dep/<hash>/` (`WorkspaceLayout.h`).
- Next: persist the compiled script artifact under a dependency-complete key (loaded
  sources, imported public interfaces, compiler build, target, relevant configuration), and
  make cache population atomic.
- Done when: a second unchanged invocation skips lexing, parsing, semantic analysis and code
  generation. Changes to the script, `#load` inputs, imported public APIs, compiler version,
  target or configuration invalidate the artifact. Cached and fresh paths preserve
  diagnostics, forwarded arguments, environment, output and exit code. Tests cover
  transitive loads, imports, configuration changes, corrupt entries and concurrent
  population.
- Related: compiler.core.001, compiler.core.002, compiler.core.006, platform.portability.080.

### compiler.core.027 — A run-time loaded shared library cannot share the host's runtime

- Evidence: an executable links its whole import closure in, which gives the process one copy of
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

### compiler.core.089 — Diagnostics name a tuple type by its generated symbol

- Evidence: `TypeInfo::toName` prints a struct by its symbol name, and a tuple such as the
  `{value: s32, eat: u32, ovf: bool}` returned by `StrConv.parseS32` is an anonymous struct
  registered as `anonymous_struct` ([Sema.Struct.cpp](../src/Compiler/Sema/Ast/Sema.Struct.cpp)).
  A diagnostic that names such a type, like `sema_err_catch_value_needs_fallback`, shows
  `'__anonymous_struct_33b4699d8228f36a'` instead of the tuple the source wrote.
- Next: find which consumers of `toName`/`toFullName` need the symbol name (reflection names,
  generated API files, mangling) and which only display it; spell an anonymous struct as its
  field list on the display paths, and cover it with a sema error fixture.
- Done when: every diagnostic that names a tuple type shows its fields, and reflection and
  generated API output are unchanged.

### compiler.core.091 — A named function passed as a value is refused without saying how to pass it

- Evidence: passing a local function by name where a callback is expected, as in
  `animator.animateF32(me, channel, from, to, follow, options)`, reports
  `sema_err_not_value_expr` ("'follow' is not a value expression; it is a function") and stops:
  the reader is not told that `&follow` is the value of a function, which is what
  `bin/reference/modules/language/src/007_002_lambda.swg` teaches.
- Next: when the symbol is a function and the expected type is a lambda, add a help that offers
  `&{sym}`, and cover it with a sema error fixture.
- Done when: that call reports the help naming `&follow`.

### compiler.core.092 — Code generation asserts on `is`/`as` narrowing returned from a loop over window children

- Evidence: `swc.dm` stops with `panic: compiler assertion does not hold` at
  `src/Compiler/CodeGen/Core/CodeGen.cpp:43` (`expression: value`, phase "Codegen parsing",
  function `PropWnd.fieldLabel`, token `if`) on this Swag Capture helper, inlined into its caller:

  ```swag
  func fieldComboCtrl(item: *PropertiesItem)->*ComboCtrl?
  {
      for child in item.line.children      // Array'(*Wnd)
      {
          if child is ComboCtrl as ctrl do
              return ctrl
      }

      return null
  }
  ```

  Writing `if child is ComboCtrl do return assume cast(*ComboCtrl, child)` compiles and runs.
- Next: reduce it to a standalone `#test` with a two-level `using` struct hierarchy and an
  `Array'(*Base)`, add it to the compiler suite, and fix the code generation of an `as` binding
  returned from a `for` body.
- Done when: the helper above compiles and returns the narrowed pointer.

### compiler.core.093 — A narrowed nullable local loses its narrowing inside a `while` nested in a `for`

- Evidence: in `GridView.onPaint` of Swag Scope's hex viewer
  (`bin/apps/modules/swagscope/src/viewers/hex/gridview.swg`), `let font = .font().regular` is
  narrowed by `if not font ... do return` and passed to `drawBuffer(..., font: *Font, ...)` in the
  body of `for row in visible`. The same call inside a `while column <= rowLast - rowOffset`
  nested in that `for`, after `.writeValueText(&.cellText, offset)` and a
  `let zero = cond ? a == 0 : (complete and .scalarAt(offset) == 0)`, is rejected with
  "argument 5 for call to 'drawBuffer' has type '*Font?', but parameter 'font' needs '*Font'";
  rewriting the `while` as `for value in count` compiles. Three standalone reductions (a `while`
  in a `for`, a mutating borrow of `me` in the loop, a conditional with `and`) keep the
  narrowing, so the trigger is still unknown.
- Next: restore the `while` form in a copy of `onPaint` and remove statements until the
  diagnostic goes, then add the reduced case to the `sema` suite.
- Done when: the reduced case compiles and a `sema` fixture holds it.

## Deliberately out of scope

- **An LLVM back end.** The native and Micro back ends are the supported architecture. Reconsider only if a concrete platform or optimization requirement cannot be met within them.
- **A second language front end.** The compiler architecture is optimized for Swag; a second parser and semantic model would dilute the persisted-state and tooling work above.
- **A package registry inside the compiler backlog.** Path and workspace dependencies remain compiler responsibilities. Registry identity, trust, lockfiles, acquisition, and publishing need a separate product backlog once their scope and owner are defined.
