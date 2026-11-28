# Repository tools

Workspace launchers in this directory are Windows batch files. Each calls the checkout's existing
compiler directly; launching a tool no longer compiles a Swag script first. Build the compiler
once with `tools\devmode.bat` or `tools\release.bat` before using the launchers.

Run the checkout's own compiler whenever more than one worktree exists. `dm` selects
`bin\swc.dm.exe`; without it, tools use `bin\swc.exe`. Tool compiler calls detect the available
processor count. Pass `--num-cores` to change compiler parallelism. Workspace tests inherit this
count for their runtime pool and application child compilers. `SWAG_RUNTIME_THREADS` overrides the
test runtime pool. Other compiled programs manage their own runtime threads.
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
python3 tools/tool.py tests functional -bc release
```

The default compiler is the checkout's `bin/swc[.exe]` or `bin/swc.dm[.exe]` with `dm`.
`SWC_COMPILER` and `SWC_DEVMODE_COMPILER` can select an external installation with its runtime.
These direct commands use normal workspace outputs and caches. Tests detect the available processor
count; explicit compiler options retain precedence. An existing `SWAG_RUNTIME_THREADS` is preserved.
The default `tests` pass is `functional`. It includes C++ tests with `dm`, compiler input suites,
workspace fixtures and the ordinary tests of the standard modules, examples, applications and
reference. It stops on failure by default and preserves the failing exit status.
WinFsp packaging runs only on Windows. Python routing tests cover both host command plans;
the PowerShell probes under `tools/tests` exercise the Windows entry points themselves.

Program configurations and `--rebuild`/`--rebuild-module` select the Swag stages' builds.
Internal C++ tests manage their own compiled fixtures and rebuilds.

Compiler input suites keep their generated artifacts and intermediates under
`bin/unittests/.output`, separated by suite. Explicit `--out-dir` and `--work-dir` options override
those defaults.

## Local Linux session from Windows

With Ubuntu WSL 2 installed and a clone at `~/swag/swc`, open `tools\linux.bat` to enter
an interactive Linux shell in that clone. The complete repository, including `tools/`, lives
there; no separate copy of the tools is needed. Inside the shell, the same workspace launcher
names and arguments work on both systems:

```sh
apps.bat build swagscope
apps.bat test swagscope --test-file commandpresentation.swg
apps.bat run swagscope
std.bat test gui --test-file appearancebutton.swg
```

In Windows CMD, `.bat` runs the batch launcher. In the Linux shell, Bash maps that same command
to the shared Python tool engine. `dm`, `-bc release`, `--test-file` and the other compiler options
keep their positions and meaning. `release.bat` builds the Linux Release compiler and refreshes its
runtime beside it. The session sets `SWAG_SOURCE`, `SWAG_PATH`, `SWC_BUILD_DIR`, `SWC_COMPILER`,
`SWC_DEVMODE_COMPILER`, `TMPDIR` and the compiler search path. WSLg displays Linux application
windows on the Windows desktop. The underlying Python interface remains available for scripting.

From Windows:

```bat
tools\linux.bat
tools\linux.bat sync
tools\linux.bat build
tools\linux.bat --release build
tools\linux.bat test compiler
tools\linux.bat test std --module core --execution native
tools\linux.bat --release test apps --module swagscope --execution native
tools\linux.bat exec pwd
```

`sync` fetches committed `master` changes from the Windows checkout containing this launcher,
then fast-forwards the Linux checkout. It never copies uncommitted edits. Commit Windows work
before syncing, then build the Linux compiler. Linux commits that diverge from Windows `master`
need an explicit merge or rebase. Build and workspace outputs remain separate on each OS.

Defaults are distribution `Ubuntu-24.04`, source `~/swag/swc` and build directory `~/swag/build`.
Override them with `SWC_WSL_DISTRO`, `SWC_WSL_SOURCE` and `SWC_WSL_BUILD` in Windows; source/build
values are absolute Linux paths. The source clone and GCC 14 dependencies must already exist.
`build` refreshes the runtime beside the selected compiler. `test` uses the isolated Linux
campaign launcher and the current WSLg display; display-server-specific or physical-device
integration tests still require their documented environment. Automated headless graphics can
use Xvfb/Openbox/Picom as described below.

## Linux compiler build

```sh
python3 tools/linux-build.py --build-dir /absolute/path/outside/checkout --configuration devmode
```

This incremental GNU Make build reuses the compiler source inventory in `swc.vcxproj` and selects
Linux OS leaves. It requires GCC 14 or later, supports `--configuration release`, `--cxx`, and
`--jobs` (default: detected processor count). Objects,
dependency files, the precompiled header and the executable remain under the supplied build
directory.
DevMode and Release compilers build on Linux x86-64. The target defaults to the compiler host:
Linux selects the System V C ABI. Use `--os linux` or `--os windows` to select the target.
The compiler includes transitive source dependencies in each executable or JIT program and
initializes one runtime for that program. `swc` links ELF executables internally and uses GNU
archives and shared libraries as native linker inputs. GCC builds `swc` itself. The installed
compiler uses system runtime libraries and links without invoking external tools.

Native `--debug` emits DWARF 4 source lines, functions, basic types and recorded stack-home
variables. Executable fixtures pass readelf and addr2line checks. GDB supports stepping and
inspection of recorded variables. Runtime panic traces use `.swagdbg` for function names and
source locations even when `--debug` is off. Without `--debug`, final ELF
executables omit `.symtab` and `.strtab`. Dynamic symbols, unwind data and
`.swagdbg` remain available. For smaller binaries, `--no-runtime-symbols` omits
`.swagdbg` on Linux and Windows.

Executable builds reuse eligible function objects from the cache in the work
directory. Reuse checks compiler identity, IR and ABI fingerprints, recorded
source coordinates and payload integrity. The compiler writes the cache after
the executable links successfully.

An externally built compiler needs `runtime` beside its executable. `SWAG_PATH` supplies the
standard-module fallback; it does not redirect runtime lookup. From the repository root, prepare
the runtime and invoke Linux workspaces directly:

```sh
mkdir -p /absolute/build/devmode/runtime
cp -a bin/runtime/. /absolute/build/devmode/runtime/
SWAG_PATH="$PWD/bin" /absolute/build/devmode/swc.dm sema \
  --workspace bin/std --workspace-module pixel
