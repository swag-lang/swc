# Application scenarios

Use complementary test families. A passing startup smoke is not a completed user journey.

| Boundary | What it establishes | Where it lives |
| --- | --- | --- |
| Ordinary tests | Model, decoder, command and layout behavior | `src/tests/cases/functional/`, with an optional area folder |
| Golden tests | Maintained text/image references | `src/tests/cases/golden/`, with snapshots in `src/tests/goldens/`, tag `golden` |
| Application journeys | Native window, real files and workers, event loop, user actions and completed presentation | `src/tests/cases/integration/<plan>.swg`, tag `integration.application.journey` |
| External integration tests | Native-host, driver, hardware or external-service contracts | `src/tests/cases/integration/<contract>.swg`, explicit `integration.*` tag |
| Stress tests | Large-volume, scale, concurrency and lifecycle limits | `src/tests/cases/stress/<subject>.swg`, `stress` or a scoped `*.stress` tag |
| Startup smoke | The shipped executable and published resources start and stop within a budget | `tools/apps.bat [dm] smoke <application>` |

Integration tags opt in ordinary `#test` functions; they are not another test language or assertion
framework. Keep the test-only guard and keep journeys out of `#main`. The directory supplies the
test type, and filenames name the subject and end in `.swg`. Name a journey for the complete
user plan, such as `cases/integration/browsemedialibrary.swg`; the first control or screen does
not own the journey. Do not mix test types in one file. Keep every module test under
`src/tests/cases/`; preserve viewer-specific grouping with an area folder such as
`src/tests/cases/functional/viewers/<viewer>/`. Put shared test helpers under `src/tests/helpers/`,
not in production APIs. A smoke test is the bounded application startup check, not a user journey.
Run the real application window and its normal event loop; do not replace filesystem enumeration,
background workers, decoders or the renderer with fakes in a test intended to cover that path.
Include production initialization such as the application icon and resource registration; redirect
persisted settings into the owned temporary directory. An empty test shell can miss startup failures.
Use the same commands and input handlers as the UI. OS-level input delivery remains a separate
integration boundary: calling an action directly does not test keyboard routing or hit testing.
Native test entry points omit `#main`. Exercise background work through the production task and
decoder path rather than replacing it with a fake in the scenario.

## Write an executable test plan

Give each independently finishable journey its own `#test`, with:

1. A short comment naming the user's task and the regression it protects.
2. Owned temporary data, seeded from the application's immutable `src/tests/datas` fixtures.
   Large libraries may repeat small real files; state that this stresses volume and lifecycle,
   not format diversity. Never depend on a personal drive, live service, or private document.
3. Explicit actions followed by observable expectations: selected file, item count, scroll
   position, active document, finished thumbnail, saved bytes, and preserved state on return.
4. Readiness conditions and bounded deadlines. Pump the actual event loop while waiting; a sleep
   alone proves nothing. Report the stage that timed out. Keep each test below 40 seconds; split
   longer plans into independent journeys rather than raising every timeout.
5. A rendering checkpoint where visual corruption is a risk. On Windows,
   `Gui.Testing.verifyNativePresentation` compares the completed native presentation bitmap with
   the GPU target and rejects a transfer error. It cannot detect identical corruption already
   present in both images, or prove what the desktop compositor displayed. CPU goldens, GPU scene
   references and explicit visible-desktop checks cover those other boundaries.
6. Scope-bound cleanup, including child processes. Failure is nonzero; missing fixtures, empty
   selections and unavailable rendering backends must not silently count as success.

Add a scenario for a production regression when it depends on a sequence or on real runtime
services. Also reduce the defect to the owning library or compiler test when possible. Keep that
focused regression even after the application journey passes: it locates failures much faster.

Start with representative journeys, not every combination of every setting. Expand dimensions
when they activate different code: cold and warm caches, navigation during pending work, a
library larger than the viewport/cache, odd window widths, resize and restore, both themes,
and a supported non-default DPI. Do not describe an unimplemented dimension as covered.

## Current executable coverage

Swag Scope's `stress/previewcache.swg` creates 160 local entries in a temporary Films folder
from real video fixtures and exercises eviction and reload across the 128-texture preview cache.
The separate `integration/browsemedialibrary.swg` follows the user journey through filtering,
viewer open/return, refresh, resize and theme changes, with visible thumbnails and native presentation
as checkpoints. These tests use local fixtures; online artwork, network shares, monitor DPI changes
and visible-compositor behavior are not covered.

