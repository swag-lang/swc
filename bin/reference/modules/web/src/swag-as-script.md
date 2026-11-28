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
    Swag.print("Hello, world!\n")
}
```

The `.swgs` extension selects script mode, so there is no separate `script`
command. The path splits the command line in two: what comes before it
configures the compilation, and everything after it is the script's own command
line, reaching it through `Swag.args()` and the Core environment helpers.

```text
swc -bc release hello.swgs --colors 16 report.txt
```

`-bc release` is read by the compiler and `--colors 16 report.txt` by the
script, whatever the words look like. A script therefore owns its own grammar,
including options that spell like the compiler's own.

The script is recognized wherever it sits, so `swc` may still be given ordinary
`run` options as long as they precede the path. `--run-arg` remains the way a
*module* receives arguments; a script has no use for it.

## Import source dependencies

Put module setup directives at the top level of the script. This imports the
standard `core` module:

```swag
#import("core", location: "swag@std")

using Core
```

`swag@std` selects the standard library beside the compiler. An installation
without a local copy finds the library under `SWAG_PATH`. The compiler includes
Core and its source dependencies in the script's JIT compilation. This works
from a fresh checkout once `swc` is built.

## Split a script across files

Use top-level `#load` directives for companion source files:

```swag
#load("symbols.swg")
#load("render/helpers.swg")
```

`#load` adds one file to the script's source group. Use `#import` to include
another source group and its dependencies.

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
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.safetyGuards = Swag.SafetyWhat.All
}
```

Prefer command-line build configurations for ordinary runs and reserve setup
code for properties the script owns.

## Break into a debugger

`Swag.breakpoint()` emits a native breakpoint instruction in JIT or native code.
Use it only while a native debugger is attached; Swag does not include the old
interactive bytecode debugger.

## Explore complete scripts

The repository includes games, visualizations, utilities, and demonstrations
under
[`bin/examples/scripts`](https://github.com/swag-lang/swc/tree/master/bin/examples/scripts).
The [Flappy Bird walkthrough](flappy.html) explains imports, compile-time module
configuration, GUI events, graphics, audio, and asset loading in one file.
