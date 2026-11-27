# Getting started

The Swag toolchain runs on Windows and Linux and targets x86-64. The compiler is
named `swc`, and the language is named Swag.

> NOTE:
> The current `swc` repository does not publish binary releases. Build the
> compiler from source, then keep the repository's `bin` directory with its
> runtime and standard workspace.

## Install the compiler on Windows

1. Clone [swag-lang/swc](https://github.com/swag-lang/swc).
2. Follow [Build Swag from source](how-to-build-swag.html). The project pins the
   Visual Studio `v145` C++ toolset and Windows SDK `10.0.26100.0`.
3. From the repository root, run `tools\setup.bat`.
4. Open a new terminal and verify the installation with `swc help`.

The setup script adds the repository's `bin` directory to the user
`PATH` and sets `SWAG_PATH` to that directory. `PATH` locates `swc.exe`.
`swc.exe` finds `bin/runtime` and `bin/std` beside itself,
so `SWAG_PATH` matters only for a compiler installed away from its library.

Keep the Windows SDK and Visual Studio libraries installed for native linking.
On Linux, follow the [Linux compiler build](https://github.com/swag-lang/swc/blob/master/tools/README.md#linux-compiler-build) instructions.

## Run a first script

Create a standalone script and run it directly:

```text
swc new script hello
swc hello.swgs
```

`swc new script` adds the `.swgs` extension when it is omitted and never
overwrites an existing path. The generated source is:

```swag
#main
{
    Swag.print("Hello, world!\n")
}
```

A script is compiled and executed through the JIT. It does not leave an
executable beside the source. See [Scripting with Swag](swag-as-script.html)
for imports, additional files, and arguments.

## Create a workspace module

Use a workspace to group executable targets and their reusable sources.

```text
swc new module hello
swc run --workspace hello --workspace-module hello
```

The first command creates this maintained source tree:

```text
hello/
`-- modules/
    `-- hello/
        |-- module.swg
        `-- src/
            `-- main.swg
```

`module.swg` executes at compile time and configures the module. The starter
selects an executable backend; `src/main.swg` contains the same `#main` hook as
the script example.

Compilation writes two directories at the workspace root.

| Directory | Contents |
|---|---|
| `.output/` | Executables and optional debug information, grouped by configuration |
| `.tmp/` | Compilation intermediates and caches |

Add another module without replacing the workspace:

```text
swc new module tools --workspace hello
```

## Build and select a configuration

```text
swc build -w hello -m hello
swc build -w hello -m hello -bc devmode
swc build -w hello -m hello -bc release
swc build -w hello -m hello --debug
```

`devmode` is the default configuration. It keeps safety and sanity checks while
using optimized code; `release` favors runtime performance. Neither emits debug
information by default. Add `--debug` when a debugger needs symbols and source
line mappings. It covers every dependency the program takes in, and keeps its
artifacts in a directory of their own, so the plain build stays as it was. Use `swc help build` for the authoritative option list and
`--show-config` to inspect the resolved toolchain and output paths.

## Import a standard module

Module dependencies are declared at the top level of `module.swg`. This imports
the standard `core` module:

```swag
#import("core", location: "swag@std")
```

The executable's compilation includes Core and its source dependencies. Source
files can use qualified names such as `Core.String` or bring names into scope with
`using Core`.

## Continue learning

- Start with the [language tour](language.html#_001_002_language_tour_swg).
- Use the [`swc` command-line reference](language.html#_001_004_swc_command_line_swg_The__swc__Command_Line).
- Read about [workspaces and modules](language.html#_002_001_workspaces_modules_and_dependencies_swg_Workspaces_and_Modules).
- Browse the [standard library](std.html) and
  [runtime API](swag.runtime.html).
- Run the programs under
  [`bin/examples`](https://github.com/swag-lang/swc/tree/master/bin/examples).
