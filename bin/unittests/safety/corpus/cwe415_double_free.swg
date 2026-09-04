#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-415 - Double free
//
// The same allocation is released twice. In a real allocator the second release corrupts the
// free list, and the failure surfaces inside an unrelated allocation far from the fault.
//
// Swag: proven at compile time on the direct shape, through the same FREES summary that
// carries CWE-416. The gap is ownership: nothing stops a value that owns a release from
// being copied, and then each copy releases the same block.
// -----------------------------------------------------------------------------

// --- Faults ---

#[Swag.Sanity(.Lifecycle, true)]
func freeTwice()
{
    let pointer = cast(*s32) heapAlloc(4)
    heapFree(pointer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    heapFree(pointer, 4)     // swc-expected-error {{sanity_err_double_free}}
}

#test
{
    #run freeTwice()
}

// Through a wrapper, so the summary has to chain. As in cwe416, the body is reached the
// ordinary way rather than through '#run'.
#[Swag.Sanity(.Lifecycle, true)]
func releaseWrapper(pointer: *s32)
{
    heapFree(pointer, 4)
}

#[Swag.Sanity(.Lifecycle, true)]
func freeTwiceThroughWrapper()
{
    let pointer = cast(*s32) heapAlloc(4)
    releaseWrapper(pointer)     // swc-expected-note {{sanity_note_pointer_released_here}}
    releaseWrapper(pointer)     // swc-expected-error {{sanity_err_double_free}}
}

#test
{
    freeTwiceThroughWrapper()
}

// --- Known misses ---

// GAP compiler.safety.002 - a value that OWNS a release is copied like an integer, and both
// copies release the same block at scope exit. Nothing is reported, in any configuration:
// this is the single largest ownership hole, and the one every ownership language closes by
// making a type with a destructor non-copyable. Left commented because it really does
// double-free and corrupts the compile-time heap.
//
// struct Owner
// {
//     pointer: *s32?
// }
//
// impl Owner
// {
//     mtd opDrop()
//     {
//         if .pointer != null
//         {
//             heapFree(.pointer!, 4)
//             .pointer = null
//         }
//     }
// }
//
// #test
// {
//     var first: Owner
//     first.pointer = cast(*s32) heapAlloc(4)
//     var second = first          // expected: a copy of an owning value must be rejected
//     discard second
// }

// GAP compiler.safety.002 - the same fault without 'opDrop': a plain struct carrying a
// pointer, released through a helper, copied in between. The analysis has no notion of an
// owner here at all.
//
// struct Handle { pointer: *s32? }
//
// #[Swag.Sanity(.Lifecycle, true)]
// func releaseHandle(handle: *Handle)
// {
//     if handle.pointer != null
//     {
//         heapFree(handle.pointer!, 4)
//         handle.pointer = null
//     }
// }
//
// #test
// {
//     var first: Handle
//     first.pointer = cast(*s32) heapAlloc(4)
//     var second = first
//     releaseHandle(&first)
//     releaseHandle(&second)     // expected: the same block, released twice
// }

// --- Sound ---

// Two distinct allocations released once each.
#[Swag.Sanity(.Lifecycle, true)]
func freeTwoBlocks()
{
    let first  = cast(*s32) heapAlloc(4)
    let second = cast(*s32) heapAlloc(4)
    heapFree(first, 4)
    heapFree(second, 4)
}

// Reallocating between the two releases makes the second one legitimate.
#[Swag.Sanity(.Lifecycle, true)]
func freeReallocateFree()
{
    var pointer = cast(*s32) heapAlloc(4)
    heapFree(pointer, 4)
    pointer = cast(*s32) heapAlloc(4)
    heapFree(pointer, 4)
}

#test
{
    freeTwoBlocks()
    freeReallocateFree()
}
