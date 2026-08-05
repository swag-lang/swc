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

### `#[Swag.Tls]` is accepted and then ignored

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

### Ten `sCrypt` tests do not pass

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

### `for &x in f()` corrupts its elements when `f` returns `const &Array'T`

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

### A reflected property label cannot be translated

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

### The drawn surface shadow is painted opaque

- Area: std/gui
- Found while: trying to make a modal dialog stand out from the application under it
- Observation: `ThemeMetrics.surfaceWnd_ShadowSize` reserves a transparent margin around a surface
  for `Surface.paintShadow` to cast a soft halo into. The margin is not transparent: the surface
  clears it with its own ground, so the halo comes out as a hard dark band around every window
  instead of a shadow, and the window looks like it grew a black frame. The metric is therefore
  pinned at zero, which also cost the outline until it was untied from it, and left a modal box
  cut from the same ink as the application with nothing to separate the two.
- Evidence: set `surfaceWnd_ShadowSize` to 12 and run any app: a solid band appears on all four
  edges of every surface, of exactly that width, with no gradient and no blending with the desktop.
  `paintShadow` itself is fine — it draws `surfaceWnd_ShadowLayers` rings of `wnd_Shadow` at
  growing spreads ([surface.swg:449-478](bin/std/modules/gui/src/surface.swg#L449-L478)).
- Next step: find out whether the native window is layered at all. `createNative` would need
  `WS_EX_LAYERED` with per-pixel alpha, or a DWM blur-behind region, for anything drawn in that
  margin to composite against the desktop; the renderer must also clear it to zero alpha rather
  than to `wnd_Bk`. If per-pixel alpha is out of reach, delete the drawn shadow and its five
  metrics instead of leaving a switch that cannot be turned on, and let the platform cast the
  shadow.

### A menu bar does not follow a live language switch

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

### A menu bar entry is clipped, and the error grows with the word

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
