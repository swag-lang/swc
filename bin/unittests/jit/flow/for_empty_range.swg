#global private

// A range loop asks a predicate, so a range that selects nothing runs zero iterations
// instead of raising an error. That covers an exclusive range whose bounds are equal and an
// inverted range alike, with or without runtime guards. Only constant bounds are rejected,
// at compile time, where the inversion is certain rather than merely possible.

//
// Constant empty exclusive ranges
//

#test
{
    func constantEmpty()->s32
    {
        var acc: s32 = 0
        for i in 0 until 0 do
            acc += i + 1
        return acc
    }

    const V = #run constantEmpty()
    #assert(V == 0)
    @assert(constantEmpty() == 0)
}

#test
{
    func constantEmptyNonZeroBound()->s32
    {
        var acc: s32 = 0
        for i in 5 until 5 do
            acc += i + 1
        return acc
    }

    const V = #run constantEmptyNonZeroBound()
    #assert(V == 0)
    @assert(constantEmptyNonZeroBound() == 0)
}

#test
{
    func constantEmptyNegativeBound()->s32
    {
        var acc: s32 = 0
        for i in -3 until -3 do
            acc += i
        return acc
    }

    const V = #run constantEmptyNegativeBound()
    #assert(V == 0)
    @assert(constantEmptyNegativeBound() == 0)
}

// The inclusive form with equal bounds still visits exactly one value.
#test
{
    func constantInclusiveSingle()->s32
    {
        var acc: s32 = 0
        for i in 5 to 5 do
            acc += i
        return acc
    }

    const V = #run constantInclusiveSingle()
    #assert(V == 5)
    @assert(constantInclusiveSingle() == 5)
}

//
// Dynamic bounds: the emblematic 'for i in 0 until count' idiom on an empty collection
//

func loopUntil(low, high: s32)->s32
{
    var acc: s32 = 0
    for i in low until high do
        acc += i + 1
    return acc
}

#test
{
    // Empty at zero, empty away from zero, then a non-empty control.
    @assert(loopUntil(0, 0) == 0)
    @assert(loopUntil(7, 7) == 0)
    @assert(loopUntil(0, 3) == 1 + 2 + 3)
    @assert(loopUntil(-2, -2) == 0)

    #assert(#run loopUntil(0, 0) == 0)
    #assert(#run loopUntil(7, 7) == 0)
    #assert(#run loopUntil(0, 3) == 6)
}

func loopUntilUnsigned(low, high: u32)->u32
{
    var acc = 0'u32
    for i in low until high do
        acc += i + 1
    return acc
}

#test
{
    @assert(loopUntilUnsigned(0, 0) == 0)
    @assert(loopUntilUnsigned(4, 4) == 0)
    @assert(loopUntilUnsigned(0, 3) == 1 + 2 + 3)

    #assert(#run loopUntilUnsigned(0, 0) == 0)
    #assert(#run loopUntilUnsigned(4, 4) == 0)
}

func countElements(values: const [..] s32)->s32
{
    var acc: s32 = 0
    for i in 0 until cast(s32) @countof(values) do
        acc += values[i]
    return acc
}

#test
{
    var storage                = [10, 20, 30]
    let empty:  const [..] s32 = @mkslice(&storage[0], 0)
    let filled: const [..] s32 = storage

    @assert(countElements(empty) == 0)
    @assert(countElements(filled) == 60)
}

//
// '#reverse' over an empty exclusive range
//

func reverseLoopUntil(low, high: s32)->s32
{
    var acc: s32 = 0
    for #reverse i in low until high do
        acc += i + 1
    return acc
}

#test
{
    @assert(reverseLoopUntil(0, 0) == 0)
    @assert(reverseLoopUntil(6, 6) == 0)
    @assert(reverseLoopUntil(0, 3) == 1 + 2 + 3)

    #assert(#run reverseLoopUntil(0, 0) == 0)
    #assert(#run reverseLoopUntil(6, 6) == 0)
}

#test
{
    func constantReverseEmpty()->s32
    {
        var acc: s32 = 0
        for #reverse i in 2 until 2 do
            acc += i + 1
        return acc
    }

    const V = #run constantReverseEmpty()
    #assert(V == 0)
    @assert(constantReverseEmpty() == 0)
}

//
// The empty range composes with the rest of 'for'
//

#test
{
    func emptyWithWhereFilter(low, high: s32)->s32
    {
        var acc: s32 = 0
        for i in low until high where i % 2 == 0 do
            acc += i + 1
        return acc
    }

    @assert(emptyWithWhereFilter(0, 0) == 0)
    @assert(emptyWithWhereFilter(0, 3) == 1 + 3)
}

#test
{
    // An empty inner loop must not disturb the outer one, and 'defer' still balances.
    func emptyInnerLoop(inner: s32)->s32
    {
        var acc: s32 = 0
        for i in 0 until 3
        {
            defer acc += 1
            for j in 0 until inner do
                acc += 10
        }

        return acc
    }

    @assert(emptyInnerLoop(0) == 3)
    @assert(emptyInnerLoop(1) == 33)
}

//
// An inverted range selects nothing, whether guards are on or off
//

#[Swag.Safety(.BoundCheck, true)]
#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func invertedExclusive(low, high: s32)->s32
    {
        var acc: s32 = 0
        for i in low until high do
            acc += i + 1
        return acc
    }

    const V = #run invertedExclusive(5, 4)
    #assert(V == 0)
    @assert(invertedExclusive(5, 4) == 0)
}

#[Swag.Safety(.BoundCheck, true)]
#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func invertedInclusive(low, high: s32)->s32
    {
        var acc: s32 = 0
        for i in low to high do
            acc += i + 1
        return acc
    }

    const V = #run invertedInclusive(5, 4)
    #assert(V == 0)
    @assert(invertedInclusive(5, 4) == 0)
}

#[Swag.Safety(.BoundCheck, false)]
#test
{
    #[Swag.Safety(.BoundCheck, false)]
    func invertedUnguarded(low, high: s32)->s32
    {
        var acc: s32 = 0
        for i in low to high do
            acc += i + 1
        return acc
    }

    @assert(invertedUnguarded(5, 4) == 0)
}

// The collection-sized idiom on a signed counter: an empty collection makes the range
// inverted, which is exactly when the loop must not run.
#[Swag.Safety(.BoundCheck, true)]
#test
{
    func sumUpToLast(count: s32)->s32
    {
        var acc: s32 = 0
        for i in 0 to count - 1 do
            acc += i + 1
        return acc
    }

    @assert(sumUpToLast(0) == 0)
    @assert(sumUpToLast(3) == 1 + 2 + 3)
}

// '#reverse' walks the same range backwards and is empty on the same input.
#[Swag.Safety(.BoundCheck, true)]
#test
{
    func invertedReverse(low, high: s32)->s32
    {
        var acc: s32 = 0
        for #reverse i in low to high do
            acc += i + 1
        return acc
    }

    @assert(invertedReverse(5, 4) == 0)
}
