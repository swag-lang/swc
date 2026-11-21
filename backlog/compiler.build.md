# Compiler Build Backlog

This file owns compilation of workspaces: dependency scheduling, incremental reuse, caches,
parallelism, memory budgets, artifact publication, linking orchestration, and the cost of compiling
swc. Language analysis belongs in [compiler.frontend.md](compiler.frontend.md), generated-code
emission in [compiler.codegen.md](compiler.codegen.md), and transformations of compiled programs in
[compiler.optimization.md](compiler.optimization.md).

Entries stay in one flat list. Keep only measurements that affect the next action; refresh them
before relying on them.

### compiler.build.114 — Resolve a DevMode host exception while compiling Swag Vault

- Evidence: `tools/apps.bat dm test swagvault --test-tag golden` with three workers raised
  `0xC0000005` after rebuilding the Pixel dependency. The read address was
  `0xFFFFFFFFFFFFFFFF`, `rcx` contained `0xDFDFDFDFDFDFDFDF`, and the faulting DevMode RVA was
  `0xCA7DBA`; the exception report contained no current source span or resolved stack symbols.
- Next: retain the matching compiler and COFF objects on recurrence, resolve the faulting
  stack against those exact artifacts, and identify which compiler-owned object was read after
  release before reducing the import path.
- Done when: a reduced workspace regression protects the corrected lifetime and the application
  compiles repeatedly with parallel workers and retained dependencies.

### compiler.build.108 — Preserve generic parameters across an incremental app build

- Evidence: an incremental Release build of Swag Capture diagnosed `unknown name 'arr'` at `core`'s `Array.opSet(arr: const [..] T)` for `T = FileInfo`, although the parameter is declared in the adjacent signature. A forced dependency rebuild compiled the same source, and the following warm build was up to date.
- Next: reproduce from a retained dependency artifact after changing a GUI or application test source, then compare the imported generic body and specialization state with a forced rebuild.
- Done when: incremental and rebuilt application compilations both resolve the `opSet` parameter, with a regression that preserves the failing dependency-reuse boundary.

### compiler.build.082 — Hot-path node containers that need more than a container swap

- Evidence: several remaining node maps are iterated in ways that affect diagnostics or output:
  sanitizer sparse facts, mem2reg `slots`, and SLP `locations`. Web-renaming's repeated-load
  grouping now uses one composite-key first-index table and a source-ordered list of instruction refs,
  instead of nested maps and per-location vectors. A worker-kept `FlatKeyMap` also clears its
  largest previously used capacity on each rebuild.
- Rejected for now: embedding `upperRegValues` in `SanitizerFlatMap` passed the compiler suites but
  adds 16 bytes to every `SanitizerState`, including empty maps. Without occupancy evidence, fewer
  node allocations do not prove that the larger, more frequently copied state is a net saving.
- Next: choose another remaining map, establish its traversal order, and design an order-preserving
  flat representation; leave the kept-table reset tradeoff for measurement.
- Done when: each remaining map has an equivalent replacement, or code evidence shows that no
  lower-work representation preserves its traversal contract.

### compiler.build.030 — Skip repeated runtime IR generation

- Evidence: automatic `MachineCodeCache` archives preserve runtime/API machine code,
  unwind data and relocations across executables, with consumer-owned reference fixups.
  Lookup still follows fresh semantic analysis and unoptimized IR generation. Conservative
  global-distance and source-context differences can also produce misses for unchanged sources.
- Next: move eligible lookup ahead of IR generation using stable body and semantic dependency
  identities, preserving configuration, target, ABI, constants, effects and source provenance.
- Done when: warm builds skip the corresponding runtime IR generation, fresh and reused paths
  preserve diagnostics and native/JIT behavior, and complete compilation remains faster after
  fingerprinting and reference fixups.
- Related: compiler.build.003, compiler.build.004, compiler.build.121.

### compiler.build.072 — Link preparation resolves and places the native image on one thread

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
- Related: compiler.build.069

### compiler.build.073 — Overlap dependent semantic analysis with the producer link

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
- Related: compiler.build.069, compiler.build.007

