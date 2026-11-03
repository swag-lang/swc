#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertBitArray(values: BitArray, expected: const [..] bool)->bool
{
    if values.count != expected.count do
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

    Swag.assert(values.count == 32)
    Swag.assert(assertBitArray(values, seed))
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
    for value, ordinal in values
    {
        visitCount  += 1
        lastOrdinal = ordinal
        lastValue   = value
    }

    Swag.assert(visitCount == 33)
    Swag.assert(lastOrdinal == 32)
    Swag.assert(lastValue)
}

#test
{
    var values: BitArray
    values.resize(33)
    values.invert()

    var expected: [33] bool
    for i in 33 do
        expected[i] = true

    var compare: BitArray
    compare = expected

    Swag.assert(values == compare)
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
    Swag.assert(orResult == compareOr)

    var xorResult = orResult
    xorResult.xorWith(rhs)
    Swag.assert(xorResult == lhs)

    var andResult = orResult
    andResult.andWith(rhs)
    Swag.assert(andResult == rhs)
}

#test
{
    var values: BitArray
    values.resize(65, true)
    values.resize(0)
    Swag.assert(values.count == 0)

    values.resize(3, true)
    Swag.assert(values[0] and values[1] and values[2])
}

// Logic operations cross four-word SIMD batches and preserve the unused bits
// in the last word for arbitrary logical lengths.
#test
{
    let lengths: [8] u64 = [1, 31, 32, 33, 127, 128, 129, 511]
    for length in lengths
    {
        var left:  BitArray
        var right: BitArray
        left.resize(length)
        right.resize(length)
        for i in length
        {
            left[i]  = i % 3 == 0
            right[i] = i % 5 == 0
        }

        let original = left
        left.invert()
        for i in length do
            Swag.assert(left[i] == (i % 3 != 0))
        left.invert()
        Swag.assert(left == original)

        var value = original
        value.orWith(right)
        for i in length do
            Swag.assert(value[i] == (i % 3 == 0 or i % 5 == 0))

        value = original
        value.andWith(right)
        for i in length do
            Swag.assert(value[i] == (i % 3 == 0 and i % 5 == 0))

        value = original
        value.xorWith(right)
        for i in length do
            Swag.assert(value[i] == ((i % 3 == 0) != (i % 5 == 0)))
    }
}

// Equality crosses four-vector batches and checks every scalar tail word.
#test
{
    let lengths: [11] u64 = [0, 1, 31, 32, 33, 127, 128, 129, 511, 512, 513]
    for length in lengths
    {
        var left, right: BitArray
        left.resize(length)
        right.resize(length)
        for index in length
        {
            let value = index % 7 == 0
            left[index]  = value
            right[index] = value
        }

        Swag.assert(left == right)

        if length
        {
            let positions: [3] u64 = [0, length / 2, length - 1]
            for position in positions
            {
                right.invert(position)
                Swag.assert(left != right)
                right.invert(position)
                Swag.assert(left == right)
            }
        }
    }
}
