#global private
using Swag

struct BorrowEscapeOwner
{
    buffer: [8] u8
    length: u64
}

impl BorrowEscapeOwner
{
    #[Swag.Implicit, Swag.Inline]
    mtd const opCast()->string
    {
        return @mkstring(&.buffer[0], .length)
    }
}

struct BorrowEscapePayload
{
    text: string
}

func borrowEscapePayload()->BorrowEscapePayload
{
    var owner: BorrowEscapeOwner
    owner.buffer[0] = 'x''u8
    owner.length = 1

    var payload = BorrowEscapePayload{text: owner}
    return payload // swc-expected-warning {{sema_warn_borrow_escape}}
}

// Returning stack-borrowed array data from a runtime function must warn.
func borrowEscapeArrayCast()->string
{
    var buf: [3] u8
    buf[0] = 'a''u8
    buf[1] = 'b''u8
    buf[2] = 'c''u8
    return cast(string) buf // swc-expected-warning {{sema_warn_borrow_escape}}
}

// Casting a scalar value to a pointer reinterprets the value: it does not
// borrow the variable storage and must not warn.
var borrowEscapeScalarSink: *void

func borrowEscapeScalarCast()->*void
{
    var idx: u64 = 42
    borrowEscapeScalarSink = cast(*void) idx
    return cast(*void) idx
}

// '#run' return payloads pointing into the local stack frame are persisted
// into the compiler segment, so no borrow can escape and no warning is expected.
const BorrowEscapeRunString: string = #run
{
    var buf: [3] u8
    buf[0] = 'r''u8
    buf[1] = 'u''u8
    buf[2] = 'n''u8
    return cast(string) buf
}

#assert(BorrowEscapeRunString == "run")

// A closure capturing a borrowed pointer is only dangerous when the closure value
// itself escapes: keeping it local must stay silent.
alias BorrowEscapeVisitor = func||()->s32

func borrowEscapeClosureLocal()->s32
{
    var total: s32 = 7
    let pTotal = &total
    let cb: BorrowEscapeVisitor = func|pTotal|()->s32 { return dref pTotal }
    return cb()
}

// Returning the closure leaks the captured borrow of 'total' out of the frame.
func borrowEscapeClosureReturn()->BorrowEscapeVisitor
{
    var total: s32 = 7
    let pTotal = &total
    return func|pTotal|()->s32 { return dref pTotal } // swc-expected-warning {{sema_warn_borrow_escape}}
}

// Capturing by reference borrows the source storage itself.
func borrowEscapeClosureByRef()->BorrowEscapeVisitor
{
    var total: s32 = 7
    return func|&total|()->s32 { return total } // swc-expected-warning {{sema_warn_borrow_escape}}
}

// Storing borrowed data through a pointer that itself borrows a local writes into
// that local's storage: nothing outlives the frame, no warning.
struct BorrowEscapeSelfRef
{
    text: string
}

func borrowEscapeThroughLocalPointer()->u64
{
    var owner: BorrowEscapeOwner
    owner.buffer[0] = 'x''u8
    owner.length = 1

    var holder: BorrowEscapeSelfRef
    let pHolder = &holder
    pHolder.text = owner
    return @countof(pHolder.text)
}

// Writing borrowed data through a local pointer only reaches storage known to this
// frame: the borrow is tracked on the pointer, not reported.
struct BorrowEscapeNode
{
    text: string
}

func borrowEscapeThroughHeapPointer(alloc: func()->*BorrowEscapeNode)->u64
{
    var owner: BorrowEscapeOwner
    owner.buffer[0] = 'x''u8
    owner.length = 1

    let node = alloc()
    node.text = owner
    return @countof(node.text)
}

// Writing borrowed data through a parameter pointer reaches caller-visible storage.
func borrowEscapeThroughParamPointer(node: *BorrowEscapeNode)
{
    var owner: BorrowEscapeOwner
    owner.buffer[0] = 'x''u8
    owner.length = 1
    node.text = @mkstring(&owner.buffer[0], owner.length) // swc-expected-warning {{sema_warn_borrow_escape}}
}

// A return inside an inline expansion hands the value back to the calling frame:
// borrowing the caller's own storage must not warn.
#[Swag.Inline]
func borrowEscapeInlineOffset(buffer: [*] u8)->[*] u8
{
    return buffer + 1
}

func borrowEscapeInlineCaller()->u64
{
    var data: [4] u8
    data[1] = 42
    let p = borrowEscapeInlineOffset(@dataof(data))
    return cast(u64) dref p
}
