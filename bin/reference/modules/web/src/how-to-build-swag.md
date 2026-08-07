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
tools\setup.swgs
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
| `tools\unittests.swgs dm cpp` | Internal C++ unit tests |
| `tools\unittests.swgs dm lexer` | Lexer source tests and expected diagnostics |
| `tools\unittests.swgs dm parser` | Parser source tests and expected diagnostics |
| `tools\unittests.swgs dm sema` | Semantic source tests and expected diagnostics |
| `tools\unittests.swgs dm jit` | JIT execution tests |
| `tools\unittests.swgs dm native` | Native code generation and execution tests |
| `tools\reference.swgs dm test` | Executable language reference |
| `tools\tests.swgs dm` | Full default DevMode test suite |
| `tools\tests.swgs dm --all-cfg` | Default suite in `release`, `debug`, and `fast-debug` |

The repository's [agent guide](https://github.com/swag-lang/swc/blob/master/AGENTS.md)
defines the required validation sequence for each change type.

## Regenerate the website

After a DevMode build, regenerate the complete documentation site with:

```text
tools\web.swgs dm
```

The command rebuilds the brand assets, standard-library API pages, runtime API,
language reference, and editorial pages. It deletes existing root HTML files in
`web` first, so edit their sources under `bin/reference`, `bin/runtime`,
`bin/std`, or `bin/examples` rather than editing generated HTML.
