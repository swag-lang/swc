#global private

/**
# Module Entry Points and Hooks

Swag reserves '#'-prefixed functions for module lifecycle events. They are
declarations, not ordinary functions, and the compiler invokes them at the
appropriate phase.

| Hook       | Purpose |
| ---------- | ------- |
| '#init'    | Initialize module runtime state before entry points or tests |
| '#premain' | Run after all module initializers and before an executable's '#main' |
| '#main'    | Enter an executable module |
| '#test'    | Declare a test executed by the 'test' command |
| '#drop'    | Release module state during shutdown |

# Initialization

A module may contain several '#init' hooks. Their relative order is unspecified,
so each hook must establish its own invariants. Dependency modules initialize
before modules that import them.
*/

var ModuleLifecycleInitialized = false

#init
{
    ModuleLifecycleInitialized = true
}

#test
{
    Swag.assert(ModuleLifecycleInitialized)
}

/**
# Executable Entry

An executable has one '#main'. Command-line arguments are available through
'Swag.args()'.

```swag
#main
{
    for argument, index in Swag.args()
        Swag.print(index, ": ", argument, "\n")
}
```

'#premain' is useful for application setup that must happen after every imported
module has initialized but before '#main' begins.

# Shutdown

'#drop' hooks run when a module unloads. Use them to release resources acquired
by '#init'. Multiple module drop hooks execute in the reverse order of their
corresponding initialization sequence.

```swag
#drop
{
    // Close handles and release module-owned resources.
}
```

> WARNING:
> Do not confuse '#init' and '#drop' module hooks with the 'Swag.init' and 'Swag.drop'
> intrinsics. The hooks manage a module's lifetime; the intrinsics operate on
> values and memory regions.
*/
