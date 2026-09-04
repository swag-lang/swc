#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-704 - Incorrect type conversion or cast
//
// A value is converted to a type whose invariants it does not satisfy. Read here as the enum
// case, because that is where the converted value goes on to select control flow.
//
// Swag: an integer converts to an enum with no check in any configuration, and the result is
// used as an ordinary member - compared, switched on, indexed with. Nothing distinguishes it
// from a declared one.
// -----------------------------------------------------------------------------

enum Colour
{
    Red
    Green
    Blue
}

#[Swag.EnumFlags]
enum Access
{
    None  = 0
    Read  = 1
    Write = 2
}

// --- Faults ---

// GAP compiler.safety.010 - the conversion is accepted and the value is not a member. Kept
// LIVE because it does not corrupt anything on its own: what it produces is a wrong value,
// and pinning the current behaviour is what makes the future rule visible.
func forgeEnumValue(raw: s32)->Colour
{
    return cast(Colour) raw     // GAP compiler.safety.010: expected a checked conversion
}

// The forged value matches no case, so a plain switch falls through it.
func rankForgedValue(colour: Colour)->s32
{
    switch colour
    {
    case .Red:   return 1
    case .Green: return 2
    case .Blue:  return 3
    }

    return -1
}

#test
{
    let forged = forgeEnumValue(opaqueS32(99))
    Swag.assert(forged != Colour.Red)
    Swag.assert(forged != Colour.Green)
    Swag.assert(forged != Colour.Blue)
    Swag.assert(rankForgedValue(forged) == -1)
}

// GAP compiler.safety.009 / compiler.safety.010 - the same forged value reaching a
// 'switch #complete'. With '.Switch' on it panics; with the guard off it matches no arm and
// walks past the switch, which is the deliberate design: '#complete' is the promise that
// makes the dispatch branch-free. What is missing is the rule that stops the forged value
// existing. Left commented because the outcome depends on the configuration, and a corpus
// case that means two things measures neither.
//
// func rankComplete(colour: Colour)->s32
// {
//     switch #complete colour
//     {
//     case .Red:   return 1
//     case .Green: return 2
//     case .Blue:  return 3
//     }
// }

// --- Sound ---

// A declared member converts back to its own value.
func roundTripDeclaredMember()->bool
{
    let raw = cast(s32) Colour.Green
    return cast(Colour) raw == Colour.Green
}

// A flags enum accepts combinations by design, so any rule on enum conversion has to exclude
// it. Pinned so a future rule does not break it.
func flagsCombine()->bool
{
    let both = Access.Read | Access.Write
    return both & Access.Read and both & Access.Write
}

#test
{
    Swag.assert(roundTripDeclaredMember())
    Swag.assert(flagsCombine())
}
