# Application scenarios

Use complementary test families. A passing startup smoke is not a completed user journey.

Every `.swg` file that defines a test case belongs under `src/tests/cases/`. The first directory
below `cases/` names the test family. `src/tests/helpers/` contains shared setup and assertions,
`src/tests/datas/` contains fixture inputs, and `src/tests/goldens/` contains reference outputs;
none of these three directories defines a test case. A viewer folder, when useful, goes below the
family: `cases/<family>/viewers/<viewer>/`. A plan spanning several viewers stays at the family root.

| Boundary | What it establishes | Where it lives |
| --- | --- | --- |
| Ordinary tests | Model, decoder, command and layout behavior | `src/tests/cases/functional/`, with an optional area folder |
| Golden tests | Maintained text/image references | `src/tests/cases/golden/`, with snapshots in `src/tests/goldens/`, tag `golden` |
| Application journeys | Native window, real files and workers, event loop, user actions and completed presentation | `src/tests/cases/journeys/<plan>.swg`, tag `integration.application.journey` |
| Desktop input journeys | Native window driven by simulated OS pointer and keyboard input, including hit testing, focus and shortcuts | `src/tests/cases/desktop/<plan>.swg`, tag `integration.desktop.input` |
| External integration tests | Native-host, driver, hardware or external-service contracts | `src/tests/cases/integration/<contract>.swg`, explicit `integration.*` tag |
| Stress tests | Large-volume, scale, concurrency and lifecycle limits | `src/tests/cases/stress/<subject>.swg`, `stress` or a scoped `*.stress` tag |
| Startup smoke | The shipped executable and published resources start and stop within a budget | `tools/apps.bat [dm] smoke <application>` |

Integration tags opt in ordinary `#test` functions; they are not another test language or assertion
framework. Keep the test-only guard and keep journeys out of `#main`. Each journey file contains
exactly one `#test` and is named for the complete user plan, such as
`journeys/browsemedialibrary.swg`; the first control or screen does not own the journey.
`integration` remains the opt-in tag family for tests that need native or external services;
the folders name the two ways a user plan is driven. Reserve `end-to-end` for a separate process
that launches and controls the shipped application executable.
The journey concept and plan format are shared across applications; setup, waiting, and cleanup
helpers stay in the owning application's `src/tests/helpers/` when their code depends on that app.
Do not mix test types in one file. Keep ordinary, golden, external integration and stress tests
under `src/tests/cases/` in their dedicated folders. Preserve viewer-specific grouping with an area folder such as
`src/tests/cases/functional/viewers/<viewer>/` or `src/tests/cases/journeys/viewers/<viewer>/`.
Keep cross-viewer plans at the family root. Put shared test helpers under `src/tests/helpers/`,
not in production APIs. A smoke test is the bounded application startup check, not a user journey.
Run the real application window and its normal event loop; do not replace filesystem enumeration,
background workers, decoders or the renderer with fakes in a test intended to cover that path.
Include production initialization such as the application icon and resource registration; redirect
persisted settings into the owned temporary directory. An empty test shell can miss startup failures.
Use the same commands and input handlers as the UI. An application journey calls those handlers
in process; a desktop input journey injects OS input and also tests hit testing, focus and shortcut
routing. Keep the user plan in one test file and drive it with `Gui.Testing.DesktopInput`.
Its Windows and Linux backends inject OS input. Before a desktop pointer action, derive its point
from the current layout and check the native foreground
window, the OS window under the pointer and the GUI hit target. Fail with the obstructing stage if
the target cannot receive input. Keep desktop input tests on an interactive desktop reserved for
that run; OS input is shared state and cannot safely run concurrently with another UI driver.
Maintain fixed key combinations only when they are part of the user contract. For a journey whose
contract is an action regardless of its configured shortcut, resolve the current binding instead.
Native test entry points omit `#main`. Exercise background work through the production task and
decoder path rather than replacing it with a fake in the scenario. Write a portable journey in an
unsuffixed `.swg` file when the user task works on both Windows and Linux. Isolate OS input or
presentation checks in a platform-specific helper; reserve `.win32.swg` and `.linux.swg` plans
for behavior that is genuinely platform-specific.

