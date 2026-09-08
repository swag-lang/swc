#global private

/**
# Intrinsics

Intrinsics are operations implemented directly by the compiler or its runtime.
Their names start with '@', so they cannot collide with application APIs. They
cover five broad areas:

- assertions, diagnostics, execution context, and compiler access;
- type erasure, reflection, and construction of slices or strings;
- explicit value lifecycle operations;
- math, bit, memory, and atomic primitives;
- interoperability with C variadic functions.

Use an intrinsic when its semantics are genuinely language-level or low-level.
Prefer a typed library abstraction for ownership, platform APIs, containers, and
application-level behavior.

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
'Swag.SafetyWhat.Assert' controls its emission through 'BuildCfg.safetyGuards' and
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
