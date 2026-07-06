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
    return payload // swc-expected-error {{sema_err_borrow_escape}}
}

// Returning stack-borrowed array data from a runtime function must warn.
func borrowEscapeArrayCast()->string
{
    var buf: [3] u8
    buf[0] = 'a''u8
    buf[1] = 'b''u8
    buf[2] = 'c''u8
    return cast(string) buf // swc-expected-error {{sema_err_borrow_escape}}
}

// Implicit conversions borrow exactly like their explicit spelling: through a user
// 'opCast' on return and assignment, and through array-to-slice decay.
func borrowEscapeImplicitOpCastReturn()->string
{
    var owner: BorrowEscapeOwner
    owner.buffer[0] = 'x''u8
    owner.length = 1
    return owner // swc-expected-error {{sema_err_borrow_escape}}
}

var borrowEscapeGlobalText: string

func borrowEscapeImplicitOpCastAssign()
{
    var owner: BorrowEscapeOwner
    owner.buffer[0] = 'x''u8
    owner.length = 1
    borrowEscapeGlobalText = owner // swc-expected-error {{sema_err_borrow_escape}}
}

func borrowEscapeImplicitArrayDecay()->[..] u8
{
    var buf: [4] u8
    buf[0] = 1
    return buf // swc-expected-error {{sema_err_borrow_escape}}
}

// The same implicit conversions bound to a local stay tracked, not reported.
func borrowEscapeImplicitLocalOnly()->u64
{
    var owner: BorrowEscapeOwner
    owner.buffer[0] = 'x''u8
    owner.length = 1
    let s: string = owner

    var buf: [4] u8
    buf[0] = 1
    let sl: [..] u8 = buf
    return @countof(s) + @countof(sl)
}

// Boxing a local value into 'any' borrows the frame storage holding the value.
func borrowEscapeAnyReturn()->any
{
    var value: BorrowEscapePayload
    value.text = "x"
    return value // swc-expected-error {{sema_err_borrow_escape}}
}

// An 'any' pointing to caller-owned data or kept local must stay silent.
func borrowEscapeAnyLocalOnly(param: *BorrowEscapePayload)->any
{
    var value: BorrowEscapePayload
    value.text = "x"
    let boxed: any = value
    @assert(@dataof(boxed) != null)
    return dref param
}

// A by-value parameter is a copy living in the callee frame: borrowing its storage
// dangles exactly like borrowing a local.
func borrowEscapeByValueParamAddress(v: s32)->*s32
{
    return &v // swc-expected-error {{sema_err_borrow_escape}}
}

func borrowEscapeByValueParamCast(o: BorrowEscapeOwner)->string
{
    return o // swc-expected-error {{sema_err_borrow_escape}}
}

// An inner-scope local does not live as long as an outer destination, even
// within the same frame.
func borrowEscapeInnerScope()->s32
{
    var p: *s32
    {
        var v: s32 = 42
        p = &v // swc-expected-error {{sema_err_borrow_scope_escape}}
    }
    return 0
}

// Same-scope borrows stay tracked, not reported.
func borrowEscapeSameScope()->s32
{
    var v: s32 = 42
    var p = &v
    return dref p
}

// Flow joins: clearing the borrow on only one path does not erase it.
func borrowEscapeConditionalClear(cond: bool)->*s32
{
    var v: s32
    var p = &v
    if cond do
        p = null
    return p // swc-expected-error {{sema_err_borrow_escape}}
}

// A borrow created in only one branch survives the join.
func borrowEscapeConditionalBorrow(cond: bool)->*s32
{
    var v: s32
    var p: *s32
    if cond do
        p = &v
    return p // swc-expected-error {{sema_err_borrow_escape}}
}

// An unconditional clear does erase the borrow.
func borrowEscapeUnconditionalClear()->*s32
{
    var v: s32
    var p = &v
    p = null
    return p
}

