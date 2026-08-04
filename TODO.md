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

### `std/gui` surfaces are DPI-unaware and bitmap-stretched

- Area: bin/std
- Found while: polishing sCrypt and chasing text that never looks clean on a 150% display
- Observation: no `std/gui` surface declares process or per-monitor DPI awareness, so Windows
  renders the whole window at its logical size and stretches the result. Every glyph, hairline,
  and border on a scaled display is therefore resampled, which no font tuning inside `pixel` can
  recover. `Application.pickColorAtMouse` is the only place that touches
  `SetThreadDpiAwarenessContext`, and only for the duration of a desktop pixel read.
- Evidence: sCrypt opens at 1100x790 logical and `GetWindowRect` from a DPI-aware process reports
  1650x1185, an exact 1.5x. In that capture the four-pixel accent rail is six pixels with a
  partial pixel on each side, and every panel edge ramps over two pixels instead of one. Raising
  `AutoMsdfMinPx` in `bin/std/modules/pixel/src/text/font.swg` from 20 to 32, which moves body
  text from the MSDF atlas to an exact-size bitmap, produced a byte-identical crop: the blur is
  applied after the app has drawn, so the font path cannot be the cause.
- Next step: make one surface DPI-aware end to end before touching the toolkit. Call
  `SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)` at startup, size the swap chain from
  `GetClientRect` in physical pixels, and push `GetDpiForWindow / 96` into the painter transform
  so `computeTextDrawInfo` receives it as `transformScale` and the existing `Auto` bitmap/MSDF
  choice starts seeing the real on-screen size. Then decide whether layout keeps logical units,
  and what `WM_DPICHANGED` has to re-arrange.
