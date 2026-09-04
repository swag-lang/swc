#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-193 - Off-by-one error
//
// One element too many, one too few, or the wrong end of a range.
//
// Swag has its own version of this: the upper bound of a slice range is INCLUSIVE, so
// 'x[0 to count]' names one element past the end while reading like the half-open form every
// neighbouring language uses. 'until' is the exclusive spelling.
// -----------------------------------------------------------------------------

// --- Faults ---

// 'to' is inclusive, so this asks for 'count + 1' elements.
#[Swag.Safety(.BoundCheck, true)]
func sliceToCount(count: u64)->s32
{
    var storage        = [10, 20, 30]
    let view: [..] s32 = storage[0 to count]     // swc-expected-error {{safety_err_runtime}}
    return view[0]
}

#test
{
    #run sliceToCount(opaqueU64(3))
}

// The loop runs one turn too many.
#[Swag.Safety(.BoundCheck, true)]
func loopOnePastEnd(count: u64)->s32
{
    var storage = [10, 20, 30]
    var total   = 0's32
    for index in 0 to count do
        total += storage[index]     // swc-expected-error {{safety_err_runtime}}
    return total
}

#test
{
    #run loopOnePastEnd(opaqueU64(3))
}

// An inverted range with CONSTANT bounds is rejected outright: the inversion is certain, so
// it does not wait for run time.
//
// func constantInvertedRange()->s32
// {
//     var total = 0's32
//     for index in 4 until 2 do     // error: range lower bound 4 is greater than upper bound 2
//         total += index
//     return total
// }

// With computed bounds an inverted range is EMPTY, not a fault: the loop asks a predicate and
// the entry test answers it, so the body runs zero times. Only slicing keeps a range check,
// because it asks for a length rather than a predicate.
#[Swag.Safety(.BoundCheck, true)]
func invertedRangeRunsEmpty(low, high: s32)->s32
{
    var turns = 0's32
    for index in low until high do
        turns += 1
    return turns
}

#test
{
    Swag.assert(invertedRangeRunsEmpty(opaqueS32(4), opaqueS32(2)) == 0)
}

// --- Sound ---

func sliceUntilCount()->s64
{
    var storage        = [10, 20, 30]
    let view: [..] s32 = storage[0 until storage.count]
    return view.count
}

#test
{
    Swag.assert(sliceUntilCount() == 3)

    // An empty 'until' range is empty, not inverted: it runs zero turns and does not panic.
    var turns = 0's32
    for index in opaqueS32(2) until opaqueS32(2) do
        turns += 1
    Swag.assert(turns == 0)
}
