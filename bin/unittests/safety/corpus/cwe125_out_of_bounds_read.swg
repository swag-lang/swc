#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-125 - Out-of-bounds read
//
// The read sink, separated from the write sink of CWE-787 because they lower differently:
// a read folds into an addressing mode, a write does not.
//
// Swag: every sized value - array, slice, string - carries its count, and indexing one is
// guarded. Slicing is guarded as a range rather than as a point.
// -----------------------------------------------------------------------------

// --- Faults ---

#[Swag.Safety(.BoundCheck, true)]
func readArray(index: u64)->s32
{
    var values = [10, 20, 30]
    return values[index]     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run readArray(opaqueU64(3))
}

#[Swag.Safety(.BoundCheck, true)]
func readSlice(index: u64)->s32
{
    var storage        = [10, 20, 30]
    let view: [..] s32 = storage
    return view[index]     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run readSlice(opaqueU64(3))
}

#[Swag.Safety(.BoundCheck, true)]
func readString(index: u64)->u8
{
    let text = "abc"
    return text[index]     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run readString(opaqueU64(3))
}

// Slicing past the end is a range check, not a point check.
#[Swag.Safety(.BoundCheck, true)]
func sliceBeyondEnd(last: u64)->s32
{
    var storage        = [10, 20, 30]
    let view: [..] s32 = storage[0 to last]     // swc-expected-error {{safety_err_runtime}}
    return view[0]
}

#test
{
    #run sliceBeyondEnd(opaqueU64(3))
}

// --- Sound ---

func readLastElement()->s32
{
    var values = [10, 20, 30]
    return values[values.count - 1]
}

#test
{
    Swag.assert(readLastElement() == 30)
    let text = "abc"
    Swag.assert(text[2] == 'c')
}