### compiler.build.069 — Measure where a module build loses its workers beyond six cores

- Evidence: `--dev-sched-stats` (DevMode) splits worker time into running jobs, serial phases,
  scheduler lock waits and starvation, and charges serial and starved time to driver phases.
  The earlier quiet 16-worker standard-library measurement found worker time lost to:
  - starvation in semantic analysis (7.4%)
  - code-generation starvation and serial time (7.0% and 2.2%, compiler.codegen.002)
  - native-backend work around code generation (3.3% serial and 2.4% starved)
  - deferred-link waits (3.2%, compiler.build.073)
  - module API export (1.3% serial)
  - the scheduler lock (0.5–0.9%, compiler.build.068)
- Next: find what the backend does serially around code generation
  (`NativeBackendBuilder::prepare` and `rebuildFunctionInfos`) and what the semantic tail
  waits on, which is its longest job at 1.5–4 s. Each becomes its own entry once named.
- Done when: each share above has an owning entry.
- Related: compiler.codegen.002, compiler.build.072, compiler.build.073, compiler.build.065,
  compiler.build.068, compiler.build.007

### compiler.build.068 — The job scheduler serializes every transition on one mutex

- Evidence: `JobManager` keeps one `mtx_` for the three ready deques, the client counters, the
  waiter map, and the worker list. Jobs are fine-grained (one per top-level declaration, one per
  function in code generation) and every enqueue, dequeue, park, and wake takes that lock.
  `growWorkersForLoadLocked` still creates threads while holding it. The queue is a global FIFO:
  a resumed job lands on any worker with a cold cache. The default worker count is
  `hardware_concurrency()`, which on a hybrid CPU includes efficiency cores and SMT siblings, so
  critical-path jobs can run on the slowest cores.
- Measured: `--dev-sched-stats` on a 16-worker DevMode `gui` rebuild charges 0.5–0.9% of worker
  time to waiting for this lock (compiler.build.069). It is not the ceiling today; revisit when
  starvation and serial phases shrink.
- Next: prototype per-worker deques with stealing behind the same `JobManager` interface, keeping
  the waiter map and client counters under their own lock, and spawn workers outside it.
- Done when: a std module build at 16 workers spends no measurable time waiting on the
  scheduler lock (VTune or ETW contention view), with the scheduler unit tests and both compiler
  executables green.
- Related: compiler.build.069

### compiler.build.065 — Remaining barrier rounds still drain the whole module

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
- Next: count rounds and re-parked sleepers per wait kind (compiler.build.069) on a std module, then
  give the dominant remaining kind a recheckable publication (a per-name generation counter for
  identifier waits closes the park race) so it no longer needs the barrier.
- Done when: a std module build needs no barrier round to resolve forward identifier and
  type-completion dependencies, with the sema suite, the C++ scheduler tests, and std release
  green under both compiler executables.
- Related: compiler.build.069, compiler.build.007

### compiler.build.061 — Type-info graph publication uses one serialization domain

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
- Related: compiler.build.007.

### compiler.build.007 — Workspace front ends and code generation run serially

- Evidence: `CompilerInstance::runWorkspace` calls `runWorkspaceModule` synchronously for
  each module in `buildOrder`, and only one `WorkspaceModuleLink` can be in flight, so
  independent ready modules never overlap. `Logger::ScopedStagesDetailed` and
  `Logger::ScopedStageMute` change shared logger state, and command metrics live in the
  process-wide `Stats` singleton. Dispatching the module loop as worker jobs would let its
  blocking `waitAll(clientId)` calls exhaust the pool they need.
- Next: give each in-flight module its own log and metric scope, and drive module stages from
  a coordinator that never blocks a compiler worker on its own pool. Preserve each
  compiler's lifetime through artifact publication and linking, then admit independent ready
  modules within the compiler.build.005 memory budget.
- Done when: independent sibling modules overlap front-end and code-generation work, and
  consumers wait only for the interface or link artifact they need. Compiler and linker
  work share a bounded concurrency policy. Logs, manifests, diagnostics and artifacts stay
  deterministic. Workspace tests cover a diamond graph, concurrent failures, cancellation
  and repeated deterministic builds.
