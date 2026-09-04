# Compiler Backlog

This backlog covers the compiler front end, back end, workspace build engine, and editor-facing compiler services. Documentation, formatting, and language-design work have their own domain files. Only unfinished work belongs here; completed investigations and implementations remain discoverable through Git history.

Items are ordered by decreasing expected value inside each tier. Every completion condition is intended to be testable. Measurements below are a dated baseline, not permanent product claims.

As of 2026-09-02, excluding the vendored `src/Support/Memory/mimalloc` tree, `src/` contains 264,112 physical lines in 687 `.cpp` and `.h` files. `src/Compiler/Sema` accounts for 85,236 lines in 154 files. The compiler diagnostic catalog contains 562 source `SWC_DIAG_DEF` entries, and `swc format --dump-config` exposes 131 options. Recompute these figures when using them to prioritize work.

## Tier A — Persisted compiler state

### compiler.core.001 — Dependencies cross the module boundary as regenerated source

**Intent.** Replace generated dependency API source with a versioned binary module interface. The interface must preserve exported symbols, types, constants, attributes, ABI information, and any bodies or metadata required by downstream optimization, while allowing lazy lookup by symbol.

**Complete when.**

- Workspace imports no longer add generated API `.swg` files to the lexer and parser.
- `--export-api-dir` still emits a human-readable `.swg` representation for inspection and tooling.
- Cache invalidation covers compiler version, build configuration, public declarations, exported constants, ABI-relevant attributes, and serialized inlinable bodies.
- Workspace tests prove that fresh and reused interfaces produce identical diagnostics and artifacts.

**Related:** compiler.core.002, compiler.core.006, compiler.core.008, compiler.core.011.

### compiler.core.002 — Front-end invalidation is module-wide

**Intent.** Persist lexical, parsed, and semantic state per source file. Cache keys must include the source content, relevant build configuration, and fingerprints of imported public symbols actually observed by the file.

**Complete when.**

- Editing a private body reanalyzes only the changed file and its semantic dependents.
- Changing a public signature invalidates every consumer that observed it.
- Adding, removing, or renaming a file, changing relevant configuration, and changing compiler versions invalidate the correct state.
- Statistics from compiler.core.004 report reused and rebuilt files, tokens, and semantic work.
- Clean and incremental workspace builds are covered by equivalent-result tests.

**Related:** compiler.core.001, compiler.core.004, compiler.core.003, compiler.core.016.

### compiler.core.003 — Code-generation invalidation is module-wide

**Intent.** Cache code generation at function granularity. A reusable artifact must be keyed by the function's semantic fingerprint plus the reachable ABI and inlinable-body dependencies that can affect its generated code.

**Complete when.**

- A body-only edit regenerates the changed function and any function whose generated code depends on it, while unrelated functions are reused.
- Reuse works for JIT and native builds, including debug and unwind metadata.
- A deterministic test compares clean and warm native images, manifests, and observable behavior.
- Cache entries reject compiler, target, configuration, ABI, and relevant optimization changes.

**Related:** compiler.core.001, compiler.core.002, compiler.core.004.

## Tier B — Measurement and budgets

### compiler.core.004 — The benchmark campaign measures only hello world

**Evidence.** `bench/history.json` currently uses protocol 2 and contains three records, all dated 2026-08-07. They cover only `hello_build_ms` (99.5432–112.6252 ms) and `hello_build_peak_mb` (105.28125–107.4375 MiB). They do not establish full-core, warm no-op, or touched-file baselines.

**Intent.** Extend the reproducible benchmark campaign with a full core rebuild, a warm no-op rebuild, and a single-file incremental edit. Measure Release and DevMode where their behavior differs.

**Complete when.**

- Each history record contains wall time, peak memory, processed and reused files, and processed and reused tokens for every workload.
- Results include a normalized control, clean-worktree provenance, compiler revision, host description, and configuration.
- At least five clean baseline campaigns establish stable thresholds before regressions are enforced.
- The campaign and CI report threshold violations without silently rewriting the baseline.

**Related:** compiler.core.002, compiler.core.005, compiler.core.007.

### compiler.core.005 — Compiler memory has no attributed, enforced budget

**Intent.** Use external profiling and the compiler.core.004 workloads to reduce retained AST, semantic, Micro, and temporary state, then turn the agreed memory targets into regression checks.

