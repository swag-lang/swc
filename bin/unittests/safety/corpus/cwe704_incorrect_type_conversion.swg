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

// The conversion remains unchecked, but an explicitly guarded complete switch rejects
// its result at dispatch. Naming the guard makes this case independent of the preset.
#[Swag.Safety(.Switch, true)]
func rankComplete(colour: Colour)->s32
{
    switch #complete colour     // swc-expected-error {{safety_err_runtime}}
    {
    case .Red:   return 1
    case .Green: return 2
    case .Blue:  return 3
    }
}

#test
{
    #run rankComplete(forgeEnumValue(opaqueS32(99)))
}

#test
{
    Swag.assert(rankComplete(forgeEnumValue(opaqueS32(0))) == 1)
    Swag.assert(rankComplete(forgeEnumValue(opaqueS32(1))) == 2)
    Swag.assert(rankComplete(forgeEnumValue(opaqueS32(2))) == 3)
}

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
