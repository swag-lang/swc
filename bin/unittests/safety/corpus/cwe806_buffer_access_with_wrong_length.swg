#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-806 - Buffer access using size of source buffer
//
// The access is bounded, but by the wrong buffer's size. The check is there and it answers
// the wrong question.
//
// Swag: a slice pairs storage with a count, and every access is checked against THAT count.
// So the class survives in exactly one form - when the pair itself is a lie. Building the
// pair is 'Swag.makeSlice', which takes the count on trust; from that point on the bound
// check faithfully enforces the wrong bound.
// -----------------------------------------------------------------------------

// --- Faults ---

// The count comes from the source buffer, and the view addresses the destination.
#[Swag.Safety(.BoundCheck, true)]
func viewWithSourceCount(index: u64)->u8
{
    var source:      [16] u8
    var destination: [4] u8
    let view = Swag.makeSlice(&destination[0], source.count)
    return view[index]     // reads past 'destination', but 'view' says it is in range
}

// GAP compiler.safety.006 - 'Swag.makeSlice' takes the count on trust, so the read above is
// checked against a count that does not describe the storage. The bound check answers
// truthfully and the answer is wrong. The call is what needs the marker; the access after it
// cannot be blamed. Left commented because it really does read out of bounds.
//
// #test
// {
//     Swag.assert(viewWithSourceCount(opaqueU64(8)) == 0)
// }

// Once the pair is honest, the same access IS judged: the fault is the count, not the index.
#[Swag.Safety(.BoundCheck, true)]
func viewWithOwnCount(index: u64)->u8
{
    var destination: [4] u8
    let view = Swag.makeSlice(&destination[0], destination.count)
    return view[index]     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run viewWithOwnCount(opaqueU64(8))
}

// --- Sound ---

// A sized value converts to a slice without anyone naming a count, which is why the
// idiomatic spelling cannot carry this fault at all.
func viewFromSizedValue()->s64
{
    var storage: [4] u8
    let view: [..] u8 = storage
    return view.count
}

#test
{
    Swag.assert(viewFromSizedValue() == 4)
}