- Related: compiler.build.004, compiler.build.005.

### compiler.build.005 — Set and enforce a compiler memory budget

- Evidence: the compiler still has no enforced workload memory budget. Frozen-source,
  six-worker application observations reach 1,443.543 MiB for the latest DevMode checkpoint;
  the final integrated Release checkpoint reaches 1,221.801 MiB. Different compiler
  checkpoints, host load and publication variation prevent treating these as a controlled
  configuration gap. See the [memory report](../bench/results/memory/20261030-devmode/README.md).
  Earlier focused GUI layout tests reached 2,842.3 MiB; `core` and hello also exceeded their
  250 MiB and 50 MiB targets. Refresh those workloads rather than extrapolating the application
  saving; see the [lifetime report](../bench/results/memory/20261029-lifetimes/README.md) and
  [core report](../bench/results/memory/20261023-alternate45/README.md).
- Next: attribute the remaining per-module peak and establish host-normalized limits across the
  benchmark workloads. Measure compiler memory while an application remains open: native
  `runAfterLink` currently waits for the child while its compiler state remains alive. The build-only
  measurements do not cover that lifetime. Keep compilation and JIT-test execution distinct;
  file filters reduce test execution while retaining whole-module compilation.
- Done when: the campaign publishes host-normalized memory limits, every selected workload stays
  within them, and a regression report names the responsible subsystem.
- Related: compiler.build.004, compiler.build.007.

### compiler.build.003 — Code-generation invalidation is module-wide

- Evidence: the per-function code cache (`functionCacheFingerprint` in
  `NativeBackendBuilder.cpp`) admits only non-debug functions with at least 64
  micro-instructions and no code relocation. Ordinary functions outside that policy still
  regenerate; this per-function incremental cache has no JIT path. The separate automatic
  `MachineCodeCache` reuses supported non-debug module, runtime and imported-API machine code
  in native and JIT builds, including relocations (compiler.build.030). Lookup still follows
  fresh IR generation.
  `NativeObjFileWriter` already writes one function per archive member, and the integrated
  linker resolves members lazily. Broader coverage therefore extends the fingerprint and
  admission policy, not the storage format.
- Next: extend reuse to debug information, and move lookup ahead of IR generation using the
  compiler.build.120 and compiler.build.119 fingerprints rather than a second dependency graph. Measure an
  adaptive size threshold so that hashing and archiving a small function never costs more
  than its micro passes.
- Done when: a body-only edit regenerates only the changed function and the functions whose
  code depends on it, for native and JIT builds, including debug and unwind metadata. Clean
  and warm builds produce byte-identical cache entries and reject compiler, target,
  configuration, ABI, API and optimization changes. The compiler.build.004 edit-build
  workloads show a material win with no measurable clean-build regression.
- Related: compiler.build.120, compiler.build.119, compiler.build.004, compiler.build.030.

### compiler.build.041 — Reduce parallel dependency registration to a workspace-suite witness

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

### compiler.build.004 — The benchmark campaign has no regression threshold on the edit-build loop

- Evidence: since benchmark protocol 3, every campaign measures `core_rebuild`, `core_noop`,
  `core_touch`, `doc_std` and `format_tree` beside the frozen reference compiler and reports
  each paired ratio with its 95 % interval and verdict. The `core` workloads build in DevMode
  only, so a Release-only edit-build regression stays invisible.
- Next: add Release variants of the three `core` workloads to `make_compiler_workloads`.
- Done when: the edit-build loop is measured in Release and DevMode against the reference, and
  every result names its mode.
- Related: compiler.build.119, compiler.build.005, compiler.build.007, repo.tooling.007.

### compiler.build.016 — Tool scripts recompile on every invocation

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
- Related: compiler.build.120, compiler.build.119, compiler.build.121, platform.portability.080.

### compiler.build.027 — A run-time loaded shared library cannot share the host's runtime

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

### compiler.build.083 — Define an embeddable compiler driver boundary

