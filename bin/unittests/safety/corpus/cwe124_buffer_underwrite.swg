#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-124 - Buffer underwrite
//
// The access lands BEFORE the start of the buffer. In C this is a distinct class because a
// negative offset is representable in the index type.
//
// Swag: an index is unsigned wherever a sized value is indexed, so a negative index does not
// address memory below the buffer - it wraps to a very large offset and is caught by the same
// bound check as an overrun. There is no separate underwrite to detect on a sized value.
// -----------------------------------------------------------------------------

// --- Faults ---

// A negative index is not representable: the conversion is what fails first, under the
// overflow guard, before any access happens.
#[Swag.Safety(.Overflow, true), Swag.Safety(.BoundCheck, true)]
func negativeIndex(offset: s64)->s32
{
    var values = [10, 20, 30]
    return values[cast(u64) offset]     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run negativeIndex(opaqueS64(-1))
}

// Wrapping the conversion deliberately keeps the huge offset, which the bound check rejects.
#[Swag.Safety(.Overflow, false), Swag.Safety(.BoundCheck, true)]
func wrappedNegativeIndex(offset: s64)->s32
{
    var values = [10, 20, 30]
    return values[cast #wrap (u64) offset]     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run wrappedNegativeIndex(opaqueS64(-1))
}

// GAP compiler.safety.006 - a block pointer walks below its allocation with no diagnostic
// and no guard: pointer arithmetic carries neither provenance nor extent. Left commented
// because it really does read before the buffer.
//
// func pointerWalksBelow()->s32
// {
//     var values = [10, 20, 30]
//     var cursor = cast([*] s32) &values[0]
//     cursor = cursor - 1
//     return cursor[0]     // reads the word before the array, silently
// }

// --- Sound ---

func lastElementFromEnd()->s32
{
    var values = [10, 20, 30]
    return values[values.count - 1]
}

#test
{
    Swag.assert(lastElementFromEnd() == 30)
}
