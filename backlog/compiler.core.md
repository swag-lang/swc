# Compiler Backlog

This backlog covers the compiler front end, back end, and workspace build engine. Documentation, formatting, and language-design work have their own domain files. Only unfinished work belongs here; completed investigations and implementations remain discoverable through Git history.

Items are ordered from the most recently updated down. Every completion condition is intended to be testable. Measurements below are a dated baseline, not permanent product claims.


### compiler.core.069 — Measure where a module build loses its workers beyond six cores

- Recorded: 2026-10-01 07:35
- Updated: 2026-10-10 15:48 — Keep only the unresolved serial and starvation shares.
- Evidence: a quiet 16-worker GUI rebuild attributed 7.4% of worker time to sema starvation, 7.0% to code-generation starvation, 2.2% to serial code generation, 3.3% to other serial native-backend work, 3.2% to deferred-link waits, and 1.3% to API export. The 6-to-16-worker comparison showed increased starvation; detailed timings are a dated baseline.
- Next: identify the remaining serial work in NativeBackendBuilder::prepare/rebuildFunctionInfos and the long semantic tail; give each worthwhile bottleneck its own lead.
- Complete when: each material serial or starvation share has an owner or is shown negligible.
- Related: compiler.optimization.128, compiler.core.072, compiler.core.073, compiler.core.065, compiler.core.068, compiler.core.007

### compiler.core.007 — Workspace front ends and code generation run serially

- Recorded: 2026-08-09 20:16
- Updated: 2026-10-10 15:48 — Reduce the workspace scheduling proposal to its blocking constraints.
- Evidence: runWorkspace compiles modules in dependency order and keeps at most one link in flight, so independent ready modules do not overlap front-end or code-generation work. Logger stage scopes and process-wide Stats are shared, and blocking waitAll calls inside workers could exhaust the pool.
- Next: give each in-flight module isolated log/metric state and use a coordinator that never blocks its own worker pool; keep compiler lifetime through publication/link and bound concurrency by CPU and memory.
- Complete when: independent siblings overlap, dependency artifacts remain deterministic, and workspace tests cover diamond graphs, failures, cancellation, and repeated builds.
- Related: compiler.core.004, compiler.core.005.

### compiler.core.061 — Type-info graph publication uses one serialization domain

- Recorded: 2026-09-30 08:34
- Updated: 2026-10-10 15:48 — Keep the canonical-identity and recursive-publication constraints.
- Evidence: reflected types share constant shard zero to preserve one runtime address, and TypeGen currently owns that segment exclusively through payload and back-reference publication. Independent roots cannot progress concurrently; splitting ownership risks duplicate identities or exposing partial recursive graphs.
- Next: separate canonical registration from payload generation and define ownership/completion for recursive components before reducing the exclusive section.
- Complete when: independent components progress concurrently while recursive graphs remain complete and reflection/interface identity tests pass.
- Related: compiler.core.020, compiler.core.007.

### compiler.core.072 — Link preparation still resolves and places the native image serially

- Recorded: 2026-10-01 14:25
- Updated: 2026-10-10 15:48 — Keep the remaining serial linker boundary after parallel description building.
- Evidence: object descriptions now build text, relocations, and unwind data in parallel and are placed in stable order; section placement, symbol/relocation resolution, symbol-table merge, and image finish remain serial. A six-description module caps the current parallel stage at six jobs.
- Next: measure link preparation in a 16-worker GUI rebuild and decide whether placement or archive resolution warrants parallel work.
- Complete when: link preparation no longer has material serial time and linker/PDB C++ tests plus native consumers pass.
- Related: compiler.core.069.

### compiler.core.073 — A dependent module waits for its dependency's whole link before starting

- Recorded: 2026-10-01 14:25
- Updated: 2026-10-10 15:48 — Keep the artifact-use boundary and current workspace wait cost.
- Evidence: workspace builds join a dependency's native link before compiling its consumer. In GUI rebuilds, link waits consumed 2.8 to 4.8% of worker time, mostly starvation while one NativeLink job ran.
- Next: identify when a consumer needs only the generated API/setup and defer waiting for the DLL until a compile-time call requires it.
- Complete when: consumer sema overlaps dependency linking and workspace/std tests pass under both compiler executables.
- Related: compiler.core.069, compiler.core.007.