Run it on the normal interactive desktop with the commands in [README.md](README.md). Logs identify each
stage. Keep the compiler, program configuration, fixture identities, renderer and failing stage
with a bug report. A deterministic failure is more useful than retries that turn it green.

`integration/playrecentvideo.swg` opens a film through the history input handler, advances beyond
four seconds of real playback, returns to history, and repeats. It checks native presentation
after playback, rather than ending at the first decoded frame. Run release regressions on the
normal interactive desktop:

```powershell
tools/apps.bat test swagscope -bc release --test-file playrecentvideo.swg --test-tag integration.application.journey
```

`integration/choosefolderhistory.swg` follows the Explore command into its folder dialog, opens
the recent-folder popup twice, selects a folder, and waits for Explorer to load it. History includes
an unavailable location: opening the menu must use saved entries without probing each volume.
It checks completed native presentation before selecting the popup row. The logged first-frame
time precedes the synchronous pixel comparison; it is a diagnostic, not a benchmark threshold.

```powershell
tools/apps.bat test swagscope -bc release --test-file choosefolderhistory.swg --test-tag integration.application.journey
```

These commands show test windows on the current desktop and need authorization for that visible
run. They do not send operating-system mouse or keyboard input. Preserve window visibility,
monitor configuration, pointer-driven controls, presentation timing, and runtime worker counts
in reproduction notes. Headless rendering remains useful for bounded library tests and goldens;
it does not establish that the shipped executable works on the normal desktop.

## Anchored popup visual coverage

Run `tools/goldens.bat test` for the shared popup design. Inspect complete images before promoting
changed references; the surrounding field, toolbar and window edge are part of the contract.
The geometry tests in GUI `menu.placement.swg` cover both directions, three button widths,
left/centre/right window placement and 150% DPI. `menu.anchors.swg` checks text alignment and
icon-only centring in front of a real field. A compact floating bar contributes its outer border
to the popup clearance. An underlined inline choice paints only its text line as selected.

| Production openers | Golden coverage |
| --- | --- |
| GUI breadcrumb children and ancestors, file/folder navigation | `breadcrumb.swg`, `filedlg.swg`; native Scope `choosefolderhistory.swg` |
| GUI menu bar, icon/text/mixed buttons, upward/right-edge menus, left-opening submenus | `menu.swg`, `menu.anchors.swg` |
| GUI appearance and property layout | `appearancebutton.swg`, `properties.swg` |
| GUI option panels, nested pages, keyboard, transitions, detail rows | `optionsheet.swg` |
| Scope Explorer view/sort/kind/artwork and home Clear | `anchoredmenus.swg`: `menus.explorer.*`, `menus.home.clear` |
| Scope image transform/zoom/playback, font ranges, PDF/MIDI/text/code/HTML/hex zoom | `anchoredmenus.swg`: `menus.image.*`, `menus.font.*`, `menus.pdf.*`, `menus.midi.*`, `menus.text.*`, `menus.code.*`, `menus.html.*`, `menus.hex.*` |
| Scope MIDI/text/hex options, document search, video speed/audio/subtitles | `anchoredmenus.swg`: options and video images |
| Scope embedded viewer selection | `viewers/archive/archive.swg`: `menus.archive.viewer` |
| Capture library view/sort/filter/folders, editor size/zoom and pointer context menu | `golden/surface.swg` |
| Vault timeout inside an explanatory paragraph | `golden/mainwindow.swg`: `options.timeout.menu` |

The retained Scope `folderHistoryButton` in the old file-panel header is explicitly hidden by
production layout; its `showFolderHistory` path still uses the shared button overload. Current
folder selection history is exercised through the real FileDlg journey above. Pointer menus and
lens follow-up menus keep their coordinate-based placement. Reading-viewer zoom buttons pass
the actual `IconButton` through `Viewer.pickZoom`, so they share fitting and opening direction.

The retained design uses Raised, a 6 px opener gap, an 8 px body-to-window margin, 30 px menu rows,
and 10 px between a row glyph and its wording. Option panels retain their 34 px setting rows.
Text openers align wording where room permits; icon-only openers and option panels centre the
body. Surface/left-aligned and Ground/centred trials were rejected after contextual rendering:
Surface merged with the dialog, while Ground added unnecessary visual weight.
