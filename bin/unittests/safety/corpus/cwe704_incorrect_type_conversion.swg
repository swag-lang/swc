#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-704 - Incorrect type conversion or cast
//
// A value is converted to a type whose invariants it does not satisfy. Read here as the enum
// case, because that is where the converted value goes on to select control flow.
//
// Swag rejects runtime integer conversions to ordinary enums. Compile-time values must match a
// declared member; EnumFlags remains the explicit representation for bit combinations.
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

// --- Rejected runtime conversion ---

func forgeEnumValue(raw: s32)->Colour
{
    return cast(Colour, raw)     // swc-expected-error {{sema_err_cannot_cast}}
}

// --- Sound ---

// A constant value for a declared member converts back to its own value.
func roundTripDeclaredMember()->bool
{
    return cast(Colour, cast(s32, Colour.Green)) == Colour.Green
}

// A flags enum accepts runtime combinations by design.
func flagsCombine()->bool
{
    let both = Access.Read | Access.Write
    return both & Access.Read and both & Access.Write
}

#test
{
    Swag.require(roundTripDeclaredMember())
    Swag.require(flagsCombine())
}
