# Findings — Compiler

Frontend, semantic analysis, and code generation defects: something observed in `swc` itself, with
a reproduction and a next investigation step. Optimization passes and generated-code performance
are [findings.optimization.md](findings.optimization.md); the borrow, lifetime and sanity analyses
are [findings.safety.md](findings.safety.md); the `doc` and `format` commands have their own files,
[findings.doc.md](findings.doc.md) and [findings.format.md](findings.format.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

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

### F-164 — DevMode assigns a semantic payload to the same slice node twice

- Area: compiler
- Found while: building the shared `bin/apps` workspace after integrating sFileScope's viewers.
- Observation: a freshly built `swc_devmode.exe` deterministically asserts while semantically
  checking the unchanged `tools/src/backlog.swg`; the Release compiler checks the same tool.
- Evidence: two consecutive `bin/swc_devmode.exe tools/apps.swgs dm build sFileScope` runs assert
  in `NodePayload::setSemaPayload` at `NodePayload.cpp:806` because
  `shard->semaPayloads` already contains the node. Both name the `start` reference inside
  `line[start until @countof(line)]` at `tools/src/backlog.swg:172`, under the `#code` body passed
  to `Utf8.visitRunes`. The defect has not yet been reduced because the tool combines a slice of a
  `string`, a captured mutable index, and macro-generated traversal; removing one without first
  identifying the second semantic visit would risk recording the wrong mechanism. A second,
  macro-free witness was found while optimizing `Latin1.trim`: passing
  `bytes[first until @countof(bytes)]` directly to `lastNonSpace` triggers the same assertion on
  `first`, while binding that slice to a local before the call compiles. This removes macro
  expansion from the minimum mechanism and leaves a slice expression used as a call argument.
  It no longer reproduces at 0.1.167: the macro-free witness — a standalone `#test` passing
  `bytes[first until @countof(bytes)]` straight into a `const [..] u8` parameter — compiles and
  runs, every `tools/*.swgs` invocation checks `backlog.swg` without asserting, and two
  consecutive `bin/swc_devmode.exe tools/apps.swgs dm build sFileScope` runs are green. Nothing
  in that release targeted payload ownership, so the double visit is more likely scheduling
  dependent than deterministic, and the "deterministic" wording above describes one machine
  state rather than the defect.
- Next step: re-evaluate on the next occurrence. Persist the failing module when one happens and
  capture both `setSemaPayload` calls for the slice node before changing payload ownership; a
  reduction that does not fail on demand cannot be turned into a `bin/unittests/sema` case.

### F-171 — A SIMD-valued conditional expression crashes JIT execution

- Area: compiler
- Found while: sharing the packed Latin-1 whitespace mask between forward and backward scans.
- Observation: a helper that selects between two `#simd [16] u8` expressions with `condition ?
  packedA : packedB` compiles and runs in native Release code, but a Core `#test` calling it through
  the JIT reads address zero inside the helper. Selecting and combining the scalar `@vecmask`
  results instead preserves the same semantics and passes.
- Evidence: `Latin1.spaceMaskAt` crashed deterministically at the SIMD-valued conditional while
  running `latin1.test.swg` in `-bc release`; the reported JIT offset mapped exactly to that line.
  Replacing it with `var mask = @vecmask(ascii); if includeLatin1 { mask |= ... }` made the same
  seven focused tests pass without changing the native benchmark result.
  It no longer reproduces at 0.1.167. Restoring the conditional spelling in `Latin1.spaceMaskAt`
  and running `swc tools/std.swgs dm test core --test-file latin1.test.swg -bc release` passes,
  with the pre-fix Release compiler as well. Standalone probes returning a conditional
  `#simd [16] u8` — from parameters, and from `@vecsplat` comparison chains — pass in `debug`,
  `fast-debug` and `release`, under the JIT and from the forged binary.
- Next step: re-evaluate on the next occurrence. The conditional alone is not the trigger, so a
  recurrence has to be captured with the exact module and configuration that produced it before
  the lowering is compared against the scalar one.

