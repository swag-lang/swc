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

## Open Investigations

<!--
Use this compact format. Keep observations factual and make the next step actionable.

### Short descriptive title

- Area: compiler | bin/std | language | tooling | documentation
- Found while: task, test, or file that exposed the issue
- Observation: awkward behavior, suspected defect, or optimization opportunity
- Evidence: reproduction, relevant paths, measurements, or diagnostics
- Next step: smallest useful investigation
- Related: issue, pull request, or TODO entry if applicable
-->

### Two sCapture modal-dialog tests fail on master

- Area: bin/apps
- Found while: validating the GUI theme rewrite, which needed a baseline to attribute failures to
- Observation: `dialogs.test.swg:23` and `files.test.swg:513` both fail on `@assert(gui.autoHandled)`
  — the headless modal driver arms `clickModalButtonWhenShown` and the dialog is never reported as
  handled. Two of the 126 sCapture tests; the other 124 and all 28 sCrypt tests pass.
- Evidence: reproduced identically in a pristine `git worktree add --detach ../swc-basecheck
  d02f74d99` with no local change, so it is not caused by the theme work. Same two tests, same
  asserts, same commit.
- Next step: instrument `Gui.Testing.HeadlessHost.clickModalButtonWhenShown` to report which
  surface it inspected and which button id it looked for; both failing cases open a real modal
  (About, File Details) rather than a `MessageDlg`, which is the difference from the passing
  modal tests.

### sCapture keeps a dark editor matte after switching to the light theme

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

### A reference to a nullable slot escapes the whole nullability system