// Clearing on both branches erases it too.
func borrowEscapeBothBranchesClear(cond: bool)->*s32
{
    var v: s32
    var p = &v
    if cond do
        p = null
    else do
        p = null
    return p
}

// A borrow created inside a loop body survives the loop.
func borrowEscapeLoopBorrow()->*s32
{
    var v: s32
    var p: *s32
    for i in 4 do
        p = &v
    return p // swc-expected-error {{sema_err_borrow_escape}}
}

// Borrowing a temporary (destroyed at the end of the statement) is reported at
// the binding; naming the owner first is the fix and stays silent locally.
func borrowEscapeMakeOwner()->BorrowEscapeOwner
{
    var o: BorrowEscapeOwner
    o.buffer[0] = 'x''u8
    o.length = 1
    return o
}

func borrowEscapeTemporary()->u64
{
    let s: string = borrowEscapeMakeOwner() // swc-expected-error {{sema_err_borrow_temporary}}
    return @countof(s)
}

func borrowEscapeNamedOwner()->u64
{
    var o = borrowEscapeMakeOwner()
    let s: string = o
    return @countof(s)
}

// Reading a carrier element by value copies it: no borrow of the array storage.
func borrowEscapeElementRead()->string
{
    var arr: [2] string
    arr[0] = "hi"
    return arr[0]
}

// Reading a carrier member through a borrowing pointer copies the member value:
// the copy does not alias the borrowed storage (Swag.Interface.obj pattern).
func borrowEscapeMemberRead(itf: Swag.Interface)->*void
{
    let p = &itf
    return p.obj
}

// A structural cast of an rvalue is materialized into a frame-lifetime runtime
// storage: binding it locally is supported and must stay silent.
func borrowEscapeMakeArray()->[4] u16
{
    return [10'u16, 20, 30, 40]
}

func borrowEscapeMaterializedTemp()->u16
{
    let view = cast(const [..] u16) borrowEscapeMakeArray()
    return view[0]
}

// ... but that storage still dies with the frame: returning it or storing it in a
// global is an escape.
func borrowEscapeMaterializedReturn()->const [..] u16
{
    return cast(const [..] u16) borrowEscapeMakeArray() // swc-expected-error {{sema_err_borrow_materialized}}
}

func borrowEscapeMaterializedTracked()->const [..] u16
{
    let view = cast(const [..] u16) borrowEscapeMakeArray()
    return view // swc-expected-error {{sema_err_borrow_materialized}}
}

var borrowEscapeGlobalSlice: const [..] u16

func borrowEscapeMaterializedGlobal()
{
    borrowEscapeGlobalSlice = cast(const [..] u16) borrowEscapeMakeArray() // swc-expected-error {{sema_err_borrow_materialized}}
}

// Boxing an rvalue into a returned 'any' leaks the frame-local box.
func borrowEscapeMaterializedAnyReturn()->any
{
    return borrowEscapeMakeOwner() // swc-expected-error {{sema_err_borrow_materialized}}
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
    return func|pTotal|()->s32 { return dref pTotal } // swc-expected-error {{sema_err_borrow_escape}}
}

// Capturing by reference borrows the source storage itself.
func borrowEscapeClosureByRef()->BorrowEscapeVisitor
{
    var total: s32 = 7
    return func|&total|()->s32 { return total } // swc-expected-error {{sema_err_borrow_escape}}
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
    node.text = @mkstring(&owner.buffer[0], owner.length) // swc-expected-error {{sema_err_borrow_escape}}
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

// Without the Lifecycle safety contract the same escapes are advisory warnings.
#[Swag.Safety(.Lifecycle, false)]
func borrowEscapeWarningMode()->*s32
{
    var v: s32
    return &v // swc-expected-warning {{sema_warn_borrow_escape}}
}

#[Swag.Safety(.Lifecycle, false)]
func borrowEscapeWarningModeTemporary()->u64
{
    let s: string = borrowEscapeMakeOwner() // swc-expected-warning {{sema_warn_borrow_temporary}}
    return @countof(s)
}