SWAG_PATH="$PWD/bin" /absolute/build/devmode/swc.dm test \
  --workspace bin/std --workspace-module pixel \
  --no-test-jit --test-tag integration.renderer.opengl
```

To build Windows applications that make Windows foreign calls at compile time, run the Windows
compiler under Wine. The Linux compiler can also emit PE executables with `--os windows`.
Compile-time foreign calls need the operating system that provides the native library.

`linux-build.py --target windows` builds the Release Windows compiler with LLVM-MinGW, using the
same source manifest. It links the C++ runtime into the compiler; only Windows
system DLLs are needed to run it. Install LLVM-MinGW and Wine outside the checkout, then use:

```sh
python3 tools/linux-build.py --build-dir /absolute/build --configuration release \
  --target windows --cxx /absolute/llvm-mingw/bin/x86_64-w64-mingw32-clang++
mkdir -p /absolute/build/windows/release/runtime
cp -a bin/runtime/. /absolute/build/windows/release/runtime/
SWAG_PATH='Z:\absolute\repo\bin' WindowsSdkDir='Z:\absolute\windows-sdk' \
  WindowsSDKVersion=10.0.26100.0 wine /absolute/build/windows/release/swc.exe build \
  --workspace 'Z:\absolute\repo\bin\apps' --workspace-module swagscope \
  -bc release --rebuild
