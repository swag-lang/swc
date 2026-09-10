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
// carries CWE-416, on a copy of the pointer into a second local, and closed on the ownership
// shape: a value that declares 'opDrop' owns what it releases and states no copy, so two
// owners of one block cannot be written. What is left is the shape nothing marks as an owner
// at all.
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

// The two releases go through two names of the same pointer. A copy between locals is a
// proven equality, so the second release is judged whichever name it is written through.
#[Swag.Sanity(.Lifecycle, true)]
func freeTwiceThroughAlias()
{
    let pointer = cast(*s32) heapAlloc(4)
    let other   = pointer
    heapFree(pointer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    heapFree(other, 4)       // swc-expected-error {{sanity_err_double_free}}
}

#test
{
    freeTwiceThroughAlias()
}

// A value that owns a release is not copied like an integer: declaring 'opDrop' states the
// ownership, and the copy is rejected without the type having to say anything more. This is
// the rule every ownership language shares, and it closes the whole class rather than one
// shape of it.
struct Owner
{
    pointer: *s32?
}

impl Owner
{
    mtd opDrop()
    {
        if .pointer != null
        {
            heapFree(.pointer, 4)
            .pointer = null
        }
    }
}

// A struct owning through a member states no copy either.
struct OwnerHolder
{
    owner: Owner
}

#test
{
    var first: Owner
    first.pointer = cast(*s32) heapAlloc(4)
    var second = first     // swc-expected-error {{sema_err_cannot_copy_owning}}
    discard second
}

#test
{
    var first: OwnerHolder
    var second = first     // swc-expected-error {{sema_err_cannot_copy_owning}}
    discard second
}

// --- Known misses ---

// GAP compiler.safety.004 - the same fault without 'opDrop': a plain struct carrying a
// pointer, released through a helper, copied in between. Nothing marks the type as an owner,
// so no ownership rule can see the second one; this is the half a runtime net is for.
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