- Evidence: `src/main.cpp` owns process setup and cleanup: allocator configuration, the Windows
  host exception hook, stdio flushing, and the PID-scoped sandbox. CLI parsing and command
  dispatch live in `src/Main/CompilerCli.cpp`. `CompilerInstance` remains the internal compilation
  entry point.
  `Global` still stores process-static services, `CommandLine` is coupled to CLI configuration,
  and `swc.vcxproj` still builds one executable rather than a reusable library target.
- Next: define a host-facing configuration and lifetime contract for diagnostics, cancellation,
  worker shutdown, and repeated compiler instances; build a core library without the CLI and
  process entry; prove a non-CLI consumer can initialize, analyze, and shut down the compiler.
- Done when: the executable entry point and process-only setup are absent from a reusable compiler
  library target, and a host can use that target without parsing command-line arguments or
  exchanging requests over process stdio.

### compiler.build.096 — Make allocator heap inspection safe for abandoned pages

- Evidence: with mimalloc 3.6.0 and `MI_DEBUG=3`, a diagnostic traversal through
  `mi_subproc_visit_heaps` and `mi_heap_visit_blocks(..., false, ...)` aborts in
  `_mi_page_update_sample_countdown` on `mi_page_is_owned(page)`. It runs on the main
  thread while the scheduler mutex is held, no worker is active or ready, and progress
  animation is disabled. `mi_heap_visit_page` collects deferred frees even when only
  areas are requested; its abandoned-page ownership guard is conditional on `MI_QSBR`.
- Next: reduce the failure to a standalone allocated/abandoned-page visitor test and
  establish the ownership transition needed by collection. Keep the memory census on
  its temporary read-only path until the normal visitor contract is validated.
- Done when: visiting live and abandoned pages with pending cross-thread frees preserves
  exact block counts and passes the allocator's internal assertions without weakening them.

### compiler.build.097 — Reduce the largest retained compiler allocations

- Evidence: the synchronized large-allocation census attributes 157.679 MiB to register
  allocation, 78.343 MiB to other Micro analyses, 94.676 MiB to AST/parser storage and
  149.927 MiB to mixed arenas at one observation. Those requested-byte totals exclude small
  C++ allocations, direct allocator calls and OS mappings. A separate typed-arena census
  partitions 150.688 MiB of arena backing: 45.421 MiB of `AttributeList`, 45.253 MiB of
  `SymbolFunction`, 20.960 MiB of `SymbolVariable`, 15.497 MiB of `SemaInlinePayload`,
  5.913 MiB of `CodeGenLoweringPayload`, 4.663 MiB of finalizers and only 1.295 MiB of unused
  tails. Do not add the two diagnostic runs as if they shared one process peak. See the
  [occupation report](../bench/results/memory/20261030-devmode/README.md) and
  [typed-arena census](../bench/results/memory/20261030-devmode/arena-types.json).
- Next: work down the concrete owners below. Keep useful buffer reuse, stable pointers,
  publication ordering and compilation speed; do not exchange a small memory reduction for
  extra allocations, lookups or repeated analysis without a justified measurement.

