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
    return payload // swc-expected-error {{sanity_err_borrow_escape}}
}

// Returning stack-borrowed array data from a runtime function must warn.
func borrowEscapeArrayCast()->string
{
    var buf: [3] u8
    buf[0] = 'a''u8
    buf[1] = 'b''u8
    buf[2] = 'c''u8
    return cast(string) buf // swc-expected-error {{sanity_err_borrow_escape}}
}

// Implicit conversions borrow exactly like their explicit spelling: through a user
// 'opCast' on return and assignment, and through array-to-slice decay.
func borrowEscapeImplicitOpCastReturn()->string
{
    var owner: BorrowEscapeOwner
    owner.buffer[0] = 'x''u8
    owner.length = 1
    return owner // swc-expected-error {{sanity_err_borrow_escape}}
}

var borrowEscapeGlobalText: string

func borrowEscapeImplicitOpCastAssign()
{
    var owner: BorrowEscapeOwner
    owner.buffer[0] = 'x''u8
    owner.length = 1
    borrowEscapeGlobalText = owner // swc-expected-error {{sanity_err_borrow_escape}}
}

func borrowEscapeImplicitArrayDecay()->[..] u8
{
    var buf: [4] u8
    buf[0] = 1
    return buf // swc-expected-error {{sanity_err_borrow_escape}}
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
    return value // swc-expected-error {{sanity_err_borrow_escape}}
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
    return &v // swc-expected-error {{sanity_err_borrow_escape}}
}

func borrowEscapeByValueParamCast(o: BorrowEscapeOwner)->string
{
    return o // swc-expected-error {{sanity_err_borrow_escape}}
}

