#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-590 - Free of memory not on the heap
//
// A frame address, a global, or a string literal is handed to the allocator. The allocator
// then writes its own bookkeeping over storage it never handed out.
//
// Swag: proven at compile time, and reported at the CALL rather than inside the allocator,
// because the route from the borrowed local to the freeing parameter is what the summary
// records. It needs no allocator cooperation and no runtime guard.
// -----------------------------------------------------------------------------

var globalValue: s32

// --- Faults ---

#[Swag.Sanity(.Lifecycle, true)]
func freeFrameAddress()
{
    var value: s32
    heapFree(&value, 4)     // swc-expected-error {{sanity_err_free_borrowed}}
}

#[Swag.Sanity(.Lifecycle, true)]
func freeElementAddress()
{
    var values: [4] s32
    heapFree(&values[1], 4)     // swc-expected-error {{sanity_err_free_borrowed}}
}

// --- Sound ---

#[Swag.Sanity(.Lifecycle, true)]
func freeOwnAllocation()
{
    let pointer = heapAlloc(4)
    heapFree(pointer, 4)
}

// A global is not frame storage, so the borrow rules leave it alone. Releasing one is still
// wrong, and nothing here claims otherwise: it is simply not this rule's question, and the
// case is pinned so a future rule that DOES judge it shows up as a change.
#[Swag.Sanity(.Lifecycle, true)]
func borrowGlobalWithoutFreeing()->*s32
{
    return &globalValue
}

#test
{
    freeOwnAllocation()
    Swag.assert(borrowGlobalWithoutFreeing() == &globalValue)
}
