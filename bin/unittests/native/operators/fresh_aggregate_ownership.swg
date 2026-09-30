#global private

// A fresh aggregate literal is a new value, not a copy of one. Each field runs its own hook
// as it enters the literal; the aggregate itself is built where it is going. Returning it or
// binding it therefore runs no 'opPostCopy', and leaves no second value behind to drop.

var FreshCopies: s32
var FreshMoves:  s32
var FreshDrops:  s32
var FreshTrace:  s64
var FreshSeed:   s64

// The seed is read at run time, so no literal built from it folds into a constant.
func resetFresh(seed: s64)
{
    FreshCopies, FreshMoves, FreshDrops = 0
    FreshTrace = 0
    FreshSeed  = seed
}

func expectFresh(copies, moves, drops: s32, trace: s64)
{
    Swag.assert(FreshCopies == copies)
    Swag.assert(FreshMoves == moves)
    Swag.assert(FreshDrops == drops)
    Swag.assert(FreshTrace == trace)
}

struct FreshOwner
{
    value: s64
    extra: s64
}

impl FreshOwner
{
    mtd opPostCopy()
    {
        FreshCopies += 1
    }

    mtd opPostMove()
    {
        FreshMoves += 1
    }

    mtd opDrop()
    {
        FreshDrops += 1
        FreshTrace = FreshTrace * 100 + .value
    }
}

struct FreshPair
{
    first:  FreshOwner
    second: FreshOwner
}

#[Swag.NoInline]
func makeExpression(value: s64)->FreshOwner => FreshOwner{value}

#[Swag.NoInline]
func makeBlock(value: s64)->FreshOwner
{
    return FreshOwner{value, value + 1}
}

#[Swag.NoInline]
func makeBare(value: s64)->FreshOwner
{
    return {value, value + 1}
}

#[Swag.NoInline]
func makeDeferred(value: s64)->FreshOwner
{
    defer FreshSeed += 1
    return FreshOwner{value}
}

#[Swag.NoInline]
func makeFallible(value: s64)->FreshOwner fail
{
    if value < 0 do
        fail Swag.BaseError{"negative"}
    return FreshOwner{value}
}

#[Swag.NoInline]
func makeConstant()->FreshOwner
{
    return FreshOwner{3, 4}
}

#[Swag.NoInline]
func makePair(source: FreshOwner)->FreshPair
{
    return FreshPair{source, makeBlock(source.value + 1)}
}

#[Swag.NoInline]
func makeArray(value: s64)->[2] FreshOwner
{
    return [FreshOwner{value}, FreshOwner{value + 1}]
}

#[Swag.NoInline]
func sumPair(pair: FreshPair)->s64 => pair.first.value + pair.second.value

#[Swag.Inline]
func makeInline(value: s64)->FreshOwner => FreshOwner{value}

#[Swag.Inline]
func makeInlineBranches(value: s64)->FreshOwner
{
    if value < 0 do
        return FreshOwner{-value, 1}
    return FreshOwner{value}
}

// Returns what an inline expansion built: the expansion's result moves into the slot.
#[Swag.NoInline]
func forwardInline(value: s64)->FreshOwner
{
    return makeInline(value)
}

// Left to the optimizer, which expands it inline in both configurations.
func makeAuto(value: s64)->FreshOwner
{
    return FreshOwner{value}
}

// A returned literal is built in the caller's result, whatever the shape of the body.
#test
{
    resetFresh(11)
    {
        let owner = makeExpression(FreshSeed)
        Swag.assert(owner.value == 11)
        expectFresh(0, 0, 0, 0)
    }
    expectFresh(0, 0, 1, 11)

    resetFresh(12)
    {
        let owner = makeBlock(FreshSeed)
        Swag.assert(owner.value == 12 and owner.extra == 13)
    }
    expectFresh(0, 0, 1, 12)

    resetFresh(13)
    {
        let owner = makeBare(FreshSeed)
        Swag.assert(owner.value == 13 and owner.extra == 14)
    }
    expectFresh(0, 0, 1, 13)

    resetFresh(0)
    {
        let owner = makeConstant()
        Swag.assert(owner.value == 3 and owner.extra == 4)
    }
    expectFresh(0, 0, 1, 3)
}

// Deferred statements run after the literal is in the result, and do not disturb it.
#test
{
    resetFresh(14)
    {
        let owner = makeDeferred(FreshSeed)
        Swag.assert(owner.value == 14)
        Swag.assert(FreshSeed == 15)
    }
    expectFresh(0, 0, 1, 14)
}