**Complete when.**

- A full core DevMode build peaks below 250 MiB and a hello-world build below 40 MiB on the campaign host.
- Every campaign workload stays within twice the best comparable compiled-language implementation measured by the same harness, or records a reviewed exception.
- Thresholds, host normalization, and variance policy are stored with the campaign.
- External profiling attributes the remaining peak well enough that a regression report names the responsible subsystem.

**Related:** compiler.core.004, compiler.core.007.

## Tier B — Reused and parallel compiler work

### compiler.core.006 — Every process rebuilds the prelude state

**Intent.** Serialize and reuse the prelude through the same module-interface mechanism as ordinary dependencies, rather than maintaining a special prelude cache.

**Complete when.**

- A warm hello-world build and a warm script launch load the prelude interface without lexing, parsing, or semantically rebuilding the prelude.
- Prelude source, compiler version, target, and relevant configuration changes invalidate the interface.
- Fresh and reused prelude paths produce identical diagnostics and artifacts.
- The compiler.core.004 campaign demonstrates the reduced fixed startup floor.

**Related:** compiler.core.001, compiler.core.004, compiler.core.016.

### compiler.core.007 — Workspace front ends and code generation run serially

**Evidence.** The workspace computes dependency order, but module front-end and code-generation work is still consumed serially. The current depth-one pipeline can overlap one background link with compilation of the next module; it does not schedule independent ready modules concurrently.

**Intent.** Schedule ready modules concurrently on the dependency DAG through a shared worker pool with explicit memory and CPU limits.

**Complete when.**

- Independent sibling modules overlap front-end and code-generation work, while consumers wait for the required interface or link artifact.
- Compiler and linker work share a bounded concurrency policy and do not oversubscribe the host.
- Logs, manifests, diagnostics, and emitted artifacts remain deterministic.
- The concurrency cap accounts for the memory measurements and budget from compiler.core.005.
- Workspace tests cover a diamond graph, concurrent failures, cancellation, and deterministic repeated builds.

**Related:** compiler.core.004, compiler.core.005.

## Tier C — Language-server capabilities

### compiler.core.008 — There is no persistent language-server process

**Intent.** Add a compiler-hosted LSP transport and session layer: initialization and shutdown, workspace discovery, document open/change/close notifications, versioned snapshots, request cancellation, and orderly teardown. Requests must call compiler-library services instead of launching a compiler process per operation.

**Complete when.**

- A standard LSP client can open a workspace, edit unsaved buffers, cancel obsolete requests, and shut down cleanly.
- Responses are computed from the requested document version and stale work cannot publish newer state.
- The session reuses persisted compiler state from compiler.core.001 and compiler.core.002 when available.
- Protocol integration tests run independently of the VSCode extension.

**Related:** compiler.core.001, compiler.core.002, compiler.core.010, compiler.core.011, compiler.core.013, compiler.core.014, compiler.core.009, compiler.core.012.

### compiler.core.009 — Open documents have no incremental diagnostics

**Intent.** Publish parser and semantic diagnostics for the accepted version of every open document, including affected dependents, without requiring a workspace build.

**Complete when.**

- Opening a file with an error publishes diagnostics, correcting it clears them, and closing it restores the on-disk view.
- A stale analysis job never overwrites diagnostics for a newer document version.
- Diagnostic identifiers, severity, primary and related locations, source snippets, and normalized paths survive the protocol conversion.
- A multi-file protocol test covers an edit that introduces and then repairs a dependent-file error.

**Related:** compiler.core.002, compiler.core.008.

### compiler.core.010 — The editor has no semantic completion service

**Intent.** Provide completion candidates from the semantic snapshot at a source position, including local scope, members, visible imports, generic parameters, and applicable language constructs.

**Complete when.**

- Completion operates on unsaved, syntactically incomplete buffers and honors shadowing and visibility.
- Items include stable kind, insertion text, signature/detail, and documentation fields where available.
- Results are deterministic and cancellable, and a stale request cannot populate a newer buffer.
- Protocol tests cover local, member, import, generic, incomplete-expression, and inaccessible-symbol cases.

**Related:** compiler.core.008, compiler.core.011, compiler.core.013.

### compiler.core.011 — The editor cannot navigate to definitions

