#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-416 - Use after free
//
// The pointer is read after the memory it addresses has been released.
//
// Swag: a compile-time proof, not a guard. The analysis infers which functions FREE what
// their parameters point at - the summary is seeded by a call reaching 'Swag.IAllocator.free'
// and chains through wrappers and across modules - then marks the slot at the call site. It
// is a must-analysis: what it cannot prove is a miss, never a false positive.
//
// A copy of a pointer between two locals is proven, and so is a release separated from its
// use by an ordinary call: neither a callee nor a store through a pointer can reach a local
// whose address the function never forms. Handing that address over is what ends the proof,
// and a release on only one path is never one.
//
// The cases below distinguish those proofs from the conditional-release and escaped-storage
// shapes the analysis deliberately says nothing about.
// -----------------------------------------------------------------------------

// --- Faults ---

#[Swag.Sanity(.Lifecycle, true)]
func readAfterFree()->s32
{
    let pointer = cast(*s32) heapAlloc(4)
    pointer[] = 1
    heapFree(pointer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return pointer[]         // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    #run readAfterFree()
}

#[Swag.Sanity(.Lifecycle, true)]
func writeAfterFree()
{
    let pointer = cast(*s32) heapAlloc(4)
    heapFree(pointer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    pointer[] = 2            // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    #run writeAfterFree()
}

// The release goes through one more wrapper, which inherits the summary through the fixpoint
// that chains them. This case exercises ordinary code generation. The compile-time path is
// covered by sanity/jit_use_after_free_summary.swg, which retains the allocation while #run
// executes so a missing diagnostic cannot corrupt the compiler's heap.
#[Swag.Sanity(.Lifecycle, true)]
func releaseWrapper(pointer: *s32)
{
    heapFree(pointer, 4)
}

#[Swag.Sanity(.Lifecycle, true)]
func readAfterWrappedFree()->s32
{
    let pointer = cast(*s32) heapAlloc(4)
    releaseWrapper(pointer)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return pointer[]            // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    discard readAfterWrappedFree()
}

// --- Proven field, element, cast and generic-release cases ---

// The shape almost every real use-after-free has: the freed object is read through a FIELD
// rather than dereferenced whole. The address is formed by arithmetic, so what carries the
// fault is the pointer's provenance rather than the value the register holds.
struct Node
{
    first, second: s32
}

#[Swag.Sanity(.Lifecycle, true)]
func readFieldAfterFree()->s32
{
    let node = cast(*Node) heapAlloc(8)
    node.second = 1
    heapFree(node, 8)      // swc-expected-note {{sanity_note_pointer_released_here}}
    return node.second     // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    discard readFieldAfterFree()
}

// The first field sits at offset zero, and is judged like any other.
#[Swag.Sanity(.Lifecycle, true)]
func readFirstFieldAfterFree()->s32
{
    let node = cast(*Node) heapAlloc(8)
    heapFree(node, 8)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return node.first     // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    discard readFirstFieldAfterFree()
}

// An ELEMENT of a freed buffer: the indexed forms address memory through a base and an
// index, a shape the instruction table cannot describe with a single offset operand.
#[Swag.Sanity(.Lifecycle, true)]
func readElementAfterFree(index: u64)->s32
{
    let block = cast([*] s32) heapAlloc(16)
    heapFree(block, 16)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return block[index]     // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    discard readElementAfterFree(opaqueU64(0))
}

// Writing through a freed buffer is the same question with the other sink.
#[Swag.Sanity(.Lifecycle, true)]
func writeElementAfterFree(index: u64)
{
    let block = cast([*] s32) heapAlloc(16)
    heapFree(block, 16)     // swc-expected-note {{sanity_note_pointer_released_here}}
    block[index] = 1        // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    writeElementAfterFree(opaqueU64(0))
}

// A cast written at the free site does not hide the release: the pointer keeps its
// provenance through the conversion.
#[Swag.Sanity(.Lifecycle, true)]
func readAfterCastFree(index: u64)->s32
{
    let block = cast([*] s32) heapAlloc(16)
    heapFree(cast(*void) block, 16)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return block[index]                 // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    discard readAfterCastFree(opaqueU64(0))
}

// Copying the pointer into a second local is a proven equality: neither name can change
// without a store the analysis sees, so releasing one releases both.
#[Swag.Sanity(.Lifecycle, true)]
func readThroughAlias()->s32
{
    let pointer = cast(*s32) heapAlloc(4)
    let other   = pointer
    pointer[] = 1
    heapFree(pointer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return other[]           // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    discard readThroughAlias()
}

// The same equality read the other way: the release goes through the copy, and the original
// is the one dereferenced.
#[Swag.Sanity(.Lifecycle, true)]
func readOriginalAfterAliasFree()->s32
{
    let pointer = cast(*s32) heapAlloc(4)
    let other   = pointer
    heapFree(other, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return pointer[]       // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    discard readOriginalAfterAliasFree()
}

// The shape a real use-after-free has: something happens between the release and the use.
// An ordinary call cannot reach a local whose address the function never forms, so the
// release still holds on the other side of it.
#[Swag.Sanity(.Lifecycle, true)]
func readAfterFreeAcrossCall()->s32
{
    let pointer = cast(*s32) heapAlloc(4)
    heapFree(pointer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    discard opaqueS32(1)
    return pointer[]     // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    discard readAfterFreeAcrossCall()
}

// The shape a real use-after-free almost always has: the released block belonged to an
// OBJECT, and the same object is asked for it again. Nothing here is in the frame, so
// the object is named by where its own pointer lives.
struct Owner
{
    buffer: *s32?
    count:  s32
}

#[Swag.Sanity(.Lifecycle, true)]
func readObjectFieldAfterFree()->s32
{
    let owner = cast(*Owner) heapAlloc(16)
    owner.buffer = cast(*s32) heapAlloc(4)
    heapFree(owner.buffer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return owner.buffer[]         // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    discard readObjectFieldAfterFree()
}

// The release crosses the function boundary: what comes back is a dangling pointer, and
// the caller has no way to know. CWE-562 is the same rule on frame storage, and Swag
// reads both the same way.
#[Swag.Sanity(.Lifecycle, true)]
func returnReleasedBlock()->*s32
{
    let pointer = cast(*s32) heapAlloc(4)
    heapFree(pointer, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return pointer           // swc-expected-error {{sanity_err_return_released}}
}

#test
{
    discard returnReleasedBlock()
}

// The release helper that then touches what it released. A parameter has no frame slot
// of its own, so the register holding it is what carries the release.
#[Swag.Sanity(.Lifecycle, true)]
func destroyThenTouch(node: *Node)
{
    heapFree(node, 8)     // swc-expected-note {{sanity_note_pointer_released_here}}
    node.first = 0        // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    destroyThenTouch(cast(*Node) heapAlloc(8))
}

// A local table of pointers is the shape a program keeps its owned blocks in. An element
// is a slot like any other once the index is known.
#[Swag.Sanity(.Lifecycle, true)]
func readTableElementAfterFree()->s32
{
    var table: [4] (*s32?)
    table[0] = cast(*s32) heapAlloc(4)
    heapFree(table[0]!, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return table[0]![]         // swc-expected-error {{sanity_err_use_after_free}}
}

#test
{
    discard readTableElementAfterFree()
}

// --- Known misses ---

// BY DESIGN - an object is named by one storage slot, not an arbitrary chain of fields.
// A retaining heap makes this documented miss executable without a real stale heap read.
struct NestedOwner { child: *Owner? }

#[Swag.Sanity(.Lifecycle, true)]
func readNestedFieldAfterFree()->s32
{
    let outer = cast(*NestedOwner) heapAlloc(#sizeof(NestedOwner))
    outer.child          = cast(*Owner) heapAlloc(#sizeof(Owner))
    outer.child.buffer   = cast(*s32) heapAlloc(4)
    outer.child.buffer[] = 11
    heapFree(outer.child.buffer, 4)
    return outer.child.buffer[]
}

#test
{
    let context = Swag.getContext()
    var heap    = RetainedHeap{base: context.allocator!}
    context.allocator = &heap
    defer context.allocator = heap.base

    let value = readNestedFieldAfterFree()
    Swag.assert(value == 11)
    Swag.assert(heap.count == 3)
    Swag.assert(heap.frees == 1)
    Swag.assert(heap.liveCount() == 2)
    Swag.assert(heap.duplicates == 0)
}

// GAP compiler.safety.018 - a release on one path only cannot be proven. Retaining the
// allocation lets the corpus exercise BOTH paths, including the stale read, without
// accessing physically freed storage. This pins a limitation, not a static guarantee.
#[Swag.Sanity(.Lifecycle, true)]
func conditionalFree(release: bool)->s32
{
    let pointer = cast(*s32) heapAlloc(4)
    pointer[] = 3
    if release do
        heapFree(pointer, 4)
    return pointer[]
}

#test
{
    let context = Swag.getContext()
    var heap    = RetainedHeap{base: context.allocator!}
    context.allocator = &heap
    defer context.allocator = heap.base

    let kept     = conditionalFree(opaqueBool(false))
    let released = conditionalFree(opaqueBool(true))
    Swag.assert(kept == 3)
    Swag.assert(released == 3)
    Swag.assert(heap.count == 2)
    Swag.assert(heap.frees == 1)
    Swag.assert(heap.liveCount() == 1)
    Swag.assert(heap.duplicates == 0)
}

// --- Sound ---

#[Swag.Sanity(.Lifecycle, true)]
func readNestedFieldBeforeFree()->s32
{
    let outer = cast(*NestedOwner) heapAlloc(#sizeof(NestedOwner))
    outer.child          = cast(*Owner) heapAlloc(#sizeof(Owner))
    outer.child.buffer   = cast(*s32) heapAlloc(4)
    outer.child.buffer[] = 11
    let value = outer.child.buffer[]
    heapFree(outer.child.buffer, 4)
    heapFree(outer.child, #sizeof(Owner))
    heapFree(outer, #sizeof(NestedOwner))
    return value
}

#test
{
    let context = Swag.getContext()
    var heap    = RetainedHeap{base: context.allocator!}
    context.allocator = &heap
    defer context.allocator = heap.base

    let value = readNestedFieldBeforeFree()
    Swag.assert(value == 11)
    Swag.assert(heap.count == 3)
    Swag.assert(heap.frees == 3)
    Swag.assert(heap.liveCount() == 0)
    Swag.assert(heap.duplicates == 0)
}

// Handing the pointer's own storage to a callee ends the proof: the callee can reassign it,
// and it does. Nothing may be reported at the read.
#[Swag.Sanity(.Lifecycle, true)]
func reallocateThrough(slot: **s32)
{
    slot[] = cast(*s32) heapAlloc(4)
}

#[Swag.Sanity(.Lifecycle, true)]
func readAfterFreeThroughEscapedSlot()->s32
{
    var pointer = cast(*s32) heapAlloc(4)
    heapFree(pointer, 4)
    reallocateThrough(&pointer)
    pointer[] = 9
    let value = pointer[]
    heapFree(pointer, 4)
    return value
}

// Reassigning the pointer makes it live again, and the analysis must see that.
#[Swag.Sanity(.Lifecycle, true)]
func reassignedAfterFree()->s32
{
    var pointer = cast(*s32) heapAlloc(4)
    heapFree(pointer, 4)
    pointer   = cast(*s32) heapAlloc(4)
    pointer[] = 7
    let value = pointer[]
    heapFree(pointer, 4)
    return value
}

// Reassigning the field is what correct code does, and the release says nothing after it.
#[Swag.Sanity(.Lifecycle, true)]
func reassignObjectFieldAfterFree()->s32
{
    let owner = cast(*Owner) heapAlloc(16)
    owner.buffer = cast(*s32) heapAlloc(4)
    heapFree(owner.buffer, 4)
    owner.buffer   = cast(*s32) heapAlloc(4)
    owner.buffer[] = 8
    let value = owner.buffer[]
    heapFree(owner.buffer, 4)
    heapFree(owner, 16)
    return value
}

// Releasing one element of a table says nothing about the next one.
#[Swag.Sanity(.Lifecycle, true)]
func readOtherTableElement()->s32
{
    var table: [2] (*s32?)
    table[0]    = cast(*s32) heapAlloc(4)
    table[1]    = cast(*s32) heapAlloc(4)
    table[1]![] = 5
    heapFree(table[0]!, 4)
    let value = table[1]![]
    heapFree(table[1]!, 4)
    return value
}

#test
{
    Swag.assert(reassignObjectFieldAfterFree() == 8)
    Swag.assert(readOtherTableElement() == 5)
    Swag.assert(readAfterFreeThroughEscapedSlot() == 9)
    Swag.assert(reassignedAfterFree() == 7)
}