### compiler.core.065 — Remaining sema barrier rounds drain the whole module

- Recorded: 2026-10-01 07:35
- Updated: 2026-10-10 15:48 — Summarize the remaining wait kinds and park races.
- Evidence: identifier, impl-registration, and type-completion waits can park on specific events, but publication races, compiler-defined names, concrete layouts, using scopes, and abandoned lazy-body runs still rely on barrier-wide wakeups. Each barrier drains the client and serializes the next round.
- Next: count rounds and re-parked jobs by wait kind; give the dominant waits recheckable publication, such as per-name generations for identifiers.
- Complete when: sema no longer needs barrier rounds for forward-name or type-completion dependencies, with sema, scheduler, and std tests green.
- Related: compiler.core.069, compiler.core.007.

### compiler.core.068 — The job scheduler serializes every transition on one mutex

- Recorded: 2026-10-01 07:35
- Updated: 2026-10-10 15:48 — Keep the measured lock cost and defer queue redesign until it matters.
- Evidence: one mutex protects ready queues, counters, waiters, and workers; the global FIFO can resume work on a cold worker. At 16 workers, lock waits were under 1% of worker time, so this is not today's ceiling.
- Next: revisit after serial phases and starvation shrink; then evaluate per-worker deques, separate waiter/counter locks, and spawning workers outside the queue lock.
- Complete when: contention is negligible in a 16-worker std build and scheduler tests pass under both compiler executables.
- Related: compiler.core.069.

### compiler.core.080 — Published generic bodies call omitted helper declarations

- Recorded: 2026-10-08 16:26
- Updated: 2026-10-10 15:47 — Keep the two importer failures and the missing dependency boundary.
- Evidence: generated Core APIs publish generic bodies that call helpers absent from the API: dynamic Hash.hash32/hash64 need private hashDynamicStorage, and XML numeric reads need internal Xml.zapBlanks. Provider tests pass, but external importers fail; the XML failure also occurs with its pre-refactoring source.
- Next: reduce the published generic/private-helper dependency to a provider/importer pair and decide whether reachable implementation is published or diagnosed. Cover internal receiver methods; keep the dynamic hash contract and do not expose raw helpers just to silence import errors.
- Complete when: external importers pass both hash widths and XML text/numeric reads, with publication regressions at the consumer boundary.

### compiler.core.064 — A compiler-held dependency DLL blocks child rebuilds

- Recorded: 2026-09-30 15:28
- Updated: 2026-10-10 15:47 — Retain the same-process publication boundary and reproduction.
- Evidence: a parent compiler loads a workspace-local core.dll for compile-time execution and retains it through ExternalModuleManager. A child compiler in the same process then cannot overwrite that DLL during a forced dependency rebuild; test and documentation commands reproduce access denied. External dependencies use immutable copies, but workspace-local dependencies still load from mutable .output paths.
- Next: add a workspace fixture that rebuilds the dependency while the parent stays alive; separate compiler-loaded DLL lifetime from publication without changing runtime linking, cache invalidation, or instance ownership.
- Complete when: the fixture passes with both compiler executables and workspace reuse/publication checks remain green.

### compiler.core.027 — A run-time loaded shared library cannot share the host's runtime

- Recorded: 2026-08-30 12:06
- Updated: 2026-10-10 15:47 — Condense the split-runtime evidence and remaining host-adoption decision.
- Evidence: a runtime-loaded shared library carried a second Core allocator and runtime context, and its consumer crashed at shutdown. Pinning Core to shared-library linkage for the whole dependency closure fixes the observed fault and is the current rule.
- Next: decide whether NativeLibrary.load can install the host allocator as well as the TLS slot and context already passed through __swc_rt_stage; otherwise define which incompatible combination the compiler can diagnose.
- Complete when: a workspace test proves host allocator/context sharing for a loaded library, or the unsupported combination is explained and diagnosed.

### compiler.core.020 — Concurrent type generation may corrupt declared-method traversal

