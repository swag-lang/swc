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

private func assertBitReads(data: const [..] u8)
{
    for position in data.count * 8 + 1
    {
        for count in 33'u32
        {
            var expected: BitReader
            var actual:   BitReader
            expected.init(data)
            actual.init(data)
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

// Multi-bit reads agree with individual reads at every alignment and truncated boundary.
#test
{
    let bytes: [10] u8 = [0x93, 0x02, 0xD7, 0x61, 0xFC, 0x35, 0x18, 0x80, 0x4D, 0xA2]
    for length in 11'u64 do
        assertBitReads(bytes[0 until length])

    var unaligned: [18] u8
    for offset in 8'u64
    {
        for index in 10'u64 do
            unaligned[offset + index] = bytes[index]
        assertBitReads(unaligned[offset until offset + 10])
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

// Compare boundary offsets and output against a scalar unescaper.
private func assertRbspBounds(data: const [..] u8, bounds: const [..] u64)
{
    var expected: Array'u8
    var positions: Array'u64
    var boundary = 0'u64
    var zeros    = 0'u32
    for index in data.count
    {
        while boundary < bounds.count and bounds[boundary] <= index
        {
            positions.add(expected.count)
            boundary += 1
        }

        let value = data[index]
        if zeros >= 2 and value == 3
        {
            zeros = 0
            continue
        }
        zeros = value == 0 ? zeros + 1 : 0
        expected.add(value)
    }
    while boundary < bounds.count
    {
        positions.add(expected.count)
        boundary += 1
    }

    var actual: Array'u8
    var actualPositions: Array'u64
    unescapeRbspWithBounds(&actual, data, bounds, &actualPositions)
    Swag.assert(Slice.equals(actual.toSlice(), expected.toSlice()))
    Swag.assert(Slice.equals(actualPositions.toSlice(), positions.toSlice()))
}

// Exercise copied blocks, duplicate boundaries, escapes, and zero runs across block edges.
#test
{
    for length in 81'u64
    {
        var bytes: [80] u8
        for index in length do
            bytes[index] = cast(u8, ((index * 37 + length * 13) & 255))
        for split in length + 1
        {
            let bounds: [5] u64 = [0, split, split, length, length + 1]
            assertRbspBounds(bytes[0 until length], bounds)
        }

        for escape in 2'u64 until length
        {
            bytes[escape - 2] = 0
            bytes[escape - 1] = 0
            bytes[escape]     = 3
            let bounds: [6] u64 = [0, escape - 2, escape - 1, escape, escape + 1, length]
            assertRbspBounds(bytes[0 until length], bounds)
            bytes[escape - 2] = 7
            bytes[escape - 1] = 11
            bytes[escape]     = 13
        }
    }

    var zeros: [65] u8
    zeros[64] = 3
    let boundaries: [5] u64 = [15, 16, 31, 32, 64]
    assertRbspBounds(zeros, boundaries)
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
