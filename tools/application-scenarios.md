# Application scenarios

Use complementary test families. A passing startup smoke is not a completed user journey.

| Boundary | What it establishes | Where it lives |
| --- | --- | --- |
| Ordinary tests | Model, decoder, command and layout behavior | `src/tests/scripts/functional/`, with an optional area folder |
| Golden tests | Maintained text/image references | `src/tests/scripts/golden/`, with snapshots in `src/tests/goldens/`, tag `golden` |
| Application scenarios | Native window, real files and workers, event loop, user actions and completed presentation | `src/tests/scripts/smoke/<plan>.smoke.test.swg`, tag `integration.application.smoke` |
| External integration tests | Native-host, driver, hardware or external-service contracts | `src/tests/scripts/integration/<contract>.integration.test.swg`, explicit `integration.*` tag |
| Startup smoke | The shipped executable and published resources start and stop within a budget | `tools/apps.bat [dm] smoke <application>` |

The scenario tag is an opt-in selection of ordinary `#test` functions, not another test language
or a second assertion framework. Keep the test-only guard and keep scenarios out of `#main`.
Keep each family in dedicated files, with `.test.swg` last. Name a smoke file for the complete
user plan, such as `browsemedialibrary.smoke.test.swg`; the first control or screen does not own
the journey. Do not mix ordinary and golden tests in one file. Keep every module test under
`src/tests/scripts/`; preserve viewer-specific grouping with an area folder such as
`src/tests/scripts/functional/viewers/<viewer>/`. Put shared test helpers under
`src/tests/scripts/helpers/`, not in production APIs.
Run the real application window and its normal event loop; do not replace filesystem enumeration,
background workers, decoders or the renderer with fakes in a test intended to cover that path.
Include production initialization such as the application icon and resource registration; redirect
persisted settings into the owned temporary directory. An empty test shell can miss startup failures.
Use the same commands and input handlers as the UI. OS-level input delivery remains a separate
integration boundary: calling an action directly does not test keyboard routing or hit testing.
Native test entry points omit `#main`. An application that relaunches itself as a worker must
dispatch that explicit helper mode before UI startup, as Scope does in `#premain`;
otherwise the child can exit successfully without performing any work. Exercise that protocol
in the scenario instead of replacing the child with an in-process decoder.

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

Swag Scope's `browsemedialibrary.smoke.test.swg` creates 160 local entries in temporary Films and
Pictures folders from four real video fixtures (MJPEG, H.264, Matroska and legacy RV40) and four
image fixtures (PNG, WebP, GIF and TIFF). It scrolls through the film library to fill and evict the
128-texture preview cache, returns to reload evicted previews, changes details/poster modes,
filters, opens a film, returns to the folder, replaces a pending navigation, refreshes Pictures,
resizes to odd dimensions and back, and changes theme. Visible thumbnails and native presentation
are checkpoints. This is local, offline coverage; online artwork, network shares, monitor DPI
changes and visible-compositor behavior are not covered by this journey.

Run it with the private-desktop launcher documented in [README.md](README.md). Logs identify each
stage. Keep the compiler, program configuration, fixture identities, renderer and failing stage
with a bug report. A deterministic failure is more useful than retries that turn it green.
