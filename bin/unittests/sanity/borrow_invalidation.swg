#global private
// Borrow invalidation: a view into the storage a value owns, read again after a call
// that can move or release that storage. This is a language rule, so it needs no
// attribute to fire; the file keeps one only to pair with the function below that sets
// it to false and is reported all the same.
#global #[Swag.Sanity(.Lifecycle, true)]
using Swag

// A minimal owner: one heap payload it allocates, reallocates and frees itself through
// the language allocator interface, the way 'Core.String' does. The owning lifecycle is
// what ties the payload's life to the value's.
struct BorrowInvBuffer
{
    data:     #null [*] u8
    length:   u64
    capacity: u64
}

impl BorrowInvBuffer
{
    mtd opDrop()
    {
        .release()
    }

    // Handing the allocator a pointer read out of 'me' is what marks a method as one
    // that can move or free what the receiver owns.
    mtd release()
    {
        if !.data do
            return

        var req: AllocatorRequest
        req.address = .data
        req.size    = .capacity

        let alloc = @getcontext().allocator!
        alloc.free(&req)

        .data     = null
        .capacity = 0
        .length   = 0
    }

    // Grows the payload: the block can move.
    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity do
            return

        var req: AllocatorRequest
        req.address = .data
        req.size    = newCapacity
        req.oldSize = .capacity

        let alloc = @getcontext().allocator!
        alloc.realloc(&req)

        .data     = cast() req.address
        .capacity = newCapacity
    }

    // Only assigns fields: every view into the payload survives it.
    mtd setLength(value: u64)
    {
        .length = value
    }

    // Grows first, then copies: the self-append shape the standard collections support.
    mtd append(values: [..] u8)
    {
        .reserve(.length + @countof(values))
        .length += @countof(values)
    }

    #[Swag.NoInline]
    mtd const view()->[..] u8
    {
        return @mkslice(.data!, .length)
    }

    #[Swag.NoInline]
    mtd const forwardedView()->[..] u8
    {
        return .view()
    }

    // The standard library marks its small accessors '#[Swag.Inline]': the expansion is
    // analyzed inside the caller, so the view roots at the receiver with no summary in
    // between. Both spellings must reach the same verdict.
    #[Swag.Inline]
    mtd const inlineView()->[..] u8
    {
        return @mkslice(.data!, .length)
    }

    #[Swag.NoInline]
    mtd const count()->u64
    {
        return .length
    }

    // 'me' is caller-owned, but the method body still knows exactly which payload its
    // own receiver view designates. Growing that receiver must invalidate the view in
    // the body just as it does at an ordinary call site.
    mtd receiverInvalidatesOwnView()->u8
    {
        let view = .data!
        .reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
        return view[0]
    }

    // Going through an accessor is the same borrow. The accessor summary is inferred
    // after its body resolves, so the receiver route has to survive until final judgement.
    mtd receiverInvalidatesAccessorView()->u8
    {
        let view = .view()
        .reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
        return view[0]
    }

    // Returned-payload summaries compose through non-inlined accessor chains.
    mtd receiverInvalidatesForwardedAccessorView()->u8
    {
        let view = .forwardedView()
        .reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
        return view[0]
    }

    // Replacing the carrier detaches the old allocation from the receiver. This is the
    // shape used by opPostCopy: allocating a fresh payload must not make a saved pointer
    // to the old payload stale before the copy from it.
    mtd receiverKeepsDetachedOldPayload()->u8
    {
        let oldData = .data!
        .data     = null
        .capacity = 0
        .reserve(64)
        return oldData[0]
    }

    mtd receiverKeepsDetachedOldAccessorPayload()->u8
    {
        let oldData = .view()
        .data     = null
        .capacity = 0
        .reserve(64)
        return oldData[0]
    }

    // Detaching on only one path cannot erase the route on the other path.
    mtd receiverConditionallyDetachesOldPayload(detach: bool)->u8
    {
        let oldData = .data!
        if detach
        {
            .data     = null
            .capacity = 0
        }
        .reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
        return oldData[0]
    }

    mtd receiverConditionallyDetachesOldAccessorPayload(detach: bool)->u8
    {
        let oldData = .view()
        if detach
        {
            .data     = null
            .capacity = 0
        }
        .reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
        return oldData[0]
    }
}

struct BorrowInvPair
{
    left:  BorrowInvBuffer
    right: BorrowInvBuffer
}

