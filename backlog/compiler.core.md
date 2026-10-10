# Compiler Backlog

This backlog covers the compiler front end, back end, and workspace build engine. Documentation, formatting, and language-design work have their own domain files. Only unfinished work belongs here; completed investigations and implementations remain discoverable through Git history.

Items are ordered from the most recently updated down. Every completion condition is intended to be testable. Measurements below are a dated baseline, not permanent product claims.


### compiler.core.001 — Dependencies cross the module boundary as regenerated source

- Recorded: 2026-08-06 20:18
- Updated: 2026-10-10 15:50 — Keep the interface contract and one dated import-cost baseline.
- Evidence: a September 2026 Prism snippet spent about 172 ms lexing, parsing, and analyzing Core's generated API (115,000 tokens); this fixed cost dominates the user's source.
- Next: replace generated dependency API source with a versioned binary interface that supports lazy symbol lookup and preserves exported types, constants, attributes, ABI, and required bodies/metadata.
- Complete when: workspace imports skip API source parsing, the human-readable export remains available, all relevant inputs invalidate the interface, and fresh/reused imports produce identical diagnostics and artifacts.
- Related: compiler.core.002, compiler.core.006, compiler.language.service.001, compiler.language.service.003, compiler.core.030.

### compiler.core.002 — Front-end invalidation is module-wide

- Recorded: 2026-08-06 20:18
- Updated: 2026-10-10 15:50 — Keep the per-file cache key and observable edit behavior.
- Intent: persist lexical, parsed, and semantic state per source, keyed by content, relevant configuration, and imported public symbols actually observed.
- Evidence: core_touch still rebuilds every file of the module.
- Complete when: private edits reanalyze only affected files; public API, file-set, configuration, and compiler changes invalidate the right dependents; clean and incremental workspace results match.
- Related: compiler.core.001, compiler.core.003, compiler.core.004, compiler.core.016.

### compiler.core.006 — Every process rebuilds the prelude state

- Recorded: 2026-08-06 20:18
- Updated: 2026-10-10 15:50 — Keep prelude reuse within the shared module-interface design.
- Evidence: a September 2026 Prism snippet spent about 52 ms analyzing the unchanged runtime prelude after process startup and module setup.
- Intent: reuse the prelude through the same module-interface mechanism as dependencies; do not add a separate prelude cache.
- Complete when: warm builds and scripts load the interface without lexing/parsing/sema, source/compiler/target/configuration changes invalidate it, and fresh/reused outputs match.
- Related: compiler.core.001, compiler.core.004, compiler.core.016.

### compiler.core.016 — Tool scripts recompile on every invocation

- Recorded: 2026-08-09 20:16
- Updated: 2026-10-10 15:50 — Reduce the script cache contract to its inputs and process behavior.
- Intent: persist compiled scripts using a key over loaded sources, imported public interfaces, compiler version, target, and relevant configuration.
- Complete when: unchanged runs skip compilation; source, load, import, target, or configuration changes invalidate the cache; fresh and cached launches preserve diagnostics, arguments, environment, output, exit code, and concurrent/corrupt-cache behavior.
- Related: compiler.core.001, compiler.core.002, compiler.core.006, platform.portability.080.

### compiler.core.079 — Tuple values never drop the owning fields they hold

- Recorded: 2026-10-07 20:33
- Updated: 2026-10-10 15:49 — Retain the ownership bug and the two producer cases.
- Evidence: tuples have no lifecycle handling in CodeGen. A tuple field initialized by a casted owning value is adopted but never dropped; a field initialized by a call result can be dropped as a temporary while the tuple retains it. Both leak or leave dangling ownership.
- Next: define field-wise tuple lifecycle behavior or reject owning fields, then cover both initializers in native tests.
- Complete when: the owning field drops exactly once or the declaration is rejected with a diagnostic.

### compiler.core.021 — JIT code leaks one thread-local index per compiler instance

- Recorded: 2026-08-12 18:01
- Updated: 2026-10-10 15:49 — Keep the remaining plain-TLS leak after fiber-slot cleanup.
- Evidence: DevMode poisoning exposed a fiber-local cleanup callback reading a destroyed compiler instance. JIT FlsAlloc/FlsFree calls now use host wrappers that run owned callbacks before instance destruction. Plain TlsAlloc indexes have no callback and remain allocated for the process; an allocator-using instance takes at least one.
- Next: count TLS indexes across a long workspace run; if counts scale with compiler instances, track and free their indexes at destruction.
- Complete when: repeated compiler-instance creation keeps TLS usage bounded and workspace tests pass under poisoning.