| Owner | Remaining investigation |
| --- | --- |
| Attribute lists | Count populated inline attribute/parameter slots and identical inherited snapshots among the 76,326 lists (624 bytes each). Evaluate smaller representations or immutable sharing while preserving scope overrides, equality, publication and fast lookup. |
| Function symbols | Profile member presence among 31,719 objects (1,496 bytes each), especially retained JIT/order caches, borrow-field vectors and cold metadata. Quantify each proposal before adding indirection or heap allocation. |
| Variable symbols and inline payloads | Review padding and duplicated binding/context records in the 161,607 variable symbols (136 bytes each) and 22,078 inline payloads (736 bytes each). Keep atomic access, reference identities and direct hot-path reads. |
| Cyclic register liveness | Dense cyclic matrices remain; measured examples have 21.978/17.763/12.090 MiB dense storage versus 5.458/4.561/2.339 MiB trimmed-band estimates. Consider an exact basic-block fixed point followed by one compact instruction-row reconstruction. Bound temporary matrices and fall back for dense/high-block-count graphs. Differentially check disconnected components, self-loops, use-before-definition, both allocators and retained capacity across functions. |
| Other retained Micro buffers | Refresh the census after mask/operand-list compaction, then inspect SSA, generic instruction use/def records, rewrite queues and per-worker high-water capacities. Avoid unconditional shrink/reallocation between functions. |
| Linker, native emission and caches | At a separate traced peak linker storage was 111.198 MiB and native emission 35.639 MiB. Attribute merged sections, relocations, final image buffers and outstanding record owners after current move/mapping changes before removing another copy or shortening a lifetime. |
| AST and semantic containers | Count clone pages, node payloads and nested small vector/map capacities by module and phase; page occupancy was already high, so do not infer a saving from smaller pages alone. |
| Allocator page slack | An exploratory `MI_ENABLE_LARGE_PAGES=0` run initially looked promising, but its baseline and candidate came from different source revisions. A same-source DevMode comparison found no RSS reduction on `doc_std` or `hello_build` and only 4.6% on `core_rebuild`; the default was restored. An immediate-purge trial reduced RSS but increased CPU time by 12–21%. See the [2026-11-17 report](../bench/results/memory/20261117-large-pages/README.md). Re-evaluate page slack against the current source on Windows before proposing another allocator default. |
| Missing ownership coverage | Add small C++ allocations, direct mimalloc allocations and OS/proximity mappings to synchronized accounting, with module/phase/worker identity and shared backing deduplicated. Keep requested bytes, allocator rounding, committed capacity and residency separate. |

- Done when: the dominant retained owners are reduced with preserved behavior and accepted
  compilation speed, and a reproducible census explains the remaining peak without summing
  independent maxima. Low-volume finalizer/header/tail savings must not distract from the
  dominant objects and allocator slack.
- Related: compiler.build.005 (budgets and compiler retention while a child application runs),
  compiler.codegen.003 (nondeterministic publication), compiler.build.096 (safe allocator inspection),
  compiler.build.098 (performance acceptance).

### compiler.build.098 — Close compilation-speed acceptance for memory reductions

- Evidence: the memory campaign has successful focused correctness, application and generated-code
  checks, but host contention changed substantially during its comparisons despite quiet start
  admission. Lower observed wall/CPU time does not prove an optimization is speed-neutral.
  The latest DevMode effects/cache pair observes 1,472.266 to 1,443.543 MiB working set; the
  corresponding host CPU averages are 63.37% and 50.84%. Earlier constant packing and compact
  acyclic liveness checkpoints have the same unresolved timing limitation. Exact observations,
  binary hashes, source revisions and exclusions are in the
  [memory report](../bench/results/memory/20261030-devmode/README.md).
- Next: compare preserved adjacent checkpoints on identical frozen sources, isolated caches,
  verified affinity and stable host load, in DevMode and Release. Cover constant-page packing,
  compact acyclic matrices (including wide dense rows), physical effect masks, fixed virtual
  operand lists and mapped cache publication. Check warm/incremental cache behavior as well as
  full builds, and separate resident memory from private backing. Keep the independent
  no-large-pages allocator candidate in compiler.build.097 separate from accepted defaults.
- Preserve unresolved failures and variation: compiler.codegen.003 owns generic instance/string
  differences and the varying `Lens.View.create` borrow mask; compiler.build.096 owns the heap
  visitor assertion. Improve generic specialization identity in Micro listings before treating
  reordered duplicate printed names as exact call-target equivalence. Do not normalize arbitrary
  integer constants to hide differences. Exercise manually enabled `SWC_DEBUG_MODE` when its
  inspection-only path is next changed; no additional build configuration is required.
- Done when: controlled comparisons bound any regression and establish that the retained
  changes respect compilation-speed priority. A slowdown is acceptable only with a genuinely
  substantial memory saving explicitly evaluated against it. Keep validation outcomes in the
  report and remove completed acceptance work from this entry.
- Related: compiler.build.004, compiler.build.005, compiler.build.097.

## Deliberately out of scope

