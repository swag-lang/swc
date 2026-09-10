#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-590 - Free of memory not on the heap
//
// A frame address, a global, or a string literal is handed to the allocator. The allocator
// then writes its own bookkeeping over storage it never handed out.
//
// Swag: proven at compile time, and reported at the CALL rather than inside the allocator.
// Frame storage is caught by the route the summary records from the borrowed local to the
// freeing parameter; a global is caught by its provenance, which the value analysis proves
// without a summary. Neither needs allocator cooperation or a runtime guard.
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

// A global outlives every scope, so the borrow rules leave it alone - and its address is
// still not something the allocator handed out.
#[Swag.Sanity(.Lifecycle, true)]
func freeGlobalAddress()
{
    heapFree(&globalValue, 4)     // swc-expected-error {{sanity_err_free_global}}
}

var globalTable: [4] s32

#[Swag.Sanity(.Lifecycle, true)]
func freeGlobalElementAddress()
{
    heapFree(&globalTable[2], 4)     // swc-expected-error {{sanity_err_free_global}}
}

// --- Sound ---

#[Swag.Sanity(.Lifecycle, true)]
func freeOwnAllocation()
{
    let pointer = heapAlloc(4)
    heapFree(pointer, 4)
}

// Borrowing a global without releasing it is ordinary code.
#[Swag.Sanity(.Lifecycle, true)]
func borrowGlobalWithoutFreeing()->*s32
{
    return &globalValue
}

// What a global HOLDS is a different question from where the global lives: releasing an
// allocation a global points at is exactly what a global owner is for.
var globalOwned: *s32?

#[Swag.Sanity(.Lifecycle, true)]
func freeWhatAGlobalHolds()->s32
{
    globalOwned    = cast(*s32) heapAlloc(4)
    globalOwned![] = 6
    let value = globalOwned![]
    heapFree(globalOwned!, 4)
    globalOwned = null
    return value
}

// A backend proof only runs on a function that is code-generated, and a '#test' calling
// one that errors never executes - so the faults get a body of their own and the sound
// half keeps running.
#test
{
    freeGlobalAddress()
    freeGlobalElementAddress()
}

#test
{
    freeOwnAllocation()
    Swag.assert(borrowGlobalWithoutFreeing() == &globalValue)
    Swag.assert(freeWhatAGlobalHolds() == 6)
}
