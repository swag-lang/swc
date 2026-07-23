#global private

// ---------------------------------------------------------------------------
// Provable out-of-bounds access on a fixed-size stack array: the index is a
// tracked constant, so the accessed frame offset is exact and provably outside
// the variable's storage. Each case is marked `#[Swag.Sanity(.BoundCheck, true)]`
// so the static check runs (and aborts codegen) in every build config; the RUNTIME
// guard is explicitly off — its panic call gives the frame a call area, and the
// codegen then rebases the stack-base register, which stands the static check down
// (see Sanitizer::stackBaseStable).
// ---------------------------------------------------------------------------

// Read past the end through a variable index.
#[Swag.Sanity(.BoundCheck, true), Swag.Safety(.BoundCheck, false)]
#test
{
    var a: [4] s32
    var i = 5
    let x = a[i]     // swc-expected-error {{sanity_err_out_of_bounds}}
    discard x
}

// Write past the end.
#[Swag.Sanity(.BoundCheck, true), Swag.Safety(.BoundCheck, false)]
#test
{
    var a: [4] s32
    var i = 4
    a[i] = 1     // swc-expected-error {{sanity_err_out_of_bounds}}
}

// The constant index propagates through a copy.
#[Swag.Sanity(.BoundCheck, true), Swag.Safety(.BoundCheck, false)]
#test
{
    var a: [4] s32
    var i = 9
    var j = i
    let x = a[j]     // swc-expected-error {{sanity_err_out_of_bounds}}
    discard x
}

// ---------------------------------------------------------------------------
// Silent cases.
// ---------------------------------------------------------------------------

// In-bounds accesses, including both edges.
#[Swag.Sanity(.BoundCheck, true)]
#test
{
    var a: [4] s32
    var lo = 0
    var hi = 3
    a[lo] = 1
    a[hi] = 2
    @assert(a[lo] == 1)
    @assert(a[hi] == 2)
}

// An unknown index is never flagged (the runtime guard covers it).
#[Swag.Sanity(.BoundCheck, true)]
func boundCheckUnknownIndex(i: s32)->s32
{
    var a: [4] s32
    a[0] = 7
    return a[i]
}

// An access beyond an inner array that stays inside the enclosing variable is not
// provably a fault at this granularity: silent by design.
struct BoundCheckPair
{
    arr:  [2] s32
    tail: s32
}

#[Swag.Sanity(.BoundCheck, true)]
func boundCheckWithinStruct()->s32
{
    var s: BoundCheckPair
    s.tail = 3
    var i = 1
    return s.arr[i]
}