- **An LLVM back end.** The native and Micro back ends are the supported architecture. Reconsider only if a concrete platform or optimization requirement cannot be met within them.
- **A second language front end.** The compiler architecture is optimized for Swag; a second parser and semantic model would dilute the persisted-state and tooling work above.
- **A package registry inside the compiler backlog.** Path and workspace dependencies remain compiler responsibilities. Registry identity, trust, lockfiles, acquisition, and publishing need a separate product backlog once their scope and owner are defined.

### compiler.build.104 — Bound JIT state lifetime after an abandoned hook

- Evidence: `runJitTests` skips later hooks after an abandoned frame. Its scope still
  restores the global data snapshot, while work owned by the failed module may remain live.
- Next: reduce a JIT hook panic with an active worker to a bounded fixture. Check the worker's
  lifetime against snapshot restoration and code disposal, including dynamic dependencies.
- Done when: the fixture proves that work from an abandoned hook cannot observe restored
  globals or released code. Recoverable failures still release resources in drop-hook order.

### compiler.build.106 — Resolve nested functions in runtime startup code

- Evidence: a noncapturing `func loadArguments()->bool` declared and called inside
  `__hostSetupProcessArguments` in `bin/runtime/os.win32.swg` passes semantic checking,
  then native tuning reports `unknown name 'loadArguments'` at its declaration. Prefixing
  the local name with `__` gives the same result. Returning the host setup status directly
  to `__setupRuntime` compiles and passes the native argument-preservation reproducer.
- Linux DevMode reductions: a nested helper in an ordinary function and the same helper in a
  temporary copy of `os.linux.process.swg`'s `__hostSetupProcessArguments` both compile and run.
  Cross-compiling a constant-return helper in `os.win32.swg` completes Micro lowering, then
  stops at the unresolved `TlsAlloc` import.
- Next: run the reduction on a Windows host with the SDK, then inspect runtime cloning,
  symbol publication, and native lowering if the unknown-name diagnostic recurs.
- Done when: a nested runtime helper resolves and executes through native startup, with
  a regression at the owning boundary and no unknown-name diagnosis on its declaration.

### compiler.build.119 — Front-end invalidation is module-wide

- Evidence: front-end state is not persisted, so the compiler.build.004 `core_touch` workload
  rebuilds every file of the module. The AST is not an immutable parse cache. Semantic
  analysis replaces expressions and appends generated nodes to the per-file AST, and
  `SourceFile::setContent` rejects a change once an AST owns the source view. Invalidation needs the dependencies each file observed.
  Append-only symbol maps also keep retired declaration ASTs alive.
- Next: separate an immutable per-file parse result from semantic substitutions. Then persist
  lexical, parsed and semantic state per file, keyed by source content, relevant
  configuration and fingerprints of the imported public symbols the file observed.
- Done when: a private-body edit reanalyzes only the changed file and its semantic
  dependents. A public-signature change invalidates every consumer that observed it.
  Adding, removing or renaming a file, or changing configuration or compiler version,
  invalidates the correct state. `core_touch` lands far below `core_rebuild`, and
  equivalent-result tests cover clean and incremental workspace builds.
- Related: compiler.build.120, compiler.build.004, compiler.build.003, compiler.build.016.

### compiler.build.120 — Replace generated dependency source with a reusable module interface

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
- Related: compiler.build.119, compiler.build.121, compiler.query.001, compiler.build.030, compiler.optimization.107.

### compiler.build.121 — Reuse analyzed prelude state

- Evidence: each fresh compiler process analyzes the unchanged runtime prelude before compiling
  a module or script. Machine-code archives amortize backend emission, but original runtime
  source loading, lexing, parsing and semantic analysis still repeat for each instance.
- Next: serialize the prelude through the ordinary module-interface mechanism and include source, compiler, target, and relevant configuration in its cache key.
- Done when: warm module builds and script launches skip prelude lexing, parsing, and semantic analysis, while fresh and reused paths produce identical diagnostics and artifacts.
- Related: compiler.build.120, compiler.build.004, compiler.build.016.
