#global private
using Swag

// ---------------------------------------------------------------------------
// Proven use-after-free / double-free through the language allocator interface.
// 'myFree' reaches 'IAllocator.free' with its parameter as the request address,
// which seeds its FREES summary; call sites then mark the pointer's slot and any
// later dereference without an intervening reassignment is a proven fault. The
// mark travels to every local proven to hold the same pointer, and survives an
// ordinary call: nothing can reach a local whose address the function never forms.
// Handing that address to a callee ends the proof, and so does a release on only
// one path - both give misses, never reports.
// ---------------------------------------------------------------------------

// The lifecycle analysis is per-function: the helpers must force it too so their
// FREES summaries exist even when sanity is disabled around them, keeping the
// expected errors independent of the surrounding configuration.
#[Swag.Sanity(.Lifecycle, true)]
func myAlloc(size: u64)->*void
{
    var req: AllocatorRequest
    req.size = size
    let allocItf = Swag.getContext().allocator!
    allocItf.alloc(&req)
    return req.address!
}

#[Swag.Sanity(.Lifecycle, true)]
func myFree(ptr: *void, size: u64)
{
    var req: AllocatorRequest
    req.address = ptr
    req.size    = size
    let allocItf = Swag.getContext().allocator!
    allocItf.free(&req)
}

struct UafIndirectResult
{
    values: [3] u64
}

// An indirect return adds a hidden ABI argument before the source parameters. Freeing
// the first source parameter must not make the caller-provided return storage look freed.
#[Swag.Sanity(.Lifecycle, true)]
func uafFreeAndReturn(ptr: *void, size: u64)->UafIndirectResult
{
    myFree(ptr, size)
    return {}
}

#[Swag.Sanity(.Lifecycle, true)]
func uafForwardFreeAndReturn(ptr: *void, size: u64)->UafIndirectResult
{
    return uafFreeAndReturn(ptr, size)
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p      = myAlloc(4)
    let result = uafForwardFreeAndReturn(p, 4)
    Swag.assert(result.values[0] == 0)
}

// Read after free.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p = cast(*s32) myAlloc(4)
    p[] = 1
    myFree(p, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    let x = p[]      // swc-expected-error {{sanity_err_use_after_free}}
    discard x
}

// Write after free.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p = cast(*s32) myAlloc(4)
    myFree(p, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    p[] = 2          // swc-expected-error {{sanity_err_use_after_free}}
}

// Double free.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p = cast(*s32) myAlloc(4)
    myFree(p, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    myFree(p, 4)     // swc-expected-error {{sanity_err_double_free}}
}

// Stack storage is borrowed, never allocator-owned. Passing it to free is a
// certain fault and should explain that ownership distinction at the call site.
#[Swag.Sanity(.Lifecycle, true)]
func rejectFreeBorrowed()
{
    var value: s32     // swc-expected-note {{sema_note_borrow_source_declared_here}}
    var req:   AllocatorRequest
    req.address = &value
    req.size    = #sizeof(s32)
    let allocItf = Swag.getContext().allocator!
    allocItf.free(&req)     // swc-expected-error {{sanity_err_free_borrowed}}
}

// A global's address never came from the allocator either, and unlike frame storage it
// outlives every scope - so the borrow rules say nothing and its provenance does.
var gUafValue: s32

#[Swag.Sanity(.Lifecycle, true)]
func rejectFreeGlobal()
{
    myFree(&gUafValue, #sizeof(s32))     // swc-expected-error {{sanity_err_free_global}}
}

// A backend proof only runs on a function that is code-generated.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    rejectFreeGlobal()
}

// What a global HOLDS is a different question from where the global lives: releasing an
// allocation a global points at is exactly what a global owner is for.
var gUafOwned: *s32?

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    gUafOwned    = cast(*s32) myAlloc(4)
    gUafOwned![] = 9
    Swag.assert(gUafOwned![] == 9)
    myFree(gUafOwned!, 4)
    gUafOwned = null
}

// Reassigning the pointer revalidates it.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var p = cast(*s32) myAlloc(4)
    myFree(p, 4)
    p   = cast(*s32) myAlloc(4)
    p[] = 3
    Swag.assert(p[] == 3)
    myFree(p, 4)
}

// A copy into a second local is a proven equality: the release marks both names.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p = cast(*s32) myAlloc(4)
    let q = p
    p[] = 6
    myFree(p, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    let x = q[]      // swc-expected-error {{sanity_err_use_after_free}}
    discard x
}

// Released through the copy, dereferenced through the original.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p = cast(*s32) myAlloc(4)
    let q = p
    myFree(q, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    let x = p[]      // swc-expected-error {{sanity_err_use_after_free}}
    discard x
}

// Both names released: the second one is a double free whichever it is written through.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p = cast(*s32) myAlloc(4)
    let q = p
    myFree(p, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    myFree(q, 4)     // swc-expected-error {{sanity_err_double_free}}
}

