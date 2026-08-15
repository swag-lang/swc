# Findings — Compiler

Frontend, semantic analysis, and code generation defects: something observed in `swc` itself, with
a reproduction and a next investigation step. Optimization passes and generated-code performance
are [findings.optimization.md](findings.optimization.md); the borrow, lifetime and sanity analyses
are [findings.safety.md](findings.safety.md); the `doc` and `format` commands have their own files,
[findings.doc.md](findings.doc.md) and [findings.format.md](findings.format.md).

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

## Published symbols, imports, and name resolution

### F-025 — An ambiguous `.member` still reads "not published yet" as "not there"

- Area: compiler
- Found while: fixing the same race for the unambiguous case, which was making `sSnapForge` fail to
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
  "complete" type can still miss members. Every sSnapForge failure was that shape:
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
- Found while: tracking an intermittent JIT '#test' failure in `swc test -w bin/apps -m sSnapForge
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
- Evidence: pre-fix, iteration 1 of every `swc test -w bin/apps -m sSnapForge --rebuild` loop on the
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
  strongest reproduction so far of the intermittent sVaultDrive JIT failures the pass set out to track.
- Observation: in `swc_devmode test -w bin/apps -bc debug --rebuild`, six sVaultDrive `#test` functions
  in `mainwindow.test.swg` (109, 133, 163, 363, 384, 494) die on the same hardware exception:
  execution lands at `rip=0x0000000080019060` (memory state FREE, "jit offset: unresolved"), which
  is a jump through a function-pointer slot holding a value no live code owns. The failure hits
  roughly two runs out of three at the first iteration, always with that same rip, and an A/B
  build bisected it as independent of the concurrent matcher fix added the same day. sSnapForge's
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

## Aggregate construction

### F-139 — A moved subexpression in a materialized value asserts in CodeGen

- Area: compiler
- Found while: building the dedicated sFileScope Markdown plugin
- Observation: embedding `#move` in an aggregate call argument or one branch of a conditional expression passes semantic analysis, then the DevMode compiler asserts while preparing the materialized value
- Evidence: `blocks.add(MarkdownBlock{kind, #move text})` and `var value = condition ? String.from("rule") : #move block.text` both assert at `CodeGenCallHelpers.Call.cpp:1062` because `argConstView.cstRef().isValid()` does not hold; assigning the moved field through an ordinary statement before the call compiles in both cases
- Next step: reduce both patterns into `bin/unittests/native`, then trace why their moved subexpressions reach `appendPreparedFixedArg` without a valid constant reference and make the original expressions compile without changing ownership

## Failure propagation across module boundaries

### F-140 — A failure raised in a standard-library module is lost inside a plugin loaded at run time

- Area: compiler
- Found while: the sFileScope sound plugin played nothing and lost its waveform on every file but
  the first. The proximate cause was an audio-engine failure that never reached the plugin's
  `catch`; the class it belongs to is this one.
- Observation: when the call chain is entered from a shared library the host opened with
  `Core.NativeLibrary.load` rather than through its import table, a `fail` raised inside a
  standard-library module does not reach a `catch` in the plugin, and the caller reads the capture
  as null. Worse, the raised state is not cleared either: every later fallible call inside that
  standard-library module returns immediately, so a function that cannot fail from where the caller
  stands hands back a zero-initialized `retval` and reports no error at all.
- Evidence: `plugin.sound.dll` calls `Audio.createEngine`, which fails inside `audio.dll` while
  initializing COM. `catch createEngine(kind) as createError` in the plugin reports
  `createError == null` while `isEngineCreated()` is false and `activeDriverKind()` is already
  `XAudio2` — the driver stopped half way through `Driver.create`. From that point every
  `SoundFile.load` in the same process returns a `SoundFile` with a zero sample rate, zero channels
  and no payload, again with a null capture, which is what emptied the waveform. Two smaller probes
  from inside the same plugin: `catch File.info("C:/definitely-missing-file.bin") as err` never
  reaches its next statement and the process exits, and `SoundFile.load` on a missing path walks
  past a failed `File.openRead` into `Wav.load`, where `FileStream.position` panics on a stream that
  was never opened. The same three shapes are correct in a script, in an executable module, and in
  `bin/unittests/workspace`, where `catch ctxSharedRaiseSystemError() as raised` already passes —
  those all reach the DLL through the import table.
- Next step: reproduce outside the application by adding a third module to
  `bin/unittests/workspace` that the consumer opens with `NativeLibrary.load` instead of importing,
  and have it call a fallible `core` function that fails. Then compare what the runtime error state
  is stored in on each side of that boundary against the import-table case — the suspect is the
  module-local copy a run-time-loaded module gets instead of the process-wide one.

### F-141 — A `defer #fail` added to `Driver.create` makes unrelated audio tests fail

- Area: compiler
- Found while: making a failed audio-engine creation leave a clean driver behind
- Observation: adding `defer #fail .destroyNative()` immediately before `.createNative(kind)` in
  `Driver.create` ([driver.swg](../bin/std/modules/audio/src/driver/driver.swg)) turns 7 of the 26
  audio tests red, all of them reporting `audio engine is already created` from an
  `expect createNoSoundEngine()` in a *later* test. Nothing in those tests fails, so the deferred
  call should never run; the engine nevertheless survives a `destroyEngine()` it should not.
- Evidence: `swc tools/std.swgs test -m audio -bc debug` passes 26/26 without that one line and
  fails 7 with it, with the whole rest of the change in place. A reduced case — a `fail` method
  holding `defer #fail cleanup()` that returns normally, then one that fails — runs the cleanup 0
  times and then 1 time, which is correct, so the reduction does not reproduce. The shipped fix
  avoids the defer by naming the backend only after it exists, in `DriverNative.createNative`.
- Next step: put the line back and bisect what makes this frame different from the reduced one:
  `Driver.create` is a method on a global, its `destroy` ends with `@drop(me, 1)` / `@init(me, 1)`,
  and it starts a thread between the defer and the end of the function. Dump the emitted unwind
  records for both shapes and compare which one the `@init` at the end of `destroy` runs against.
