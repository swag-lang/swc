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

### `notnull` launders `readonly` away, `!.` does not

- Area: compiler
- Found while: sweeping `(notnull x).m` to `x!.m` after adding the `!.` not-null access
- Observation: `notnull` yields a fresh *value*, so the qualifiers of the path it came from are
  dropped. Reaching a member through it therefore hands out a mutable reference into storage the
  caller only had read access to. `!.` accesses through the original path and keeps the
  qualifier, which is why exactly one site out of 326 stopped compiling when it was converted.
- Evidence: `SplitterCtrl.items` is declared `readonly`
  ([splitterctrl.swg:40-42](bin/std/modules/gui/src/composite/splitterctrl.swg#L40-L42)), so from
  outside `std/gui` the const `Array.opIndex` overload applies. `&(notnull
  me.quickStyleBar.items[0]).size` compiles and produces a writable `*f32`;
  `&me.quickStyleBar.items[0]!.size` produces `const *f32` and is rejected. sCapture uses the
  first form to serialize pane sizes into a `readonly` collection
  ([mainwnd.swg:210-211](bin/apps/modules/sCapture/src/mainwnd.swg#L210-L211)).
- Next step: decide whether `notnull` should preserve the const/readonly qualifier of its operand
  like `!.` does. It probably should — the current behavior is an unannounced escape hatch out of
  `readonly`. Closing it needs a serialization path for `SplitterCtrl` pane sizes first
  (`setPaneSize` exists for writes, but the serializer wants one address for read and write), then
  a sweep of the other `notnull` sites that may be relying on the same laundering.
- Related: the `!.` operator, `bin/unittests/jit/operators/notnull_access.swg`

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
  test-only types to dependents in the first place. Making the test types non-`public` is NOT the
  fix: without export, runtime interface dispatch stops binding the impl (the TagBin
  `readElement` hook is silently never called and `tagbin.test.swg:611` fails), so the `public`
  markers are required and the resolver is the only correct place.

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
- Related: the `gui-resources` branch settled the compile-time half for the string and theme
  layers. `Gui.validateStrings` parses a language file inside a `#run` block against a struct of
  `string` fields whose declared values are the reference wording, so the resource is validated at
  build time and read through typed fields with no lookup boundary; theme sheets reuse `TweakFile`
  at runtime because a theme is a delta over a live value, not a set of declarations. The
  remaining open half is only the original one: emitting typed *members* for a whole window.

### Dangling `else` after a guarded statement binds to `try`, not to `if`

- Area: language
- Found while: implementing recursive `Directory.delete` on the `gui-resources` branch
- Observation: in `if c do try a() else do try b()`, the `else` binds to `try a()` as its
  failure handler instead of to the `if`. With `c` false, nothing runs at all; with `c` true and
  `a()` succeeding, `b()` never runs either. The code compiles silently and both branches are
  effectively lost, which turned `File.delete` calls into no-ops inside the first version of the
  recursive delete.
- Evidence: a 30-line repro with two counters shows `shapePlain(true); shapePlain(false)` calling
  `fa` once and `fb` never; bracing both branches restores the expected behavior. The whole
  repository was searched for the shape (`do (try|catch|expect) ...` followed by `else`) and holds
  no other occurrence.
- Next step: decide the language rule. Either refuse an `else` whose owner is ambiguous between a
  guarded `do` statement and `try`/`catch`, or require `catch`-style `else` to sit on the same
  statement. A parser diagnostic is enough to make the trap impossible.

### TweakFile silently keeps the previous folder on an unknown `/Folder` line

- Area: bin/std
- Found while: debugging theme sheets on the `gui-resources` branch
- Observation: a `/Name` line that matches no registered folder only fails when no folder was
  selected yet. After a first successful folder line, an unknown folder name silently keeps the
  previous folder current, so the following values are decoded into the wrong struct or fail with
  a misleading `value not found` error.
- Evidence: `TweakFile.parse` only checks `if !currentFolder` after the match loop
  (`bin/std/modules/core/src/filesystem/tweakfile.swg`).
- Next step: fail on any unmatched folder line, with the line number, and add the covering test.

### Property-grid names and descriptions cannot follow a language switch

- Area: bin/std
- Found while: localizing sCapture on the `gui-resources` branch
- Observation: the property grid reads `#[Name]`, `#[Description]`, and `#[Category]` attribute
  strings, which are compile-time constants, so options dialogs keep their English wording when
  `Application.setLanguage` retargets every string table.
- Evidence: sCapture ships fully localized except its options dialog and the form property
  panels (`bin/apps/modules/sCapture/src/options.swg`, `src/forms/*.swg`).
- Next step: decide where translation belongs. The grid could resolve the attribute string
  through the registered string tables when a matching key exists, which keeps attributes as the
  reference wording and adds no lookup at call sites; measure whether that lookup at grid-build
  time is acceptable before generalizing.

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
  borders; icons remain the only upscaled raster element. sCapture compiles and the main grab
  path converts spaces explicitly (`capturerectwnd.swg`, `screenshot.swg`,
  `inplaceeditwnd.swg`). Automatic vectorization of the existing 24-pixel glyphs (`Svg.trace`
  over each atlas cell) produces faithful but visually unconvincing outlines at that source
  resolution, and was rejected.
- Next step: the icon atlases need authored vector sources (or higher-resolution raster
  sources) before the image lists can rebuild per scale the way the widgets atlas now does
  through `Theme.ensureAtlasScale`. For sCapture, run a capture and in-place edit session on a
  150% display and on mixed-DPI monitors, and fix the remaining space mismatches the session
  exposes.
