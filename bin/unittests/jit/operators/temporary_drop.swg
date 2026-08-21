#global private

var DropCount:     u32 = 0
var DropTrace:     s64 = 0
var EventTrace:    u32 = 0
var PostCopyCount: u32 = 0
var PostMoveCount: u32 = 0
var Seed:          s32 = 0

struct TemporaryOwner
{
    value: s32
    pad:   [3] s64
}

impl TemporaryOwner
{
    #[Swag.Inline]
    mtd const inlineValue()->s32
    {
        EventTrace = EventTrace * 10 + 1
        return .value
    }

    #[Swag.Implicit, Swag.NoInline]
    mtd const opCast()->s32
    {
        EventTrace = EventTrace * 10 + 1
        return .value
    }

    mtd opDrop()
    {
        DropCount  += 1
        DropTrace  = DropTrace * 10 + cast(s64) .value
        EventTrace = EventTrace * 10 + 2
    }
}

struct TransferOwner
{
    value: s32
    pad:   [3] s64
}

struct OwnerPair
{
    first:  TemporaryOwner
    second: TemporaryOwner
}

struct TransferPair
{
    first:  TransferOwner
    second: TransferOwner
}

impl TransferOwner
{
    mtd opDrop()
    {
        DropCount += 1
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
    }
}

struct TemporaryError
{
    using base: Swag.BaseError
    code:       s32
}

struct TemporaryVisits
{
    value: s32 = 0
}

