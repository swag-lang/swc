#global private

/**
# Workspaces and Modules

A **workspace** is the unit selected by the command line. Its 'modules'
directory contains one folder per module. A **module** is the compilation and
API boundary: it produces an executable, library, or exported API description.

```text
my-workspace/
└── modules/
    ├── app/
    │   ├── module.swg
    │   └── src/
    │       └── main.swg
    └── support/
        ├── module.swg
        └── src/
            └── support.swg
```

The module folder name is its default name. All '.swg' files below 'src' belong
to that module; their subdirectories are organizational and do not create
namespaces.
*/

#assert(#typeof(#module) == string)

/**
# The 'module.swg' File

'module.swg' executes at compile time and configures the current module through
'@compiler'. A minimal executable configuration looks like this:

```swag
#run
{
    let cfg = @compiler.getBuildCfg()!
    cfg.moduleVersion  = 1
    cfg.moduleRevision = 0
    cfg.moduleBuildNum = 0
    cfg.backendKind    = .Executable
}
```

Common backend kinds are '.Executable', '.SharedLibrary', '.StaticLibrary', and
'.Export'. A module can also set 'moduleNamespace' when its public API should
live under an explicit root namespace.
*/

/**
# Importing Another Module

Imports belong in 'module.swg'. The following form imports the standard 'core'
module from the compiler's standard workspace:

```swag
#import("core", location: "swag@std")
```

An import makes the dependency's public API available and ensures that the
dependency is built first. It does not import all names into the current lexical
scope; use qualified names or a targeted 'using' declaration in source files.

> NOTE:
> '#load' includes source selected by the compiler, while '#import' establishes a
> module dependency. They solve different problems and are not interchangeable.
*/

/**
# Where a Dependency Lives

A workspace keeps the same dependency in more than one place, and each answers a
question the others cannot:

| Directory | Holds |
|---|---|
| '<workspace>/.output/<module>' | what building that module produced and what modules in the same workspace consume |
| '<workspace>/.dep/<module>' | the copy the workspace consumes for a dependency imported from outside itself |
| beside the executable | the copy that lets the program run with nothing else present |

Modules in the same workspace compile and link directly against their producer's
'.output' artifacts. The '.dep' copy exists only for external dependencies because
compile-time execution loads a dependency's shared library and holds it open, and
a held file cannot be replaced: reading an external workspace's original would
stop a build that has to rewrite it.

An executable asks for the third copy itself:

```swag
#run
{
    let cfg = @compiler.getBuildCfg()!
    cfg.backendKind         = .Executable
    cfg.publishDependencies = true
}
```

The link then places every shared library the program needs beside it, so it runs
from its own directory without the compiler. Whether a program has to stand on its
own is a fact about the program, so it is stated in 'module.swg' and not on the
command line: no later command can take it away.
*/

/**
# Sharing Source Between Modules

'#load' belongs in 'module.swg' too, and names one extra source file by path. The
file becomes part of the module, exactly as if it sat under 'src':

```swag
#import("gui", location: "swag@std")
#load("../../shared/pluginapi.swg")
```

A loaded file may state '#import' and '#load' of its own, and it may declare
against the module's dependencies: its declarations are compiled with the regular
sources, after every import is resolved.

Use it when several modules must agree on the same declarations — a version
constant, an entry-point signature, the shape of a structure crossing a library
boundary — and none of them owns runnable code for it. Making that agreement a
module instead would add an entry to the build graph and an artifact under
'.output' to publish names that carry no code. Reach for '#import' as soon as the
shared thing has an implementation: each loading module compiles its own copy of a
loaded file, which is what makes it the wrong tool for anything but declarations.
*/
