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

### F-163 — Destructuring assignment into fields leaks the old values and double-drops the temporary

- Area: compiler (Sema/CodeGen of `{a.x, a.y} = call()` — the assignment form, not the declaration)
- Found while: adding a context menu to RichEdit; the `ClipboardCut` path corrupted the heap and
  the debug allocator reported "memory block is freed twice" when the undo record was released.
- Observation: `{holder.first, holder.second} = makeTuple(...)` with droppable field types gets
  the ownership wrong twice. The old target values are never dropped (leak), and the temporary's
  fields are dropped after their bits were bit-copied into the targets, so target and temporary
  own the same payload. A later drop of the receiver frees that payload a second time. With
  `Core.Array` fields the debug allocator panics; the declaration form (`var {a, b} = call()`,
  covered by `bin/unittests/jit/operators/temporary_drop.swg`) transfers correctly.
- Evidence: standalone reproducer, fails in JIT with the release 0.1.153 compiler (`swc test -d`),
  no Core needed. Drop-count assertions alone cannot see it — the wrong values die with the right
  count — the per-value trace is what discriminates:

  ```swag
  var DropTrace: s64
  struct Owner { value: s32, pad: [3] s64 }
  impl Owner { mtd opDrop() { DropTrace = DropTrace * 10 + cast(s64) .value } }
  struct Holder { first: Owner, second: Owner }
  #[Swag.NoInline]
  func makeTuple(first, second: s32)->{ x: Owner, y: Owner }
  {
      var result: retval
      result.x.value = first
      result.y.value = second
      return result
  }
  #test
  {
      var holder: Holder
      holder.first.value  = 8
      holder.second.value = 9
      {holder.first, holder.second} = makeTuple(4, 5)
      @assert(DropTrace == 89 or DropTrace == 98)     // FAILS: the temporary's 4/5 die instead
  }
  ```

  In-tree witness: `bin/std/modules/gui/src/controls/richedit/selection.swg`
  `deleteSelectionPrivate` used `{undo.runes, undo.styles} = .textRangeData(...)`; running
  `richedit.test.swg` in `-bc debug` panicked "memory block is freed twice" in `clearUndo`. It now
  uses `var range = ...; undo.runes = #move range.text` as the correct spelling, which also keeps
  working after the fix.
- Next step: route the assignment form through the same per-field transfer the declaration form
  uses (drop the old target, move the field out of the temporary, neutralize the temporary's
  field), then land the reproducer as `bin/unittests/jit/operators/temporary_drop.swg`'s missing
  case plus its `native` twin, asserting the drop *trace*, not the drop count.

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
- Next step: reduce the direct-call form into a standalone sema input, trace both calls to
  `setSemaPayload` for its slice node, and add that input to `bin/unittests/sema` before changing
  payload ownership; then keep the macro-generated `markdownHeadingAnchor` form as downstream
  coverage.

### F-168 — A pointer converts only through 'u64', so every other integer needs two casts

- Area: compiler
- Found while: auditing the cast surface after the `Core.Math.Simd` pass.
- Observation: `u64` is the only numeric type that converts to and from a pointer in one explicit
  cast. `cast(s64) ptr`, `cast(u32) ptr`, `cast([*] u8) someU32`, `cast(*void) someS32`, and
  `cast(*void) SomeEnum.Case` are all rejected, and `cast #bit` is refused in both directions, so
  the only spelling is a two-step through `u64`.
- Evidence: a 24-case standalone probe confirms the split — legal: `cast(u64) ptr`,
  `cast([*] u8) u64Value`, `cast(*u8) u64Value`, pointer-to-pointer, `*T` ↔ `[*] T`,
  `cast(u64) SomeEnum.Case`; rejected: the five forms above. In-tree witnesses of the resulting
  double cast: `bin/apps/modules/sSnapForge/src/propwnd.swg:35`
  (`cast(*void) cast(u64) value`) and `bin/runtime/os_windows.swg:284-285`
  (`cast(const *void) cast(u64) @countof(message)`).
- Next step: decide the rule before touching `Cast::castAllowed`. An explicit cast to a pointer is
  already an unsafe act, and requiring two of them adds noise rather than proof, so the candidate
  is: one explicit cast from any integer-like of at most pointer size (enums included,
  zero-extended), and from a pointer to any integer of at least pointer size — keeping the refusal
  for a narrowing `cast(u32) ptr`, with a help line naming the widening. Then migrate the in-tree
  double casts and add the matrix to `bin/unittests/sema/types`.

### F-169 — No indexed reinterpretation: 'p[as T][i]' cannot name the i-th T at a pointer

- Area: compiler
- Found while: auditing the `[as T]` place syntax against the h264 vector code.
- Observation: `expr[as T]` opens one place of `T` at a pointer, so a following `[i]` indexes the
  scalar `T` and fails with "type 'u32' does not support indexing". Reaching element `i` of a
  reinterpreted buffer therefore needs either `(p + i * #sizeof(T))[as T]` or
  `(cast([*] T) p)[i]`; both work, neither is the postfix form the rest of the chain uses.
- Evidence: `p[as [4] u32][1]` is accepted (an array place indexes fine) while `p[as u32][2]` is
  rejected, so the gap is only the single-element form. `p[2 as u32]` cannot carry the meaning: it
  already parses as the `as` cast expression applied to the index.
- Next step: none proposed yet — this is a discoverability gap with two working idioms, not a
  defect, and the natural syntax slot is taken. Record whether the `(cast([*] T) p)[i]` idiom
  should become the documented spelling in
  `bin/reference/modules/language/src/004_007_pointers.swg` before considering new syntax.

### F-170 — An intrinsic cannot start a statement, and the diagnostic does not say so

- Area: compiler
- Found while: writing `@dataof(target)[as Simd.U8x16] = value` in a `bin/std` test.
- Observation: an assignment whose target begins with an intrinsic is rejected with "intrinsic
  '@dataof' does not belong here". The restriction is the statement position alone, not the
  postfix chain: the same expression is accepted everywhere else.
- Evidence: `@dataof(buf)[as u32] = 1` and `@dataof(buf)[0] = 1` are both rejected as statements,
  while `(@dataof(buf))[as u32] = 1` and `let p = @dataof(buf); p[as u32] = 1` compile, and
  `use(@dataof(buf)[as u32])` compiles as a sub-expression. So the parser refuses an intrinsic as
  the first token of a statement and the message names the intrinsic instead of the position.
- Next step: either accept an intrinsic-rooted assignment target, or keep the restriction and give
  the diagnostic its missing help line — "an intrinsic cannot start a statement; parenthesize it,
  or bind it to a local first" — then cover the accepted and rejected spellings in
  `bin/unittests/errors/parser`.

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
- Next step: reduce a standalone JIT test returning a conditional `U8x16`, compare its true and
  false branch register/stack locations with the scalar conditional lowering, then add the native
  twin before fixing conditional-result materialization.