- Recorded: 2026-08-10 12:35
- Updated: 2026-10-10 15:47 — Keep the unexplained corruption watch and replace its investigation transcript.
- Evidence: one multi-configuration campaign reported a mimalloc free-list corruption while type generation traversed declared methods. The stack passed through implicit-method discovery and TypeGen. Since then, 100 Release Core rebuilds and 20 rebuilds each of Ogl in Release and DevMode passed; current traversal snapshots shared lists under locks, and several nearby publication races were fixed. No writer has been tied to the original report.
- Next: investigate only if it recurs; the allocator now captures the reporting thread's stack. Persist the failing module and stress parallel type generation before changing code.
- Complete when: a recurrence is attributed and fixed with a regression, or a parallel standard-library stress campaign under both executables stays clean and the lead is retired.

### compiler.core.052 — Isolate a transient null-capture diagnosis in a macro binding

- Recorded: 2026-09-16 19:54
- Updated: 2026-10-10 15:47 — Keep only the unresolved work-directory or code-generation-state question.
- Evidence: Release build 718 once diagnosed null dereferences in the permanent native regression binding_visit_growth.swg. The same source passed with new work/output roots and outside the checkout; tracing and the integrated build also passed. Evidence does not distinguish cache/work-directory state from scheduling or shared code-generation state.
- Next: repeat the source with controlled roots and six workers, preserving the failing pre-sanity capture lowering if it recurs.
- Complete when: a stable reproducer identifies and fixes the cause, or the failure is confined to transient build state and the native suite remains green.

### compiler.core.004 — The benchmark campaign has no regression threshold on the edit-build loop

- Recorded: 2026-08-09 11:30
- Updated: 2026-10-10 15:47 — Reduce campaign history to the missing baseline and reporting criteria.
- Evidence: the campaign records core rebuild/no-op/private-touch, hello build, docs, and formatting workloads with samples and memory. The initial edit-loop record is insufficient to establish a five-campaign noise band. Peak working set is now separated from the older process-tree committed-memory field; formatter input-opening bias is tracked in repo.tooling.007.
- Next: collect enough clean campaigns to establish each edit-loop band, then report regressions without silently replacing baselines.
- Complete when: every workload has a five-campaign resolution band, the report flags out-of-band movement, and configuration-specific results are labelled.
- Related: compiler.core.002, compiler.core.005, compiler.core.007.

### compiler.core.047 — Imported generic bodies intermittently lose or duplicate bindings

- Recorded: 2026-09-16 09:28
- Updated: 2026-10-10 15:46 — Combine the duplicate-local and missing-parameter sightings.
- Evidence: imported generic specializations intermittently report a duplicate local in HashTable or an unknown parameter in Array.opSet, although the generated API contains the declaration. The first duplicate appeared while script smokes shared a checkout; the later parameter loss occurred during a forced dependency rebuild with no competing checkout command. Immediate retries and full forced rebuilds passed.
- Reduction: 40 pixel rebuilds, 40 same-process dependency rebuilds, 60 randomized seeds, 30 two-process rounds, and 12 exact Core-then-brand replays did not reproduce the parameter loss. The earlier duplicate-local rerun and all 21 script smokes also passed.
- Next: preserve a failing process and capture generic-instance ownership, parameter-scope restoration, and semantic restarts; then sweep the exact path before assigning the cause to parsing, publication, or scheduling.
- Complete when: a bounded reproduction identifies and fixes the ordering fault, or the imported generic body is proved safe by construction.

### compiler.core.082 — Hot-path node containers that need more than a container swap

- Recorded: 2026-10-09 12:37
- Updated: 2026-10-10 15:44 — Retain only the remaining order and table-lifetime constraints.
- Evidence: flat tables now replace node-based containers across sema, code generation, optimization, sanitization, linking, and native dependency walks. Per-run side tables are lazy, and type interning builds TypeInfo only for new types. Native listings and linked sections remain identical. A CallArgMapping reuse needs proof that attempted and selected generic functions agree; TypeGen's deep stackSet may be cheaper than scanning.
- Remaining: order-preserving replacements for sanitizer sparse facts, mem2reg slots, SLP locations and entry values, web loads, LICM hoistSet, and native dependency rejections. A worker-kept FlatKeyMap also clears at the largest size seen, not the current function's size.
- Next: replace one ordered map with an output-equivalent flat map, or benchmark a kept-table clear against rebuilding a fresh table.
- Complete when: each remaining table is replaced with identical output and its owning tests pass, or its added design cost is shown not worthwhile.
- Related: compiler.core.060.