```

Use the version directory present under the SDK's `Lib` directory. Both `um/x64` and `ucrt/x64`
import libraries are needed. Wine maps absolute Linux paths through drive `Z:` by default. This
produces the normal Windows application, including every viewer; Wine is part of the build host,
not an application dependency. Runtime checks under Wine do not replace tests on a Windows machine.

The OpenGL integration tests need an X11 display, libEGL.so.1, libGL.so.1,
EGL_EXT_platform_xcb and OpenGL 3.3 compatibility support. They pass with Xvfb and Mesa software
rendering; physical GPU coverage is separate. Core, Ogl, TrueType and Pixel build on Linux.
GUI integration runs under Xvfb/Openbox with a compositor. Capture, Scope and Vault pass native graphical smokes;
complete application workflows and physical desktop/GPU validation remain.

## Isolated Linux test campaigns

```sh
python3 tools/linux-tests.py lexer --compiler /absolute/build/devmode/swc.dm
python3 tools/linux-tests.py parser --compiler /absolute/build/devmode/swc.dm
python3 tools/linux-tests.py cpp --compiler /absolute/build/devmode/swc.dm
python3 tools/linux-tests.py dynamic-library --compiler /absolute/build/devmode/swc.dm
python3 tools/linux-tests.py std --compiler /absolute/build/devmode/swc.dm --module core --test-file environment.locale.linux.swg
python3 tools/linux-tests.py native --compiler /absolute/build/devmode/swc.dm --execution native
python3 tools/linux-tests.py native --compiler /absolute/build/devmode/swc.dm --file-filter global_cache_line_alignment.swg
```

To run the complete campaign, provide both compiler executables. The C++ stage uses DevMode;
all other stages use the selected main compiler (Release is recommended for applications):

```sh
python3 tools/linux-tests.py all --compiler /absolute/build/release/swc \
  --dev-compiler /absolute/build/devmode/swc.dm \
  --output-dir /absolute/scratch/linux-tests --keep-going
```

`all` runs the portability check, C++ filesystem tests, lexer/parser/sema normal and error inputs,
JIT, safety, sanity, native, every compiler workspace fixture, and every module in std, examples,
apps and reference. `compiler` selects only the compiler suites and workspace fixtures.
The command builders are shared with `tool.py` and the Windows batch entry points.
The sandbox workspace fixture runs in JIT. Script fixtures use assertions and the process exit status.

The launcher stages this checkout's sources, runtime, fixtures and compilers in a new external
folder. It isolates caches with `TMPDIR`.
Campaigns use caches from that snapshot. Focused selections force rebuilds.
Each compiler invocation has a 900-second timeout (`--timeout` overrides it). Timeout cleanup stops
the owned process tree, including native tests that create separate sessions.
Sources, caches, one log per stage, `plan.json` and `report.json` remain in the printed directory
on success or failure. `--output-dir` must not exist and must be outside the checkout. Without
it, a new temporary directory is retained. `--keep-going` continues independent stages after
errors; a dependent stage whose prerequisite failed is reported as blocked. Any failure, timeout,
blocked stage or unfinished campaign returns a nonzero status. `--dry-run` records the plan
without executing tests.

`std`, `examples`, `apps`, `reference` and `workspace` accept an optional `--module`.
Repeat `--test-file` or `--test-tag` to select tests without dropping implementation files.
`--file-filter` narrows standalone compiler-suite inputs. `--build-cfg` selects the program
configuration independently of the compiler executable. Standard/application campaigns run
native tests; examples, reference and the native language suite run both execution modes.
For compatibility, a focused `std --module` runs both modes by default. `--execution` overrides
these defaults. The focused `cpp` suite requires DevMode; add `--dev-full` for filesystem tests.
`dynamic-library` runs the Core FFI test against the system math library.

The Linux `all` campaign includes ordinary, golden and stress cases. Cases tagged `integration.*`
are opt-in. Select them with `--test-tag` and supply their external services or
hardware. Platform guards restrict native API tests to their owning operating system.
Golden failures are never promoted or ignored; `SWAG_GOLDEN_CONTINUE=1` is rejected.
GUI and GPU-backed golden cases need an X11 display and the libraries described above.
Set the launcher's `TMPDIR` to an external disk directory if the system temporary directory is
memory-backed. A runnable campaign does not imply every Linux test currently passes.

The Linux desktop-registration integration is native-only because its peer is the generated
executable. It uses private XDG directories and needs GIO, `gio`, `/usr/bin/env`, `chmod` and
`update-mime-database`; it never changes the current user's associations:

```sh
python3 tools/linux-tests.py std --compiler /absolute/build/devmode/swc.dm --module core \
  --execution native --test-file environment.registration.linux.swg \
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
  --execution native --test-file environment.chooser.linux.swg \
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
Linux 5.9 with pidfds, subreapers and `close_range` permitted. Compilation is sequential. Builds
and fixtures use a temporary directory outside the checkout and are removed on completion.

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