// An ordinary call between the release and the use cannot reach the pointer's storage,
// so the release still holds on the other side of it. The freed local is deliberately
// not the first one in the frame: every slot of the frame has to be nameable there.
#[Swag.Sanity(.Lifecycle, true)]
func opaqueStep(value: s32)->s32
{
    return value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let first = cast(*s32) myAlloc(4)
    let p     = cast(*s32) myAlloc(4)
    myFree(p, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    discard opaqueStep(1)
    let x = p[]     // swc-expected-error {{sanity_err_use_after_free}}
    discard x
    myFree(first, 4)
}

// Handing the pointer's own storage to a callee ends the proof: the callee reassigns it.
#[Swag.Sanity(.Lifecycle, true)]
func reallocateThrough(slot: **s32)
{
    slot[] = cast(*s32) myAlloc(4)
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var p = cast(*s32) myAlloc(4)
    myFree(p, 4)
    reallocateThrough(&p)
    p[] = 8
    Swag.assert(p[] == 8)
    myFree(p, 4)
}

// The commonest shape a real use-after-free has: a buffer an OBJECT owns, released and
// touched again through the same object. Its storage is not in the frame, so the object
// is named by where its own pointer lives and the field by the offset from it.
struct UafNode
{
    data:  *s32?
    count: s32
}

#[Swag.Sanity(.Lifecycle, true)]
func releaseObjectField()->s32
{
    let node = cast(*UafNode) myAlloc(16)
    node.data = cast(*s32) myAlloc(4)
    myFree(node.data!, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return node.data![]       // swc-expected-error {{sanity_err_use_after_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
func releaseFieldOfParameterObject(n: *UafNode)->s32
{
    myFree(n.data!, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return n.data![]       // swc-expected-error {{sanity_err_use_after_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    discard releaseObjectField()

    let node = cast(*UafNode) myAlloc(16)
    node.data = cast(*s32) myAlloc(4)
    discard releaseFieldOfParameterObject(node)
}

// The release helper judged inside its own body: the receiver names the object, so a
// method that releases what it owns and then reaches for it again is proven where it is
// written, with no summary crossing a call.
impl UafNode
{
    #[Swag.Sanity(.Lifecycle, true)]
    mtd releaseThenTouch()
    {
        myFree(.data!, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
        .data![] = 0          // swc-expected-error {{sanity_err_use_after_free}}
    }

    // Putting the field back is what a correct one does, whether with null or with a
    // fresh allocation, and neither may be reported.
    #[Swag.Sanity(.Lifecycle, true)]
    mtd release()
    {
        myFree(.data!, 4)
        .data = null
    }

    #[Swag.Sanity(.Lifecycle, true)]
    mtd reset()
    {
        myFree(.data!, 4)
        .data    = cast(*s32) myAlloc(4)
        .data![] = 1
    }
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var touched: UafNode
    touched.data = cast(*s32) myAlloc(4)
    touched.releaseThenTouch()
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var released: UafNode
    released.data = cast(*s32) myAlloc(4)
    released.release()
    Swag.assert(released.data == null)

    var recycled: UafNode
    recycled.data = cast(*s32) myAlloc(4)
    recycled.reset()
    Swag.assert(recycled.data![] == 1)
    myFree(recycled.data!, 4)
}

// What correct code does with that shape, and what the rule may not claim: the field is
// reassigned, another object's field is read, a callee handed the object puts a live
// pointer back, and a different field of the same object is untouched.
#[Swag.Sanity(.Lifecycle, true)]
func refillNode(n: *UafNode)
{
    n.data = cast(*s32) myAlloc(4)
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let node = cast(*UafNode) myAlloc(16)
    node.data  = cast(*s32) myAlloc(4)
    node.count = 4

    myFree(node.data!, 4)
    Swag.assert(node.count == 4)

    node.data    = cast(*s32) myAlloc(4)
    node.data![] = 7
    Swag.assert(node.data![] == 7)

    myFree(node.data!, 4)
    refillNode(node)
    node.data![] = 9
    Swag.assert(node.data![] == 9)

    myFree(node.data!, 4)
    myFree(node, 16)
}

// Handing a released address back to the caller is the same fault as handing back a
// frame address, on the other kind of storage: the value is dead as it crosses the
// return, and nothing the caller does with it can be right.
#[Swag.Sanity(.Lifecycle, true)]
func returnReleasedLocal()->*s32
{
    let p = cast(*s32) myAlloc(4)
    myFree(p, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return p         // swc-expected-error {{sanity_err_return_released}}
}

#[Swag.Sanity(.Lifecycle, true)]
func returnReleasedParameter(p: *s32)->*s32
{
    myFree(p, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return p         // swc-expected-error {{sanity_err_return_released}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    discard returnReleasedLocal()
    discard returnReleasedParameter(cast(*s32) myAlloc(4))
}

// Reading the value out before the release, and reallocating before the return, are
// what correct code does with the same shape.
#[Swag.Sanity(.Lifecycle, true)]
func returnValueBeforeRelease()->s32
{
    let p = cast(*s32) myAlloc(4)
    p[] = 3
    let value = p[]
    myFree(p, 4)
    return value
}

#[Swag.Sanity(.Lifecycle, true)]
func returnFreshAllocation()->*s32
{
    var p = cast(*s32) myAlloc(4)
    myFree(p, 4)
    p = cast(*s32) myAlloc(4)
    return p
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    Swag.assert(returnValueBeforeRelease() == 3)
    let fresh = returnFreshAllocation()
    fresh[] = 4
    Swag.assert(fresh[] == 4)
    myFree(fresh, 4)
}

// A released PARAMETER has no frame slot of its own: the register holding it is what
// names it, and only a redefinition of that register clears the release.
#[Swag.Sanity(.Lifecycle, true)]
func releaseThenUseParameter(p: *s32)->s32
{
    myFree(p, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return p[]       // swc-expected-error {{sanity_err_use_after_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
func releaseParameterTwice(p: *s32)
{
    myFree(p, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    myFree(p, 4)     // swc-expected-error {{sanity_err_double_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    discard releaseThenUseParameter(cast(*s32) myAlloc(4))
    releaseParameterTwice(cast(*s32) myAlloc(4))
}

// Releasing one parameter says nothing about the other.
#[Swag.Sanity(.Lifecycle, true)]
func releaseOneOfTwoParameters(first: *s32, second: *s32)->s32
{
    myFree(first, 4)
    let value = second[]
    myFree(second, 4)
    return value
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let one = cast(*s32) myAlloc(4)
    let two = cast(*s32) myAlloc(4)
    two[] = 11
    Swag.assert(releaseOneOfTwoParameters(one, two) == 11)
}

// A pointer kept in a local table. An element is a slot like any other once the index
// is known, and element zero has to be nameable like the rest of them.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var table: [4] (*s32?)
    table[0] = cast(*s32) myAlloc(4)
    myFree(table[0]!, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    let x = table[0]![]      // swc-expected-error {{sanity_err_use_after_free}}
    discard x
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var table: [4] (*s32?)
    table[2] = cast(*s32) myAlloc(4)
    myFree(table[2]!, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    table[2]![] = 1          // swc-expected-error {{sanity_err_use_after_free}}
}

// Releasing one element says nothing about the next one.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var table: [2] (*s32?)
    table[0]    = cast(*s32) myAlloc(4)
    table[1]    = cast(*s32) myAlloc(4)
    table[1]![] = 4
    myFree(table[0]!, 4)
    Swag.assert(table[1]![] == 4)
    myFree(table[1]!, 4)
}

// A pointer kept in a field of a local, which is what an owning value looks like.
struct UafOwner
{
    data:  *s32?
    count: s32
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var owner: UafOwner
    owner.data = cast(*s32) myAlloc(4)
    myFree(owner.data!, 4)     // swc-expected-note {{sanity_note_pointer_released_here}}
    let x = owner.data![]      // swc-expected-error {{sanity_err_use_after_free}}
    discard x
}

// One call both releases the pointer and reassigns the storage holding it. What the
// callee can put back, it did not leave released.
#[Swag.Sanity(.Lifecycle, true)]
func releaseAndReplace(ptr: *void, slot: **s32)
{
    myFree(ptr, 4)
    slot[] = cast(*s32) myAlloc(4)
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var p = cast(*s32) myAlloc(4)
    releaseAndReplace(p, &p)
    p[] = 5
    Swag.assert(p[] == 5)
    myFree(p, 4)
}

// A conditional free never proves the fault (must-join).
#[Swag.Sanity(.Lifecycle, true)]
func useAfterConditionalFree(cond: bool)->s32
{
    let p = cast(*s32) myAlloc(4)
    p[] = 4
    if cond do
        myFree(p, 4)
    let x = p[]
    if not cond do
        myFree(p, 4)
    return x
}

// Another pointer is untouched by the free.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let p = cast(*s32) myAlloc(4)
    let q = cast(*s32) myAlloc(4)
    q[] = 5
    myFree(p, 4)
    Swag.assert(q[] == 5)
    myFree(q, 4)
}

// ---------------------------------------------------------------------------
// Releasing an object that merely CARRIES a pointer to the receiver frees that
// object, never the receiver. The FREES summary must not travel up from there:
// it did, and the report came out on a caller three frames away, on a value
// that had nothing to do with the release.
// ---------------------------------------------------------------------------

struct UafCarrier
{
    owner: *UafHost?
}

struct UafHost
{
    value: s32
}

impl UafHost
{
    // 'p' carries the receiver and is released; only 'p' dies.
    #[Swag.Sanity(.Lifecycle, true)]
    mtd setup()
    {
        let p = cast(*UafCarrier) myAlloc(#sizeof(UafCarrier))
        p.owner = me
        myFree(p, #sizeof(UafCarrier))
        .value = 1
    }
}

// One more frame, because the wrong conclusion was reached by summary propagation
// and only showed up at the end of the chain.
#[Swag.Sanity(.Lifecycle, true)]
func uafCarrierThroughFrame(host: *UafHost)
{
    host.setup()
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var host: UafHost
    uafCarrierThroughFrame(&host)
    Swag.assert(host.value == 1)
}