### compiler.core.053 — Confirm that a linked PDB keeps one definition per structure

- Recorded: 2026-09-17 08:42
- Updated: 2026-10-10 15:49 — Keep the remaining linked-debug-archive check.
- Evidence: TypeTableBuilder now hash-conses identical CodeView records and points structures to forward declarations. A 60-structure probe reduced TPI records from 1,253 to 913, and each type kept one forward declaration and one definition; DebugInfo and PDB tests passed.
- Next: build Swag Scope with debug archives and compare linked PDB size and structure records by name.
- Complete when: linked programs keep one definition per distinct layout, focused debug tests pass, and the PDB shrinks.

### compiler.core.075 — Aligned node references collapse semantic metadata partitions

- Recorded: 2026-10-03 16:28
- Updated: 2026-10-10 15:49 — Keep the measured memory cost and the remaining storage-design question.
- Evidence: node references are aligned, so selecting 16 payload shards with reference modulo 16 uses only two. Hashing the reference distributed access and preserved outputs, but raised peak committed memory by 17% for Core and 3% for GUI; timing was noisy and a single-worker Core build slowed about 6%. The experiment was not retained.
- Next: separate sparse side-table distribution from payload-page allocation, then measure serial and parallel builds with bounded memory cost.
- Complete when: concurrent publication/readback stays correct and the revised layout has a repeatable compile-time benefit.

### compiler.core.057 — The lazy-body completion race has no deterministic regression

- Recorded: 2026-09-24 14:07
- Updated: 2026-10-10 15:49 — Retain the fixed ownership rule and the missing stress-test seam.
- Evidence: semaPostNode could complete a lazy body while its runner was starting, then publish it before symbol resolution finished. The declaration walk now leaves delegated bodies to the runner. A temporary 3 ms delay exposed six premature completions before the fix; three delayed and ten normal post-fix runs passed.
- Boundary: the race window is only a few instructions, so ordinary source and C++ tests cannot place another task there.
- Next: add a DevMode stress hook that delays lazy-body post-node handling; check whether compiler.core.047's imported generic binding failure shares the race.
- Complete when: the deterministic stress case fails without the ownership fix and passes with it.

### compiler.core.038 — Measure the remaining semantic frame construction cost

- Recorded: 2026-09-09 15:04
- Updated: 2026-10-10 15:49 — Keep current frame members and defer changes until they are measured.
- Evidence: Sema now copies frames only when entering syntax, compile-time, or generated-top-level context; attribute safety/sanity overrides use masks. Frames still own namespace, binding, borrow, hidden-symbol, and narrowing collections, but their current construction/destruction cost is unknown. A previous copy-only change showed no paired timing gain and predates these reductions.
- Next: profile current frame pushes, populated members, and constructor/destructor cost on a large file and an imported-Core snippet; change only a measured hotspot.
- Complete when: a current paired measurement identifies a worthwhile change or rules out the remaining cost.
- Related: compiler.core.001, compiler.core.005, compiler.core.006.

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

## Deliberately out of scope

- **An LLVM back end.** The native and Micro back ends are the supported architecture. Reconsider only if a concrete platform or optimization requirement cannot be met within them.
- **A second language front end.** The compiler architecture is optimized for Swag; a second parser and semantic model would dilute the persisted-state and tooling work above.
- **A package registry inside the compiler backlog.** Path and workspace dependencies remain compiler responsibilities. Registry identity, trust, lockfiles, acquisition, and publishing need a separate product backlog once their scope and owner are defined.

Frontend, semantic analysis, and code generation defects: something observed in `swc` itself, with
a reproduction and a next investigation step. Optimization passes and generated-code performance
are [compiler.optimization.md](compiler.optimization.md); the borrow, lifetime and sanity analyses
are [compiler.safety.md](compiler.safety.md); the `doc` and `format` commands have their own files,
[compiler.command.doc.md](compiler.command.doc.md) and [compiler.command.format.md](compiler.command.format.md).
