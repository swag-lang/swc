# Scripting with Swag

A `.swgs` file is a standalone Swag program. `swc` compiles the file and runs
its lifecycle hooks through the JIT, which makes scripts useful for build tools,
asset processing, experiments, and small applications without producing a
native executable.

## Create and run a script

```text
swc new script hello
swc hello.swgs
```

The generated file contains a `#main` hook:

```swag
#main
{
    @print("Hello, world!\n")
}
```

The `.swgs` extension selects script mode, so there is no separate `script`
command. The path splits the command line in two: what comes before it
configures the compilation, and everything after it is the script's own command
line, reaching it through `@args` and the Core environment helpers.

```text
swc -bc release hello.swgs --colors 16 report.txt
```

`-bc release` is read by the compiler and `--colors 16 report.txt` by the
script, whatever the words look like. A script therefore owns its own grammar,
including options that spell like the compiler's own.

The script is recognized wherever it sits, so `swc` may still be given ordinary
`run` options as long as they precede the path. `--run-arg` remains the way a
*module* receives arguments; a script has no use for it.

`setup` claims the `.swgs` extension for the current user, so a script also runs
from a double-click, arguments and exit code included.

## Import compiled dependencies

Put module setup directives at the top level of the script. This imports the
standard `core` module:

```swag
#import("core", location: "swag@std")

using Core
```

`swag@std` is the standard library beside the compiler that runs the script, and
`SWAG_PATH` answers only for a compiler installed without one. A compiler and its
library are one thing, so a second checkout on the same machine keeps its own
rather than the one the environment happens to name. A module that library has
but has not been built for this configuration is built there and then, rather
than reported missing, so a script runs from a checkout that has never been
registered or built. The compiler builds imported dependencies as native modules
and reuses compatible output on later runs.

Script dependency state is cached under the system temporary directory in
`swag/scripts`. Its directory key is derived from the build configuration,
target architecture, and resolved imports, so compatible scripts can reuse the
same dependency output. Use `--show-config` to inspect resolved paths and tools.

## Split a script across files

Use top-level `#load` directives for companion source files:

```swag
#load("symbols.swg")
#load("render/helpers.swg")
```

`#load` adds source to the current script module. It does not create a compiled
module dependency; use `#import` for that boundary.

`#load` nests, and every path is relative to the file that writes it, so a
script spread over many sources names them once:

```swag
// main.swgs
#load("src/all.swg")

// src/all.swg loads its siblings by their own names
#load("options.swg")
#load("commands/build.swg")
```

A loaded file states module setup directives of its own — `#import` as well as
`#load` — and a file already loaded is never loaded twice, so two files that
load each other are fine.

## Configure the script

A top-level `#run` block can update the script's build configuration before the
rest of the file is compiled:

```swag
#run
{
    let cfg = @compiler.getBuildCfg()!
    cfg.safetyGuards = Swag.SafetyWhat.All
}
```

Prefer command-line build configurations for ordinary runs and reserve setup
code for properties the script owns.

## Break into a debugger

`@breakpoint()` emits a native breakpoint instruction in JIT or native code.
Use it only while a native debugger is attached; Swag does not include the old
interactive bytecode debugger.

## Explore complete scripts

The repository includes games, visualizations, utilities, and demonstrations
under
[`bin/examples/scripts`](https://github.com/swag-lang/swc/tree/master/bin/examples/scripts).
The [Flappy Bird walkthrough](flappy.html) explains imports, compile-time module
configuration, GUI events, graphics, audio, and asset loading in one file.
