#global if #command == Swag.CompilerCommand.Test
#global private

using Core

private func referenceUe(bits: *BitReader)->u32
{
    var zeros = 0'u32
    while not bits.bit()
    {
        zeros += 1
        if zeros > 31 or bits.overran
        {
            bits.overran = true
            return 0
        }
    }

    var suffix = 0'u32
    for zeros do
        suffix = (suffix << 1) | bits.bit()
    return zeros ? (1'u32 << zeros) - 1 + suffix : 0
}

private func assertExpGolomb(data: const [..] u8)
{
    for position in data.count * 8 + 1
    {
        var expected: BitReader
        var actual:   BitReader
        expected.init(data)
        actual.init(data)
        expected.skip(cast(u32, position))
        actual.skip(cast(u32, position))
        let value = referenceUe(&expected)
        let read  = actual.ue()
        Swag.assert(read == value)
        Swag.assert(actual.bitPos == expected.bitPos and actual.overran == expected.overran)
    }
}

// Exp-Golomb reads preserve values and overrun state at every alignment and boundary.
#test
{
    var bytes: [5] u8
    for seed in 32'u32
    {
        for i in 5 do
            bytes[i] = cast(u8, ((seed * 53 + i * 79) & 255))
        for length in 6'u64 do
            assertExpGolomb(bytes[0 until length])
    }

    for position in 40'u64
    {
        for i in 5 do
            bytes[i] = 0
        bytes[position / 8] = cast(u8, (1 << (7 - position % 8)))
        for length in 6'u64 do
            assertExpGolomb(bytes[0 until length])
    }
}

// Multi-bit reads agree with individual reads at every alignment and truncated boundary.
#test
{
    let bytes: [6] u8 = [0x93, 0x02, 0xD7, 0x61, 0xFC, 0x35]
    for length in 7'u64
    {
        for position in length * 8 + 1
        {
            for count in 33'u32
            {
                var expected: BitReader
                var actual:   BitReader
                expected.init(bytes[0 until length])
                actual.init(bytes[0 until length])
                expected.skip(cast(u32, position))
                actual.skip(cast(u32, position))

                var value = 0'u32
                for count do
                    value = (value << 1) | expected.bit()
                let read = actual.read(count)
                Swag.assert(read == value)
                Swag.assert(actual.bitPos == expected.bitPos and actual.overran == expected.overran)
            }
        }
    }
}

func referenceUnescapeRbsp(data: const [..] u8)->Array'u8
{
    var result: #returntype
    var zeros = 0'u32
    for value in data
    {
        if zeros >= 2 and value == 3
        {
            zeros = 0
            continue
        }

        zeros = value == 0 ? zeros + 1 : 0
        result.add(value)
    }

    return result
}

func assertRbspUnescape(data: const [..] u8)
{
    let expected = referenceUnescapeRbsp(data)
    var actual: Array'u8
    unescapeRbsp(&actual, data)
    Swag.assert(actual.count == expected.count)
    Swag.assert(Slice.equals(actual.toSlice(), expected.toSlice()))
}

// Exercise every vector alignment and tail, with the escape triplet at every possible byte.
#test
{
    for alignment in 16'u64
    {
        for length in 81'u64
        {
            var storage: Array'u8
            storage.resize(alignment + length + 1)
            let data = storage.toSlice()[alignment until alignment + length]
            for index in length do
                data[index] = cast(u8, ((index * 37 + 11) & 255))
            assertRbspUnescape(data)

            for escape in 2'u64 until length
            {
                data[escape - 2] = 0
                data[escape - 1] = 0
                data[escape]     = 3
                assertRbspUnescape(data)
                data[escape - 2] = 17
                data[escape - 1] = 29
                data[escape]     = 43
            }
        }
    }

    const Repeated = [0'u8, 0, 3, 0, 0, 3, 0, 0, 0, 3, 1]
    assertRbspUnescape(Repeated)
}
