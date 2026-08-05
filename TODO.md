# Swag Investigation Backlog

This file records compiler, standard-library, tooling, and language-design issues discovered while
working on otherwise unrelated tasks. An entry is a lead worth preserving, not a commitment to
implement it.

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
  `<name>.actual.txt`/`.png` next to a mismatching golden for `tools/accept-test-goldens.bat` —
  both write into the module source tree, so they silently stopped working when the sandbox
  landed: a failing golden reports `[golden] cannot write ...` and leaves nothing to accept.
- Evidence: the 13 gui golden mismatches printed `cannot write` for every actual; recording them
  required launching the tests with an explicit repo-rooted sandbox
  (`--run-arg "swag.sandbox=<repo root>"`), which redirects the special directories into the
  repository and allows the corpus writes.
- Next step: decide where golden actuals should land under a sandbox. Candidates: the launcher
  grants the corpus root explicitly (a `swag.sandbox.corpus=<dir>` run argument the golden store
  consults), or the golden store mirrors actuals under the sandbox root at a deterministic path
  and `accept-test-goldens.bat` harvests them. Writing straight to the source tree from a
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

### Appending a `String` rvalue with `+=` corrupts the heap

- Area: bin/std | compiler
- Found while: accumulating traced SVG fragments into one `String` in a script
- Observation: `someString += Format.toString(...)` — appending a temporary `String` value —
  corrupts the heap. The damage surfaces later, as access violations inside unrelated
  allocations, so the crash site points far away from the append. Appending a `string` view
  (`+= s.toString()`) and `String.appendFormat` are sound. Appending a `String` lvalue was
  replaced in the same experiment and has not been exonerated separately.
- Evidence: scripted loop calling `Svg.trace` over 16 icon cells: with `outSvg +=
  Format.toString(...)` in the loop, iteration 3 dies with 0xC0000005 inside `pixel.dll`; the
  identical run with `appendFormat` plus `+= body.toString()` completes all 16 cells. The same
  loop with no appends at all also completes, and the failure point moves with unrelated
  allocation changes — classic layout-sensitive out-of-bounds or use-after-free behavior.
- Next step: build a minimal repro without `pixel` (a loop appending `String` rvalues to a
  growing `String`), then inspect which `opAssign`/append overload a `String` rvalue selects and
  the drop ordering of the temporary around `+=` — the append may be reading the operand's
  buffer after the temporary was dropped, or routing through a byte-slice overload whose length
  is read from freed storage.

### `Image.load` hands back the magenta placeholder for PNGs that decode correctly

- Area: bin/std
- Found while: regenerating the `texteffect.zoom` golden and comparing theme-atlas fidelity in
  standalone scripts
- Observation: `Image.load(path)` returned the magenta "missing image" placeholder for valid
  theme PNGs, while `File.readAllBytes` + `Image.decode(".png", bytes)` decodes the same files
  correctly. The placeholder makes the failure silent: a comparison harness happily measured
  differences against solid magenta.
- Evidence: the gui theme PNG atlases during the DPI/theme work; switching the scripts to
  read-then-decode was the entire fix at first. Later in the same work, `Image.decode(".png",
  bytes)` itself returned the placeholder for the same files when executed as a JIT-run script,
  while the identical call decodes correctly compiled into a native module — so the failure is
  context-dependent (JIT execution), not a parsing defect.
- Next step: run one PNG decode under the JIT with the decoder instrumented, find which stage
  fails only there (the placeholder swallows it), and make the failure loud (return the decode
  failure) instead of returning placeholder pixels.

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

### sCrypt integration working-set growth

- Area: bin/std
- Found while: reproducing an sCrypt WinFsp mount in the privileged integration test
- Observation: the process working set grows far beyond the 64 MiB test container during ordinary
  filesystem scenarios; the test still completes and cleans up normally.
- Evidence: `tools/test-scrypt-integration.bat dm` reached about 760 MiB in release, and the same
  34-scenario run in fast-debug reached about 835 MiB before passing, unmounting `Y:`, and exiting.
  Windows also recorded `RADAR_PRE_LEAK_64` for an earlier sCrypt run.
- Next step: record process heap and working-set deltas at every integration stage and across
  repeated mount/unmount cycles in one process, then attribute retained allocations to sCrypt,
  WinFsp, or the core allocator before changing ownership or allocation policy.

### Remaining DPI work: icon sources and the in-place capture editor

- Area: bin/std
- Found while: making `std/gui` and `Env.Window` per-monitor DPI aware (surfaces are physical
  windows, the window tree stays logical, the renderer maps painter streams through
  `Painter.contentScale`, and theme tiles sample with sharp bilinear at fractional scales)
- Observation: the 24/64-pixel icon atlases are still 1x raster sources, so at 150% an icon is a
  sharpened upscale rather than a re-rasterization; SVG sources rendered per scale would make
  them native. Separately, sCapture's in-place capture editor mixes desktop-physical and logical
  spaces in its editing overlay; the grab flow, bars, and 1:1 capture display were adapted, but
  the gizmo/form editing interactions inside the in-place overlay have not been visually
  verified on a scaled or mixed-DPI multi-monitor setup.
- Evidence: gui2 and the dark default theme at 150% show crisp text, hairlines, and tile
  borders. The theme widgets atlas, the theme icon set, and sCapture's application icon set
  are now vector sources (`gui/src/theme/widgets.svg`, `gui/src/theme/icons.svg`,
  `sCapture/datas/icons.svg` — the two icon sets from Fluent UI System Icons) rasterized per
  size and scale through `Gui.IconSet`, so the only remaining raster source is the spinner
  strip (`theme/spin.png`). sCapture compiles and the main grab path converts spaces
  explicitly (`capturerectwnd.swg`, `screenshot.swg`, `inplaceeditwnd.swg`).
- Next step: fold the spinner into a vector or procedural form, then run a capture and
  in-place edit session on a 150% display and on mixed-DPI monitors, and fix the remaining
  space mismatches the session exposes.