impl TemporaryVisits
{
    #[Swag.Macro]
    func(ptr: bool) opVisit(const me, stmt: #code(item: s32, index: u64))
    {
        for idx in 2
        {
            #inject(stmt, item = cast(s32) @index, index = @index)
        }
    }
}

#[Swag.NoInline]
func makeTemporaryOwner(value: s32)->TemporaryOwner
{
    var result: retval
    result.value = value
    return result
}

#[Swag.NoInline]
func makeTransferOwner(value: s32)->TransferOwner
{
    var result: retval
    result.value = value
    return result
}

#[Swag.NoInline]
func makeOwnerPair(first, second: s32)->OwnerPair
{
    var result: retval
    result.first.value  = first
    result.second.value = second
    return result
}

#[Swag.NoInline]
func makeTransferPair(first, second: s32)->TransferPair
{
    var result: retval
    result.first.value  = first
    result.second.value = second
    return result
}

#[Swag.NoInline]
func makeLoopTemporaryOwner(value: s32)->TemporaryOwner
{
    Seed += 1
    return makeTemporaryOwner(value)
}

#[Swag.NoInline]
func consume(value: s32)
{
    EventTrace = EventTrace * 10 + 3
    @assert(value == Seed)
}

#[Swag.NoInline]
func consumePair(left: s32, right: s32)
{
    EventTrace = EventTrace * 10 + 3
    @assert(left == 4)
    @assert(right == 5)
}

#[Swag.NoInline]
func isSeed(value: s32)->bool => value == Seed

#[Swag.Inline]
func forwardTemporaryOwner()->TemporaryOwner => makeTemporaryOwner(Seed)

#[Swag.NoInline]
func relayTemporaryOwner(value: s32)->TemporaryOwner => makeTemporaryOwner(value)

#[Swag.NoInline]
func visitFailureTemporary() fail
{
    for value in TemporaryVisits{}
    {
        if value == -1 do
            fail TemporaryError{code: makeTemporaryOwner(7)}
    }
}

// An ignored owned result dies at the end of its statement.
#test
{
    DropCount  = 0
    EventTrace = 0
    Seed       += 1
    discard makeTemporaryOwner(Seed)
    @assert(DropCount == 1)
}

// A conversion may borrow the result until its consumer returns; the owner dies after
// that whole statement, not immediately after the producing call.
#test
{
    DropCount  = 0
    EventTrace = 0
    Seed       += 1
    consume(makeTemporaryOwner(Seed))
    @assert(DropCount == 1)
    @assert(EventTrace == 132)
}

// An inline borrower does not shorten the lifetime of its receiver.
#test
{
    DropCount  = 0
    EventTrace = 0
    Seed       += 1
    consume(makeTemporaryOwner(Seed).inlineValue())
    @assert(DropCount == 1)
    @assert(EventTrace == 132)
}

// Several temporaries survive through the same consumer and then die in reverse order.
#test
{
    DropCount  = 0
    DropTrace  = 0
    EventTrace = 0
    consumePair(makeTemporaryOwner(4), makeTemporaryOwner(5))
    @assert(DropCount == 2)
    @assert(DropTrace == 54)
    @assert(EventTrace == 11322)
}

// A nested temporary does not take over the destination storage of the outer call.
#test
{
    DropCount  = 0
    EventTrace = 0
    Seed       += 1
    {
        var owner = relayTemporaryOwner(makeTemporaryOwner(Seed))
        @assert(DropCount == 1)
        @assert(owner.value == Seed)
    }
    @assert(DropCount == 2)
}

// Destructuring transfers every owned field out of the aggregate call result.
#test
{
    DropCount = 0
    DropTrace = 0
    {
        var {first, second} = makeOwnerPair(4, 5)
        @assert(DropCount == 0)
        @assert(first.value == 4)
        @assert(second.value == 5)
    }
    @assert(DropCount == 2)
    @assert(DropTrace == 54)
}

// A temporary created only in a conditional branch is dropped only when that branch runs.
#test
{
    DropCount  = 0
    EventTrace = 0
    Seed       += 1
    if Seed == -1 do consume(makeTemporaryOwner(Seed))
    @assert(DropCount == 0)
    if true do consume(makeTemporaryOwner(Seed))
    @assert(DropCount == 1)
}

// An opVisit expansion preserves the caller's branch and statement boundaries.
#test
{
    DropCount  = 0
    EventTrace = 0
    for value in TemporaryVisits{}
    {
        if value == 0 do discard makeTemporaryOwner(7)
        @assert(DropCount == 1)
    }
    @assert(DropCount == 1)

    // The unused failure branch must not drop its uninitialized call temporary
    // when the opVisit expansion ends.
    DropCount = 0
    catch visitFailureTemporary()
    @assert(DropCount == 0)
}

// A temporary in an unbraced loop body dies on every iteration.
#test
{
    DropCount  = 0
    EventTrace = 0
    Seed       = 0
    while Seed < 2 do discard makeLoopTemporaryOwner(7)
    @assert(DropCount == 2)
}

// A loop condition owns a fresh temporary on every evaluation, not until loop exit.
#test
{
    DropCount  = 0
    EventTrace = 0
    Seed       += 1
    while isSeed(makeTemporaryOwner(Seed))
    {
        @assert(DropCount == 1)
        break
    }
    @assert(DropCount == 1)
}

// A drop-only assignment transfers the bits; only the old target and the new owner die.
#test
{
    DropCount  = 0
    EventTrace = 0
    Seed       += 1
    {
        var owner = TemporaryOwner{value: -1}
        owner = makeTemporaryOwner(Seed)
        @assert(DropCount == 1)
        @assert(owner.value == Seed)
    }
    @assert(DropCount == 2)
}

// Assigning an owned result uses post-move repair, then transfers its lifetime.
#test
{
    DropCount     = 0
    PostCopyCount = 0
    PostMoveCount = 0
    {
        var owner = TransferOwner{value: -1}
        PostCopyCount = 0
        PostMoveCount = 0
        discard makeTransferOwner(0)
        let callPostCopyCount = PostCopyCount
        let callPostMoveCount = PostMoveCount
        DropCount     = 0
        PostCopyCount = 0
        PostMoveCount = 0
        owner         = makeTransferOwner(7)
        @assert(DropCount == 1)
        @assert(PostCopyCount == callPostCopyCount)
        @assert(PostMoveCount == callPostMoveCount + 1)
        @assert(owner.value == 7)
    }
    @assert(DropCount == 2)
}

// Destructuring assignment drops each old target value before the matching field of the
// call result lands on it, and the temporary never drops what it handed over. The trace,
// not the count, is what tells a correct transfer from a swapped one.
#test
{
    var pair = makeOwnerPair(8, 9)
    DropCount = 0
    DropTrace = 0
    {pair.first, pair.second} = makeOwnerPair(4, 5)
    @assert(DropCount == 2)
    @assert(DropTrace == 89)
    @assert(pair.first.value == 4)
    @assert(pair.second.value == 5)
}

// A field the pattern skips still belongs to the call result, so it dies with the statement
// instead of leaking, and the target it does not name keeps its own value.
#test
{
    var pair = makeOwnerPair(8, 9)
    DropCount = 0
    DropTrace = 0
    {pair.first, ?} = makeOwnerPair(4, 5)
    @assert(DropCount == 2)
    @assert(DropTrace == 85)
    @assert(pair.first.value == 4)
    @assert(pair.second.value == 9)
}

// A right side that outlives the statement is copied, not moved: every target repairs the
// payload it now shares through post-copy.
#test
{
    var source = makeTransferPair(4, 5)
    var target = makeTransferPair(8, 9)
    DropCount     = 0
    PostCopyCount = 0
    PostMoveCount = 0
    {target.first, target.second} = source
    @assert(DropCount == 2)
    @assert(PostCopyCount == 2)
    @assert(PostMoveCount == 0)
    @assert(target.first.value == 4)
    @assert(target.second.value == 5)
}

// A consumed call result is moved instead, so every target repairs through post-move.
#test
{
    var target = makeTransferPair(8, 9)
    PostCopyCount = 0
    PostMoveCount = 0
    discard makeTransferPair(0, 0)
    let callPostCopyCount = PostCopyCount
    let callPostMoveCount = PostMoveCount
    DropCount     = 0
    PostCopyCount = 0
    PostMoveCount = 0
    {target.first, target.second} = makeTransferPair(4, 5)
    @assert(DropCount == 2)
    @assert(PostCopyCount == callPostCopyCount)
    @assert(PostMoveCount == callPostMoveCount + 2)
    @assert(target.first.value == 4)
    @assert(target.second.value == 5)
}

// Returning through an inline result transfers the call temporary to the caller.
#test
{
    DropCount  = 0
    EventTrace = 0
    Seed       += 1
    {
        var owner = forwardTemporaryOwner()
        @assert(owner.value == Seed)
    }
    @assert(DropCount == 1)
}
