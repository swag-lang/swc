# Swag Findings

This file records compiler, standard-library, tooling, and language-design issues discovered while
working on otherwise unrelated tasks. An entry is a lead worth preserving, not a commitment to
implement it.

It is not a roadmap. Intent — what a subsystem should become and in which order — lives in the
matching `TODO.md`: [TODO.md](TODO.md) for the compiler, its `doc` and `format` commands, and the
language; `bin/std/modules/<module>/TODO.md` and `bin/apps/modules/<app>/TODO.md` for everything
under `bin`. This file holds evidence; those files hold intent. An entry that graduates into a
plan moves there and disappears from here.

Fix a finding immediately when it is sufficiently understood, relevant to the current task, and
safe to validate. Add it here when it needs separate investigation, broader design work, or stronger
evidence. Search before adding an entry, enrich existing entries instead of duplicating them, and
remove or update entries when later work resolves or disproves them.

Every entry carries a permanent `F-NNN` identifier, which is how a finding is named everywhere else.
Take the next one from the counter below and advance it; never renumber an entry and never reuse an
identifier, so a reference made today still resolves after the entry is gone. Entries are sorted by
identifier, ascending: a new one goes at the end, a deleted one leaves a gap, and position carries
no priority.

Next identifier: F-031

## Open Investigations

<!--
Use this compact format. Keep observations factual and make the next step actionable.

### F-000 — Short descriptive title

- Area: compiler | bin/std | language | tooling | documentation
- Found while: task, test, or file that exposed the issue
- Observation: awkward behavior, suspected defect, or optimization opportunity
- Evidence: reproduction, relevant paths, measurements, or diagnostics
- Next step: smallest useful investigation
- Related: issue, pull request, or TODO entry if applicable
-->

### F-002 — Golden snapshots cannot be recorded under the test sandbox

- Area: compiler | bin/std
- Found while: regenerating the gui widget goldens after the theme-atlas format change
- Observation: `swc test` always arms the sandbox, and the sandbox refuses every write outside
  its root. The golden store's documented flows — create a missing golden on first run, write
  `<name>.actual.txt`/`.png` next to a mismatching golden for `tools/goldens.bat` —
  both write into the module source tree, so they silently stopped working when the sandbox
  landed: a failing golden reports `[golden] cannot write ...` and leaves nothing to accept.
- Evidence: the 13 gui golden mismatches printed `cannot write` for every actual; recording them
  required launching the tests with an explicit repo-rooted sandbox
  (`--run-arg "swag.sandbox=<repo root>"`), which redirects the special directories into the
  repository and allows the corpus writes.
- Next step: decide where golden actuals should land under a sandbox. Candidates: the launcher
  grants the corpus root explicitly (a `swag.sandbox.corpus=<dir>` run argument the golden store
  consults), or the golden store mirrors actuals under the sandbox root at a deterministic path
  and `goldens.bat` harvests them. Writing straight to the source tree from a
  sandboxed test contradicts the sandbox guarantee, so the escape must stay launcher-owned.

### F-004 — Droppable call-result temporaries are never dropped

- Area: compiler
- Found while: fixing the `String`-rvalue `+=` heap corruption (root cause was the return
  path: `return local` bit-copied and still dropped the local — a use-after-free/double-free
  for any `opDrop`-without-`opPostCopy` struct, and for every inlined `String` return; both
  now move out, see `CodeGenMoveElision::canMoveOutAtReturn`)
- Observation: a call result with a `Drop` lifecycle that lands in a compiler temporary is
  never dropped. `discard makeThing()`, `takeView(makeThing())` through an implicit `opCast`,
  and `acc += Format.toString(...)` all leak the temporary's buffer on every execution;
  `Format.toString` itself leaks its inner `ConcatBuffer.toString` temporary per call.