**Intent.** Resolve the symbol referenced at a source position and return its canonical declaration location, including declarations in dependencies represented by persisted interfaces.

**Complete when.**

- Navigation covers locals, parameters, members, overloads after resolution, generics, aliases, generated declarations with an available source origin, and imported symbols.
- Ambiguous or unresolved positions return no misleading location.
- Paths and ranges are valid for open snapshots and on-disk dependency sources.
- Protocol tests cover same-file, cross-file, cross-module, overload, and no-result cases.

**Related:** compiler.core.001, compiler.core.008, compiler.core.012.

### compiler.core.012 — The editor cannot find semantic references

**Intent.** Enumerate references to the resolved declaration at a source position across the workspace, distinguishing declarations from uses and excluding textually identical but semantically different symbols.

**Complete when.**

- Results cover locals, members, overloads, generics, aliases, and cross-module references.
- The request supports including or excluding the declaration and uses versioned open-document snapshots.
- Shadowed names, comments, strings, and unrelated overloads do not appear.
- Results are deterministic, deduplicated, cancellable, and covered by same-file and cross-module protocol tests.

**Related:** compiler.core.008, compiler.core.011, compiler.core.014.

### compiler.core.013 — The editor has no semantic hover service

**Intent.** Render concise semantic information for the resolved entity at a source position: declaration signature, inferred type or constant value, ownership and relevant attributes, and public documentation.

**Complete when.**

- Hover covers values, types, functions and selected overloads, generic parameters, fields, aliases, and literals with inferred types.
- Output uses stable Markdown escaping and does not expose internal compiler-only names.
- Unknown or ambiguous positions return no misleading result.
- Protocol tests cover imported documentation, inferred values, overload resolution, and no-result cases.

**Related:** compiler.core.008, compiler.core.010, compiler.core.011.

### compiler.core.014 — The editor cannot rename a symbol semantically

**Intent.** Validate a requested identifier at a resolved declaration, reuse the semantic reference set, and produce a versioned workspace edit without changing unrelated text.

**Complete when.**

- Prepare-rename rejects keywords, compiler-generated or immutable declarations, ambiguous positions, and names that would create a known collision.
- Rename covers declarations and references across open and on-disk workspace files while preserving comments and strings.
- Edits are sorted, non-overlapping, versioned where required, and rejected when snapshots become stale.
- Protocol tests cover shadowing, members, overloads, aliases, cross-module use, collision, and cancellation.

**Related:** compiler.core.008, compiler.core.012.

## Tier C — Command-line and script workflows

### compiler.core.015 — The VSCode task provider emits obsolete command lines

**Evidence.** `vscode/src/providers.js` currently constructs `swag build -w:${workspaceFolder}` and `swag format -f:${file}` as command strings. These spellings do not match the current long-form CLI and string concatenation makes paths with spaces shell-dependent. The module-level task array can also accumulate duplicates across repeated provider calls.

**Intent.** Build tasks from the current compiler argument contract and pass executable plus argument vector through VSCode's task API.

**Complete when.**

- Build, rebuild, and format tasks invoke the intended compiler command with the correct current arguments.
- Workspace and file paths containing spaces or shell metacharacters reach the compiler as one argument.
- Repeated task discovery returns a stable set without duplicates.
- An automated extension test, or an injectable command-builder test, asserts the exact executable and argument vector.

**Related:** compiler.core.008.


### compiler.core.016 — Tool scripts recompile on every invocation

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

---

The entries below were open investigations when the unified backlog was introduced. Update their
next action in place as the evidence matures. They retain their former order until re-triaged, so
position in this imported block carries no priority claim.

Frontend, semantic analysis, and code generation defects: something observed in `swc` itself, with
a reproduction and a next investigation step. Optimization passes and generated-code performance
are [compiler.optimization.md](compiler.optimization.md); the borrow, lifetime and sanity analyses
are [compiler.safety.md](compiler.safety.md); the `doc` and `format` commands have their own files,
[compiler.command.doc.md](compiler.command.doc.md) and [compiler.command.format.md](compiler.command.format.md).

## Published symbols, imports, and name resolution

### compiler.core.019 — An ambiguous `.member` still reads "not published yet" as "not there"

