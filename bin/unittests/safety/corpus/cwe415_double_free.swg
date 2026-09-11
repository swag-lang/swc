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

// GAP compiler.safety.020 - the same fault without 'opDrop': a plain struct carrying a
// pointer, released through a helper, copied in between. Nothing marks the type as an owner,
// and the caller has no field-release summary. The retaining allocator makes the second
// release observable without handing it to the real allocator.
struct Handle { pointer: *s32? }

#[Swag.Sanity(.Lifecycle, true)]
func releaseHandle(handle: *Handle)
{
    if handle.pointer != null
    {
        heapFree(handle.pointer, 4)
        handle.pointer = null
    }
}

#test
{
    let context = Swag.getContext()
    var heap    = RetainedHeap{base: context.allocator!}
    context.allocator = &heap
    defer context.allocator = heap.base

    var first: Handle
    first.pointer = cast(*s32) heapAlloc(4)
    var second = first
    releaseHandle(&first)
    releaseHandle(&second)
    Swag.assert(first.pointer == null)
    Swag.assert(second.pointer == null)
    Swag.assert(heap.count == 1)
    Swag.assert(heap.frees == 2)
    Swag.assert(heap.duplicates == 1)
    Swag.assert(heap.liveCount() == 0)
}

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
    let context = Swag.getContext()
    var heap    = RetainedHeap{base: context.allocator!}
    context.allocator = &heap
    defer context.allocator = heap.base

    freeTwoBlocks()
    freeReallocateFree()
    Swag.assert(heap.count == 4)
    Swag.assert(heap.frees == 4)
    Swag.assert(heap.duplicates == 0)
    Swag.assert(heap.liveCount() == 0)
}

// Resetting one handle makes a repeated call harmless; copying it created the fault above.
#test
{
    let context = Swag.getContext()
    var heap    = RetainedHeap{base: context.allocator!}
    context.allocator = &heap
    defer context.allocator = heap.base

    var handle: Handle
    handle.pointer = cast(*s32) heapAlloc(4)
    releaseHandle(&handle)
    releaseHandle(&handle)
    Swag.assert(heap.count == 1)
    Swag.assert(heap.frees == 1)
    Swag.assert(heap.duplicates == 0)
    Swag.assert(heap.liveCount() == 0)
}