// A fallible factory builds its success value in place; a failure leaves a zero result.
#test
{
    resetFresh(15)
    {
        let owner = catch makeFallible(FreshSeed)
        Swag.assert(owner.value == 15)
    }
    expectFresh(0, 0, 1, 15)

    resetFresh(-16)
    {
        let owner = catch makeFallible(FreshSeed)
        Swag.assert(owner.value == 0)
    }
    expectFresh(0, 0, 1, 0)
}

// An inline expansion builds the literal in its own temporary, which the binding adopts:
// one relocation, still no copy, and nothing left behind to drop.
#test
{
    resetFresh(17)
    {
        let owner = makeInline(FreshSeed)
        Swag.assert(owner.value == 17)
    }
    expectFresh(0, 1, 1, 17)

    resetFresh(18)
    {
        let owner = makeInlineBranches(FreshSeed)
        Swag.assert(owner.value == 18)
    }
    expectFresh(0, 1, 1, 18)

    resetFresh(-19)
    {
        let owner = makeInlineBranches(FreshSeed)
        Swag.assert(owner.value == 19 and owner.extra == 1)
    }
    expectFresh(0, 1, 1, 19)

    // The expansion's result moves into the return slot. Whether the literal was built in
    // that result or moved into it first is the expansion's business: the contract is no
    // copy and a single drop.
    resetFresh(31)
    {
        let owner = forwardInline(FreshSeed)
        Swag.assert(owner.value == 31)
    }
    Swag.assert(FreshMoves == 1 or FreshMoves == 2)
    FreshMoves = 0
    expectFresh(0, 0, 1, 31)

    // Whether the optimizer expands this one decides between zero and one relocation.
    resetFresh(20)
    {
        let owner = makeAuto(FreshSeed)
        Swag.assert(owner.value == 20)
    }
    Swag.assert(FreshMoves <= 1)
    FreshMoves = 0
    expectFresh(0, 0, 1, 20)
}

// Assigning a call result moves the temporary the factory filled: one move, no copy,
// and one drop each for the overwritten value and the final one.
#test
{
    resetFresh(21)
    {
        var owner: FreshOwner
        owner = makeBlock(FreshSeed)
        Swag.assert(owner.value == 21)
    }
    expectFresh(0, 1, 2, 21)
}

// Fields keep their own hooks: a named source is copied into its field, a call result is
// moved into its field, and the enclosing aggregate adds nothing. Every value is dropped
// once: the two fields, then the source.
#test
{
    resetFresh(22)
    {
        let source = makeBlock(FreshSeed)
        let pair   = makePair(source)
        Swag.assert(pair.first.value == 22 and pair.second.value == 23)
        expectFresh(1, 1, 0, 0)
    }
    expectFresh(1, 1, 3, 232_222)

    resetFresh(32)
    {
        let source = makeBlock(FreshSeed)
        let pair   = FreshPair{source, makeBlock(FreshSeed + 1)}
        Swag.assert(pair.first.value == 32 and pair.second.value == 33)
        expectFresh(1, 1, 0, 0)
    }
    expectFresh(1, 1, 3, 333_232)
}

// A literal passed as an argument owns the call result it adopted, and drops it with the
// statement.
#test
{
    resetFresh(34)
    {
        let source = makeBlock(FreshSeed)
        let sum    = sumPair(FreshPair{source, makeBlock(FreshSeed + 1)})
        Swag.assert(sum == 69)
        expectFresh(1, 1, 2, 3534)
    }
    expectFresh(1, 1, 3, 353_434)
}

// An array literal of fresh elements owns them. Each element is built in a temporary of its own
// and moved into the array, so a value that points into itself is repaired by its move hook.
#test
{
    resetFresh(24)
    {
        let owners = makeArray(FreshSeed)
        Swag.assert(owners[0].value == 24 and owners[1].value == 25)
    }
    expectFresh(0, 2, 2, 2425)
}

// Binding a literal builds it in the variable. The elements of an array literal are moved into it.
#test
{
    resetFresh(26)
    {
        let owner = FreshOwner{FreshSeed}
        Swag.assert(owner.value == 26)
    }
    expectFresh(0, 0, 1, 26)

    resetFresh(27)
    {
        var owner: FreshOwner = {FreshSeed, 1}
        Swag.assert(owner.value == 27 and owner.extra == 1)
    }
    expectFresh(0, 0, 1, 27)

    resetFresh(28)
    {
        let owners = [FreshOwner{FreshSeed}, FreshOwner{FreshSeed + 1}]
        Swag.assert(owners[0].value == 28 and owners[1].value == 29)
    }
    expectFresh(0, 2, 2, 2829)
}

// Assigning a literal moves it over the value it replaces.
#test
{
    resetFresh(30)
    {
        var owner: FreshOwner
        owner = FreshOwner{FreshSeed}
        Swag.assert(owner.value == 30)
    }
    expectFresh(0, 1, 2, 30)
}
