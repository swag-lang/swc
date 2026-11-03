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

Swag Scope's `stress/previewcache.swg` creates 160 local entries in a temporary Films folder
from real video fixtures and exercises eviction and reload across the 128-texture preview cache.
The separate `integration/browsemedialibrary.swg` follows the user journey through filtering,
viewer open/return, refresh, resize and theme changes, with visible thumbnails and native presentation
as checkpoints. These tests use local fixtures; online artwork, network shares, monitor DPI changes
and visible-compositor behavior are not covered.

Run it with the private-desktop launcher documented in [README.md](README.md). Logs identify each
stage. Keep the compiler, program configuration, fixture identities, renderer and failing stage
with a bug report. A deterministic failure is more useful than retries that turn it green.
