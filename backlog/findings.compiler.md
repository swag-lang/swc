# Findings — Compiler

Frontend, semantic analysis, and code generation defects: something observed in `swc` itself, with
a reproduction and a next investigation step. Optimization passes and generated-code performance
are [findings.optimization.md](findings.optimization.md); the borrow, lifetime and sanity analyses
are [findings.safety.md](findings.safety.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

## Global initialization and storage

### F-019 — A thread-local global cannot hold a droppable type

- Area: compiler
- Found while: implementing `#[Swag.Tls]`, which until then was parsed and then ignored
- Observation: a thread-local global now has one copy per thread, created from the declared value on
  first access and released when the thread ends. What is released is the storage, not the value:
  nothing calls `opDrop` on it. Shutdown cannot stand in for that either, because it runs on one
  thread and dropping only that thread's copy would pick an arbitrary one, so thread-local globals
  are excluded from the shutdown drop list on purpose. A `#[Swag.Tls] var s: String` therefore leaks
  every thread's buffer, silently.
- Evidence: `collectGvtdEntriesRec` skips `symVar->isThreadLocal()`
  ([CodeGen.Function.cpp](../src/Compiler/CodeGen/Ast/CodeGen.Function.cpp)), and the fiber-local
  destructor `__releaseTlsVar` ([os_windows.swg](../bin/runtime/os_windows.swg)) frees the block
  without knowing its type. The three users in `bin/` — `Random.shared()`, and the generator behind
  `Guid64`/`Guid128` — are plain value types, so nothing leaks today.
- Next step: decide whether to reject the combination or support it. Rejecting is one diagnostic on
  a global that carries `Swag.Tls` and a type with a lifecycle, and it is honest. Supporting it
  means the per-thread block has to carry a drop hook the destructor can call, which is the same
  type-erased drop the `@gvtd` table already builds — reuse that shape rather than inventing a
  second one.

### F-021 — A `#run` block cannot initialize a zero-segment global

- Area: compiler
- Found while: the language reference's `Swag.Late` page, whose `#run` set a global and whose
  `@isset` then failed in the native build only. The page now sets the global from a setup
  function, which is what the attribute is for.
- Observation: a global written by a `#run` block keeps its value into the emitted binary only
  when the global was declared with an initializer. Without one it lives in the zero segment,
  which the native backend emits as `.bss`, so every compile-time write is dropped. The JIT run of
  the same `#test` sees the values, so the two halves of the language disagree about what `#run`
  can establish.
- Evidence: a module with `var zero: s32` and `var init: s32 = 1`, both assigned in one `#run`,
  prints `zero 7 / init 9` under the JIT and `zero 0 / init 9` from the produced executable. Same
  split for a struct global and for a `#[Swag.Late]` pointer. `dataSectionName` maps
  `DataSegmentKind::GlobalZero` to `.bss`
  ([DebugRecordCollector.cpp:50](../src/Backend/Debug/DebugRecordCollector.cpp#L50)).
- Next step: decide the rule before touching the backend, because the scalar half is the easy
  half. Promoting a written zero-segment global to initialized data is mechanical; a *pointer*
  written at `#run` time holds a compiler host address, and emitting those bytes verbatim would
  ship a wild pointer — worse than the current zero. Persisting them needs the store to record a
  `DataSegmentRelocation` at the written offset, which nothing does today because the write comes
  from JIT-executed code rather than from a sema-built initializer. Either instrument those stores
  or reject a `#run` write to a global that no initializer placed in the initialized segment.

## Published symbols, imports, and name resolution

### F-025 — An ambiguous `.member` still reads "not published yet" as "not there"

- Area: compiler
- Found while: fixing the same race for the unambiguous case, which was making `sCapture` fail to
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
  "complete" type can still miss members. Every sCapture failure was that shape:
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

### F-111 — Concurrent type generation can corrupt declared-method traversal

- Area: compiler
- Found while: rerunning `tools/tests.swgs dm --all-cfg` for F-106 after an unrelated intermittent
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
  imported native modules keeping `@pinfos.args` slices into a destroyed compiler instance's
  storage (`ensureProcessInfosRunArgs`, now interning into process-lifetime storage); and the call
  matcher reading the signature type of a selected candidate before that type was published
  (`Match::resolveFunctionCandidates`, which now parks until the winner is typed — caught live as
  a `typeRef.isValid()` assertion under `finalizeAutoEnumArgs` while building the generated `ogl`
  wrappers, one run in ~20; in Release that read returned an out-of-bounds `TypeInfo`). A mimalloc
  report now appends the reporting thread's stack (`MemoryProfile.cpp`), so a recurrence names its
  culprit directly; if one does recur, persist the failing module and stress parallel type
  generation as originally planned.

## JIT-hosted runs

### F-124 — A dangling reference into a destroyed compiler instance has no deterministic detector

- Area: compiler
- Found while: tracking an intermittent JIT '#test' failure in `swc test -w bin/apps -m sCapture
  --rebuild`, which turned out to be imported native modules (core.dll and siblings, loaded once
  per process) keeping `@pinfos.args` slices into the run-argument storage of a dependency-build
  compiler instance that had already been destroyed. That defect is fixed by interning the handed
  storage for the lifetime of the process, but the *class* — long-lived imported modules holding a
  pointer into per-instance state — was only caught because a heap block happened to be reused with
  bytes that failed a `Debug.assert` inside `Path.extension`, in the Release compiler binary only,
  roughly once per run.
- Observation: nothing makes such a stale reference fail deterministically, so a suite regression
  cannot be written that reliably turns red without the fix: the dead storage usually still holds
  its old bytes, and every read through it then looks healthy. The DevMode binary never tripped at
  all because its allocator reused the freed block differently.
- Evidence: pre-fix, iteration 1 of every `swc test -w bin/apps -m sCapture --rebuild` loop on the
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

### F-125 — A JIT '#test' can call through a function slot that was never patched

- Area: compiler
- Found while: the 2026-08-12 sanification pass, looping the apps workspace in debug. This is the
  strongest reproduction so far of the intermittent sCrypt JIT failures the pass set out to track.
- Observation: in `swc_devmode test -w bin/apps -bc debug --rebuild`, six sCrypt `#test` functions
  in `mainwindow.test.swg` (109, 133, 163, 363, 384, 494) die on the same hardware exception:
  execution lands at `rip=0x0000000080019060` (memory state FREE, "jit offset: unresolved"), which
  is a jump through a function-pointer slot holding a value no live code owns. The failure hits
  roughly two runs out of three at the first iteration, always with that same rip, and an A/B
  build bisected it as independent of the concurrent matcher fix added the same day. sCapture's
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

### F-128 — A fallible rune return can fail during backend lowering

- Area: compiler
- Found while: implementing the JSON Unicode escape decoder for T-029
- Observation: a function returning `rune fail` reaches an internal compiler error when a branch executes `fail`; returning `u32 fail` and casting the successful value at the caller compiles.
- Evidence: `Json.readUnicodeEscape()->rune fail` in `bin/std/modules/core/src/serialization/read/json.swg` failed with `cannot materialize the synthesized zero fallible result payload` at its first `fail` expression in DevMode; changing only its result type to `u32` made the same body compile.
- Next step: reduce this to a native compiler-suite case with a standalone fallible function returning `rune`, then repair synthesized result initialization in backend lowering.

### F-129 — A documentation run spends nine tenths of its time re-running sema

- Area: compiler
- Found while: investigating why some documentation pages take several seconds to generate
- Observation: `swc doc` runs full workspace sema on every invocation, with or without
  `--rebuild`, and the per-module stage line the user reads as "doc time" is dominated by it.
  The page generation itself is small: with the reachable-node index in place, the doc side of
  the whole `std` workspace is under 1 s of a ~8 s wall run (Stats build, 22 workers), and no
  single module keeps a doc stage above ~0.3 s. Inside the sema time, compile-time execution
  JIT-emits 7 803 functions: session timers report 77 s CPU of semantic analysis plus 24.5 s CPU
  codegen and 21.7 s CPU micro lowering, against 2.7 s parser and 0.7 s lexer. Each module also
  re-analyzes its dependencies' exported public API (`ogl` has 29 own sources but sema
  processes 133 files).
- Evidence: `swc doc --workspace bin/std --doc-output-dir <tmp> --rebuild --stats` with a Stats
  configuration build; timing probes around `Command::doc`'s sema call and inside
  `DocApi::generate` ([Command.Doc.cpp](../src/Main/Command/Command.Doc.cpp),
  [DocApi.cpp](../src/Doc/DocApi.cpp)). Omitting `--rebuild` changes nothing: a doc run persists
  no sema artifact it could reuse.
- Next step: measure which compile-time callers demand the 7 803 JIT emissions during a doc run,
  and whether any lowering is demanded by paths documentation never needs; that number bounds
  what any doc-mode fast path could save before the larger incrementality work.

### F-130 — Export-root resolution walks the declaration tree once per symbol

- Area: compiler
- Found while: removing the per-symbol whole-AST scans this entry originally described
- Observation: the memoized `Ast::reachableNodeRef` index removed the dominant scan (`ogl`
  `collectDocItems` 803 ms to ~190 ms, its doc stage 1 159 ms to ~315 ms, and the same index
  serves `collectPublicEntries` inside sema), but the collector still resolves each item's
  export root through `findExportDeclRoot`, whose `collectModuleApiNodePath` runs a
  root-to-target DFS over the declaration tree for every symbol. A generated binding file with
  thousands of top-level declarations pays declarations-times-tree-size again there; it is the
  main suspected share of `ogl`'s remaining ~190 ms collect.
- Evidence: [ModuleApi.Decl.cpp:32](../src/Compiler/ModuleApi/ModuleApi.Decl.cpp#L32)
  (`collectModuleApiNodePath`), reached per candidate from
  [DocApi.Collect.cpp:864](../src/Doc/DocApi.Collect.cpp#L864); measured with the F-129 probes
  after the reachable-index fix.
- Next step: record each node's parent in the same single traversal that builds
  `Ast::ReachableNodeIndex` and derive the root-to-target path by walking parents upward,
  keeping the additional-node and function-body constraints as per-ancestor checks; re-measure
  `ogl` collect.
- Related: F-129

### F-132 — A constant source through a non-ConstExpr implicit opSet in an aggregate literal is lost

- Area: compiler
- Found while: the noref campaign's core native run, reducing the angle literal failure.
- Observation: an aggregate-literal field converted through an `#[Implicit]` `opSet` that is NOT
  `#[ConstExpr]` reads the wrong value when the source is a constant. The compile-time fold
  rightly declines, and the runtime Set-cast lowering then reads the source from uninitialized
  storage instead of materializing the constant. A runtime source through the same shape works,
  and a `#[ConstExpr]` `opSet` folds correctly.
- Evidence: `struct Angle { radians: f32 }` with `#[Swag.Implicit, Swag.Inline] mtd opSet(v: f32)`
  and `let holder = Holder{angle: 1.5}` asserts `radians == 1.5` false in fast-debug, JIT and
  native alike; the unoptimized micro shows the inlined-set body reading `[frame+0]`, a slot
  nothing wrote, while the 1.5 constant is loaded into a float register and dropped. The master
  reference compiler (build of 2026-08-13) fails the identical probe, so this predates the noref
  campaign and is not a pointer-receiver regression.
- Next step: in `emitStructSetCast` (CodeGen.Cast.cpp), trace the source argument's payload when
  it is a constant: `appendResolvedCallArguments` hands `codeGenCallExprCommon` the literal node,
  and its constant payload appears to be consumed by the aggregate-literal storage machinery
  before the set call reads it. Reduce with the probe above, fix on master, and let the campaign
  branch inherit the fix.
