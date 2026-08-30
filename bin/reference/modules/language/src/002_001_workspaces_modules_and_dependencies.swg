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
'Swag.compiler()'. A minimal executable configuration looks like this:

```swag
#run
{
    let cfg = Swag.compiler().getBuildCfg()!
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
| beside the executable | the shared libraries a program still imports at run time |

Modules in the same workspace compile and link directly against their producer's
'.output' artifacts. The '.dep' copy exists only for external dependencies because
compile-time execution loads a dependency's shared library and holds it open, and
a held file cannot be replaced: reading an external workspace's original would
stop a build that has to rewrite it.
*/

/**
# How a Dependency Is Taken In

A module that builds a library publishes its code twice, from one compilation:

| Directory | Holds |
|---|---|
| '<module>/shared-library/<config>/<arch>' | the shared library, and the API every consumer compiles against |
| '<module>/static-library/<config>/<arch>' | an archive of the same code, one function per member |

Both are needed, and they answer different questions. The compiler loads the
shared library to run that module's code at compile time — a '#run' calling into
'core' calls into 'core.dll'. The archive is what a program links.

The consumer chooses, and its own kind chooses for it:

- An **executable** links its dependencies' code in. It ships as one file, and it
  carries only the functions it actually reaches, because the linker pulls archive
  members on demand.
- A **shared library** keeps importing its dependencies, so everything that loads
  it shares one copy of a module's code and of the runtime state that comes with
  it — one allocator, one context.

An import states a kind explicitly with 'link:':

```swag
#import("plugin_host", link: "shared-library")
```

Asking for one shared library asks for all of them. An executable that linked one
module in while loading another built against that same module's library would run
two copies of it, with two allocators and two runtime contexts, and memory could
not cross between them. So the answer covers the whole import closure or none of
it: one 'link: "shared-library"' makes every dependency of that executable shared.

An executable that still imports at run time asks for its libraries to be placed
beside it:

```swag
#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.backendKind         = .Executable
    cfg.publishDependencies = true
}
```

The link then places every shared library the program still needs beside it, and
takes back out any that an earlier build left there and the program no longer
imports. Whether a program has to stand on its own is a fact about the program, so
it is stated in 'module.swg' and not on the command line: no later command can take
it away.
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
