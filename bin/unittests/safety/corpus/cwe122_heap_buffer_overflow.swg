#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-122 - Heap-based buffer overflow
//
// A write or a read reaches past the end of a heap allocation.
//
// Swag: a heap block is addressed through a block pointer, which carries no extent, so
// nothing bounds it. Pairing the block with a count - the slice a container hands out - is
// what makes the access checkable, and that form IS guarded.
// -----------------------------------------------------------------------------

// --- Faults ---

// Once the block is paired with the count it really has, the read is judged.
#[Swag.Safety(.BoundCheck, true)]
func heapReadThroughSlice(index: u64)->u8
{
    let block = cast([*] u8) heapAlloc(8)
    let view  = Swag.makeSlice(block, 8)
    let value = view[index]     // swc-expected-error {{safety_err_runtime}}
    heapFree(block, 8)
    return value
}

#test
{
    #run heapReadThroughSlice(opaqueU64(8))
}

// GAP compiler.safety.006 - a bare '[*] T' has no extent, so indexing one past the end of
// the block it addresses is not judged by anything: no static proof, no runtime guard.
// This is the shape the unsafe-surface entry has to cover. Left commented because it
// really does read out of bounds.
//
// func heapReadThroughBlockPointer(index: u64)->u8
// {
//     let block = cast([*] u8) heapAlloc(8)
//     let value = block[index]     // reads past the allocation, silently
//     heapFree(block, 8)
//     return value
// }

// --- Sound ---

func heapReadInRange()->u8
{
    let block = cast([*] u8) heapAlloc(8)
    let view  = Swag.makeSlice(block, 8)
    view[0] = 42
    let value = view[0]
    heapFree(block, 8)
    return value
}

#test
{
    Swag.assert(heapReadInRange() == 42)
}
