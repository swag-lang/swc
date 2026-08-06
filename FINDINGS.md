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
identifier, so a reference made today still resolves after the entry is gone. Entry order in this
file is free and carries no priority.

Next identifier: F-016

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

### F-007 — `#[Swag.Tls]` is accepted and then ignored

- Area: compiler
- Found while: attributing the sCrypt/WinFsp integration working-set growth to the runtime
  allocator rather than to sCrypt or WinFsp
- Observation: the attribute is parsed into `RtAttributeFlagsE::Tls`
  ([AttributeList.h:37](src/Compiler/Sema/Core/AttributeList.h#L37), assigned at
  [Sema.Attributes.cpp:181](src/Compiler/Sema/Ast/Sema.Attributes.cpp#L181)) and never read again;
  no backend emits a thread-local segment. A `#[Swag.Tls]` global is an ordinary shared global, so
  every "one copy per thread" design built on it is silently one shared copy. The language
  reference documents the feature as working
  ([003_005_variables.swg:128-131](bin/reference/modules/language/src/003_005_variables.swg#L128-L131)).
- Evidence: a native program writes `0xAAAA` into a `#[Swag.Tls] var u64` on the main thread; a raw
  `CreateThread` worker reads back `0xAAAA` (a real slot reads 0), writes `0xBBBB`, and the main
  thread then reads `0xBBBB`. The remaining users in `bin/` are `Random.shared()`
  ([random.swg:3](bin/std/modules/core/src/rand/random.swg#L3)) and the Mersenne Twister plus counter
  behind `Guid64`/`Guid128`
  ([guid64.swg:6](bin/std/modules/core/src/system/guid64.swg#L6),
  [guid128.swg:6](bin/std/modules/core/src/system/guid128.swg#L6)), so identifier and random
  streams are raced on and can repeat across threads.
- Next step: decide between implementing the attribute (a `.tls` section and an
  `IMAGE_TLS_DIRECTORY` in the PE writer and the integrated linker, plus an equivalent under the
  JIT) and rejecting it with a diagnostic. Either way the remaining `bin/` users need a mechanism
  that exists today: an explicit slot through `__tlsAlloc`/`__tlsGetPtr`, which is already how the
  runtime context reaches per-thread storage
  ([os_windows.swg:298](bin/runtime/os_windows.swg#L298)).

### F-008 — Ten `sCrypt` tests do not pass

- Area: bin/apps
- Found while: fixing the native test runner, which until now executed none of them
- Observation: `sCrypt` runs its 26 tests in about 15 seconds and 10 do not pass. The same 10 fail
  under the JIT runner, so they are genuine and independent of the runner change. Six of the eight
  failing assertions are the single expression `@assert(rejectsPassword(...))`, which either means
  `Volume.open` accepts a password or a container it should reject, or means the helper never
  observes the error — one shared cause, with very different severities. `sCapture` is not yet
  measured.
- Evidence: `tools/apps.bat dm test sCrypt`. Eight assertions do not hold —
  [mainwindow.test.swg:62](bin/apps/modules/sCrypt/src/tests/mainwindow.test.swg#L62) and
  [:88](bin/apps/modules/sCrypt/src/tests/mainwindow.test.swg#L88) on the French wording and the
  language picker, [volume.test.swg:148](bin/apps/modules/sCrypt/src/tests/volume.test.swg#L148),
  [:317](bin/apps/modules/sCrypt/src/tests/volume.test.swg#L317),
  [:338](bin/apps/modules/sCrypt/src/tests/volume.test.swg#L338),
  [:499](bin/apps/modules/sCrypt/src/tests/volume.test.swg#L499),
  [:564](bin/apps/modules/sCrypt/src/tests/volume.test.swg#L564) through `rejectsPassword`, and
  [:595](bin/apps/modules/sCrypt/src/tests/volume.test.swg#L595) on a cancelled create. Two more
  die on an uncaught `Core.Swag.SystemError` from `expect File.duplicate(salvaged, path)`
  ([:400](bin/apps/modules/sCrypt/src/tests/volume.test.swg#L400),
  [:433](bin/apps/modules/sCrypt/src/tests/volume.test.swg#L433)).
- Next step: settle the `rejectsPassword` cluster first, because it is six of the ten and because
  one of its two readings is a defect in the encryption itself. `discard catch Volume.open(path,
  password) as openError; return openError != null` — check that `catch ... as` binds the error
  through a `discard`, by asserting directly on `catch Volume.open(...)` with a knowingly wrong
  password. If the binding is sound, the container format accepts input it must refuse.

### F-009 — `for &x in f()` corrupts its elements when `f` returns `const &Array'T`

- Area: compiler
- Found while: filling the `sCrypt` language picker from `Gui.languages()`
- Observation: iterating by reference directly over a call that returns `const &Array'T` yields
  elements whose fields are garbage. Binding the call to a pointer first and iterating the
  dereferenced pointer over the same array is correct, so the returned reference itself is sound
  and the defect is in what the `for` binding does with a call result.
- Evidence: `func languages()->const &Array'Language { return g_Localization.languages }` in
  `gui.dll`, then `for &one in Gui.languages() do combo.addItem(one.nativeName.toString())` in
  `sCrypt`: `String.opSet` receives a garbage count and the run dies on `Memory.alloc returned
  null`. `let all = &Gui.languages()` followed by `for &one in dref all` over the same data is
  correct. The same source shape run in the module's own test binary did not fault, so the symptom
  needs the shared-library boundary or a particular allocation layout.
- Next step: reduce it to two modules — a shared library exporting `Array'T` by `const &` and an
  executable iterating the call by reference — and inspect what the `for` lowering binds to: a
  temporary copy that is dropped before the body would explain both the garbage and why taking the
  address first is sound. Deciding whether a container should be returned by reference at all is
  the design half of the question; the API here now returns `const [..] T`, which behaves.

### F-010 — A reflected property label cannot be translated

- Area: std/gui
- Found while: giving sCapture its own surface and translating its tool panel
- Observation: in a French session the panel mixes languages. The hand-built rows read `Fond`,
  `Contour`, `Tirets`, while the rows the `Properties` grid generates from reflection read
  `Thickness`, `Rotate`, `Opacity`, `Shadow`, and the boolean combos offer `Straight`/`Bezier`
  and `No Shadow`/`Small`. This holds for any application that builds a panel from attributes.
- Evidence: the label and the combo entries come from `#[Name(...)]`, `#[Unit(...)]` and
  `#[BoolCombo(...)]` string literals carried by the field
  ([form.swg:66-80](bin/apps/modules/sCapture/src/forms/form.swg#L66-L80)). An attribute value is a
  compile-time literal, so it cannot be a key resolved through `Gui.registerStrings`, and the grid
  has no hook to remap it. sCapture works around one row only, by walking the built items and
  re-labelling the border-size slider
  ([propwnd.swg](bin/apps/modules/sCapture/src/propwnd.swg)) — a loop per row would not scale and
  would still miss the combo entries.
- Next step: give `Properties` a resolver the host installs once — a callback taking the field's
  declared name and returning the displayed text — and route every generated label, unit, and
  enumeration entry through it. A `#[Name("Thickness")]` then becomes a translation key rather
  than a final wording, and the per-row workaround disappears.

### F-011 — A fully transparent fill is dropped even under `Copy` blending

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

### F-012 — A surface outline must be stroked before its shadow, and nobody knows why

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

### F-013 — A menu bar does not follow a live language switch

- Area: std/gui
- Found while: applying the sCapture language at construction instead of only on state load
- Observation: `MenuCtrl.addPopup(name, popup)` copies the wording into the item once, so the six
  entries of an application menu bar keep the language they were built in. Everything below them is
  added by command id and refreshes through the command state, which is why only the bar is stale.
  sCapture now builds its bar after reading the persisted options, so a start-up in any language is
  correct; changing the language from the Options dialog still leaves the bar behind.
- Evidence: with `EditorLanguage.French` persisted, a bar built during `create` reads
  `File Capture Edit` while the tool rail beside it reads `Favoris Sélection Forme`.
- Next step: the hook already exists — `MenuCtrl.onPrepareItem` runs for every visible item at the
  top of `computeLayoutBar`. Either document it as the supported way to re-resolve a literal
  label, or let `addPopup` take a resolver instead of a string so the wording is re-read on every
  layout, the way a command-driven item already is.

### F-014 — A menu bar entry is clipped, and the error grows with the word

- Area: std/gui
- Found while: seeing the sCapture menu bar in French for the first time
- Observation: the bar clips the last glyph of its longest entry. `Affichage` loses half of its
  final `e`; `Fichier`, `Capture`, `Image` and `Aide` beside it are intact. The shortfall scales
  with the length of the label, which points at a per-glyph difference between measuring and
  painting rather than at a missing constant margin.
- Evidence: `computeLayoutBar` measures into a layout-only painter with `rsf.font = .font()` and
  stores the result as the item extent
  ([menuctrl.swg:757-768](bin/std/modules/gui/src/composite/menuctrl.swg#L757-L768));
  `getBarLabelRect` then hands exactly that extent to the real draw
  ([menuctrl.swg:444-453](bin/std/modules/gui/src/composite/menuctrl.swg#L444-L453)), so any
  advance the measuring pass under-counts is shaved off the end. Reproduce with a French sCapture:
  the entries are set from `ui_MenuFile` and friends, and `Affichage` is the longest.
- Next step: compare the two paths on one string — the width `RichString.boundRect` reports after a
  `layoutOnly` `drawRichString`, against the advance the same font accumulates when actually
  painting. If they differ per glyph, the layout-only path is the bug; if they agree, the clip
  comes from the rounding of `item.pos`/`item.size` into the label rectangle.

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