- Area: compiler
- Found while: fixing the same race for the unambiguous case, which was making `Swag Capture` fail to
  compile with 18 to 26 errors per attempt, a different set every run
- Observation: `probeAutoMemberCandidates` looks every candidate up with `noWaitOnEmpty`, because
  with several candidates it must step over the ones that legitimately lack the name. An empty
  result therefore means both "this scope has no such member" and "this scope has not published it
  yet", and the two are indistinguishable. With exactly one candidate the lookup now waits, like
  the qualified spelling of the same access; with more than one it still decides immediately and
  reports `sema_err_cannot_compute_auto_scope`.
- Evidence: a member minted by a `#[Swag.Mixin]` inside one `impl` block of a type arrives when
  that block's body runs, and a struct is marked sema-completed once its `impl` blocks are
  *registered* — `decPendingImplRegistrations` fires before the body
  ([Sema.Impl.cpp:157-166](../src/Compiler/Sema/Ast/Sema.Impl.cpp#L157-L166)) — so a lookup on a
  "complete" type can still miss members. Every Swag Capture failure was that shape:
  `struct 'ActionQuickStyle' has no field 'Reset'` for a `Reset` that `newCmdId("Reset")` mints in
  a neighbouring `impl` block. The single-candidate half is fixed; a `with` block or a method
  carrying binding vars puts more than one candidate in scope and reopens it.
- Next step: reproduce it deliberately before changing anything — a type whose id is minted by a
  mixin, used as `.Id` inside a `with` block over an unrelated value, in a module big enough to
  spread the jobs. Then decide whether the multi-candidate path can park too: waiting on each
  candidate in turn is wrong (one of them is expected to lack the name), so the wait has to be
  "no candidate can still grow", which needs a scope-settled predicate the compiler does not have.
  A cheaper answer may be to park only while at least one candidate type has an `impl` block whose
  body has not run.

### compiler.core.020 — Concurrent type generation can corrupt declared-method traversal

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
  report now appends the reporting thread's stack (`Allocator.cpp`), so a recurrence names its
  culprit directly; if one does recur, persist the failing module and stress parallel type
  generation as originally planned.

## JIT-hosted runs

### compiler.core.021 — A dangling reference into a destroyed compiler instance has no deterministic detector

- Area: compiler
- Found while: tracking an intermittent JIT '#test' failure in `swc test -w bin/apps -m swagcapture
  --rebuild`, which turned out to be imported native modules (core.dll and siblings, loaded once
  per process) keeping `Swag.processInfos().args` slices into the run-argument storage of a dependency-build
  compiler instance that had already been destroyed. That defect is fixed by interning the handed
  storage for the lifetime of the process, but the *class* — long-lived imported modules holding a
  pointer into per-instance state — was only caught because a heap block happened to be reused with
  bytes that failed a `Debug.assert` inside `Path.extension`, in the Release compiler binary only,
  roughly once per run.
- Observation: nothing makes such a stale reference fail deterministically, so a suite regression
  cannot be written that reliably turns red without the fix: the dead storage usually still holds
  its old bytes, and every read through it then looks healthy. The DevMode binary never tripped at
  all because its allocator reused the freed block differently.
- Evidence: pre-fix, iteration 1 of every `swc test -w bin/apps -m swagcapture --rebuild` loop on the
  Release binary failed in `library.test.swg` (the one test that funnels `Env.executablePath()`
  into a validated path API), while the same command on the DevMode binary passed 10/10; post-fix
  the Release loop passed 8/8. A probe comparing the live instance against what JIT code reads
  showed five compiler instances writing five run-argument storages in one process, the test
  instance healthy, and the imported module reading a sixth, dead one.
- Next step: poison the global segments and other instance-owned storage handed across the JIT
  boundary when a `CompilerInstance` is destroyed, under `SWC_DEV_MODE` — a stale cross-instance
  reference then reads the poison pattern instead of plausible stale bytes, which makes this whole
  class reproduce on the first run. Then add a `bin/unittests/workspace` case that rebuilds a
  dependency and asserts `Env.executablePath()` is a valid, existing path from the tested module.

### compiler.core.022 — A JIT '#test' can call through a function slot that was never patched

- Area: compiler
- Found while: the 2026-08-12 sanification pass, looping the apps workspace in debug. This is the
  strongest reproduction so far of the intermittent Swag Vault JIT failures the pass set out to track.
- Observation: in `swc.dm test -w bin/apps -bc debug --rebuild`, six Swag Vault `#test` functions
  in `mainwindow.test.swg` (109, 133, 163, 363, 384, 494) die on the same hardware exception:
  execution lands at `rip=0x0000000080019060` (memory state FREE, "jit offset: unresolved"), which
  is a jump through a function-pointer slot holding a value no live code owns. The failure hits
  roughly two runs out of three at the first iteration, always with that same rip, and an A/B
  build bisected it as independent of the concurrent matcher fix added the same day. Swag Capture's
  151 tests pass in the same runs; the release and fast-debug legs of the same workspace pass far
  more often.
- Evidence: the run reports `state: Run JIT`, `__test_14` at `mainwindow.test.swg:109:1`,
  `0xC0000005` at `0x0000000080019060`, `memory: state=FREE`. The constant-side patcher leaves a
  slot untouched when its relocation carries `allowUnresolvedFunction` and the target is not ready
  (`shouldLeaveOptionalFunctionRelocationUnresolved`, [JIT.cpp](../src/Backend/JIT/JIT.cpp)), and
  the `LazyGenericBodyRunning` case explicitly defers; nothing re-patches such a slot when the
  target becomes ready afterward, so a test that reaches one through an interface table or stored
  callback jumps into the placeholder bytes. The rip being identical across six tests and several
  runs says the slot content is deterministic, not heap garbage.
- Next step: reproduce with the command above (two runs usually suffice), then dump the pointed-to
  slot: identify which constant allocation contains `0x80019060` at patch time and which symbol its
  relocation names. Decide between re-running the constant patcher when a deferred target publishes
  its JIT address, and refusing to defer relocations that are reachable from an interface table.

### compiler.core.023 — DevMode assigns a semantic payload to the same slice node twice

- Area: compiler
- Found while: building the shared `bin/apps` workspace after integrating Swag Scope's viewers.
- Observation: at 0.1.166, two consecutive runs of a freshly built `swc.dm.exe` asserted
  while semantically checking the unchanged `tools/src/backlog.swg`; the Release compiler checked
  the same tool. At 0.1.167 the reduced witness and the original commands no longer reproduce,
  without a change known to target payload ownership, so this is now an unresolved
  scheduling-dependent lead rather than a deterministic defect.
- Evidence: two consecutive `bin/swc.dm.exe tools/apps.swgs dm build swagscope` runs assert
  in `NodePayload::setSemaPayload` at `NodePayload.cpp:806` because
  `shard->semaPayloads` already contains the node. Both name the `start` reference inside
  `line[start until line.count]` at `tools/src/backlog.swg:172`, under the `#code` body passed
  to `Utf8.visitRunes`. The defect has not yet been reduced because the tool combines a slice of a
  `string`, a captured mutable index, and macro-generated traversal; removing one without first
  identifying the second semantic visit would risk recording the wrong mechanism. A second,
  macro-free witness was found while optimizing `Latin1.trim`: passing
  `bytes[first until bytes.count]` directly to `lastNonSpace` triggers the same assertion on
  `first`, while binding that slice to a local before the call compiles. This removes macro
  expansion from the minimum mechanism and leaves a slice expression used as a call argument.
  At 0.1.167, the macro-free witness — a standalone `#test` passing
  `bytes[first until bytes.count]` straight into a `const [..] u8` parameter — compiles and
  runs, every `tools/*.swgs` invocation checks `backlog.swg` without asserting, and two
  consecutive `bin/swc.dm.exe tools/apps.swgs dm build swagscope` runs are green. Nothing
  in that release targeted payload ownership, so the double visit is more likely scheduling
  dependent rather than resolved.
- Next step: re-evaluate on the next occurrence. Persist the failing module when one happens and
  capture both `setSemaPayload` calls for the slice node before changing payload ownership; a
  reduction that does not fail on demand cannot be turned into a `bin/unittests/sema` case.

### compiler.core.024 — A JIT '#test' can silently compute a wrong value in a release run

- Area: compiler
- Found while: validating the `x86-64-v3` baseline change with
  `swc tools/unittests.swgs dm native -bc release`, on the first run after a `SWC_BUILD_NUM` bump
  had invalidated every cache.
- Observation: `bin/unittests/native/casts/autocast_pointer_receiver.swg:35` reported
  `assertion does not hold: AutoCastStorage.lo == 16` from the JIT `#test` at line 31, which writes
  a file-scope struct through a pointer receiver. Nothing faulted: the global simply did not hold
  what the call had written. This widens the class compiler.core.021 and compiler.core.022 describe -- both of those
  manifest as a hardware exception, so a run that survives is trusted; here a run survived and the
  data was wrong, which no `#test` outside this one would have noticed.
- Evidence: the failure reproduced twice in a row -- once in the full suite, once with
  `--file-filter autocast_pointer_receiver` -- then never again. The same filtered command passed
  5/5, the full suite passed, and a full cold-cache `--rebuild` of the same suite passed 2_919/2_919.
  Stashing the change and running the same filtered test on the pre-change `bin/swc.exe` also
  passed, so the two failures sit on the changed tree and the eight successes sit on the same
  changed tree; the discriminator is not the diff. Both failures were on caches invalidated by the
  version bump, which is the one condition the eight green runs did not share.
- It is deterministic, and the discriminator is the suite, not the cache (2026-08-24). The same
  assertion fires on every run of `swc tools/unittests.swgs native -bc release` and never on
  `--file-filter autocast_pointer_receiver`, with a warm cache, with the release compiler built
  from an untouched `master`, and equally with one carrying unrelated backend changes. So the
  trigger is compiling the whole `native` suite as one module: the failing `#test` is the same,
  and what changes around it is the rest of the sources. That also means the failure halts the
  release run of that suite for everyone, and every file after `casts/` goes untested there.
- Next step: bisect the suite by removing files rather than by repeating the run — take the
  `native` directory, keep `casts/autocast_pointer_receiver.swg`, and halve the rest until the
  smallest set that still fails is known. Then dump `setRange` and the `#test` body from that set
  and from the filtered one and compare; two compiles of the same function that differ is what to
  look for before the allocator or global-segment publication.

### compiler.core.026 — A namespace-qualified generic type cannot take a generic parameter

- Area: compiler
- Found while: moving Swag Scope's viewer contract into an app-published `Viewer` namespace, which
  put a generic support type behind a namespace for the first time.
- Observation: `Ns.Box'T` is rejected wherever `T` is the enclosing generic parameter, while the
  same type with a concrete or aliased argument (`Ns.Box'u32`, `Ns.Box'MyAlias`) resolves, and the
  unqualified `Box'T` resolves. The qualified spelling reaches instantiation and then waits on `T`
  forever, so the cycle checker reports it as an unknown symbol at the argument, not at the use.
- Evidence: with `namespace Ns { struct(T) Box { value: T } }` in one file, each of
  `struct(T) Holder { boxed: Ns.Box'T }`, `func(T) f(box: *Ns.Box'T)->T => box.value` called as
  `f'u32(&box)`, and `func(T) g()->Ns.Box'T` fails with `unknown symbol 'T'` pointing at the
  argument. Replacing `Ns.Box'T` with `Ns.Box'u32` in the same file compiles and runs. Reproduced
  on 0.1.288.
- Second defect behind it: deduction never reaches instantiation for the same spelling. Calling
  `f(&box)` without an explicit argument reports `cannot deduce generic parameter 'T'` instead,
  because `tryGetStructPatternGenericArgs` in
  `src/Compiler/Sema/Generic/SemaGeneric.Deduce.cpp` reads the pattern's `nodeIdentRef` as a
  quoted expression and returns empty for the `AstMemberAccessExpr` a qualifier produces. Walking
  down to that member access's right side makes deduction succeed and uncovers the resolution
  failure above; the two are one feature and are worth fixing together.
- Next: find where the quoted suffix of a qualified type is resolved. `lookupScopedMember` in
  `src/Compiler/Sema/Helpers/SemaHelpers.Symbol.cpp` binds the matched `Ns.Box` symbols onto the
  quoted callee and substitutes the member access with the quoted expression; establish which scope
  the suffix identifier is then matched in, and why a file-scope alias resolves there but a
  function- or struct-local generic parameter does not.
- Complete when: a `sema` suite test declares a generic struct in a namespace and uses
  `Ns.Box'T` as a struct field, a function parameter, and a return type, with both explicit
  instantiation and deduction from the argument.

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
- Complete when: either a loaded shared library provably shares the host's allocator and context in
  a workspace test that links its dependencies in, or the backlog records why it cannot and the
  compiler diagnoses the combination it can see.

### compiler.core.028 — Auto-inlining loses the null-narrowing facts, so release rejects a correct program

- Area: compiler/sema, `SemaInline`, nullability narrowing
- Found while: running the new CWE safety corpus
  (`bin/unittests/safety/corpus/cwe476_null_pointer_dereference.swg`) in `release`, where the
  most basic narrowing case failed and the same case passed in `devmode`.
- Evidence: minimal reproduction, rejected in `release` and accepted in `devmode`:

```swag
struct Plain { value: s32 }

func testPlain(node: *Plain?)->s32
{
    if node == null do
        return -1
    return node.value          // release: "member access through '*Plain?' dereferences a
}                              // value that can still be null"

var a: Plain

#test
{
    Swag.assert(testPlain(&a) == 0)
    Swag.assert(testPlain(null) == -1)     // this call site is what triggers it
}
```

  The error is reported against the FUNCTION body, not the call site. It appears only once the
  function is called with an argument that is really nullable — calling it with `&a` alone is
  accepted — and `#[Swag.NoInline]` on `testPlain` makes it go away. Auto-inlining is a
  release-only decision, which is why the divergence follows the configuration.
- Consequence: a correct program compiles in one configuration and is rejected in another, on
  the first narrowing route the reference teaches (`if p == null do return`). That is worse
  than a missing check: nothing about the source says which build will take it, and the
  failure appears at ship time. `bin/std` happens to build in `release`, so nothing in the
  repository catches it today.
- Next: the inline expansion re-runs the body without rebuilding the flow facts the original
  pass established, so the guard that dominates the access is not in scope for the expanded
  copy. Either carry the narrowing facts into the expansion, or skip the nullability use-site
  check on a body that is being expanded, since the original body was already judged.
- Complete when: the reproduction above compiles in both configurations, the `#[Swag.NoInline]`
  workarounds in `cwe476_null_pointer_dereference.swg` are removed, and a case covering
  narrow-then-inline is pinned in `bin/unittests/sema`.

### compiler.core.029 — A cross-file inlined call assigned into a struct field trips a compiler assertion in release

- Area: compiler/sema, `SemaCheck`, inlining
- Found while: running the new CWE safety corpus in `release`.
- Evidence: `SWC_ASSERT` failure at
  [SemaCheck.cpp:393](../src/Compiler/Sema/Helpers/SemaCheck.cpp#L393) — the `SWC_UNREACHABLE`
  in `tokenIdForModifierFlag`, reached from `reportUnsupportedModifier`, so sema is reporting
  an unsupported modifier whose flag the switch does not name. Minimal reproduction, two files
  in one module, `release` only:

```swag
// file one
#global namespace Corpus
func heapAlloc(size: u64)->*void { ... }     // any body; returns '*void'

// file two
struct LeakyOwner { pointer: *s32? }

func leak()
{
    var owner: LeakyOwner
    owner.pointer = cast(*s32) heapAlloc(4)     // panics the compiler
}
```

  The same code in ONE file compiles. `#[Swag.NoInline]` on `heapAlloc` does not help, so the
  trigger is not the callee's own expansion. `devmode` is unaffected, which points at the
  release-only automatic inlining.
- Consequence: a compiler crash, not a diagnostic, on ordinary code — a call assigned into a
  nullable struct field across a file boundary. It ends the build with a stack trace and no
  usable message.
- Next: find which modifier flag reaches `tokenIdForModifierFlag`. The switch names ten; the
  one arriving is outside them, so the first question is whether an inline substitution is
  carrying a flag from another node, and the second is why the modifier check runs on a
  substituted assignment at all.
- Complete when: the reproduction compiles in both configurations, the commented case in
  `bin/unittests/safety/corpus/cwe401_memory_leak.swg` and the `#[Swag.NoInline]` in that
  folder's `helpers.swg` are removed, and a case is pinned in `bin/unittests/sema`.
- Related: compiler.core.028 is the other release-only defect the same corpus surfaced, in the
  same inlining neighbourhood.