// An inner-scope local does not live as long as an outer destination, even
// within the same frame.
func borrowEscapeInnerScope()->s32
{
    var p: *s32
    {
        var v: s32 = 42
        p = &v // swc-expected-error {{sanity_err_borrow_scope_escape}}
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
    return p // swc-expected-error {{sanity_err_borrow_escape}}
}

// A borrow created in only one branch survives the join.
func borrowEscapeConditionalBorrow(cond: bool)->*s32
{
    var v: s32
    var p: *s32
    if cond do
        p = &v
    return p // swc-expected-error {{sanity_err_borrow_escape}}
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
    return p // swc-expected-error {{sanity_err_borrow_escape}}
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
    let s: string = borrowEscapeMakeOwner() // swc-expected-error {{sanity_err_borrow_temporary}}
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
    return cast(const [..] u16) borrowEscapeMakeArray() // swc-expected-error {{sanity_err_borrow_materialized}}
}

func borrowEscapeMaterializedTracked()->const [..] u16
{
    let view = cast(const [..] u16) borrowEscapeMakeArray()
    return view // swc-expected-error {{sanity_err_borrow_materialized}}
}

var borrowEscapeGlobalSlice: const [..] u16

func borrowEscapeMaterializedGlobal()
{
    borrowEscapeGlobalSlice = cast(const [..] u16) borrowEscapeMakeArray() // swc-expected-error {{sanity_err_borrow_materialized}}
}

// Boxing an rvalue into a returned 'any' leaks the frame-local box.
func borrowEscapeMaterializedAnyReturn()->any
{
    return borrowEscapeMakeOwner() // swc-expected-error {{sanity_err_borrow_materialized}}
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
    return func|pTotal|()->s32 { return dref pTotal } // swc-expected-error {{sanity_err_borrow_escape}}
}

// Capturing by reference borrows the source storage itself.
func borrowEscapeClosureByRef()->BorrowEscapeVisitor
{
    var total: s32 = 7
    return func|&total|()->s32 { return total } // swc-expected-error {{sanity_err_borrow_escape}}
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
    node.text = @mkstring(&owner.buffer[0], owner.length) // swc-expected-error {{sanity_err_borrow_escape}}
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

// Disabling the Lifecycle sanity turns the whole borrow analysis off: the same
// escapes compile without any diagnostic. The Memory sanity is disabled too, so the
// codegen sanitizer does not catch the escape in its place.
#[Swag.Sanity(.Lifecycle, false), Swag.Sanity(.Memory, false)]
func borrowEscapeSanityOff()->*s32
{
    var v: s32
    return &v
}

#[Swag.Sanity(.Lifecycle, false)]
func borrowEscapeSanityOffTemporary()->u64
{
    let s: string = borrowEscapeMakeOwner()
    return @countof(s)
}

// ---------------------------------------------------------------------------
// Opaque-call summaries: the callee records which parameters its return value may
// borrow; the call site is judged once the whole module is analyzed, so the result
// does not depend on the sema job order.
// ---------------------------------------------------------------------------

func borrowEscapePassthrough(p: *s32)->*s32
{
    return p
}

// Handing a local's address to a borrowing callee and returning the result escapes.
func borrowEscapeThroughCall()->*s32
{
    var v: s32
    return borrowEscapePassthrough(&v) // swc-expected-error {{sanity_err_borrow_escape}}
}

var borrowEscapeGlobalPtr: *s32

// Same through a global destination.
func borrowEscapeThroughCallGlobal()
{
    var v: s32
    borrowEscapeGlobalPtr = borrowEscapePassthrough(&v) // swc-expected-error {{sanity_err_borrow_escape}}
}

// Caller-owned data flows through the same callee untouched.
func borrowEscapeThroughCallParam(q: *s32)->*s32
{
    return borrowEscapePassthrough(q)
}

var borrowEscapeGlobalInt: s32

func borrowEscapeThroughCallGlobalSource()->*s32
{
    return borrowEscapePassthrough(&borrowEscapeGlobalInt)
}

// Carrier summary: identity on a string borrows its parameter.
func borrowEscapeIdentity(s: string)->string
{
    return s
}

func borrowEscapeThroughCallCarrier()->string
{
    var buf: [3] u8
    buf[0] = 'a''u8
    return borrowEscapeIdentity(cast(string) buf) // swc-expected-error {{sanity_err_borrow_escape}}
}

// A callee that does NOT return its parameter stays silent at the call site.
func borrowEscapeReadOnly(p: *s32)->s32
{
    return dref p
}

func borrowEscapeThroughCallValue()->s32
{
    var v: s32 = 7
    return borrowEscapeReadOnly(&v)
}

// Mutual recursion stays legal (no stalled sema dependency) and the summary of the
// direct-return path is still applied at the call site.
func borrowEscapeMutualA(p: *s32, n: s32)->*s32
{
    if n <= 0 do
        return p
    return borrowEscapeMutualB(p, n - 1)
}

func borrowEscapeMutualB(p: *s32, n: s32)->*s32
{
    if n <= 0 do
        return p
    return borrowEscapeMutualA(p, n - 1)
}

func borrowEscapeMutualCall()->*s32
{
    var v: s32
    return borrowEscapeMutualA(&v, 3) // swc-expected-error {{sanity_err_borrow_escape}}
}

// ---------------------------------------------------------------------------
// Transitive summaries: a wrapper that returns 'g(p)' borrows whatever 'g' borrows,
// however deep the chain, resolved by fixpoint once the whole module is analyzed.
// ---------------------------------------------------------------------------

func borrowEscapeWrapOnce(p: *s32)->*s32
{
    return borrowEscapePassthrough(p)
}

func borrowEscapeWrapTwice(p: *s32)->*s32
{
    return borrowEscapeWrapOnce(p)
}

func borrowEscapeThroughWrapper()->*s32
{
    var v: s32
    return borrowEscapeWrapOnce(&v) // swc-expected-error {{sanity_err_borrow_escape}}
}

func borrowEscapeThroughWrapperChain()->*s32
{
    var v: s32
    return borrowEscapeWrapTwice(&v) // swc-expected-error {{sanity_err_borrow_escape}}
}

func borrowEscapeThroughWrapperGlobal()
{
    var v: s32
    borrowEscapeGlobalPtr = borrowEscapeWrapTwice(&v) // swc-expected-error {{sanity_err_borrow_escape}}
}

// A wrapper whose callee returns caller-independent data borrows nothing: the chain
// stays silent whatever was passed in.
func borrowEscapeGlobalSource(p: *s32)->*s32
{
    return &borrowEscapeGlobalInt
}

func borrowEscapeWrapGlobalSource(p: *s32)->*s32
{
    return borrowEscapeGlobalSource(p)
}

func borrowEscapeThroughNonBorrowingWrapper()->*s32
{
    var v: s32
    return borrowEscapeWrapGlobalSource(&v)
}

// Carrier chain: the string identity summary flows through its wrapper.
func borrowEscapeWrapIdentity(s: string)->string
{
    return borrowEscapeIdentity(s)
}

func borrowEscapeThroughWrapCarrier()->string
{
    var buf: [3] u8
    buf[0] = 'a''u8
    return borrowEscapeWrapIdentity(cast(string) buf) // swc-expected-error {{sanity_err_borrow_escape}}
}

// A pure passthrough cycle has no direct borrow to seed the masks: the fixpoint
// converges with nothing set and the call site stays silent.
func borrowEscapeCycleA(p: *s32)->*s32
{
    return borrowEscapeCycleB(p)
}

func borrowEscapeCycleB(p: *s32)->*s32
{
    return borrowEscapeCycleA(p)
}

func borrowEscapeThroughCycle()->*s32
{
    var v: s32
    return borrowEscapeCycleA(&v)
}

// Only one side of the cycle returns its parameter directly; the other side gets the
// borrow through the fixpoint, across the cycle.
func borrowEscapeSeededA(p: *s32, n: s32)->*s32
{
    if n <= 0 do
        return p
    return borrowEscapeSeededB(p, n - 1)
}

func borrowEscapeSeededB(p: *s32, n: s32)->*s32
{
    return borrowEscapeSeededA(p, n - 1)
}

func borrowEscapeThroughSeededCycle()->*s32
{
    var v: s32
    return borrowEscapeSeededB(&v, 3) // swc-expected-error {{sanity_err_borrow_escape}}
}

// ---------------------------------------------------------------------------
// Chained locals: a borrowed call result bound to a local is judged when the
// LOCAL escapes, not at the binding.
// ---------------------------------------------------------------------------

func borrowEscapeChainedReturn()->*s32
{
    var v: s32
    let p = borrowEscapePassthrough(&v)
    return p // swc-expected-error {{sanity_err_borrow_escape}}
}

func borrowEscapeChainedGlobal()
{
    var v: s32
    let p = borrowEscapePassthrough(&v)
    borrowEscapeGlobalPtr = p // swc-expected-error {{sanity_err_borrow_escape}}
}

// Rebinding through a second local keeps the deferred borrow alive.
func borrowEscapeChainedCopy()->*s32
{
    var v: s32
    let p = borrowEscapePassthrough(&v)
    let q = p
    return q // swc-expected-error {{sanity_err_borrow_escape}}
}

// A local bound to a non-borrowing callee stays silent when returned.
func borrowEscapeChainedReadOnly()->*s32
{
    var v: s32
    let p = borrowEscapeWrapGlobalSource(&v)
    return p
}

// The chained local kept local never escapes: silent.
func borrowEscapeChainedLocalOnly()->s32
{
    var v: s32 = 7
    let p = borrowEscapePassthrough(&v)
    return dref p
}

// Clearing the local erases the deferred borrow.
func borrowEscapeChainedCleared()->*s32
{
    var v: s32
    var p = borrowEscapePassthrough(&v)
    p = null
    return p
}

// The summary chains through a wrapper that binds the result before returning it.
func borrowEscapeChainedWrapper(p: *s32)->*s32
{
    let q = borrowEscapePassthrough(p)
    return q
}

func borrowEscapeThroughChainedWrapper()->*s32
{
    var v: s32
    return borrowEscapeChainedWrapper(&v) // swc-expected-error {{sanity_err_borrow_escape}}
}

// ---------------------------------------------------------------------------
// Stored-argument summaries: a callee that stores its parameter into a global
// makes any borrowed argument escape, whatever happens to the call result.
// ---------------------------------------------------------------------------

var borrowEscapeGlobalStash: *s32

func borrowEscapeStash(p: *s32)
{
    borrowEscapeGlobalStash = p
}

func borrowEscapeStashLocal()
{
    var v: s32
    borrowEscapeStash(&v) // swc-expected-error {{sanity_err_borrow_escape}}
}

// Caller-owned data can be stashed freely.
func borrowEscapeStashParam(q: *s32)
{
    borrowEscapeStash(q)
}

func borrowEscapeStashGlobalSource()
{
    borrowEscapeStash(&borrowEscapeGlobalInt)
}

// The stores summary chains through forwarding wrappers.
func borrowEscapeStashForward(p: *s32)
{
    borrowEscapeStash(p)
}

func borrowEscapeStashForwardLocal()
{
    var v: s32
    borrowEscapeStashForward(&v) // swc-expected-error {{sanity_err_borrow_escape}}
}

// A callee that only reads its parameter leaves call sites silent.
func borrowEscapeStashReadOnlyLocal()->s32
{
    var v: s32 = 3
    return borrowEscapeReadOnly(&v)
}

// ---------------------------------------------------------------------------
// Method receiver: the summaries chain through 'me' like any other parameter.
// ---------------------------------------------------------------------------

struct BorrowEscapeSelf
{
    x: s32
}

func borrowEscapeSelfPtr(s: *BorrowEscapeSelf)->*s32
{
    return &s.x
}

impl BorrowEscapeSelf
{
    mtd xptr()->*s32
    {
        return borrowEscapeSelfPtr(me)
    }
}

func borrowEscapeMethodChain()->*s32
{
    var s: BorrowEscapeSelf
    return s.xptr() // swc-expected-error {{sanity_err_borrow_escape}}
}

var borrowEscapeGlobalSelf: BorrowEscapeSelf

func borrowEscapeMethodChainGlobal()->*s32
{
    return borrowEscapeGlobalSelf.xptr()
}

// ---------------------------------------------------------------------------
// Materialized cast storage created in an inner scope dies with it: binding it
// to an outer variable escapes. Same-scope bindings stay silent (see
// borrowEscapeMaterializedTemp above).
// ---------------------------------------------------------------------------

func borrowEscapeMaterializedScope()->u16
{
    var view: const [..] u16
    {
        view = cast(const [..] u16) borrowEscapeMakeArray() // swc-expected-error {{sanity_err_borrow_materialized}}
    }
    return 0
}

// ---------------------------------------------------------------------------
// Owner structs (heap payload freed by 'opDrop', like Core.String): a view of a
// LOCAL owner's payload dies with the owner's drop at scope end — same report
// sites as a frame borrow.
// ---------------------------------------------------------------------------

struct BorrowEscapeOwned
{
    buffer: [*] u8
    length: u64
}

impl BorrowEscapeOwned
{
    mtd opDrop() {}

    #[Swag.Implicit, Swag.Inline]
    mtd const opCast()->string
    {
        return @mkstring(.buffer, .length)
    }
}

func borrowEscapeOwnedReturn()->string
{
    var str: BorrowEscapeOwned
    return str // swc-expected-error {{sanity_err_borrow_escape}}
}

func borrowEscapeOwnedGlobal()
{
    var str: BorrowEscapeOwned
    borrowEscapeGlobalText = str // swc-expected-error {{sanity_err_borrow_escape}}
}

// A view kept local is fine while the owner lives.
func borrowEscapeOwnedLocalOnly()->u64
{
    var str: BorrowEscapeOwned
    let view: string = str
    return @countof(view)
}

// The view bound to a local and returned later.
func borrowEscapeOwnedChained()->string
{
    var str: BorrowEscapeOwned
    let view: string = str
    return view // swc-expected-error {{sanity_err_borrow_escape}}
}

// A pointed-to owner belongs to the caller: returning its view is fine HERE and
// feeds the summary, so call sites are judged against what was really passed.
func borrowEscapeOwnedParamView(str: *BorrowEscapeOwned)->string
{
    return dref str
}

func borrowEscapeOwnedThroughParam()->string
{
    var str: BorrowEscapeOwned
    return borrowEscapeOwnedParamView(&str) // swc-expected-error {{sanity_err_borrow_escape}}
}

var borrowEscapeGlobalOwned: BorrowEscapeOwned

func borrowEscapeOwnedGlobalSource()->string
{
    return borrowEscapeGlobalOwned
}

// An rvalue owner is dropped at the end of the statement: its view dangles as
// soon as it is bound.
func borrowEscapeMakeOwned()->BorrowEscapeOwned
{
    var o: BorrowEscapeOwned
    return o
}

func borrowEscapeOwnedTemporary()->u64
{
    let view: string = borrowEscapeMakeOwned() // swc-expected-error {{sanity_err_borrow_temporary}}
    return @countof(view)
}
