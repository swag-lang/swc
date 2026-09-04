#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-369 - Divide by zero
//
// Swag: both halves. A divisor the value analysis can fold to zero is a compile-time error in
// every configuration, including the ones with the dynamic guards off; a divisor that only
// exists at run time is a panic under '.Math'.
//
// The same guard covers the intrinsics whose domain excludes part of their input type.
// -----------------------------------------------------------------------------

// --- Faults ---

// Proven: reported even with the runtime guard off.
#[Swag.Safety(.Math, false), Swag.Sanity(.Math, true)]
func divideByProvenZero()->s32
{
    var divisor = 0's32
    var value   = 10's32
    return value / divisor     // swc-expected-error {{sanity_err_division_zero}}
}

#test
{
    #run divideByProvenZero()
}

// Only known at run time: the guard answers. Without it the division reaches the hardware,
// which traps with no location and no message.
#[Swag.Safety(.Math, true)]
func divideByComputedZero(value, divisor: s32)->s32
{
    return value / divisor     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run divideByComputedZero(opaqueS32(10), opaqueS32(0))
}

// The remainder operator has the same domain.
#[Swag.Safety(.Math, true)]
func remainderByZero(value, divisor: s32)->s32
{
    return value % divisor     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run remainderByZero(opaqueS32(10), opaqueS32(0))
}

// The compound form is guarded at the same place.
#[Swag.Safety(.Math, true)]
func divideAssignByZero(value, divisor: s32)->s32
{
    var result = value
    result /= divisor     // swc-expected-error {{safety_err_runtime}}
    return result
}

#test
{
    #run divideAssignByZero(opaqueS32(10), opaqueS32(0))
}

// Float division by zero is NOT this class: it is IEEE-defined and yields an infinity, so it
// carries no guard and needs none. Pinned so a future rule that changes it shows up here.
#[Swag.Safety(.Math, true)]
func divideFloatByZero(value, divisor: f32)->f32
{
    return value / divisor
}

#test
{
    let result = divideFloatByZero(opaqueF32(1.0), opaqueF32(0.0))
    Swag.assert(result > 0)
}

// An intrinsic argument outside its domain is the same class: a partial function applied
// where it is not defined.
#[Swag.Safety(.Math, true)]
func squareRootOfNegative(value: f32)->f32
{
    return Swag.sqrt(value)     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run squareRootOfNegative(opaqueF32(-2.0))
}

// --- Sound ---

func divideByGuardedDivisor(value, divisor: s32)->s32
{
    if divisor == 0 do
        return 0
    return value / divisor
}

#test
{
    Swag.assert(divideByGuardedDivisor(opaqueS32(10), opaqueS32(0)) == 0)
    Swag.assert(divideByGuardedDivisor(opaqueS32(10), opaqueS32(2)) == 5)
    Swag.assert(Swag.sqrt(opaqueF32(4.0)) == 2.0)
}
