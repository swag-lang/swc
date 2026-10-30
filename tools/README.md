# Repository tools

Every launcher in this directory is a Windows batch file. It calls the checkout's existing
compiler directly; launching a tool no longer compiles a Swag script first. Build the compiler
once with `tools\devmode.bat` or `tools\release.bat` before using the launchers.

Run the checkout's own compiler whenever more than one worktree exists. `dm` selects
`bin\swc.dm.exe`; without it, tools use `bin\swc.exe`. Tool compiler calls default to six workers.
Compiler options can be forwarded after the command and module.

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
`--all-cfg` and `apps run --async` are not supported by the batch launchers; run each configuration
separately.

## Compiler suites and campaigns

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