impl BorrowInvPair
{
    mtd receiverInvalidatesMatchingField()->u8
    {
        let view = .right.data!
        .right.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
        return view[0]
    }

    // A receiver parameter is not one undifferentiated allocation: changing one owned
    // field cannot invalidate a view into a sibling field.
    mtd receiverKeepsSiblingPayload()->u8
    {
        let view = .left.data!
        .right.reserve(64)
        return view[0]
    }

    mtd receiverKeepsSiblingAccessorPayload()->u8
    {
        let view = .left.view()
        .right.reserve(64)
        return view[0]
    }
}

// ---------------------------------------------------------------------------
// A view read after the storage it views was moved or released.
// ---------------------------------------------------------------------------

// Straight through the payload member.
func borrowInvDirectMember()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.data!
    buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

// The most common spelling: the view comes from an accessor call.
func borrowInvThroughAccessor()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

// The same view through an INLINED accessor.
func borrowInvThroughInlineAccessor()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.inlineView()
    buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

// Releasing the payload invalidates the view exactly like growing it.
func borrowInvRelease()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    buf.release()     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

// The spelling the standard library actually uses: the payload goes to a free HELPER,
// and "this method can move what its receiver owns" is inferred through that helper's
// own summary rather than from an allocator call in the method itself.
func borrowInvFreeBlock(block: #null [*] u8, size: u64)
{
    if !block do
        return

    var req: AllocatorRequest
    req.address = block
    req.size    = size

    let alloc = @getcontext().allocator!
    alloc.free(&req)
}

struct BorrowInvChained
{
    data:     #null [*] u8
    capacity: u64
}

impl BorrowInvChained
{
    mtd opDrop()
    {
        borrowInvFreeBlock(.data, .capacity)
    }

    mtd reset()
    {
        borrowInvFreeBlock(.data, .capacity)
        .data     = null
        .capacity = 0
    }

    #[Swag.NoInline]
    mtd const view()->[..] u8
    {
        return @mkslice(.data!, .capacity)
    }
}

func borrowInvThroughFreeHelper()->u8
{
    var box: BorrowInvChained
    let view = box.view()
    box.reset()     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

// ---------------------------------------------------------------------------
// The same rule when the storage is a GLOBAL. A global outlives every frame, so a view
// of one can never dangle by outliving its owner - that is why the ESCAPE rules leave
// globals alone. Invalidation is a different fault: growing a global container moves
// the very bytes a view was reading, exactly like growing a local one.
// ---------------------------------------------------------------------------
var borrowInvGlobalBuf:   BorrowInvBuffer
var borrowInvGlobalOther: BorrowInvBuffer
var borrowInvGlobalBox:   BorrowInvChained

func borrowInvGlobalDirectMember()->u8
{
    borrowInvGlobalBuf.reserve(4)
    let view = borrowInvGlobalBuf.data!
    borrowInvGlobalBuf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

func borrowInvGlobalThroughAccessor()->u8
{
    borrowInvGlobalBuf.reserve(4)
    let view = borrowInvGlobalBuf.view()
    borrowInvGlobalBuf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

func borrowInvGlobalThroughInlineAccessor()->u8
{
    borrowInvGlobalBuf.reserve(4)
    let view = borrowInvGlobalBuf.inlineView()
    borrowInvGlobalBuf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

func borrowInvGlobalRelease()->u8
{
    borrowInvGlobalBuf.reserve(4)
    let view = borrowInvGlobalBuf.view()
    borrowInvGlobalBuf.release()     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

// The helper-chained owner, so the global route is judged through a summary too.
func borrowInvGlobalThroughFreeHelper()->u8
{
    let view = borrowInvGlobalBox.view()
    borrowInvGlobalBox.reset()     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

// ---------------------------------------------------------------------------
// Shapes that must stay silent.
// ---------------------------------------------------------------------------

// Reading the view only BEFORE the change is safe.
func borrowInvReadBefore()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view  = buf.view()
    let first = view[0]
    buf.reserve(64)
    return first
}

// Taking the view again after the change is the fix, and must stay silent.
func borrowInvRebound()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    var view = buf.view()
    buf.reserve(64)
    view = buf.view()
    return view[0]
}

// Replacing the carrier keeps the accessor's old allocation independent from later
// mutations of the owner, outside a method body as well.
func borrowInvDetachedOldAccessorPayload()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let oldData = buf.view()
    buf.data     = null
    buf.capacity = 0
    buf.reserve(64)
    return oldData[0]
}

func borrowInvConditionallyDetachedOldAccessorPayload(detach: bool)->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let oldData = buf.view()
    if detach
    {
        buf.data     = null
        buf.capacity = 0
    }
    buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return oldData[0]
}

// Detaching one possible owner must not detach the same-named field of another.
func borrowInvDetachedAccessorFromOneOfTwoOwners(first: bool)->u8
{
    var left:  BorrowInvBuffer
    var right: BorrowInvBuffer
    left.reserve(4)
    right.reserve(4)

    var view = left.view()
    if !first
    {
        view = right.view()
    }

    left.data     = null
    left.capacity = 0
    right.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

// A method that only assigns fields moves nothing.
func borrowInvFieldOnlyMethod()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    buf.setLength(2)
    return view[0]
}

// A 'const' method cannot change the storage.
func borrowInvConstMethod()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view  = buf.view()
    let total = buf.count()
    return view[total]
}

// A pointer to the VALUE keeps addressing the same frame slot: it is the handle the
// change is made through, not something the change invalidates.
func borrowInvPointerToValue()->u64
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let p = &buf
    buf.reserve(64)
    return p.length
}

// Handing the view to the mutating call itself reads it BEFORE the call runs: the
// arguments are evaluated first, so this is not a read of moved storage.
func borrowInvViewAsArgument()->u64
{
    var buf: BorrowInvBuffer
    buf.reserve(8)
    let view = buf.view()
    buf.append(view)
    return buf.length
}

// Mutating a different owner leaves this view alone.
func borrowInvOtherOwner()->u8
{
    var buf:   BorrowInvBuffer
    var other: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    other.reserve(64)
    return view[0]
}

// The owner outlives every view taken from it and nothing structural happens in
// between: a container of views is not by itself a fault.
func borrowInvContainerOfViews()->u64
{
    var buf: BorrowInvBuffer
    buf.reserve(8)
    let views = [buf.view(), buf.view()]
    return @countof(views[0]) + @countof(views[1])
}

interface IBorrowInvSink
{
    mtd feed(value: u8)
}

impl IBorrowInvSink for BorrowInvBuffer
{
    mtd impl feed(value: u8)
    {
        .length += value
    }
}

// An interface bound to the value itself addresses the value, not its payload.
func borrowInvInterfaceToValue()
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let sink: IBorrowInvSink = &buf
    buf.reserve(64)
    sink.feed(1)
}

