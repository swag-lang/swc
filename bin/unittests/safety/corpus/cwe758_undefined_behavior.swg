#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-758 - Reliance on undefined, unspecified or implementation-defined behavior
//
// Read here as the control-flow form: a function that promises a value and can reach its end
// without producing one. No 'ret' is emitted at all, so control runs into whatever was
// emitted next - the worst outcome in the whole corpus, because it is a transfer rather than
// a bad value. MISRA C:2012 rule 17.4 is the same requirement.
//
// Swag: rejected at compile time, in every configuration, at zero runtime cost.
// -----------------------------------------------------------------------------

enum Season { Summer, Winter }

// --- Faults ---

func noReturnAtAll(flag: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    discard flag
}

func returnOnOneBranchOnly(flag: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    if flag do
        return 1
}

// A plain 'switch' is not exhaustive whatever its cases cover, so a value outside the set
// walks past it and off the end of the function.
func plainSwitchOverEveryMember(season: Season)->s32     // swc-expected-error {{sema_err_missing_return}}
{
    switch season
    {
    case .Summer: return 92
    case .Winter: return 90
    }
}

// A loop that can leave through 'break' does not end the function.
func loopThatCanBreak()->s32     // swc-expected-error {{sema_err_missing_return}}
{
    for
    {
        break
    }
}

// A lambda is judged like any other body.
func lambdaWithoutReturn()->s32
{
    let compute: func(bool)->s32 = func(flag: bool)->s32     // swc-expected-error {{sema_err_missing_return}}
    {
        discard flag
    }

    return compute(true)
}

// --- Sound ---

func everyBranchReturns(flag: bool)->s32
{
    if flag do
        return 1
    return 2
}

// '#complete' is the promise that some case always matches, and it is what lets the switch
// end the function without a dead 'return' after it.
func completeSwitchEndsTheFunction(season: Season)->s32
{
    switch #complete season
    {
    case .Summer: return 92
    case .Winter: return 90
    }
}

func defaultArmEndsTheFunction(value: s32)->s32
{
    switch value
    {
    case 0:  return 1
    default: return 2
    }
}

// A case that falls through leaves through the body it continues into.
func fallthroughEndsTheFunction(value: s32)->s32
{
    switch value
    {
    case 0:
        fallthrough
    default:
        return 2
    }
}

// A loop with no way out of it ends the function.
func loopWithoutBreak()->s32
{
    for
    {
        if true do
            return 1
    }
}

// A nested loop's own 'break' does not leave the outer one.
func nestedBreakDoesNotEscape()->s32
{
    for
    {
        for
        {
            break
        }

        return 1
    }
}

// 'unreachable' is the escape hatch for a path the compiler cannot see is impossible, and it
// costs nothing once its guard is off.
func endsInUnreachable(flag: bool)->s32
{
    if flag do
        return 1
    unreachable
}

// A fallible function can end by failing instead of returning.
func endsInFail(flag: bool)->s32 fail
{
    if flag do
        return 1
    fail Swag.BaseError{"no value here"}
}

// An expression body IS the value, so the question never arises.
func expressionBody(value: s32)->s32 => value + 1

// A void function owes nothing.
func voidOwesNothing(flag: bool)
{
    discard flag
}

#test
{
    Swag.assert(everyBranchReturns(opaqueBool(true)) == 1)
    Swag.assert(completeSwitchEndsTheFunction(Season.Winter) == 90)
    Swag.assert(defaultArmEndsTheFunction(opaqueS32(3)) == 2)
    Swag.assert(fallthroughEndsTheFunction(opaqueS32(0)) == 2)
    Swag.assert(loopWithoutBreak() == 1)
    Swag.assert(nestedBreakDoesNotEscape() == 1)
    Swag.assert(endsInUnreachable(opaqueBool(true)) == 1)
    Swag.assert((catch endsInFail(opaqueBool(true))) == 1)
    Swag.assert(expressionBody(1) == 2)
}