- Evidence: micro dump of `g_Str += Format.toString(...)` shows no drop call anywhere after
  `String.opAssign`; a Tracer struct counting drops confirms zero drops for the `discard` and
  argument-cast shapes while `var x = makeThing()` drops exactly once. An implementation of the
  statement-end flush below was written, measured, and reverted: it took the `core` suite from
  green to 36 crashing tests, then to 5 failing ones once the ownership transfers were found, and
  the last 5 are the design question, not a defect in the mechanism.
- Next step: settle the lifetime question FIRST, because the mechanism is straightforward and the
  rule is not. Dropping at the end of the consuming statement is what a temporary means everywhere
  else, but `bin/std` currently keeps views into temporaries alive past that point:
  `splitArgumentsEx` stores `Latin1.trim(split[0])` — a `string` into the buffer of an `Array`
  temporary — into the array it returns
  ([commandline.swg:93-100](bin/std/modules/core/src/system/commandline.swg#L93-L100)), and
  `textreader`/`reflection`/`log` do the same shape. Either those sites are wrong and get fixed, or
  a temporary lives to the end of its block, which needs its slot zeroed on entry so a path that
  never produced a value still drops nothing.
- Next step (mechanism, once the rule is settled): register `{flushRootRef, storageSym}` when a
  call's result lands in a compiler temporary and flush in the generic `CodeGen::postNode`. Four
  things the reverted attempt had to get right, each of which cost a debugging session:
  (1) read the storage with `CodeGen::runtimeStorageSymbol`, the way the sret argument reads it —
  the node payload's `runtimeStorageSym` is overwritten by a surrounding cast, so it names the
  cast's slot and the drop lands on the wrong stack offset; (2) resolve the address UNCACHED
  (`resolveLocalStackPayload(sym, false)`), since the call can sit in another block; (3) clear the
  pending list per function in `CodeGen::start`, or an unflushed entry drops a slot belonging to
  the next function's frame; (4) cancel the pending drop wherever a consumer takes over the bits
  instead of copying them — a plain `=` store with no `opPostCopy` and no source reset
  (`emitAssignLifecycle`), and a return that moves out (`returnSourceIsOwnedTemporary`, whose
  comment already states that nothing drops the abandoned temporary). Registration must also stand
  down inside a lazily-evaluated region (ternary, `and`/`or`, `orelse`, `?.`, `try`/`catch`), where
  a skipped path leaves the slot unwritten.
- Next step (flush root): the nearest ancestor that is a block child, EXCEPT that a statement
  keeping the value it evaluates — a `for` range, a `switch` value, a `with` subject — must flush
  after the whole statement, while a loop condition flushes per evaluation. `for` needs more than
  that: it lowers through the `opVisit` macro, so the range expression is emitted inside an
  expansion and the ancestor walk lands inside the macro body, dropping the container before the
  first iteration (`for one in probeList()` then counts 0 elements). A flush point taken from the
  visit stack cannot see through an expansion; the root has to come from the pre-expansion AST.

### F-006 — Data-driven UI resource for `std/gui`

- Area: bin/std
- Found while: simplifying the sCrypt vault cards after `FormCtrl` was judged too heavy
- Observation: a UI described by a data string is only worth it when the caller never needs the
  controls back. The removed `FormCtrl` proved the opposite case: every consumer built an
  `Array'FormFieldDefinition`, then immediately recovered typed pointers by string identifier
  (`notnull (notnull form.findField("create.size")).accessoryChoice`), so the data layer added a
  stringly-typed boundary without removing a single control pointer. A full markup would extend
  that boundary from four fields to the whole window unless the resource is resolved at compile
  time into typed members.
- Evidence: commits 3b382e68a and 8009467a0 removed `FormCtrl`, `FormFieldDefinition`,
  `FormFieldKind`, `FormChoice`, and `FormField` (177 lines) and replaced three consumers with
  `FormLayoutCtrl` builders that return the concrete control. sCrypt's two cards lost their two
  field-description functions and every `findField` lookup. `Core.File.TweakFile` already parses a
  text format onto struct fields through reflection, and `ThemeStyle.addStyleSheetColors` shows the
  existing string-resource precedent in `std/gui`.
- Next step: prototype the compile-time half first, since it is what decides the design. Parse a
  small UI resource in a `#run` block with `TweakFile` as the model, and check whether the parsed
  tree can emit typed member declarations for a window struct through `#code`/generated source. If
  typed accessors cannot be generated at compile time, a UI resource reintroduces exactly the
  lookup boundary the builders just removed, and a resource editor would ship that cost to every
  window. Only then evaluate the editor.

### F-015 — Calling through a reference to a function pointer never reaches a backend

- Area: compiler
- Found while: closing the use-site nullability hole on a call through a reference (`&#null
  func()->T` now needs a proof like every other nullable value)
- Observation: a call whose callee is a reference to a function value compiles, and then no backend
  can emit the function that contains it. The JIT dies on a hardware exception and the native
  backend refuses the relocation, both while emitting the CALLER of that function, which reads like
  a linker problem rather than a lowering gap. Sema is happy; only codegen is not.
- Evidence: a struct holding `fn: func()->s32` with `mtd const atFn()->const &(func()->s32)`, then
  `let fn = h.atFn(); return fn()`. JIT: `native backend cannot resolve a local function relocation
  for 'probeCallPlain'` / `local target function has no prepared JIT address`; native
  (`--no-test-jit`): the same message with an empty name. The nullable spelling of the same shape is
  now rejected in sema, so only the plain one reaches codegen
  ([sema_err_nullable_use_site.swg](bin/unittests/errors/sema/sema_err_nullable_use_site.swg) pins
  the rejection). Reproduced identically on the pre-change compiler, so it predates that work.
- Next step: find what the callee payload holds for a reference-typed call target.
  `materializeCallTargetReg` receives the payload of the callee expression; for a reference it is
  the address of the slot holding the code pointer, which needs one load before the call, and the
  emitted relocation suggests it is instead treated as a direct local target. Compare against
  `normalizeIndexReferenceOperand`/`CodeGenReferenceHelpers::unwrapAliasRefPayload`, which is how
  the index and `dref` paths resolve the same reference layer.
### F-017 — sCapture keeps a dark editor matte after switching to the light theme

- Area: bin/apps
- Found while: comparing sCapture in both Swag palettes through the gui10 theme inspector
- Observation: the matte around the capture is `EditorOptions.editBackColor`, whose default was a
  fixed `0xFF2E2E2E`. It now defaults to transparent, meaning "follow the theme", and `EditView`
  resolves it to `view_Bk` — but an existing installation has the old opaque value persisted, so
  it keeps a near-black matte under a white interface.
- Evidence: [editview.swg](bin/apps/modules/sCapture/src/editview.swg),
  [options.swg](bin/apps/modules/sCapture/src/options.swg). A fresh profile picks up the theme; a
  profile written before this change does not.
- Next step: decide whether the options loader should migrate the one legacy value to transparent,
  or whether an application is expected to version its settings. The same question applies to any
  future option whose default becomes theme-derived.

### F-018 — A sandbox root is never removed, and the process id does not make it private

- Area: bin/std
- Found while: validating a runtime allocator rewrite, where `tools/scripts.bat smoke` failed
  intermittently; the fatal half of that failure is fixed, this half is not
- Observation: nothing ever removes a sandbox root, and the root is named after the process id,
  which the operating system reuses. A run whose id matches a dead run's therefore adopts that
  run's leftover files instead of starting on an empty private root — the opposite of what the
  sandbox promises. `createDirectoryTree` accepts an existing directory silently, so nothing
  reports it.
- Evidence: `%TEMP%/swag-sandbox` holds 4125 `run-<pid>` directories, 846 of them non-empty. Id
  reuse is not theoretical at that density: one `tools/scripts.bat dm smoke` pass of 21 scripts
  handed pid 29356 to two different script processes. A stale root can change behavior rather
  than just waste space, which is what
  [F-017](#f-017--scapture-keeps-a-dark-editor-matte-after-switching-to-the-light-theme) shows for
  a persisted option.
- Next step: make a default root start empty, and keep the two deletion questions apart. Clearing
  a *default* root at arming time is the safe half — no live process can hold that id, the
  launcher did not name the directory, and an explicit root (the golden-recording flow, which
  points the sandbox at the repository) must never be touched. Removing the root at exit is the
  separate half and needs the `#drop` ordering checked first, since another module's drop hook may
  still write inside it. Neither may become an enumerate-and-delete sweep over `swag-sandbox`.
- Related: the fatal half — the hook arming a second time and being rejected with "the sandbox
  root cannot change once armed" — was `defaultSandboxRoot` reading `getSpecialDirectory(.Temp)`,
  which answers *inside* an armed sandbox, so the second pass computed a root nested under the
  first (`<root>/Temp/swag-sandbox/run-<pid>`). It now reads `realSpecialDirectory(.Temp)`, which
  makes a repeated arming the no-op `enterSandbox` documents.

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
  ([CodeGen.Function.cpp](src/Compiler/CodeGen/Ast/CodeGen.Function.cpp)), and the fiber-local
  destructor `__releaseTlsVar` ([os_windows.swg](bin/runtime/os_windows.swg)) frees the block
  without knowing its type. The three users in `bin/` — `Random.shared()`, and the generator behind
  `Guid64`/`Guid128` — are plain value types, so nothing leaks today.
- Next step: decide whether to reject the combination or support it. Rejecting is one diagnostic on
  a global that carries `Swag.Tls` and a type with a lifecycle, and it is honest. Supporting it
  means the per-thread block has to carry a drop hook the destructor can call, which is the same
  type-erased drop the `@gvtd` table already builds — reuse that shape rather than inventing a
  second one.

### F-020 — Arming the headless modal driver for an absent button fails silently

- Area: std/gui
- Found while: the two `sCapture` dialog tests that did not pass — both armed a button their
  dialog does not offer (`BtnYes` for `AboutDlg`, `BtnOk` for File Details), while each of those
  boxes carries exactly one `Close` button under `BtnCancel`. Fixed in the tests.
- Observation: `clickModalButtonWhenShown(id)` accepts any `WndId`. When no modal surface ever
  exposes that id, the driver spins to `autoMaxFrames`, cancels the dialog, and leaves
  `autoHandled` false — so the test fails on an assertion far from the mistake, and the failure
  reads exactly like "the dialog never opened" even though it opened and was answered.
- Evidence: `tools/apps.bat dm test sCapture` before the fix reported 2 of 126 not passing on
  `@assert(autoHandled)`; the dialogs did open. `runAutoStage` returns false for both a missing
  modal surface and a missing button ([headless.swg:191](bin/std/modules/gui/src/tests/framework/headless.swg#L191)),
  and only the frame ceiling distinguishes them, after the fact.
- Next step: separate the two outcomes in the driver. Remember, per stage, whether any modal
  surface was ever seen while it was armed; on the timeout path report which of the two happened —
  a modal that never appeared, or a modal that appeared without the requested button (naming the
  ids it did offer). A `Debug.assert` on the second case turns a silent 60-frame spin into a
  message that names the mistake.

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
  ([DebugRecordCollector.cpp:50](src/Backend/Debug/DebugRecordCollector.cpp#L50)).
- Next step: decide the rule before touching the backend, because the scalar half is the easy
  half. Promoting a written zero-segment global to initialized data is mechanical; a *pointer*
  written at `#run` time holds a compiler host address, and emitting those bytes verbatim would
  ship a wild pointer — worse than the current zero. Persisting them needs the store to record a
  `DataSegmentRelocation` at the written offset, which nothing does today because the write comes
  from JIT-executed code rather than from a sema-built initializer. Either instrument those stores
  or reject a `#run` write to a global that no initializer placed in the initialized segment.

### F-023 — A per-frame event can be sent but never asked for

- Area: std/gui
- Found while: making the sCapture property panel follow a live language switch
- Observation: `Application.sendFrameEvents` walks `Application.frameEvents`, and nothing in
  the repository ever adds to it. `registerFrameEvent` and `unregisterFrameEvent` are declared
  `internal` and have no caller, so the array is empty for the whole run and the call is a
  no-op every frame. The only `FrameEvent` a window actually receives is the single
  `firstFrame` one `Application.run` sends to each surface view before the loop starts, which
  means `IWnd.onFrameEvent` is a first-frame hook wearing the name of a per-frame one.
- Evidence: `grep -rn registerFrameEvent bin --include=*.swg` returns the two declarations and
  no call. Two consumers already depend on the missing half: `MainWnd.onFrameEvent` in
  sCapture only tests `evt.firstFrame`, so it works by accident, while
  `PropWnd.needRebuild` never drains — `PropWnd.onFrameEvent` is the only place that clears
  it ([propwnd.swg:1025](bin/apps/modules/sCapture/src/propwnd.swg#L1025)) and PropWnd is not
  a surface view, so the deferred rebuild that
  [propwnd.swg:998](bin/apps/modules/sCapture/src/propwnd.swg#L998) asks for after a
  `FormImage.kind` change silently never happens.
- Next step: decide which of the two the interface means. Either publish the registration —
  a `Wnd` flag next to `BeforeChildrenPaint`, or a public `registerFrameEvent` — and send the
  event from `runFrame` to everything registered, which makes `PropWnd.needRebuild` work as
  written; or drop `frameEvents` and `sendFrameEvents` and rename the hook for what it is,
  which then needs a different deferral for a rebuild asked for from inside the grid's own
  change notification (a posted event is the obvious one). Whichever way it goes, the
  `FormImage.kind` rebuild has to end up actually running.


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
  ([Sema.Impl.cpp:157-166](src/Compiler/Sema/Ast/Sema.Impl.cpp#L157-L166)) — so a lookup on a
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

### F-026 — Escape in the property grid commits the edit it is supposed to cancel

- Area: std/gui
- Found while: putting the dialog keyboard model on its feet. `EditBox` now reverts to the text it
  was given when it took the focus if — and only if — it carries
  `EditBoxFlags.ReleaseFocusOnEnterOrEscape`, which is the flag that says the box is an edit of its
  own. The property grid never lets its editors see either key, so its own answer to Escape is the
  one that counts, and that answer is wrong.
- Observation: `Properties.editKeyEvent` maps `Return` and `Escape` to the same
  `commitEdit()` ([properties.keyboard.swg:186](bin/std/modules/gui/src/property/properties.keyboard.swg#L186)),
  which moves the focus back to the grid view; the editor's `sigFocusLost` then writes the typed
  value through. So typing over a value and pressing Escape stores what was typed. Every grid the
  reader has ever used undoes it instead, and the undo stack makes the write a second surprise.
- Evidence: `commitEdit()` is the only exit from edition mode; the two cases share one `case` arm.
  `EditBox.restoreOriginalText` already exists and does exactly what cancelling needs, and
  `EditBox.originalText` is captured on `FocusEvent.Gained`, so the value to put back is on hand.
- Next step: split the arm. `Return` keeps `commitEdit()`; `Escape` restores the editor to the
  value the row held before edition, then returns to navigation without notifying — for an
  `EditBox` that is `restoreOriginalText()`, and a `ComboBox`/`Slider` row needs the equivalent
  captured on the same focus event. Pin it with a headless test that types into a grid row, presses
  Escape, and asserts both the stored value and the empty undo stack.

### F-028 — mem2reg can attribute accesses to a stale offset after address arithmetic

- Area: compiler/backend
- Found while: tracing why `chacha20Block` never promoted its inlined parameter homes
- Observation: pass 1 of `Pass.MemToReg.cpp` records `lea ar, [fb + off]` into `addrRegOffset`
  and never invalidates the entry when `ar` is later redefined by plain arithmetic
  (`ar += reg`). Pass 2 does flag the redefinition as an escape and poisons the variable at the
  ORIGINAL offset, but subsequent accesses through `ar` still resolve against that original
  offset, so a store through the modified pointer can be attributed to a slot the pointer no
  longer addresses. Today the poisoning of the original variable happens to block the promotion
  of the mis-attributed slot itself, and variable-index addressing normally goes through the
  Amc forms (whose result register is untracked), which is why no miscompile has been observed —
  the hole needs a hand-written `lea` + register add + constant-offset store to line up.
- Next step: in pass 2, move a redefined tracked register into `badAddrReg` at the redefinition
  point (position-aware, since the map is currently flow-insensitive), or verify while
  classifying accesses that the base register's definition still is the recorded lea.

### F-029 — ChaCha20 throughput is bounded by memory round-trips, not by round arithmetic

- Area: std/core (crypto), compiler/backend
- Found while: benchmarking the auto-vectorized ChaCha20 rounds (sCrypt entry 2)
- Observation: with the rounds fully vectorized (the double-round loop compiles to ~90 packed
  instructions instead of ~500 scalar ones, `chacha20Block` overall 2794 -> 915), end-to-end
  `chacha20Xor` throughput did not move measurably (medians 34.4 vs 34.0 MiB/s vectorized vs
  scalar, DLL-swap interleaved protocol, though on a machine whose baseline drifted 2-40 MiB/s
  between sweeps). Two structural costs dominate: the vectorized state is loaded from and
  stored back to the frame on EVERY round-loop iteration (10 x 4 loads + 4 stores of 16 bytes,
  each on the store-to-load forwarding latency chain), where hand-written SIMD keeps the four
  row vectors in registers across all ten iterations; and the per-block plumbing around the
  rounds (key-stream application, marshalling, wipes) is byte- and word-granular — the
  word-at-a-time key-stream application and `load32`/`store32` word accesses landed with this
  investigation, the register-resident state did not.
- Next step: teach the backend to keep vectorized memory locations in vector registers across
  loop iterations (a vector-width mem2reg, or letting the SLP pass claim whole-loop regions),
  then re-measure with the interleaved DLL-swap harness on a quiet machine before drawing any
  throughput conclusion.

### F-030 — A by-value owning argument carries no borrow, so its payload escapes unjudged

- Area: compiler
- Found while: closing the container-of-views hole F-027 described (now detected: a store into a
  container's `[*] T` payload is summarized, and judged wherever the container outlives what was
  stored into it)
- Observation: `typeCanCarryBorrow` excludes structs with an owning lifecycle, so an argument of
  such a type produces no borrow at a call site. A callee that hands back its parameter's owned
  payload records the return summary correctly, but no call site is ever judged against it.
  Passing the same value by POINTER works, because a pointer is a carrier.
- Evidence: `borrowEscapeHeapParamPayload(box: BorrowEscapeHeapBox)->[*] BorrowEscapeSlot`
  returning `box.slots!` is silent at every call site, while the `*BorrowEscapeHeapBox` spelling
  right next to it errors ([borrow_escape.swg](bin/unittests/sanity/borrow_escape.swg), section
  "Owned payloads"). The exclusion dates from the field-scan rule: a bitwise walk of an owner's
  fields would confuse ownership with borrowing.
- Next step: the exclusion is about SCANNING an owner's fields, not about the owner being unable
  to lend anything — a by-value owning argument should yield a borrow rooted at that argument
  without the field scan, the way `typeHasBorrowableStorage` already does for owner views. Try it
  behind the usual sweep (build every workspace, zero-hit baseline) and triage: the risk is that
  every owner passed by value starts feeding the stores and frees summaries.
