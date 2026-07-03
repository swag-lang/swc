#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertBitArray(values: const &BitArray, expected: const [..] bool)->bool
{
    if values.count != @countof(expected) do
        return false

    for i in values.count
    {
        if values.get(i) != expected[i] do
            return false
    }

    return true
}

#test
{
    var seed: [32] bool
    for i in 32 do
        seed[i] = (i & 1) == 0

    var values: BitArray
    values = seed

    @assert(values.count == 32)
    @assert(assertBitArray(values, seed))
}

#test
{
    var seed: [33] bool
    seed[0]  = true
    seed[32] = true

    var values: BitArray
    values = seed

    var visitCount: u64 = 0
    var lastOrdinal: u64 = 0
    var lastValue = false
    foreach value, ordinal in values
    {
        visitCount += 1
        lastOrdinal = ordinal
        lastValue   = value
    }

    @assert(visitCount == 33)
    @assert(lastOrdinal == 32)
    @assert(lastValue)
}

#test
{
    var values: BitArray
    values.reserve(33, false)
    values.invert()

    var expected: [33] bool
    for i in 33 do
        expected[i] = true

    var compare: BitArray
    compare = expected

    @assert(values == compare)
}

#test
{
    var lhs: BitArray
    lhs.reserve(33, false)
    lhs[0] = true

    var rhs: BitArray
    rhs.reserve(33, false)
    rhs[32] = true

    var orResult = lhs
    orResult.orWith(rhs)

    var expectedOr: [33] bool
    expectedOr[0]  = true
    expectedOr[32] = true

    var compareOr: BitArray
    compareOr = expectedOr
    @assert(orResult == compareOr)

    var xorResult = orResult
    xorResult.xorWith(rhs)
    @assert(xorResult == lhs)

    var andResult = orResult
    andResult.andWith(rhs)
    @assert(andResult == rhs)
}
