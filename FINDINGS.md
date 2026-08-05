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

### A failing assertion in a `bin/apps` test does not fail the run

- Area: tooling
- Found while: adding headless layout tests to `sCrypt`
- Observation: `apps.bat test` builds a test executable and runs it (`--no-test-jit`), and the run
  reports success whatever the tests assert. The whole applications suite — 149 tests across
  `sCapture` and `sCrypt` — therefore proves nothing today.
- Evidence: inserting `#test { @assert(false) }` at the top of
  `bin/apps/modules/sCrypt/src/tests/volume.test.swg` still gives
  `✓ tested 25 tests`. The reported run time is the giveaway: 166 ms for 24 tests, several of
  which build a headless GUI host with a rasterized theme — the same work takes seconds in the
  `gui` module, whose tests do execute (a wrong expectation in `measure.test.swg` fails the run as
  it should). Launching `sCrypt.test.exe` by hand dies with `0xC0000135`, so the test executable
  does not even find its libraries beside it.
- Next step: check what `swc test --no-test-jit` does with the exit code and the output of the
  test executable it launches, and whether that executable is published with the shared libraries
  it links against — the missing-DLL exit code suggests the launch fails and the failure is
  swallowed. Until then, cover application behavior from a `bin/std` test where the runner is
  known to execute.

### Every GUI surface opens at its logical size in physical pixels on a scaled display

- Area: bin/std
- Found while: looking at `sCrypt` on a 150% display to check the French wording of its layout
- Observation: `Application.createSurface` takes logical units and
  [surface.win32.swg:369-376](bin/std/modules/gui/src/surface.win32.swg#L369-L376) resizes the
  still-hidden window to `size * dpiScale`. That resize does not survive: the window ends up the
  requested size in *physical* pixels. Meanwhile
  [surface.swg:192-201](bin/std/modules/gui/src/surface.swg#L192-L201) sizes the render context and
  the first resize event to `size * dpiScale`, so the tree is laid out for 1.5× more logical room
  than the window actually has and the painter draws it 1.5× too large. Everything past the first
  screenful is simply outside the window.
- Evidence: on a 144-DPI monitor, `sCrypt` asks for 1100×790 and `GetWindowRect` reports exactly
  1100×790 with `GetDpiForWindow` = 144; its two cards measure 764 physical pixels each and need
  ~1616 where 1100 exist. The `gui2` example asks for 1034×779 and reports exactly 1034×779, so
  this is not application-specific. Deleting the persisted placement changes nothing: a first-run
  window is wrong too, which rules out the state restore.
- Next step: `Application.createSurface` seeds `surface.position` with the *logical* rectangle
  ([application.swg:704](bin/std/modules/gui/src/application.swg#L704)) although `position` is
  documented as physical desktop pixels; check whether `show()` or any later
  `setPosition(.position)` writes that logical rectangle back over the physical one the native
  layer computed. Log the window rectangle right after `createNative`, after `Surface.create`, and
  after `show()` — the first of the three that reports the logical size names the culprit.
- Related: this is what makes a scaled `sCrypt` look broken whatever its language; the wording is
  a separate matter.

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

### The in-place capture overlay has never run on genuinely mixed-DPI monitors

- Area: bin/apps
- Found while: closing the per-monitor DPI work on `std/gui`, the theme art and sCapture
- Observation: sCapture's overlay covers the whole virtual desktop with one surface, so it holds
  one logical-to-physical factor — the DPI of its own monitor — while the capture, the grab
  rectangle and the annotation sizes are all in the physical pixels of whatever monitor the
  selection sits on. Every conversion between the two now goes through one of two places
  (`EditView.zoom` for the capture, `captureMonitorScale` for the chrome and the annotation
  defaults), but the case where those two disagree has only been reasoned about, never run.
- Evidence: a full grab, gizmo resize and arrow-drawing session at 150% is correct — the frozen
  desktop the overlay paints back is bit-identical to the live one inside the selection (40800
  samples), a 300-pixel drag of a gizmo anchor moves the edge exactly 300 pixels, and an arrow
  lands where the cursor went. That session ran on two monitors *both* at 150%, so
  `captureMonitorScale` returned the surface's own scale and the residual factor stayed 1: the
  branch that matters on a mixed setup never executed. The same session before the fix was 23.7%
  identical, so the check does discriminate.
- Next step: set the two monitors to different scales (150% and 100%), then grab on the second
  monitor and check the three things the residual factor drives: the bars keep their size, the
  selection stays glued to the desktop, and a fresh annotation keeps its weight.
