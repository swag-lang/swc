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

A module may contain several '#init' hooks. They run in source-location order
(path, then declaration position). Dependency modules initialize before modules
that import them.
*/

var ModuleLifecycleInitialized = false

#init
{
    ModuleLifecycleInitialized = true
}

#test
{
    Swag.require(ModuleLifecycleInitialized)
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
by '#init'. Multiple module drop hooks execute in reverse source-location order.
Dependency modules unload after modules that import them.

Loading a Swag shared library dynamically acquires its dependencies first. All dependency
and library '#init' hooks finish before their '#premain' hooks begin. Closing the last
dynamic reference runs the library's '#drop' hooks before its dependencies' hooks.

A script still drops modules whose initialization completed when its '#main', '#init',
or '#premain' fails. If one script '#drop' fails, the remaining drop hooks are attempted
and the command reports failure. An uncaught panic in a native or JIT lifecycle hook
stops later hooks: abandoned frames and their resources cannot be used safely by
further cleanup code.

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
