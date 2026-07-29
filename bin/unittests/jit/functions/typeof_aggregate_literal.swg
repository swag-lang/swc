#global private

func typeofMixedArrayLiteral()->bool
{
    #assert(#typeof([1, 2.5]) == const [2] f32)
    let values = [1, 2.5]
    let idx    = 1
    return values[0] == 1.0'f32 and values[idx] == 2.5'f32
}

func typeofWideArrayLiteral()->bool
{
    #assert(#typeof([1, 5_000_000_000]) == const [2] s64)
    let values = [1, 5_000_000_000]
    let idx    = 1
    return values[0] == 1's64 and values[idx] == 5_000_000_000's64
}

// An untyped element adapts to a suffixed sibling instead of widening it, so a narrow suffix
// still drives the whole literal. A reflected literal must report the type the very same literal
// receives through a variable declaration.
func typeofNarrowSuffixArrayLiteral()->bool
{
    #assert(#typeof([1'u8, 2, 3]) == const [3] u8)
    #assert(#sizeof([1'u8, 2, 3]) == 3)

    let values = [1'u8, 2, 3]
    #assert(#typeof(values) == [3] u8)
    #assert(#sizeof(values) == 3)

    let idx = 2
    return values[0] == 1'u8 and values[idx] == 3'u8
}

func typeofSignedNarrowSuffixArrayLiteral()->bool
{
    #assert(#typeof([-1's16, 2, 3]) == const [3] s16)
    let values = [-1's16, 2, 3]
    let idx    = 0
    return values[idx] == -1's16 and values[1] == 2's16
}

// A suffixed element that cannot hold an untyped sibling still promotes: unification stays
// value-aware, the suffix is a seed and not a cap.
func typeofOverflowingUntypedSibling()->bool
{
    #assert(#typeof([1'u8, 300]) == const [2] s32)
    let values = [1'u8, 300]
    let idx    = 1
    return values[0] == 1's32 and values[idx] == 300's32
}

#test
{
    const mixedOk        = #run typeofMixedArrayLiteral()
    const wideOk         = #run typeofWideArrayLiteral()
    const narrowOk       = #run typeofNarrowSuffixArrayLiteral()
    const signedNarrowOk = #run typeofSignedNarrowSuffixArrayLiteral()
    const overflowOk     = #run typeofOverflowingUntypedSibling()
    #assert(mixedOk)
    #assert(wideOk)
    #assert(narrowOk)
    #assert(signedNarrowOk)
    #assert(overflowOk)
}
