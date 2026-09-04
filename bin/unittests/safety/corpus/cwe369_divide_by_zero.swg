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

// GAP compiler.safety.015 - '.Math' does not guard DIVISION at run time, in any form. The
// reference documents that it does ("Swag panics for invalid math, such as division by zero",
// bin/reference/modules/language/src/013_002_safety.swg, with a worked example) and with the
// guard explicitly on: an integer division reaches the hardware and raises #DE, taking the
// compile-time JIT down with it, and a float division quietly produces an infinity. What
// '.Math' really guards today is the intrinsic domains below. The static proof covers a
// divisor it can fold, so the hole is exactly the divisor that only exists at run time.
// Left commented because the integer form really does fault.
//
// #[Swag.Safety(.Math, true)]
// func divideByComputedZero(value, divisor: s32)->s32
// {
//     return value / divisor     // expected: safety_err_runtime
// }
//
// #test
// {
//     #run divideByComputedZero(opaqueS32(10), opaqueS32(0))
// }
//
// #[Swag.Safety(.Math, true)]
// func remainderByZero(value, divisor: s32)->s32
// {
//     return value % divisor     // expected: safety_err_runtime
// }
//
// #test
// {
//     #run remainderByZero(opaqueS32(10), opaqueS32(0))
// }

// The float half of the same gap, kept live because it does not fault: it produces an
// infinity where the reference says it panics. Pinned so the change is visible when the
// guard is restored.
#[Swag.Safety(.Math, true)]
func divideFloatByZero(value, divisor: f32)->f32
{
    return value / divisor     // GAP compiler.safety.015: expected safety_err_runtime
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
