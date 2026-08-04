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

### Cold-cache `std` test runs fail resolving core test-only exports

- Area: compiler
- Found while: validating a `bin/std` change with `swc test --workspace bin/std` after deleting
  `.dep`/`.output`
- Observation: on a cold cache, building `pixel.test` fails with `native backend cannot resolve a
  foreign function relocation for '<jit-constant>'` requesting `tag_bin_hook_payload__read` and
  `tag_bin_interface_probe__score` from module `core`. Those are public *test-only* symbols
  (`TagBinHookPayload`, `TagBinInterfaceProbe` in
  `bin/std/modules/core/src/unittests/serialization/tagbin.test.swg`): they are exported by
  `core.test.dll` and declared in the test-variant interface, but the resolver looks them up in
  the non-test `core` module. The suite only passes with warm caches from an earlier state.
- Evidence: reproduces deterministically at clean HEAD (65b0e0271) in a fresh worktree with both
  `bin/swc.exe` and `bin/swc_devmode.exe`: `build --rebuild` succeeds, the following
  `test --workspace bin/std` stops at pixel with the two relocations above. The strings
  `tag_bin_hook_payload__read/write/post` are present in
  `.output/core/shared-library/fast-debug/x86_64/core.test.dll`.
- Next step: in the native-backend foreign resolver, check how a `<jit-constant>` relocation maps
  a module name to a concrete dll in test mode: downstream test builds must resolve `core` to
  `core.test.dll` (where test-only exports live), or the test-variant interface must not leak
  test-only types to dependents in the first place.

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

### Remaining DPI work: bitmap chrome assets and the in-place capture editor

- Area: bin/std
- Found while: making `std/gui` and `Env.Window` per-monitor DPI aware (surfaces are now
  physical-pixel windows, the window tree stays logical, and the renderer maps painter streams
  through `Painter.contentScale`)
- Observation: two things still resample on a scaled display. First, the theme remains a 1x
  bitmap atlas: `widgets.png` nine-slice tiles and the 24/64-pixel icon atlases are linearly
  upscaled at 125-175%, so atlas borders and icons are the one soft element left in an otherwise
  crisp UI. Second, sCapture's in-place capture editor mixes desktop-physical and logical spaces
  in its editing overlay; the grab flow, bars, and 1:1 capture display were adapted, but the
  gizmo/form editing interactions inside the in-place overlay have not been visually verified on
  a scaled or mixed-DPI multi-monitor setup.
- Evidence: gui2 at 150% shows a 1551x1169 physical window (1034x779 logical, DPI 144) with
  crisp MSDF text, device-snapped hairlines, and correct layout; only atlas-sourced chrome is
  interpolated. sCapture compiles and the main grab path converts spaces explicitly
  (`capturerectwnd.swg`, `screenshot.swg`, `inplaceeditwnd.swg`).
- Next step: for the chrome, either ship a 2x `widgets.png`/icon atlas variant selected by
  surface scale, or draw the flat Swag-theme chrome (square fills, hairline borders) vectorially
  through the painter; the icons want SVG sources rasterized per scale. For sCapture, run a
  capture and in-place edit session on a 150% display and on mixed-DPI monitors, and fix the
  remaining space mismatches the session exposes.
