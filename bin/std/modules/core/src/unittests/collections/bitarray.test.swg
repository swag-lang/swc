#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertBitArray(values: const &BitArray, expected: const [..] bool)->bool
{
    if values.count != @countof(expected) do
        return false

    for [i] in values.count
    {
        if values.get(i) != expected[i] do
            return false
    }

    return true
}

#test
{
    var seed: [32] bool
    for [i] in 32 do
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

    var visitCount:  u64 = 0
    var lastOrdinal: u64 = 0
    var lastValue        = false
    for value, [ordinal] in values
    {
        visitCount  += 1
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
    values.resize(33)
    values.invert()

    var expected: [33] bool
    for [i] in 33 do
        expected[i] = true

    var compare: BitArray
    compare = expected

    @assert(values == compare)
}

#test
{
    var lhs: BitArray
    lhs.resize(33)
    lhs[0] = true

    var rhs: BitArray
    rhs.resize(33)
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

#test
{
    var values: BitArray
    values.resize(65, true)
    values.resize(0)
    @assert(values.count == 0)

    values.resize(3, true)
    @assert(values[0] and values[1] and values[2])
}
