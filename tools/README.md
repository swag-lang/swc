# Repository tools

Every launcher in this directory is a Windows batch file. It calls the checkout's existing
compiler directly; launching a tool no longer compiles a Swag script first. Build the compiler
once with `tools\devmode.bat` or `tools\release.bat` before using the launchers.

Run the checkout's own compiler whenever more than one worktree exists. `dm` selects
`bin\swc.dm.exe`; without it, tools use `bin\swc.exe`. Tool compiler calls default to three workers.
Pass `--num-cores` to change compiler parallelism. Workspace tests inherit this count for their
runtime pool and application child compilers, capped at three; zero uses that cap. `SWAG_RUNTIME_THREADS`
overrides the test runtime pool. Other compiled programs manage their own runtime threads.
Compiler options can be forwarded after the command and module.

For application iteration, use the default `bin\swc.exe` by omitting `dm` or `-DevMode`. Reserve
`swc.dm.exe` for debugging compiler problems. `-bc` and `-Configuration` select the compiled
program configuration independently.

## Shared Windows and Linux launchers

Workspace commands and test selection live in `tool.py` and require Python 3.9 or newer.
The Windows `tests.bat`, `unittests.bat`, and `_tool.bat` entry points delegate to it through
`python` on PATH. Their existing arguments remain valid; `std.bat`, `apps.bat`, `examples.bat`
and `reference.bat` keep using `_tool.bat`. On Linux, call the same engine with `python3`:

```sh
python3 tools/tool.py unittests dm sema
python3 tools/tool.py std test core
python3 tools/tool.py apps test swagcapture
python3 tools/tool.py examples test gui1
python3 tools/tool.py tests dm
```

The default compiler is the checkout's `bin/swc[.exe]` or `bin/swc.dm[.exe]` with `dm`.
`SWC_COMPILER` and `SWC_DEVMODE_COMPILER` can select an external installation with its runtime.
These direct commands use normal workspace outputs and caches. Tests default to three compiler
workers; explicit compiler options retain precedence. Runtime and child-compiler worker defaults
are capped at three, and an existing `SWAG_RUNTIME_THREADS` is preserved.
The complete `tests` campaign includes C++ tests with `dm`, then every compiler input suite,
workspace fixtures, standard modules, examples, applications and reference tests. It stops on
failure and preserves the failing exit status. Dynamic-library fixtures use the host extension;
WinFsp packaging runs only on Windows. Python routing tests cover both host command plans;
the PowerShell probes under `tools/tests` exercise the Windows entry points themselves.

## Workspaces

```text
tools\std.bat [dm] [build|test] [module] [options...]
tools\examples.bat [dm] [build|run|test|smoke] [module] [options...]
tools\apps.bat [dm] [build|run|test|smoke] [application] [options...]
tools\reference.bat [dm] [build|test] [options...]
tools\scripts.bat [dm] [run|smoke] [script] [options...]
```

Examples:

```text
tools\examples.bat run gui2
tools\apps.bat test swagcapture --test-file files.swg
tools\std.bat dm test gui --test-tag golden
tools\scripts.bat snake
```

Use `-bc release` or `-bc devmode` to select a program configuration. `--debug`,
`--test-file`, `--test-tag`, `--run-arg`, `--frames`, and other compiler options are forwarded.
`scripts.bat smoke` recognizes a script's imports and setup, then runs its native executable
with the smoke frame budget, isolation arguments, and executable timeout.
For module and application tests, `--test-file` and `--test-tag` select which tests execute; the complete
owning module is still compiled. Standard module and application tests use native executables,
which the compiler reuses while their inputs and dependencies are unchanged. Standard module
tests override the library artifact kind only for the selected test module; dependencies retain
their normal library artifacts. Add `--test-jit --no-test-native` to exercise the JIT explicitly.
Compiler JIT suites and reference tests retain their existing execution modes.
Workspace test launchers set `SWAG_RUNTIME_THREADS` from
`--num-cores`, capped at three, unless that environment variable is already defined. The setting
is local to the launcher and its children. Application helper processes inherit the same capped
count when testing the entire application workspace.
`--all-cfg` and `apps run --async` are not supported by the batch launchers; run each configuration
separately.
For a selected workspace module, `--rebuild-module` forces only that module and reuses
current dependencies. `--rebuild` forces the module and its dependency closure.

### Limit runtime threads

Set `SWAG_RUNTIME_THREADS` before launching a compiled program or its test executable:

```powershell
$env:SWAG_RUNTIME_THREADS = '2'
tools\apps.bat test swagcapture --test-file files.swg
# An already built test executable honors the same variable when launched from its prepared directory.
.\app.test.exe
Remove-Item Env:SWAG_RUNTIME_THREADS
```

The runtime reads the ceiling once when it starts the process pool. It limits the shared
pool used by tasks and `parallel for`, including later `Swag.setWorkerCount()` requests and work
submitted by shared libraries. The main thread, dedicated executors, and foreign-library threads
are additional; this is a pool-size ceiling, not a CPU percentage or a process-wide thread limit.
Unset, empty, or `0` keeps the automatic hardware policy. Other values must contain up to ten
decimal digits with a value from 1 through 4294967295; malformed or overflowing values stop the
program when the pool starts.
The hardware and runtime maximum still apply. Existing binaries need to be rebuilt with this
runtime before they honor the variable.

## Compiler suites and campaigns

### Frequent application and rendering coverage

`coverage.bat` separates frequent functional feedback from deliberate stress cases, complete CPU
image references and driver parity checks. It runs existing tests and retains their assertions; no
image tolerance or golden is changed by choosing a suite.

```text
tools\coverage.bat -DevMode
tools\coverage.bat -Workspace apps -Module swagscope
tools\coverage.bat -Suite gpu -Workspace apps -Module swagscope
tools\coverage.bat -DevMode -Suite stress
tools\coverage.bat -DevMode -Suite goldens
tools\coverage.bat -DevMode -Suite parity
tools\coverage.bat -DevMode -Suite full
```

| Suite | Backend and coverage | Environment / frequency |
| --- | --- | --- |
| `fast` (default) | GPU hosts by default; all ordinary standard-module and application tests except `golden` and `stress` | Workstation or CI, frequent iteration |
| `gpu` | Same functional selection using offscreen OpenGL hosts | GPU backend validation and focused rendering scenarios |
| `stress` | Selected GPU or CPU hosts; tests tagged `stress`, including large inputs and scale boundaries | Scheduled or focused performance and scale checks |
| `goldens` | Complete repository `golden` campaign on the selected renderer | Controlled CI environment, rendering changes and scheduled runs |
| `parity` | Pixel tests tagged `integration.renderer.opengl`, including CPU/GPU comparisons | GPU machine, renderer changes and scheduled runs |
| `full` | All standard-module and application tests, including goldens and stress, on the selected renderer | Complete functional/visual pass before integration |

`-Workspace std|apps -Module <name>` and `-TestFile <substring>` focus the functional suites.
`-Configuration devmode|release` selects the program preset; goldens are recorded in devmode.
Each workspace reports elapsed wall time including compilation. Shared-machine admission rules
still apply. Integration tests for native windows, application journeys, networks and drivers
keep their explicit launchers; `full` is not the compiler or privileged integration campaign.

`HeadlessHost` uses GPU hosts by default. `-Renderer cpu` opts into CPU rendering for CI or cloud
machines without a usable graphics device; direct compiler test commands can set
`SWAG_TEST_RENDERER=cpu`. GPU uses an invisible drawable and render targets, with no desktop
presentation. OpenGL must initialize successfully; there is no automatic CPU fallback. Pixel's
explicit CPU renderer tests continue testing CPU in either environment. Goldens run on the selected
renderer, so review and update references only after investigating a mismatch.

Keep test surfaces proportional to the assertion. Decoder and cache tests should use compact
images and scenes that still exercise every branch and keep all compared content visible.
Reserve large images for explicit dimension, tiling, DPI, memory-budget and stress boundaries;
do not repeat a desktop-sized render merely to check that a decoded page is valid. Goldens
should show the smallest complete, readable surface that owns the regression. Changing their
size still requires reviewing each new reference.

Use `HeadlessHost.renderSettled(wnd)` to finish animations and capture their final frame.
It avoids repainting an unchanged frame after `settleAnimations`. Keep explicit consecutive
`render` calls when repainting or retained caches are the behavior under test.

Tag inclusion is an exact match. Repeating `--test-tag` forms a union; `--test-tag !golden`
excludes that tag, with exclusions taking precedence. Exclusions alone retain ordinary tests
and do not enable `integration.*`. File filters still intersect the tag selection. Filters
affect execution and reuse the same native test artifact; they do not remove implementation
sources or rebuild a smaller test binary.

### Application integration journeys