## Workspaces

```text
tools\std.bat [dm] [sema|build|test] [module] [options...]
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

The standard-library launcher defaults to `sema`. It checks every standard source group,
including each group's dependencies. Supply a module name to check one group. `build` without a
module selection processes the workspace's executable targets. A named source group can also
be checked explicitly with `build`.

Use `-bc release` or `-bc devmode` to select a program configuration. `--debug`,
`--test-file`, `--test-tag`, `--run-arg`, `--frames`, and other compiler options are forwarded.
`scripts.bat smoke` recognizes a script's imports and setup, then runs its native executable
with the smoke frame budget, isolation arguments, and executable timeout.

`python tools/capture-web.py` runs the Windows browser/video/audio integration for Swag Capture
on an interactive desktop with Chrome. Use `--browser <executable>` to select its installation.
It serves the owned `webcapture.webm` fixture over loopback HTTP, records six seconds through
the native selector and recording HUD, reopens the saved capture, and plays it in the editor.
The browser is paused and muted before a second WASAPI loopback checks the editor's actual
440 Hz output through a full playback loop and pause. Every MP4 picture is decoded and the
native presentation bitmap is checked.
This is an in-process application integration; external mouse hit testing is not covered.
The runner explicitly enables real screen pixels (`swag.capture.native-screen=true`) and
native audio output (`swag.audio.native-output=true`); ordinary tests retain their simulated
desktop and silent engine. Files and settings stay sandboxed. The runner waits for the source
tone to disappear from the measured output before checking replay. The runner owns and removes
its temporary browser profile;
`test.log`, `browser.json`, `sandbox/web.mp4`, decoded pictures and the editor screenshot
remain in the printed temporary evidence directory, or the external directory passed with
`--output`. This integration is opt-in and is not part of ordinary coverage.

For a native 1080p performance check, supply `--width 1920 --height 1080 --media <movie.mp4>`
and `--stall-ms 0 --max-missed-frames 2`. The source must itself be 1920 by 1080 and contain the
440 Hz reference sound. The run reports fresh and repeated slots, readback and encoder work,
queue wait, and sound losses; the missed-slot budget makes a throughput regression fail.
Use `--devmode-compiler` to drive the same Release program with `swc.dm.exe`.
Use `--capture-mode monitor --width 3200 --height 1800 --duration 60` to record the
monitor containing the browser fixture for one minute. `--capture-mode desktop` records
every connected screen; both modes decode the first and last frames and report DXGI work
and missed frame slots. Long runs keep their MP4 in the printed sandbox without making a
second in-memory copy. `--video-quality maximum|balanced|compact` tests the three recording
settings; Balanced is the application default.
Add `--motion-stress` to animate a dense pattern across the browser viewport, then
use `--max-missed-frames` to gate sustained high-motion capture. The runner keeps
the browser video and its reference sound under that pattern. Keep the Windows desktop
unlocked and dismiss the screen saver: DXGI cannot duplicate its output while that desktop
is active, and the full-screen scenario stops after three failed source reads.
`capture-web-source.py --input <1080p-movie> --output <external-source.mp4> --start 30`
prepares an eight-second native-resolution excerpt and reference sound with PyAV and NumPy,
using the codec's automatic thread selection. One reproducible source is Blender Foundation's
[Sintel trailer](https://download.blender.org/durian/trailer/sintel_trailer-1080p.mp4).
Download and generate this media outside the checkout; it is not shipped with the application.

For module and application tests, `--test-file` and `--test-tag` select which tests execute; the complete
owning module is still compiled. Module and application tests run with a twenty-minute `--run-timeout` unless one is given:
the compiler's five-minute default suits one program, not a whole suite in one process. Standard module and application tests use native executables,
which include their source dependencies. The compiler reuses a test executable while its inputs
are unchanged. Add `--test-jit --no-test-native` to exercise the JIT explicitly.
Compiler JIT suites and reference tests retain their existing execution modes.
Workspace test launchers set `SWAG_RUNTIME_THREADS` from
`--num-cores`, or the detected processor count, unless that environment variable is already
defined. The setting is local to the launcher and its children. Application helper processes
inherit the same count when testing the entire application workspace.
`--all-cfg` and `apps run --async` are not supported by the batch launchers; run each configuration
separately.
For a selected workspace module, `--rebuild-module` forces a build and retains eligible
dependency setup caches. `--rebuild` bypasses the compilation caches for the selected target
and its source dependencies. It publishes fresh entries in the shared compiler cache and leaves
entries for other builds available.

Module setup snapshots and compatible function machine code are shared by applications and scripts
through the compiler cache shown by `swc info`. This includes standard-library and project modules.
The `.output` and `.tmp` directories hold artifacts and intermediates for explicit builds or tests.

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
pool used by tasks and `parallel for`, including later `Swag.setWorkerCount()` requests.
The main thread, dedicated executors, and foreign-library threads
are additional; this is a pool-size ceiling, not a CPU percentage or a process-wide thread limit.
Unset, empty, or `0` keeps the automatic hardware policy. Other values must contain up to ten
decimal digits with a value from 1 through 4294967295; malformed or overflowing values stop the
program when the pool starts.
The hardware and runtime maximum still apply. Existing binaries need to be rebuilt with this
runtime before they honor the variable.

## Compiler suites and campaigns

### Repository test passes

```text
tools\tests.bat functional -bc release
tools\tests.bat goldens
tools\tests.bat smoke -bc release
tools\tests.bat integrations -bc release
```

| Pass | Coverage |
| --- | --- |
| `functional` (default) | Compiler suites and workspace tests, including `stress` cases. Goldens and opt-in integrations have dedicated passes. |
| `goldens` | Every `golden` case, with exact CPU references in Release. |
| `smoke` | Bounded startup of the examples and applications, plus the example scripts on Windows. |
| `integrations` | OpenGL, native host tests, application journeys and desktop input. |

On Linux, use `python3 tools/tool.py tests` with the same pass and options. `--keep-going` continues
independent stages after a failure. The tagged passes `goldens` and `integrations` always
continue with the other modules. Use `--test-file <substring>` to focus these passes.

`tools\tests.bat integrations --list` lists integration tags and their source modules for the host.
The default groups need a compatible graphical session. Use `--test-tag integration.<name>` to
select explicit groups in place of the defaults. The compiler applies the case guards at build time.
Specialized integrations may also need fixtures, compile-time `--tag` options, privileges or hardware.
Use their documented launchers for GPU reset, capture fixtures and privileged Vault scenarios.

### Focused application and rendering coverage

`coverage.bat` selects `functional` by default. Use `-Workspace std|apps -Module <name>` and
`-TestFile <substring>` to focus `functional`, `goldens` or `parity`.

```text
tools\coverage.bat -Configuration release -Suite functional -Workspace apps -Module swagscope
tools\coverage.bat -Configuration release -Suite goldens -Workspace std -Module gui
tools\std.bat test video -bc release --test-tag stress
tools\coverage.bat -Configuration release -Suite parity
```

`-Configuration devmode|release` selects the program preset for coverage. Goldens use Release.
The compatibility alias `fast` selects `functional`. The legacy `full` suite adds goldens in Release
for `std` and `apps`. Use `--test-tag stress` with a workspace launcher to focus its scale cases.

`HeadlessHost` always uses `RenderCpu`. This also applies to direct compiler invocations.
Native application scenarios and dedicated OpenGL integrations create their own graphics
contexts through the code under test.

Two campaigns own what the screen looks like, and they do not overlap.

**Goldens render on CPU in Release.** A PNG golden is a CPU reference: only the CPU renderer draws
the same pixels on every machine and Release is the canonical program configuration for both
recording and comparison. DevMode does not compare against or generate golden snapshots; use it
for functional behavior and safety checks. A Release mismatch leaves `<name>.actual.png` to review
and promote with `goldens.bat accept`.

```text
tools\coverage.bat -Configuration release -Suite goldens
tools\coverage.bat -Configuration release -Suite goldens -Workspace std -Module gui -TestFile menu.swg
```

**Parity compares the renderers.** Tests tagged `integration.renderer.opengl` draw one scene with
`RenderCpu` and with the GPU renderer and compare the two images through
`Pixel.Testing.assertRenderersAgree`. That comparison accepts what separates one graphics device
from another: three levels on every channel anywhere, for rounding in blending, and 35% of the
contrast around the pixel, for antialiasing and filtering. A flat area therefore only gets the
rounding slack, while a shape that moved by a pixel, lost a stroke or changed color costs the
whole contrast and is a difference; rejected pixels count only when they form a shape. A
difference leaves `<name>.parity.cpu.png` and `<name>.parity.gpu.png` beside the goldens of the
test. Neither is a reference: a real divergence is fixed in the renderer, the GPU being presumed
right, and the scene that showed it stays as its regression test.

```text
tools\coverage.bat -Configuration release -Suite parity
tools\coverage.bat -Configuration release -Suite parity -Workspace std -Module pixel -TestFile sampling.ogl.swg
```

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

### Application journeys and desktop input

`apps.bat smoke` is the bounded startup check of the shipped executable. User journeys belong
in `<application>/src/tests/cases/journeys/<plan>.swg`, guarded by `#command ==
Swag.CompilerCommand.Test` and tagged `integration.application.journey`. They use the ordinary
test runner; integration tags keep them out of default headless tests. See
[the scenario contract](application-scenarios.md) for fixtures, checkpoints, and coverage limits.
Simulated native pointer and keyboard plans live in `src/tests/cases/desktop/<plan>.swg` and use
the `integration.desktop.input` tag.

On Windows, run native scenarios on the normal interactive desktop:

```powershell
tools/apps.bat test swagscope -bc release --test-file browsemedialibrary.swg --test-tag integration.application.journey --run-timeout 60
tools/apps.bat test swagscope -bc release --test-file playrecentvideo.swg --test-tag integration.application.journey --run-timeout 60
tools/apps.bat test swagcapture -bc devmode --test-file drawandundo.swg --test-tag integration.desktop.input --run-timeout 60
tools/std.bat test gui -bc release --test-file presentation.win32.swg --test-tag integration.host.windows --run-timeout 60
```

These commands show real windows and may take focus. Application journeys call input handlers;
desktop input journeys send operating-system pointer and keyboard input. Keep native presentation,
monitor configuration, and ordinary window
visibility in the reproduction boundary. Use `tools/apps.bat smoke swagscope -bc release` for
the shipped executable's startup smoke. `--run-timeout` bounds the test process; each individual
journey must still finish within its own deadline below 40 seconds.

Tests tagged `integration.renderer.reset` make their own OpenGL context stall until the system
resets the graphics device, then check that the renderer and a native window recover exactly. The
reset is real: run one at a time, on purpose, and expect displays driven through a USB graphics
adapter to go dark for a few seconds while the driver recovers.

```powershell
tools/std.bat dm test pixel --test-file devicereset.ogl.swg --test-tag integration.renderer.reset --run-timeout 120
tools/std.bat dm test gui --test-file devicereset.win32.swg --test-tag integration.renderer.reset --run-timeout 120
```

| Launcher | Purpose |
| --- | --- |
| `unittests.bat [dm] [suite] [options...]` | C++, lexer, parser, semantic, JIT, safety, sanity, native, and workspace input suites |
| `build.bat [dm] [options...]` | Check standard sources and build examples, applications, and reference targets |
| `tests.bat [dm] [functional\|goldens\|smoke\|integrations] [options...]` | Run a repository test pass |
| `integrations.bat [dm] [all\|opengl\|windows\|smoke] [options...]` | Run the integration pass or use the focused OpenGL, Windows host and smoke commands |
| `portability.bat` | Check that no Swag script launcher remains under `tools/` |
| `vault.bat [dm]` | Build, launch, and restore the Swag Vault integration |

The former backlog, third-party-notice, and native-import audits are retired. The compiler
workspace suite still runs its standalone inputs, but no longer performs the repository's custom
artifact-layout and cache-invalidation probes. The integration launcher accepts one configuration
per run.

`unittests.bat` applies `-bc` to Swag programs only; internal C++ tests use the DevMode compiler's
own configuration. Parallel C++ fixtures and their child compilers inherit `--num-cores`.
Fixtures that specifically test sequential behavior keep one worker.
The workspace suite compiles each fixture with its source dependencies. Runner option routing,
failure propagation, and fixture selection are covered by
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/unittests.ps1`.

