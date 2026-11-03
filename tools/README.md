# Repository tools

Workspace launchers in this directory are Windows batch files. Each calls the checkout's existing
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

## Linux compiler build

```sh
python3 tools/linux-build.py --build-dir /absolute/path/outside/checkout --configuration devmode
```

This incremental GNU Make build reuses the compiler source inventory in `swc.vcxproj` and selects
Linux OS leaves. It requires GCC 14 or later, supports `--configuration release`, `--cxx`, and
`--jobs 1` through `--jobs 3`, and checks machine load before invoking Make. Objects, dependency
files, the precompiled header and the executable remain under the supplied build directory.
DevMode and Release compilers build on Linux x86-64. The target defaults to the compiler host:
Linux selects the System V C ABI; `--os linux` and `--os windows` override that choice. JIT execution, ELF
executables, GNU static archives and shared modules are available, including transitive imports
and shared runtime initialization. Shared libraries are position-independent and reject dynamic
text relocations; relocated constants become read-only after loading. Native `--debug` emits DWARF 4
source lines, functions, basic types and recorded stack-home variables. Dedicated executable/shared
fixtures pass readelf/addr2line checks, and GDB stepping and variable inspection work. Optimized-away
variables and richer debug records remain unsupported. Runtime panic traces resolve function names
and recorded source locations across executables, static archives and shared libraries without
`--debug`; stripping `.swagdbg` removes those runtime frame names. Linux executable builds reuse eligible
self-contained function objects from `<name>.incremental.elfcache` in the work directory. The cache
checks compiler identity, IR/ABI fingerprints, recorded source coordinates and payload integrity;
`--rebuild`, `--debug`, tests and compile-time native imports disable it. Publication follows a successful
link. Executables with static dependencies also retain a checksummed `<name>.relink.elfcache`: when
only a native dependency changes, the workspace relinks the saved objects against current libraries.
Compiler/API/configuration changes or missing/damaged cache inputs fall back to compilation.

An externally built compiler needs `runtime` beside its executable. `SWAG_PATH` supplies the
standard-module fallback; it does not redirect runtime lookup. From the repository root, prepare
the runtime and invoke Linux workspaces directly:

```sh
mkdir -p /absolute/build/devmode/runtime
cp -a bin/runtime/. /absolute/build/devmode/runtime/
SWAG_PATH="$PWD/bin" /absolute/build/devmode/swc.dm build \
  --workspace bin/std --workspace-module pixel --num-cores 3
SWAG_PATH="$PWD/bin" /absolute/build/devmode/swc.dm test \
  --workspace bin/std --workspace-module pixel --num-cores 3 \
  --artifact-kind executable --no-test-jit --test-tag integration.renderer.opengl
```

The OpenGL integration tests need an X11 display, libEGL.so.1, libGL.so.1,
EGL_EXT_platform_xcb and OpenGL 3.3 compatibility support. They pass with Xvfb and Mesa software
rendering; physical GPU coverage is separate. Core, Ogl, TrueType and Pixel build on Linux.
GUI integration runs under Xvfb/Openbox with a compositor. Capture, Scope and Vault pass native graphical smokes;
complete application workflows and physical desktop/GPU validation remain.

## Linux compiler and standard-module suites

```sh
python3 tools/linux-tests.py lexer --compiler /absolute/build/devmode/swc.dm
python3 tools/linux-tests.py parser --compiler /absolute/build/devmode/swc.dm
python3 tools/linux-tests.py cpp --compiler /absolute/build/devmode/swc.dm
python3 tools/linux-tests.py dynamic-library --compiler /absolute/build/devmode/swc.dm
python3 tools/linux-tests.py std --compiler /absolute/build/devmode/swc.dm --module core --test-file environment.locale.linux.test.swg
python3 tools/linux-tests.py native --compiler /absolute/build/devmode/swc.dm --execution native
python3 tools/linux-tests.py native --compiler /absolute/build/devmode/swc.dm --file-filter global_cache_line_alignment.swg
```