// The global half of every negative above. Widening the rule to global owners must not
// cost any of the precision the local half already has.

// Reading the view only BEFORE the change is safe.
func borrowInvGlobalReadBefore()->u8
{
    borrowInvGlobalBuf.reserve(4)
    let view  = borrowInvGlobalBuf.view()
    let first = view[0]
    borrowInvGlobalBuf.reserve(64)
    return first
}

// Taking the view again after the change is the fix.
func borrowInvGlobalRebound()->u8
{
    borrowInvGlobalBuf.reserve(4)
    var view = borrowInvGlobalBuf.view()
    borrowInvGlobalBuf.reserve(64)
    view = borrowInvGlobalBuf.view()
    return view[0]
}

// A method that only assigns fields moves nothing.
func borrowInvGlobalFieldOnlyMethod()->u8
{
    borrowInvGlobalBuf.reserve(4)
    let view = borrowInvGlobalBuf.view()
    borrowInvGlobalBuf.setLength(2)
    return view[0]
}

// A 'const' method cannot change the storage.
func borrowInvGlobalConstMethod()->u8
{
    borrowInvGlobalBuf.reserve(4)
    let view  = borrowInvGlobalBuf.view()
    let total = borrowInvGlobalBuf.count()
    return view[total]
}

// A pointer to the VALUE addresses the global itself, not its payload.
func borrowInvGlobalPointerToValue()->u64
{
    borrowInvGlobalBuf.reserve(4)
    let p = &borrowInvGlobalBuf
    borrowInvGlobalBuf.reserve(64)
    return p.length
}

// Mutating a different global leaves this view alone.
func borrowInvGlobalOtherOwner()->u8
{
    borrowInvGlobalBuf.reserve(4)
    let view = borrowInvGlobalBuf.view()
    borrowInvGlobalOther.reserve(64)
    return view[0]
}