- Area: compiler
- Found while: checking whether the postfix `!` leaks `readonly` (it does not — `readonly`
  deliberately "restricts writing through the field's name; it does not freeze the whole value",
  [002_009_visibility_and_exports.swg:107-109](bin/reference/modules/language/src/002_009_visibility_and_exports.swg#L107-L109))
- Observation: `&#null *T` — a reference bound to a nullable slot, which is exactly what
  `Array.opIndex` hands back — is not seen as nullable anywhere. `isNullable()` is asked of the
  reference, and a reference is never nullable, so: the use-site rules let a member access through
  it compile with no proof at all, and the postfix `!` is a silent no-op on it. The nullability
  system simply does not apply to values reached through a reference.
- Evidence: with `mtd const at()->const &(#null *Item)`, `bound.value` compiles unguarded and
  `#typeof(bound.value)` reports `#null *Item` rather than the field type — member resolution
  peels one pointer-or-reference layer and then stops, so it never reaches the struct.
  `#typeof(bound!)` is unchanged by the assertion.
- Next step: this needs three coordinated changes, which is why an attempt was reverted rather
  than half-shipped. (1) The use-site check must look through the reference
  (`SemaHelpers::unwrapAliasRefType` in `resolveMemberAccess`). (2) `notNullUnwrappedTypeRef` must
  strip `Nullable` INSIDE the reference — rebuilding `&(#null *T)` as `&*T` rather than dropping
  the reference, so the payload convention is untouched. (3) Member resolution must peel every
  reference layer and then exactly one pointer (`**T` must still stop after one), and codegen must
  do the matching double indirection — step 3 is where the reverted attempt failed: it compiled
  but read the wrong address at run time. Start with a runtime test for `bound!.value`, since that
  is what catches the codegen half.
- Related: `bin/unittests/jit/operators/notnull_access.swg`

### The sandbox is armed twice per run, and the second attempt fails the whole process

- Area: bin/std | compiler
- Found while: validating a runtime allocator rewrite, where `tools/scripts.bat smoke` failed
  intermittently and the failure had to be cleared as pre-existing
- Observation: `Env`'s sandbox `#init` hook runs more than once in a single script run. The first
  call carries the launcher's explicit root and arms correctly; a later call arrives with an empty
  run-argument value, falls back to `defaultSandboxRoot()`, and is rejected by
  "the sandbox root cannot change once armed". The rejection is fatal by design, so the run dies
  with `compiler panic: sandbox setup failed` — and it dies at a different script on every attempt,
  which is what makes the suite look flaky rather than broken.
- Evidence: printing inside `enterSandbox` over three `tools/scripts.bat smoke -bc release` runs
  gives, in the same process, `rootLen=56 armed=false exists=true` followed by
  `rootLen=84 armed=true exists=false` (84 is `<temp>/swag-sandbox/run-<pid>`, the default root).
  Two of three runs failed. Reproduced identically with the baseline runtime, so this is not
  allocator-related. Separately, `%TEMP%/swag-sandbox` had accumulated 3871 `run-<pid>` directories:
  nothing ever removes a sandbox root, so the name is not the private-per-run identity it claims.
- Next step: find out which stage runs the hook the second time and why the run argument is empty
  there. The prime suspect is the runtime hook chain, where `PreMain` is emitted twice with
  separate guards — a runtime stage and a compiler stage
  ([NativeArtifactBuilder.cpp:298-304](src/Backend/Native/NativeArtifactBuilder.cpp#L298-L304)) —
  against a single `Init` guard, combined with process-argument adoption that differs between the
  two. Print the stage and `@pinfos` arguments from the hook to tell "the hook runs twice" apart
  from "the arguments were re-adopted empty". Whichever it is, `enterSandbox` should also treat a
  second arm with no explicit root as a no-op rather than a fatal mismatch.

### Golden snapshots cannot be recorded under the test sandbox

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

### Constant branches survive until the sanitizer after inlining

- Area: compiler
- Found while: `notnull_access.swg` release-mode sanity false positive (fixed in the sanitizer)
- Observation: inlining `redundant(null)` folds the null test to `%2 = 1; %3 = %2;
  cmp %3, 0; je`, yet no pass folds the constant compare-and-branch before sanity runs, so the
  dead dereference block survives the whole pre-RA pipeline. The sanitizer now prunes the
  infeasible edge itself, but the optimizer keeps emitting the dead block.
- Evidence: `#[Swag.PrintMicro("pre-sanity")]` on a `#test` calling `redundant(null)` shows the
  folded guard and the unreachable dereference block still present at the sanity stage.
- Next step: teach branch-simplify (or const-fold) to evaluate a conditional jump whose flags
  come from a compare against an immediate on a register holding a known constant, then let DCE
  drop the unreachable block; measure code-size impact on the release suites.

### Droppable call-result temporaries are never dropped

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
  argument-cast shapes while `var x = makeThing()` drops exactly once.
- Next step: mark function-owned result storages in sema (cast-source, discard, optional
  chains, index temporaries — call-argument storages are callee-dropped and `retval` storages
  are caller-owned, so both stay out), then flush their drops in CodeGen at the end of the
  consuming statement: register `{flushRootRef, storageSym}` at call emission, where the flush
  root is the nearest ancestor that is a block child, and emit the pending drops in the
  generic `postNode` when it closes. Loop conditions need the condition node as flush root.

### A folded `typeinfo ==` answers differently from the same comparison at run time

- Area: compiler
- Found while: fixing `switch` over a `typeinfo`, which compared descriptor addresses and so
  never selected `case string` for a `#null string` (`CodeGenCompareHelpers::emitTypeInfoEqualJump`
  is now the single rule for both `==` and `case`)
- Observation: type identity at run time is the runtime hash, which deliberately ignores the
  qualifiers — `#null string` and `string` are the same type, as `@typecmp` documents. Constant
  folding does not follow that rule: `sameTypeValuePayload` rejects the pair on
  `leftType.flags() != rightType.flags()`. The same source expression therefore reports `false`
  when both sides fold and `true` when either side is a variable.
- Evidence: `alias NullString = #null string; const TN: typeinfo = NullString; #assert(TN ==
  string)` fails, while `var a: typeinfo = NullString; @assert(a == string)` passes
  ([switch_type.swg](bin/unittests/native/flow/switch_type.swg)). A `#run` of a function that
  switches on the same constant does match `case string`, because that comparison goes through
  codegen.
- Next step: decide which answer is the language rule, then make one side follow the other.
  Aligning the fold on the runtime hash is the consistent choice, but `sameTypeValuePayload` also
  answers `#typeof(a) == #typeof(b)` for generic and compile-time code, so the flag comparison has
  to be replaced by the runtime-hash rule (`TypeRuntimeHash`) only where the operands are
  typeinfo values, and the generic paths audited for cases that rely on the stricter answer.

### Data-driven UI resource for `std/gui`

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

### A thread-local global cannot hold a droppable type

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

### Arming the headless modal driver for an absent button fails silently

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

### A `#run` block cannot initialize a zero-segment global

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

### A failing `@assert` reports the source line below itself

- Area: compiler
- Found while: reading the two `sCapture` dialog failures above, where the reported line pointed at
  an assertion that was not the one failing
- Observation: the runtime panic location of a failed `@assert` is the assertion's own column but
  one line too far down. It misattributes every failure to the following statement, which is worse
  than a missing location: the reported line is usually a real, passing assertion. Compile-time
  diagnostics on the same file are correct, so the line table is sound and only the runtime
  `SourceCodeLocation` is wrong.
- Evidence: put `@assert(false)` on line 22 of
  [dialogs.test.swg](bin/apps/modules/sCapture/src/tests/dialogs.test.swg) and run
  `tools/apps.bat dm test sCapture`: the panic reads `dialogs.test.swg:23:6`. Column 6 is where
  `assert` starts on line 22, so only the line is displaced. Reproduced a second time by injecting
  `@assert(false)` at line 24 of `sCrypt`'s `crypto.test.swg`, reported as `:25:6`.
- Next step: `codeGenAssert` builds the location through
  `ConstantHelpers::makeSourceCodeLocation(sema, ref, node)`
  ([CodeGen.Intrinsic.Call.cpp:1292](src/Compiler/CodeGen/Ast/CodeGen.Intrinsic.Call.cpp#L1292)),
  which takes `node.codeRangeWithChildren` and ends in
  `SourceCodeRange::fromOffset`. `codeRange()` uses the token directly and is correct, so compare
  the two on the same node: the suspect is the offset-to-line conversion counting the newline that
  *precedes* the span. Check whether the runtime safety checks that share this helper
  ([CodeGenSafety.cpp:88](src/Compiler/CodeGen/Core/CodeGenSafety.cpp#L88)) are displaced too — if
  they are, every runtime panic location in the language is off by one and the fix is one place.

### A per-frame event can be sent but never asked for

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

### A fully transparent fill is dropped even under `Copy` blending

- Area: bin/std
- Found while: giving the surface drop shadow its transparent margin back
- Observation: `Painter.fillRect` cannot clear a region to premultiplied nothing. Every fill entry
  point skips a fully transparent source (`color.a == 0`, then `Brush.hasVisibleAlpha`), which is
  right under alpha compositing and wrong under `BlendingMode.Copy`, where the source replaces the
  destination and a transparent fill is the only way to erase. The CPU renderer already states the
  correct rule — `if src.a == 0 and .blendingMode != .Copy`
  ([rendercpu.swg:322](bin/std/modules/pixel/src/render/cpu/rendercpu.swg#L322)) — and so does the
  antialiasing shader, which discards a zero-coverage fragment only when `!copyMode`
  ([aa.frag:31](bin/std/modules/pixel/src/render/ogl/shaders/aa.frag#L31)). The painter contradicts
  both.
- Evidence: with `setColorMaskFull` and `setBlendingMode(.Copy)`, filling a region with
  `Color.fromArgb(0'u8, Argb.Black)` leaves it untouched; the same fill with alpha `1` clears it as
  intended. Routing the two guards through a blend-aware painter predicate was not enough — a third
  cull further down still drops it — so the search has to continue past `fillRect`/`hasVisibleAlpha`
  into `fillRectRaw`, the command packer, or the renderer.
- Next step: find the remaining cull by emitting a `Copy` fill of `a = 0` and one of `a = 1` and
  diffing the recorded command stream, then put one blend-aware predicate on the painter — it owns
  the blending mode, `Brush` does not — and route every `color.a == 0` and `hasVisibleAlpha` guard
  in `src/painter` through it.

### A surface outline must be stroked before its shadow, and nobody knows why

- Area: std/gui
- Found while: moving the surface outline above the hierarchy so docked views stop covering it
- Observation: `Surface.paint` ends with `paintBorder`, `paintShadowOutsideBody`, `paintAlphaMask`.
  Swapping the first two — stroking the outline after the shadow rather than before — costs the
  surface its entire drop shadow, on all four edges, not just where the two meet. The two passes
  touch disjoint regions: the outline is inside the body, the shadow is stencil-clipped to outside
  it. An ordering that matters between disjoint regions means one of them leaves painter or
  renderer state the other depends on, and the order is currently load-bearing by accident.
- Evidence: with the order `paintShadowOutsideBody`, `paintBorder`, the margin of gui1 reads flat
  `#D2D2D2` (the bare backdrop) on every edge; with `paintBorder` first the same build reads a
  clean gradient from `#D2D2D2` down to `#898989` at the body. Nothing else differs.
  `paintBorder` sets `setColorMaskColor` and strokes a pen with `borderPos = .Inside`;
  `paintShadowOutsideBody` opens a clipping region, sets `setColorMaskFull`, and fills rounded
  rectangles. Fixing the separate defect where the alpha channel composited with the source alpha
  as its own factor did not change this: the ordering was retested afterwards and still decides
  whether there is a shadow at all.
- Next step: dump the command stream for both orders and diff it. The suspects are the pen stroke
  path leaving clipping-region or overlap state behind — `StartNoOverlap` defers drawing, and the
  OpenGL renderer skips `DrawTriangles` outright while `overlapMode` is set — and
  `setColorMaskColor` reaching the shadow fills rather than the `setColorMaskFull` that precedes
  them, which would explain the loss exactly, since a shadow written without alpha is invisible to
  the compositor.