The launcher stages the selected executable and this checkout's runtime in an external temporary
folder, isolates caches with `TMPDIR`, and removes the staging folder afterwards. Each invocation
has its own load-admission check, three compiler workers and a 180-second timeout (`--timeout`
overrides it). Lexer/parser suites include their expected-error inputs. The native suite runs
JIT and native tests by default; `--execution jit` or `--execution native` selects one path.
`--file-filter` narrows standalone source inputs. Source suites force a rebuild in their isolated
cache; the native suite uses the default host target. The C++ suite requires
DevMode; add `--dev-full` to include its filesystem tests. The Linux DevMode full C++ suite
passes 1,780 tests as of 2026-11-03, including ELF linking, native ABI, runtime stack/symbol boundaries and module-publication cases.
The native language suite passes 4,047 tests in each execution mode.
The `dynamic-library` boundary stages Core and the existing runtime-context workspace fixtures.
It builds a shared library and tests native context sharing, initialization, repeated loads,
final-close destruction and reloading through `Core.NativeLibrary`.
The `std` suite copies the standard workspace, including module fixtures and resources, and tests
one `--module` with executable output. It runs JIT and native tests by default; `--execution`
selects either path. Repeat `--test-file` to select module test files while retaining the complete
implementation, and use `--test-tag` for an opt-in integration family. External requirements such
as an X11 display still need to be supplied. Set the launcher's `TMPDIR` to an existing external
disk directory when the system temporary directory is memory-backed and space is limited.
These focused selections do not establish complete Linux support for every `bin/` module.

The Linux desktop-registration integration is native-only because its peer is the generated
executable. It uses private XDG directories and needs GIO, `gio`, `/usr/bin/env`, `chmod` and
`update-mime-database`; it never changes the current user's associations:

```sh
python3 tools/linux-tests.py std --compiler /absolute/build/devmode/swc.dm --module core \
  --execution native --test-file environment.registration.linux.integration.test.swg \
  --test-tag integration.desktop.registration
```

The native-only `integration.desktop.chooser` family requires a private session bus, `gdbus`,
libsystemd and the Python GIO bindings. Start a test-owned bus with
`dbus-daemon --session --fork --print-address=1 --print-pid=1`, retain its address and PID, and run
`/usr/bin/python3 bin/std/modules/core/src/tests/datas/desktop.chooser.peer.py ADDRESS`.
Wait for `READY`, set both `DBUS_SESSION_BUS_ADDRESS` and `SWAG_CHOOSER_PRIVATE_BUS` to that
address, then run:

```sh
python3 tools/linux-tests.py std --compiler /absolute/build/devmode/swc.dm --module core \
  --execution native --test-file environment.chooser.linux.integration.test.swg \
  --test-tag integration.desktop.chooser
```

Terminate the peer and the test-owned bus afterward. The peer never uses the ambient desktop
bus; these checks exercise real descriptor transport and chooser request lifetime, not the
appearance of a desktop application's dialog.

## Linux host primitives

```sh
python3 tools/linux-host.py --configuration devmode
python3 tools/linux-host.py --configuration release
```

This focused Linux x86-64 boundary builds the implemented C++ host services
adapters with a C++23 compiler and library (GCC 14 or later), then runs their native tests.
Use `--cxx /path/to/compiler` to select the compiler. The current baseline is glibc 2.36 and
Linux 5.9 with pidfds, subreapers and `close_range` permitted. Python 3, procfs, and cgroup v2 are needed
for machine-load admission; the launcher checks independently before building and testing and
stops with exit code 2 when the machine needs to wait. Compilation is sequential. Builds and
fixtures use a temporary directory outside the checkout and are removed on completion.

