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

const IntrinsicCompileTimeMinimum = @min(12's32, 7's32)
#assert(IntrinsicCompileTimeMinimum == 7)

#test
{
    var left:  s32 = 12
    let right: s32 = 7
    @assert(@min(left, right) == 7)
}

/**
# Failure Behavior

'@assert' and '@panic' stop execution. Compiler-facing code can report
diagnostics with '@compilererror' and '@compilerwarning'. Memory and math
intrinsics are also subject to the safety and sanity policies described later in
this reference.

> WARNING:
> Intrinsics do not imply ownership. '@mkslice' and '@mkstring' create views,
> while '@memcpy' ignores value lifecycle hooks. The caller remains responsible
> for lifetime, bounds, alignment, and element semantics.
*/