## Maintenance

| Launcher | Purpose |
| --- | --- |
| `format.bat [dm] [options...]` | Format sources under `bin/` |
| `help.bat [dm] [options...]` | Regenerate the standard-library and language-reference pages in `bin/help/` |
| `goldens.bat [dm] test [options...]` | Run tests tagged `golden` with the program built as Release |
| `goldens.bat accept` / `python3 tools/tool.py goldens accept` | Promote every reviewed pending `.actual.txt` and `.actual.png` under `bin/` |
| `setup.bat` | Add this checkout's `bin/` to the user `PATH` and set `SWAG_PATH` |
| `setup.sh` | Configure Bash or Zsh with this checkout's Linux compiler and `SWAG_PATH` |
| `package-linux.py` | Package the Capture or Scope executable, desktop entry and icon in a tar archive |

The golden campaign discovers `golden` tags in module case sources under `src/tests/cases/` and skips workspaces
that declare no golden tests; quoted tags in reference prose do not select a workspace. Its argument
forwarding, and failure propagation can be checked without a compiler or desktop:
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/goldens.ps1`.

The batch setup does not claim the `.swgs` file association. It updates the user environment;
open a new terminal after running it.

On Linux, `tools/setup.sh --status` reports whether the current Bash or Zsh profile has a setup
block. Build the compiler first, then run `tools/setup.sh --install --compiler /absolute/path/to/swc`
or pass a `swc.dm` binary. The script updates only its marked block in `~/.bashrc` or `~/.zshrc`,
and `tools/setup.sh --remove` removes it. Open a new shell after either change. The compiler path
and this checkout's `bin/` directory are refreshed when setup is rerun after moving the checkout.
These shells do not execute `.swgs` files directly; run `swc file.swgs` or `swc.dm file.swgs`.

To stage a Linux GUI build without changing the host system, run
`python3 tools/package-linux.py swagcapture --build-dir /path/to/executable/release/x86_64 --output /tmp/swagcapture-linux.tar.gz`.
The default install prefix is `/usr/local`; `--prefix` selects another absolute prefix. The archive
contains the executable under `libexec/swag/`, a desktop entry, and
the shipped 512 px icon. Scope is also supported. A clean-target launch and dependency audit are
still required before release.

`tools/devmode.bat` builds the DevMode compiler. `tools/release.bat` is an owner-only full-machine
build entry point.
The C++ project uses the detected processor count for compilation jobs by default.
Both compiler build scripts accept `SWC_COMPILE_JOBS` for a different native job count.

DevMode keeps assertions, compiler validators, race checks, allocator checks and C++ tests.
Fields maintained only for debugger inspection are disabled by default in both compiler builds.
For an interactive C++ debugging session, manually set `SWC_DEBUG_MODE` to `1` in `src/pch.h`
and rebuild the compiler. This restores reference debug pointers, token locations and AST
visitor inspection fields. Reset it to `0` and rebuild when finished. There is no additional
build configuration or executable; compiler PDB settings remain a separate manual choice.
This define concerns debugging the compiler itself; the compiler's `--debug` option concerns
debug information in the Swag program it generates.