## Write an executable test plan

Give each independently finishable journey its own file and its own `#test`, with the plan visible
in this order:

1. A short comment naming the user's task and the regression it protects.
2. Owned temporary data, seeded from the application's immutable `src/tests/datas` fixtures or
   generated as a small deterministic image when its pixels are the entire input contract.
   Large libraries may repeat small real files; state that this stresses volume and lifecycle,
   not format diversity. Never depend on a personal drive, live service, or private document.
3. Explicit actions followed by observable expectations: selected file, item count, scroll
   position, active document, finished thumbnail, saved bytes, and preserved state on return.
4. Readiness conditions and bounded deadlines. Pump the actual event loop while waiting; native
   `Application.runFrame` already yields on idle turns, so do not add fixed sleeps or frame counts
   to a journey wait. Report the stage that timed out. Keep each test below 40 seconds; split
   longer plans into independent journeys rather than raising every timeout.
5. A rendering checkpoint where visual corruption is a risk. Keep platform-specific pixel checks
   outside a portable journey helper. On Windows,
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

Swag Capture keeps portable plans in `cases/journeys/`, including `annotatereopen.swg`,
`exportreopen.swg`, `importreopen.swg`, `searchlibrary.swg`, and
`transformreopen.swg`. Each uses `helpers/capturejourney.swg` for a private native
window, library, event-loop readiness deadlines, render-failure checks, and cleanup.
The synthetic image plans exercise the editor and document lifecycle, while the
OS screen-grab contracts remain separate platform integrations.
Its portable `cases/desktop/drawandundo.swg` clicks the Shape tool, drags on the canvas, and uses
Control+Z and Control+Y through the shared Windows or Linux desktop input backend.
`cases/desktop/deleteandundo.swg` covers Delete and undo on a preselected mark through native keyboard input.

Swag Scope's `cases/stress/previewcache.swg` creates 160 local entries in a temporary Films folder
from real video fixtures and exercises eviction and reload across the 128-texture preview cache.
The separate `cases/journeys/browsemedialibrary.swg` follows the user journey through filtering,
viewer open/return, refresh, resize and theme changes, with visible thumbnails and native presentation
as checkpoints. These tests use local fixtures; online artwork, network shares, monitor DPI changes
and visible-compositor behavior are not covered.

Run it on the normal interactive desktop with the commands in [README.md](README.md). Logs identify each
stage. Keep the compiler, program configuration, fixture identities, renderer and failing stage
with a bug report. A deterministic failure is more useful than retries that turn it green.

`cases/journeys/viewers/video/playrecentvideo.swg` opens a film through the history input handler, advances beyond
four seconds of real playback, returns to history, and repeats. It checks native presentation
after playback, rather than ending at the first decoded frame. Run release regressions on the
normal interactive desktop:

```powershell
tools/apps.bat test swagscope -bc release --test-file cases/journeys/viewers/video/playrecentvideo.swg --test-tag integration.application.journey
```

`cases/journeys/choosefolderhistory.swg` follows the Explore command into its folder dialog, opens
the recent-folder popup twice, selects a folder, and waits for Explorer to load it. History includes
an unavailable location: opening the menu must use saved entries without probing each volume.
It checks completed native presentation before selecting the popup row. The logged first-frame
time precedes the synchronous pixel comparison; it is a diagnostic, not a benchmark threshold.

```powershell
tools/apps.bat test swagscope -bc release --test-file choosefolderhistory.swg --test-tag integration.application.journey
```

These commands show test windows on the current desktop. They do not send operating-system mouse
or keyboard input; `cases/desktop/` tests do. Preserve window visibility,
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