The tests cover executable-page publication and patching, page protection, concurrent proximity
allocations, arena exhaustion, release, mapped-cache lifetime across replacement and unlink,
common file I/O and atomic publication, directory-lock aliases and replacement, TLS isolation,
shared-library loading, terminal capabilities/redirection, native stack capture and ELF symbols,
guarded signal stacks and stack overflow, generated DWARF frames and registration lifetime,
C++ cleanup across generated frames (ordinary exceptions and repeated hardware faults),
process arguments/output, timeouts and descendant cleanup after caller death or callback failure,
file-user diagnostics (including mappings without descriptors), safe diagnostic reads, and explicitly
configured Windows cross-toolchain discovery. These discovery fixtures validate paths and failures,
not execution of Windows linker tools or production of a runnable Linux artifact.
A separate fixture prevents CPU detection from initializing and verifies that the startup guard
rejects the host before C++ constructors run, even when built for x86-64-v3. A native C++ shared-library fixture
is built in the external temporary directory; it does not stand in for the Swag foreign-call ABI.
`devmode` enables host assertions; `release` checks optimized code without those assertions.
These are host-test build modes, not Swag program configurations. This launcher does not build
`swc`, execute Swag sources, or establish Linux target-ABI support. See
[the capability inventory](../bin/PORTABILITY.md#host-capability-inventory) and
[the portability backlog](../backlog/platform.portability.md) for the remaining boundaries.

The admission check's host/container pressure cases run with
`python3 tools/tests/test_linux_host_admission.py` after a fresh machine-load check.

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
tools\apps.bat test swagcapture --test-file files.test.swg
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

### Limit runtime threads

Set `SWAG_RUNTIME_THREADS` before launching a compiled program or its test executable:

```powershell
$env:SWAG_RUNTIME_THREADS = '2'
tools\apps.bat test swagcapture --test-file files.test.swg
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

### Application smoke scenarios

`apps.bat smoke` is the bounded startup check of the shipped executable. User journeys belong
in `<application>/src/tests/scripts/smoke/<plan>.smoke.test.swg`, guarded by `#command ==
Swag.CompilerCommand.Test` and tagged `integration.application.smoke`. They use the ordinary
test runner; integration tags keep them out of default headless tests. See
[the scenario contract](application-scenarios.md) for fixtures, checkpoints, and coverage limits.

On Windows, run a scenario without taking focus or showing test windows on the user's desktop:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-desktop.ps1 -Module swagscope -TestFile browsemedialibrary.smoke.test.swg
```

The launcher creates a private desktop without switching to it, invokes `apps.bat test`, and
retains its log under the printed temporary directory. A job owns the compiler and all children;
the process timeout is 15 minutes including compilation, and `-RunTimeout` bounds each test
executable (60 seconds by default). `-Configuration release` selects the program configuration;
omitting `-DevMode` selects `swc.exe`. `-Workspace std -Module gui -TestTag integration.host.windows`
selects native GUI integration tests instead. It never automates the user's mouse or keyboard.
Use `-Action smoke -Module swagscope` for the shipped executable's startup smoke on the
same private-desktop boundary, without test filters.

Native GPU rendering still depends on the installed driver. A private desktop does not reproduce
the visible desktop compositor, monitor changes, or live border dragging. Keep those tests in an
explicit interactive integration campaign.

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
| `goldens.bat accept` | Promote every pending `.actual.txt` and `.actual.png` under `bin/` |
| `bench.bat [options...]` | Run the Python benchmark campaign |
| `vsix.bat` | Test and package the VSCode extension |
| `setup.bat` | Add this checkout's `bin/` to the user `PATH` and set `SWAG_PATH` |

The golden campaign discovers tags in module test files (`*.test.swg`) and skips workspaces
that declare no golden tests; quoted tags in reference prose do not select a workspace. Its argument
forwarding, and failure propagation can be checked without a compiler or desktop:
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/goldens.ps1`.

The batch setup does not claim the `.swgs` file association. It updates the user environment;
open a new terminal after running it.

`tools/devmode.bat` builds the DevMode compiler. `tools/release.bat` is an owner-only full-machine
build entry point.

DevMode keeps assertions, compiler validators, race checks, allocator checks and C++ tests.
Fields maintained only for debugger inspection are disabled by default in both compiler builds.
For an interactive C++ debugging session, manually set `SWC_DEBUG_MODE` to `1` in `src/pch.h`
and rebuild the compiler. This restores reference debug pointers, token locations and AST
visitor inspection fields. Reset it to `0` and rebuild when finished. There is no additional
build configuration or executable; compiler PDB settings remain a separate manual choice.
This define concerns debugging the compiler itself; the compiler's `--debug` option concerns
debug information in the Swag program it generates.
