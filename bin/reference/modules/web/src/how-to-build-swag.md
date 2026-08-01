# Build Swag from source

The compiler is a Windows x86-64 C++ application built with MSBuild. The source
tree no longer embeds LLVM or uses the old `build/vs_build_*.bat` scripts;
`swc.sln` and the repository tools are the maintained build path.

## Prerequisites

Install Visual Studio 2026 or its standalone Build Tools with:

- the Desktop development with C++ workload;
- the MSVC `v145` x64/x86 toolset;
- Windows SDK `10.0.26100.0`.

The exact toolset and SDK are pinned in `swc.vcxproj`. If MSBuild reports that
either component is missing, install that component through Visual Studio
Installer before changing the project target.

## Build the compiler

Open a Developer PowerShell for Visual Studio, change to the repository root,
and build the release configuration:

```text
msbuild swc.sln /m /p:Configuration=Release /p:Platform=x64
```

The solution also opens directly in Visual Studio. Select `x64` and the desired
configuration, then build the `swc` project.

| Configuration | Output | Purpose |
|---|---|---|
| `Release` | `bin/swc.exe` | Compiler used by applications and normal repository tools |
| `DevMode` | `bin/swc_devmode.exe` | Compiler with internal validation and C++ unit tests enabled |
| `Stats` | `bin/swc_stats.exe` | Release-style compiler with internal statistics forced on |

All intermediate C++ files stay under the repository's `.tmp/x64` tree.

## Register the checkout

Run this once from the repository root:

```text
tools\register-compiler-path.bat
```

Open a new terminal afterward. The script adds `bin` to the user `PATH` and
sets `SWAG_PATH`, which is required to locate the compiler runtime and standard
workspace.

Verify both the compiler and native toolchain:

```text
swc help
swc new module hello
swc run -w hello -m hello
```

## Validate repository changes

Build `DevMode` before using the `dm` form of a tool. The narrow commands are
useful while iterating:

| Command | Scope |
|---|---|
| `tools\test-cpp-units.bat dm` | Internal C++ unit tests |
| `tools\test-lexer-suite.bat dm` | Lexer source tests and expected diagnostics |
| `tools\test-parser-suite.bat dm` | Parser source tests and expected diagnostics |
| `tools\test-semantic-suite.bat dm` | Semantic source tests and expected diagnostics |
| `tools\test-jit-suite.bat dm` | JIT execution tests |
| `tools\test-native-suite.bat dm` | Native code generation and execution tests |
| `tools\manage-reference-workspace.bat dm test` | Executable language reference |
| `tools\test-all-workspaces.bat dm` | Full default DevMode test suite |
| `tools\test-all-configurations.bat dm` | Default suite in `release`, `debug`, and `fast-debug` |

The repository's [agent guide](https://github.com/swag-lang/swc/blob/master/AGENTS.md)
defines the required validation sequence for each change type.

## Regenerate the website

After a DevMode build, regenerate the complete documentation site with:

```text
tools\generate-web-documentation.bat dm
```

The command rebuilds the brand assets, standard-library API pages, runtime API,
language reference, and editorial pages. It deletes existing root HTML files in
`web` first, so edit their sources under `bin/reference`, `bin/runtime`,
`bin/std`, or `bin/examples` rather than editing generated HTML.
