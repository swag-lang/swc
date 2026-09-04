#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-562 - Return of stack variable address
//
// A view of frame storage leaves the frame. The caller then reads recycled stack.
//
// Swag: this is the one place where the language is at its strongest. The rule is part of the
// language - no attribute and no build configuration turns it off - it needs no annotation,
// and it holds through returns, globals, caller-visible pointers, closures, interfaces, and
// across opaque calls in both directions. Every case below is rejected in every build.
// -----------------------------------------------------------------------------

var globalValue:  s32
var globalBuffer: [4] u8
var globalStash:  *s32?

// --- Faults ---

func returnAddressOfLocal()->*s32
{
    var value: s32
    return &value     // swc-expected-error {{sanity_err_borrow_escape}}
}

// A copy on the way out changes nothing.
func returnAddressThroughCopy()->*s32
{
    var value: s32
    var pointer = &value
    return pointer     // swc-expected-error {{sanity_err_borrow_escape}}
}

// A slice of a local array is a view of the frame just as much as a pointer is.
func returnSliceOfLocal()->const [..] u8
{
    var buffer: [4] u8
    return cast(const [..] u8) buffer     // swc-expected-error {{sanity_err_borrow_escape}}
}

// The view leaves through a caller-visible pointer instead of the return value.
func storeAddressThroughParameter(out: *(*s32?))
{
    var value: s32
    out[] = &value     // swc-expected-error {{sanity_err_borrow_escape}}
}

// The view leaves into a global.
func storeAddressInGlobal()
{
    var value: s32
    globalStash = &value     // swc-expected-error {{sanity_err_borrow_escape}}
}

// A closure that captures by address, and itself escapes, carries the frame with it.
func returnClosureOverLocal()->func||()->s32
{
    var value = 42's32
    let captured: func||()->s32 = func|&value|()->s32 { return value }
    return captured     // swc-expected-error {{sanity_err_borrow_escape}}
}

// An interface built from a local is a view of that local.
interface IValue { mtd read()->s32 }
struct Holder { value: s32 }
impl IValue for Holder { mtd read()->s32 => .value }

func returnInterfaceOverLocal()->IValue
{
    var holder = Holder{value: 42}
    return cast(IValue) &holder     // swc-expected-error {{sanity_err_borrow_escape}}
}

// The borrow leaves through a chain of opaque calls: the summary of each one is inferred and
// composed, so a wrapper level does not hide it.
func passthrough(pointer: *s32)->*s32
{
    return pointer
}

func wrapper(pointer: *s32)->*s32
{
    return passthrough(pointer)
}

func returnThroughCallChain()->*s32
{
    var value: s32
    return wrapper(&value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

// The view outlives its source without leaving the function: an inner scope dies first.
func escapeInnerScope()->s32
{
    var pointer: *s32?
    {
        var value = 42's32
        pointer = &value     // swc-expected-error {{sanity_err_borrow_scope_escape}}
    }

    return pointer![]
}

// The callee KEEPS the borrow rather than returning it. The summary records that, and the
// call site is judged against what was really passed in.
func stash(pointer: *s32)
{
    globalStash = pointer     // legal here: 'pointer' is caller-owned, judged at call sites
}

func handOverLocalToKeeper()
{
    var value: s32
    stash(&value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

// A container that outlives what it stores. Storing one parameter into storage reachable from
// another is summarized as a pair, and reaching in through the container's own heap buffer
// counts: this is the shape that fills a collection of views from a per-iteration owner.
struct ViewBag
{
    slots: [*] (*s32?)?
    count: u64
}

impl ViewBag
{
    mtd opDrop()
    {
        if .slots != null do
            heapFree(cast(*void) .slots!, 4 * 8)
        .slots = null
    }

    mtd add(pointer: *s32)
    {
        if .slots == null do
            .slots = cast([*] (*s32?)) heapAlloc(4 * 8)
        .slots![.count] = pointer
        .count          += 1
    }
}

func fillBagFromInnerScope()
{
    var bag: ViewBag
    for turn in 2
    {
        var value = cast(s32) turn
        bag.add(&value)     // swc-expected-error {{sanity_err_borrow_escape}}
    }
}

// The runtime's own storage counts as well: 'Swag.setContext' installs a POINTER to what it
// is given, so handing it a frame local and leaving would leave every later 'getContext'
// reading recycled stack.
func installLocalContext()
{
    var replacement = Swag.getContext()[]
    Swag.setContext(&replacement)     // swc-expected-error {{sanity_err_context_escape}}
}

// --- Sound ---

func returnAddressOfGlobal()->*s32
{
    return &globalValue
}

func returnSliceOfGlobal()->const [..] u8
{
    return cast(const [..] u8) globalBuffer
}

// A pointer received as a parameter is caller-owned, and passing it on is fine.
func returnParameter(pointer: *s32)->*s32
{
    return wrapper(pointer)
}

#test
{
    Swag.assert(returnAddressOfGlobal() == &globalValue)
    Swag.assert(returnSliceOfGlobal().count == 4)
    Swag.assert(returnParameter(&globalValue) == &globalValue)
}