### compiler.core.074 — Repeated native rebuilds still vary in data layout

- Recorded: 2026-10-01 17:08
- Updated: 2026-10-10 15:44 — Narrow the remaining variation to empty-string placement and parallel global layout.
- Evidence: normalized code, unwind data, debug data, exports, and imports are stable across repeated builds. A single-core lz77 build still shifts .rdata and relocations when an empty reflected type name points to an earlier shared string in one build and its own allocation in another. Global .data and .bss offsets also vary because sema assigns them concurrently.
- Next: assign global layout at emission from a stable module, file, and declaration key while preserving JIT addresses; then compare normalized unwind records again.
- Complete when: repeated builds have stable normalized code, data layout, and unwind records, with the native regression suite green.

### compiler.core.060 — A compile-time call still pays per-call plumbing its call graph does not need

- Recorded: 2026-09-30 08:32
- Updated: 2026-10-10 15:44 — Summarize the remaining walks and their invalidation constraints.
- Evidence: compile-time calls still repeat four walks: relocation patching traverses constant closures per function; JIT preparation rebuilds call order before and after sema; runtime type hashing reconstructs scoped names already cached by symbols; and escape summaries rescan pending edges plus guarded return summaries. Patch walks now keep relocations inline.
- Constraints: patched function addresses can move from work to patch addresses; JIT order also depends on ignored functions and macro attributes; scoped-name caching requires immutable scope chains; escape summaries must preserve guarded proofs and late completion.
- Next: measure these costs on a gui Release rebuild and change only a bounded walk with a repeatable gain.
- Complete when: each walk is removed with compile-time execution and safety coverage, or measured and retained as not worth its risk.
- Related: compiler.core.030.

### compiler.core.003 — Code-generation invalidation is module-wide

- Recorded: 2026-08-09 11:30
- Updated: 2026-10-10 15:44 — Condense the implemented cache layers and remaining invalidation work.
- Current cache layers: workspace manifests reuse unchanged modules; interface-compatible dynamic dependency edits republish the DLL without rebuilding consumers; static dependency edits can relink persisted consumer objects; and non-debug executables reuse large relocation-free function members, including unwind data. Cache writes are atomic and best-effort; missing, changed, or malformed artifacts fall back to ordinary compilation. Imported native code run at compile time remains an invalidation boundary.
- Next: admit relocation-bearing functions by fingerprinting referenced symbols, constant payloads, ABI, and inlinable bodies. Add debug records only when source identities and line mappings are deterministic; keep an adaptive threshold so cache work costs less than the code generation it saves.
- Performance gate: compare clean, no-op, private-body, static-dependency, and public-API edits with compiler.core.004; clean builds must stay within the established noise band.
- Complete when: safe native and JIT builds reuse body-only edits with correct dependency invalidation, fresh and cached artifacts are identical, and the campaign shows a repeatable gain without a clean-build regression.
- Related: compiler.core.001, compiler.core.002, compiler.core.004, compiler.core.030.

### compiler.core.030 — Every executable lowers the runtime's functions again

- Recorded: 2026-09-05 22:13
- Updated: 2026-10-10 15:43 — Keep the current runtime-closure cost and discard superseded profiles.
- Evidence: executables now lower only functions reached from their roots, but the reachable runtime closure is still lowered for every executable. The function cache in compiler.core.003 excludes functions with code relocations, which covers most of that closure. The earlier JIT cost was removed from native builds; historical timings no longer describe the current compiler.
- Next: measure the runtime functions and time in a current hello-world Release rebuild, then compare relocation-aware function reuse with a runtime-code cache keyed by compiler build, configuration, architecture, and runtime inputs.
- Complete when: fresh and reused runtime code produce identical artifacts, all relevant inputs invalidate the cache, and the current edit-build campaign shows a repeatable gain.
- Related: compiler.core.001, compiler.core.003, compiler.core.004, compiler.core.006, compiler.optimization.029.

### compiler.core.039 — One module analysis resolves four and a half million substitutions

