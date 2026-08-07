# Getting started

The current Swag toolchain runs on Windows and targets x86-64. The compiler is
named `swc`; `Swag` is the language name.

> NOTE:
> The current `swc` repository does not publish binary releases. Build the
> compiler from source, then keep the repository's `bin` directory with its
> runtime and standard workspace.

## Install the compiler

1. Clone [swag-lang/swc](https://github.com/swag-lang/swc).
2. Follow [Build Swag from source](how-to-build-swag.html). The project pins the
   Visual Studio `v145` C++ toolset and Windows SDK `10.0.26100.0`.
3. From the repository root, run `tools\setup.swgs`.
4. Open a new terminal and verify the installation with `swc help`.

The registration script adds the repository's `bin` directory to the user
`PATH` and sets `SWAG_PATH` to that directory. `PATH` locates `swc.exe`;
`SWAG_PATH` lets the compiler find `bin/runtime` and `bin/std`.

The compiler invokes the Microsoft x64 linker and Windows SDK tools when it
produces native artifacts, so keep the Visual Studio C++ workload installed
after building `swc`.

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
    @print("Hello, world!\n")
}
```

A script is compiled and executed through the JIT. It does not leave an
executable beside the source. See [Scripting with Swag](swag-as-script.html)
for imports, additional files, arguments, and the script cache.

## Create a workspace module

Use a workspace when the program has modules, produces a native artifact, or
will be consumed by another module:

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

Compilation owns three generated directories at the workspace root:

| Directory | Contents |
|---|---|
| `.output/` | Native artifacts and exported module APIs, grouped by configuration |
| `.tmp/` | Intermediate compiler and native-tool files |
| `.dep/` | Materialized dependency APIs and native dependency artifacts |

Add another module without replacing the workspace:

```text
swc new module tools --workspace hello
```

## Build and select a configuration

```text
swc build -w hello -m hello
swc build -w hello -m hello -bc debug
swc build -w hello -m hello -bc release
```

`fast-debug` is the default configuration. It keeps safety and sanity checks
while using optimized code. `debug` favors diagnostics, and `release` favors
runtime performance. Use `swc help build` for the authoritative option list and
`--show-config` to inspect the resolved toolchain and output paths.

## Import a standard module

Module dependencies are declared at the top level of `module.swg`. This imports
the standard `core` module:

```swag
#import("core", location: "swag@std")
```

Source files can then use qualified names such as `Core.String`, or bring
selected names into scope with `using Core`.

## Continue learning

- Start with the [language tour](language.html#_001_002_language_tour_swg).
- Use the [`swc` command-line reference](language.html#The__swc__Command_Line).
- Read about [workspaces and modules](language.html#Workspaces_and_Modules).
- Browse the [standard library](std.html) and
  [runtime API](swag.runtime.html).
- Run the programs under
  [`bin/examples`](https://github.com/swag-lang/swc/tree/master/bin/examples).
