#global private

/**
# Intrinsics

Intrinsics are operations implemented directly by the compiler or its runtime.
They use qualified names in the built-in 'Swag' namespace, while native views
expose '.count' and '.buffer' as members. They cover five broad areas:

- assertions, diagnostics, execution context, and compiler access;
- type erasure, reflection, and construction of slices or strings;
- explicit value lifecycle operations;
- math, bit, memory, and atomic primitives;
- packed vector operations.

Use an intrinsic when its semantics are genuinely language-level or low-level.
Prefer a typed library abstraction for ownership, platform APIs, containers, and
application-level behavior.

# What Belongs in 'Swag'

A declaration belongs to 'Swag' when the compiler knows it by contract: it emits
calls to it, lowers syntax to it, mirrors its layout, or reads it back at compile
time. 'Swag.Task' is there because 'parallel for' lowers to the scheduler, and
'Swag.CompilerCommand' because '#command' compares against it. So does what a
process must have exactly one of: its allocator, its scheduler, the context of each
thread. Everything else belongs to a module. A module's build configuration is
compiler-facing data rather than language vocabulary, and lives one level down, in
'Swag.Build'.

Every intrinsic is spelled in camelCase, like the rest of the language, and named
after what it computes rather than after a processor instruction. The four memory
operations keep their C names: 'Swag.memcpy', 'Swag.memmove', 'Swag.memset' and
'Swag.memcmp'.

# Compile Time and Runtime

Many pure intrinsics accept constant operands and are evaluated by the compiler.
The same call can also execute at runtime when an operand is dynamic.
*/

const IntrinsicCompileTimeMinimum = Swag.min(12's32, 7's32)
#assert(IntrinsicCompileTimeMinimum == 7)

#test
{
    var left:  s32 = 12
    let right: s32 = 7
    Swag.assert(Swag.min(left, right) == 7)
}

/**
# Failure Behavior

'Swag.assert(condition, message)' is the standard assertion for programmer invariants,
available without importing Core. It stops execution when an enabled assertion is false.
'Swag.SafetyWhat.Assert' controls its emission through 'Swag.Build.Config.safetyGuards' and
'#[Swag.Safety(.Assert, true/false)]': enabled by default in devmode and disabled in
release. The 'test' command enables assertions by default in every configuration,
including release; explicit local 'Swag.Safety' overrides still apply.
Disabled assertions evaluate none of their arguments, so keep required side effects
outside them. Arguments still type-check, and the asserted invariant still narrows
subsequent code. A message is optional and is evaluated only on failure.

Use '#assert' for an unconditional compile-time assertion, and 'Swag.panic' for an
unconditional stop.
Compiler-facing code can report diagnostics with 'Swag.compilerError' and 'Swag.compilerWarning'. Memory and math
intrinsics are also subject to the safety and sanity policies described later in
this reference.

> WARNING:
> Intrinsics do not imply ownership. 'Swag.makeSlice' and 'Swag.makeString' create views,
> while 'Swag.memcpy' ignores value lifecycle hooks. The caller remains responsible
> for lifetime, bounds, alignment, and element semantics.
*/

#test
{
    #[Swag.Safety(.Assert, true)]
    {
        Swag.assert(2 + 2 == 4, "arithmetic invariant")
    }

    #[Swag.Safety(.Assert, false)]
    {
        Swag.assert(false, "this assertion emits no code")
    }
}
