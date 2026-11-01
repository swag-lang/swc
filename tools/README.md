# Repository tools

Every launcher in this directory is a Windows batch file. It calls the checkout's existing
compiler directly; launching a tool no longer compiles a Swag script first. Build the compiler
once with `tools\devmode.bat` or `tools\release.bat` before using the launchers.

Run the checkout's own compiler whenever more than one worktree exists. `dm` selects
`bin\swc.dm.exe`; without it, tools use `bin\swc.exe`. Tool compiler calls default to three workers.
Pass `--num-cores` to change compiler parallelism; it does not limit a compiled program's runtime
threads. Compiler options can be forwarded after the command and module.

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
tools\apps.bat dm test swagcapture --test-file files.test.swg
tools\std.bat dm test gui --test-tag golden
tools\scripts.bat snake
```

Use `-bc release` or `-bc devmode` to select a program configuration. `--debug`,
`--test-file`, `--test-tag`, `--run-arg`, `--frames`, and other compiler options are forwarded.
For application tests, `--test-file` and `--test-tag` select which tests execute; the complete
application module is still compiled. `apps.bat test` sets `SWAG_RUNTIME_THREADS=3` unless that
environment variable is already defined. The setting is local to the launcher and its children.
`--all-cfg` and `apps run --async` are not supported by the batch launchers; run each configuration
separately.

### Limit runtime threads

Set `SWAG_RUNTIME_THREADS` before launching a compiled program or its test executable:

```powershell
$env:SWAG_RUNTIME_THREADS = '2'
tools\apps.bat dm test swagcapture --test-file files.test.swg
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

### Application smoke scenarios

`apps.bat smoke` is the bounded startup check of the shipped executable. User journeys belong
in `<application>/src/tests/<plan>.smoke.test.swg`, guarded by `#command ==
Swag.CompilerCommand.Test` and tagged `integration.application.smoke`. They use the ordinary
test runner; integration tags keep them out of default headless tests. See
[the scenario contract](application-scenarios.md) for fixtures, checkpoints, and coverage limits.

On Windows, run a scenario without taking focus or showing test windows on the user's desktop:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-desktop.ps1 -Module swagscope -DevMode -TestFile browsemedialibrary.smoke.test.swg
```

The launcher creates a private desktop without switching to it, invokes `apps.bat test`, and
retains its log under the printed temporary directory. A job owns the compiler and all children;
the process timeout is 15 minutes including compilation, and `-RunTimeout` bounds each test
executable (60 seconds by default). `-Configuration release` selects the program configuration;
omitting `-DevMode` selects `swc.exe`. `-Workspace std -Module gui -TestTag integration.host.windows`
selects native GUI integration tests instead. It never automates the user's mouse or keyboard.
Use `-Action smoke -Module swagscope -DevMode` for the shipped executable's startup smoke on the
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