// Mutating a LOCAL leaves a view of the global alone, and the other way round.
func borrowInvGlobalAndLocalAreDistinct()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    borrowInvGlobalBuf.reserve(4)
    let globalView = borrowInvGlobalBuf.view()
    let localView  = buf.view()
    let first      = localView[0]
    buf.reserve(64)
    return globalView[0] + first
}

// The arguments run before the callee: a view named inside the mutating call is read
// before the change, not after it.
func borrowInvGlobalViewAsArgument()->u64
{
    borrowInvGlobalBuf.reserve(8)
    let view = borrowInvGlobalBuf.view()
    borrowInvGlobalBuf.append(view)
    return borrowInvGlobalBuf.length
}

// ---------------------------------------------------------------------------
// Control flow, not source order. A read that follows the change in the TEXT is only a
// read of moved storage when a path actually reaches it from there.
// ---------------------------------------------------------------------------

// The change and the read sit in sibling arms: whichever one runs, the other did not.
func borrowInvExclusiveBranches(grow: bool)->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    if grow
    {
        buf.reserve(64)
    }
    else
    {
        return view[0]
    }

    return 0
}

// The same, spelled as a switch: two cases never both run either.
func borrowInvExclusiveCases(kind: s32)->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    switch kind
    {
    case 0:
        buf.reserve(64)
    case 1:
        return view[0]
    }

    return 0
}

// The change inside a branch and the read after it: the path that grew reaches the read.
func borrowInvBranchThenRead(grow: bool)->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    if grow
    {
        buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    }

    return view[0]
}

// Both in the same arm, in order.
func borrowInvSameBranch(grow: bool)->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    if grow
    {
        buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
        return view[0]
    }

    return 0
}

// Sibling arms of a loop are not exclusive at all: growing on one pass and reading on the
// next reads storage the growth moved.
func borrowInvExclusiveBranchesInLoop(grow: bool)->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    var total: u8
    for 4
    {
        if grow
        {
            buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
        }
        else
        {
            total += view[0]
        }
    }

    return total
}

// A view rebuilt at the start of every iteration cannot be read after a mutating arm
// that unconditionally continues: the next iteration replaces it first.
func borrowInvContinueRebuildsView(grow: bool)->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    var total: u8
    for 4
    {
        let view = buf.view()
        if grow
        {
            buf.reserve(64)
            continue
        }
        total += view[0]
    }

    return total
}

// The same continue does not save a view declared outside the loop: a later iteration
// can still read it without rebuilding it.
func borrowInvContinueKeepsOuterView(grow: bool)->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    var total: u8
    for 4
    {
        if grow
        {
            buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
            continue
        }
        total += view[0]
    }

    return total
}

// Source order wraps at the loop back edge: this read follows the mutation on
// every iteration after the first one.
func borrowInvReadAcrossBackEdge()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    var total: u8
    for 4
    {
        total += view[0]
        buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    }

    return total
}

// A view declared inside the loop is rebuilt before every read.
func borrowInvBackEdgeLocalView()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    var total: u8
    for 4
    {
        let view = buf.view()
        total += view[0]
        buf.reserve(64)
    }

    return total
}

// Rebinding an outer view before the first read of each iteration is safe too.
func borrowInvBackEdgeRebound()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    var view = buf.view()
    var total: u8
    for 4
    {
        view  = buf.view()
        total += view[0]
        buf.reserve(64)
    }

    return total
}

// No back edge is taken after the mutation.
func borrowInvBackEdgeExit()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    var total: u8
    for 4
    {
        total += view[0]
        buf.reserve(64)
        break
    }

    return total
}

// Breaking an inner loop does not stop the outer loop from reading the stale view.
func borrowInvNestedBackEdge()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    var total: u8
    for 4
    {
        total += view[0]
        for 2
        {
            buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
            break
        }
    }

    return total
}

// Invalidation is a language rule like the escape rules: an attribute that turns the
// sanity analyses off does not make the program legal.
#[Swag.Sanity(.Lifecycle, false)]
func borrowInvSanityOff()->u8
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[0]
}

// A generic macro has no resolved body before it is expanded. Its local owner and view
// therefore become judgeable only inside the materialized expansion.
#[Swag.Macro]
func(var T) borrowInvMacroInvalidates(_: T)
{
    var buf: BorrowInvBuffer
    buf.reserve(4)
    let view = buf.view()
    buf.reserve(64)     // swc-expected-error {{sanity_err_borrow_invalidated}}
    let value = view[0]
}

#test
{
    if false do
        borrowInvMacroInvalidates(0)
}
