#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-197 / CWE-195 / CWE-194 - Numeric truncation, signed-to-unsigned conversion, and
// unexpected sign extension
//
// A value crosses into a type that cannot hold it. In C these are silent conversions, and
// they are how a length check on a 'long' fails to protect a copy indexed by an 'int'.
//
// Swag: a conversion that can lose information is checked. Narrowing needs an explicit
// 'cast', the cast is guarded under '.Overflow', and '#wrap' is how a caller asks for the
// truncating result on purpose.
// -----------------------------------------------------------------------------

// --- Faults ---

// A value that does not fit the narrower type.
#[Swag.Safety(.Overflow, true)]
func truncateToS8(value: s32)->s8
{
    return cast(s8) value     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run truncateToS8(opaqueS32(255))
}

// Signed to unsigned, where the bit pattern survives and the meaning does not (CWE-195).
#[Swag.Safety(.Overflow, true)]
func negativeToUnsigned(value: s8)->u8
{
    return cast(u8) value     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run negativeToUnsigned(opaqueS8(-1))
}

// The exploit shape: a size validated as signed, used as unsigned. The conversion is where
// the check stops applying, and it is guarded.
#[Swag.Safety(.Overflow, true)]
func validatedSignedUsedAsUnsigned(length: s32)->u32
{
    if length > 1024 do
        return 0
    return cast(u32) length     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run validatedSignedUsedAsUnsigned(opaqueS32(-1))
}

// --- Sound ---

// '#wrap' asks for the truncating result explicitly.
func truncatesOnRequest(value: s32)->s8
{
    return cast #wrap (s8) value
}

// Widening loses nothing and needs no cast at all.
func widensImplicitly(value: s8)->s32
{
    return value
}

// A value that fits passes the guard untouched.
#[Swag.Safety(.Overflow, true)]
func fitsInTarget(value: s32)->s8
{
    return cast(s8) value
}

#test
{
    Swag.assert(truncatesOnRequest(opaqueS32(255)) == -1)
    Swag.assert(widensImplicitly(opaqueS8(-1)) == -1)
    Swag.assert(fitsInTarget(opaqueS32(120)) == 120)
}
