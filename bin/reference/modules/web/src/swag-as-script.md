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
command. Pass normal `run` options after the path. Repeat `--run-arg` to append
arguments exposed through `@args` and the Core environment helpers:

```text
swc hello.swgs --run-arg first --run-arg second
```

## Import compiled dependencies

Put module setup directives at the top level of the script. This imports the
standard `core` module:

```swag
#import("core", location: "swag@std")

using Core
```

`SWAG_PATH` must point to the compiler's `bin` directory so `swag@std` can
resolve `bin/std`. The compiler builds imported dependencies as native modules
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