- Recorded: 2026-09-09 17:44
- Updated: 2026-10-10 15:43 — Retain the unresolved repeated-query question and current structural savings.
- Evidence: an imported-module analysis once resolved 4.55 million substitute chains, averaging two links. Passing already-read payload state through comparison lowering and metadata merging removed redundant queries without changing substitution rules; the attempted call-site shortcut showed no reliable timing gain and was reverted. A combined type-and-constant view is unsafe because flow narrowing can suppress a null constant.
- Next: attribute current resolutions to repeated questions within one pass versus callers rebuilding views they already hold; retain a change only with equivalent analysis results and a paired timing on an imported-module workload.
- Complete when: the remaining query cost is attributed and either reduced with a repeatable gain or shown not worth additional state.
- Related: compiler.core.001, compiler.core.038.

### compiler.core.005 — Compiler memory has no attributed, enforced budget

- Recorded: 2026-08-06 20:18
- Updated: 2026-10-10 15:43 — Keep the current memory attribution and discard superseded snapshots.
- Evidence: September 29 Release measurements reduced a six-worker Core DevMode rebuild from 579 to 389 MB with a 0.87x wall-time ratio, and hello build from 112 to 78 MB. The remaining committed-memory gap grows with worker count while live allocation stays near 16 to 17 MiB, chiefly from per-thread Micro scratch and semantic-analysis high-water marks. Earlier snapshots predate page, sanitizer-state, symbol-map, and job-lifetime reductions.
- Next: reduce and attribute per-worker retained scratch without reducing parallelism; share JIT code pages when patching no longer requires page-sized allocations.
- Complete when: Core and hello builds stay below 250 MB and 40 MB on the campaign host, workloads remain within twice the best comparable implementation or record a reviewed exception, and campaign thresholds and variance are explicit.
- Related: compiler.core.004, compiler.core.007, runtime.allocator.017.

### compiler.core.079 — Tuple values never drop the owning fields they hold

- Recorded: 2026-10-07 20:33
- Found while: fixing the ownership of values an implicit `opSet` builds inside literal fields.
- Evidence: a struct-literal type (a tuple) has no lifecycle: `resolveEffectiveLifecycleFunction`
  and `tryBuildLifecycleActionRec` in `CodeGen.cpp` only answer for structs and arrays, so
  `functionHasImplicitDrops` and `registerImplicitDrop` see nothing to drop in a tuple local.
  With a field type that counts its `opDrop` calls, `let t = {owned: cast(Owned, name())}`
  adopts the value with `opPostMove` and never drops it (one set, zero drops), and
  `let t = {owned: mk()}` with `mk()->Owned` moves the call result into the tuple while the
  call temporary is dropped at the end of the statement, so the tuple keeps a released value.
  Every owning type held in a tuple local, such as `Core.String`, leaks or dangles the same way.
- Next: decide whether a tuple owns its fields like a struct (field-wise drop, post-copy and
  post-move derived from the field types) or rejects owning field types; then implement that
  rule in the lifecycle resolution and cover both producers above in the `native` suite.
- Complete when: a tuple local holding an owning field drops it exactly once at scope end, or
  the declaration is rejected with a diagnostic, and the two reproducers above are suite tests.

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

**Related:** compiler.core.002, compiler.core.006, compiler.language.service.001, compiler.language.service.003, compiler.core.030.

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

## Deliberately out of scope

- **An LLVM back end.** The native and Micro back ends are the supported architecture. Reconsider only if a concrete platform or optimization requirement cannot be met within them.
- **A second language front end.** The compiler architecture is optimized for Swag; a second parser and semantic model would dilute the persisted-state and tooling work above.
- **A package registry inside the compiler backlog.** Path and workspace dependencies remain compiler responsibilities. Registry identity, trust, lockfiles, acquisition, and publishing need a separate product backlog once their scope and owner are defined.

Frontend, semantic analysis, and code generation defects: something observed in `swc` itself, with
a reproduction and a next investigation step. Optimization passes and generated-code performance
are [compiler.optimization.md](compiler.optimization.md); the borrow, lifetime and sanity analyses
are [compiler.safety.md](compiler.safety.md); the `doc` and `format` commands have their own files,
[compiler.command.doc.md](compiler.command.doc.md) and [compiler.command.format.md](compiler.command.format.md).
