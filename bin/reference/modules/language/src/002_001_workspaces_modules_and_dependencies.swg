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
