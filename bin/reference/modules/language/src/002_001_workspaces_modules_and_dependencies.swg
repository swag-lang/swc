#global private

/**
# Workspaces and Modules

A workspace groups source folders. Each folder under its 'modules' directory
contains a 'module.swg' descriptor and a 'src' tree.

```text
my-workspace/
  modules/
    app/
      module.swg
      src/
        main.swg
    support/
      module.swg
      src/
        support.swg
```

The folder name is the default module name. Subdirectories under 'src' organize
files. A '#global namespace' directive or a 'namespace' declaration gives
declarations their qualified names.

A module configured with '.Executable' is a build target. The compiler takes in
its sources and the complete graph of source dependencies. A module configured
with '.None' supplies sources and can be imported. The standard library groups
its sources under 'std/namespaces', with one descriptor per group.
*/

#assert(#typeof(#module) == string)

/**
# Configuring an Executable

'module.swg' runs at compile time and configures its source group through
'Swag.compiler()'. A group can set 'moduleNamespace' to choose its root namespace.

```swag
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.backendKind = .Executable
}
```

The executable's build configuration applies to the sources it takes in.
All of them share the runtime and its context. Dependency initializers run before
their dependents and finalizers run in reverse order. These hooks run when the
executable starts or exits. A compile-time call sees statically initialized
values and any state set by compile-time code.

# Importing Sources

Put '#import' in 'module.swg'. By default the compiler looks for the named group
in the current workspace. Use 'location:' to select another workspace. Relative
paths are resolved from the descriptor. 'swag@std' selects the standard library.

```swag
#import("core", location: "swag@std")
#import("support")
```

Each source group is compiled once per target, including when several paths
through the graph reach it. Every imported group supplies sources and has a
unique root namespace within the graph. Imports must form an acyclic graph.
Public declarations are available through qualified names or a 'using'
declaration. Internal declarations stay within their source group and private
declarations stay within their file.

'#load' adds one file to the source group that contains the directive. A file
loaded by several groups is compiled within each group's own scope. Use '#import'
to share a source group and its dependencies.

```swag
#load("../../shared/options.swg")
```

# Building and Testing

With no module selected, 'swc build', 'swc run', and 'swc smoke' select the
workspace's executable targets. Use 'swc sema' to check source groups, or select
one by name with 'swc build'. Source groups can be tested directly with
'swc test', which builds an executable for native tests.

Build output lives under the workspace's '.output' directory, with temporary
files under '.tmp'. Use 'Swag.Foreign' or 'NativeLibrary' to call native libraries.
*/