`apps.bat smoke` is the bounded startup check of the shipped executable. User journeys belong
in `<application>/src/tests/cases/integration/<plan>.swg`, guarded by `#command ==
Swag.CompilerCommand.Test` and tagged `integration.application.journey`. They use the ordinary
test runner; integration tags keep them out of default headless tests. See
[the scenario contract](application-scenarios.md) for fixtures, checkpoints, and coverage limits.

On Windows, run native scenarios on the normal interactive desktop:

```powershell
tools/apps.bat test swagscope -bc release --test-file browsemedialibrary.swg --test-tag integration.application.journey --run-timeout 60
tools/apps.bat test swagscope -bc release --test-file playrecentvideo.swg --test-tag integration.application.journey --run-timeout 60
tools/std.bat test gui -bc release --test-file presentation.win32.swg --test-tag integration.host.windows --run-timeout 60
```

These commands show real windows and may take focus. Authorization for a native desktop run
covers those windows; the tests call application input handlers without sending operating-system
mouse or keyboard input. Keep native presentation, monitor configuration, and ordinary window
visibility in the reproduction boundary. Use `tools/apps.bat smoke swagscope -bc release` for
the shipped executable's startup smoke. `--run-timeout` bounds the test process; each individual
journey must still finish within its own deadline below 40 seconds.

| Launcher | Purpose |
| --- | --- |
| `unittests.bat [dm] [suite] [options...]` | C++, lexer, parser, semantic, JIT, safety, sanity, native, and workspace input suites |
| `build.bat [dm] [options...]` | Build the standard library, examples, applications, and reference |
| `tests.bat [dm] [options...]` | Run compiler input suites and workspace tests |
| `integrations.bat [dm] [opengl\|windows\|smoke] [options...]` | Run selected tagged integrations or smoke programs |
| `portability.bat` | Check that no Swag script launcher remains under `tools/` |
| `vault.bat [dm]` | Build, launch, and restore the Swag Vault integration |

The former backlog, third-party-notice, and native-import audits are retired. The compiler
workspace suite still runs its standalone inputs, but no longer performs the repository's custom
artifact-layout and cache-invalidation probes. The integration launcher accepts one configuration
per run.

`unittests.bat` applies `-bc` to Swag programs only; internal C++ tests use the DevMode compiler's
own configuration. Parallel C++ fixtures and their child compilers inherit `--num-cores`, capped
at three workers. Fixtures that specifically test sequential behavior keep one worker.
The workspace suite builds its dynamically loaded DLL before running its
consumer. Runner option routing, failure propagation, and fixture ordering are covered by
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/unittests.ps1`.

## Maintenance

| Launcher | Purpose |
| --- | --- |
| `format.bat [dm] [options...]` | Format sources under `bin/` and `bench/src/` |
| `help.bat [dm] [options...]` | Regenerate the standard-library and language-reference pages in `bin/help/` |
| `goldens.bat [dm] test [options...]` | Run tests tagged `golden` |
| `goldens.bat accept` / `python3 tools/tool.py goldens accept` | Promote every reviewed pending `.actual.txt` and `.actual.png` under `bin/` |
| `bench.bat [options...]` | Run the Python benchmark campaign |
| `vsix.bat` | Test and package the VSCode extension |
| `setup.bat` | Add this checkout's `bin/` to the user `PATH` and set `SWAG_PATH` |

The golden campaign discovers `golden` tags in module case sources under `src/tests/cases/` and skips workspaces
that declare no golden tests; quoted tags in reference prose do not select a workspace. Its argument
forwarding, and failure propagation can be checked without a compiler or desktop:
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/goldens.ps1`.

The batch setup does not claim the `.swgs` file association. It updates the user environment;
open a new terminal after running it.

`tools/devmode.bat` builds the DevMode compiler. `tools/release.bat` is an owner-only full-machine
build entry point.
The C++ project uses eight compilation jobs by default; `tools/devmode.bat` keeps code-generation
threads at one per compiler process. Both compiler build scripts accept `SWC_COMPILE_JOBS` for a
different native job count.

DevMode keeps assertions, compiler validators, race checks, allocator checks and C++ tests.
Fields maintained only for debugger inspection are disabled by default in both compiler builds.
For an interactive C++ debugging session, manually set `SWC_DEBUG_MODE` to `1` in `src/pch.h`
and rebuild the compiler. This restores reference debug pointers, token locations and AST
visitor inspection fields. Reset it to `0` and rebuild when finished. There is no additional
build configuration or executable; compiler PDB settings remain a separate manual choice.
This define concerns debugging the compiler itself; the compiler's `--debug` option concerns
debug information in the Swag program it generates.
