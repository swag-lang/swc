#global private
using Swag

#[Swag.Optimize(true), Swag.NoInline]
func indexedXor4(values: [*] u32, index: u64, mask: u32)
{
    values[index]     ^= mask
    values[index + 1] ^= mask
    values[index + 2] ^= mask
    values[index + 3] ^= mask
}

#[Swag.Optimize(true), Swag.NoInline]
func indexedXor16(values: [*] u32, index: u64, mask: u32)
{
    for i in 16 do values[index + i] ^= mask
}

#[Swag.Optimize(true), Swag.NoInline]
func indexedAddImmediate4(values: [*] u32, index: u64)
{
    values[index]     += #wrap 3
    values[index + 1] += #wrap 3
    values[index + 2] += #wrap 3
    values[index + 3] += #wrap 3
}

#[Swag.Optimize(true), Swag.NoInline]
func indexedChain4(values: [*] u32, index: u64)
{
    values[index]     += #wrap values[index + 1]
    values[index + 1] ^= values[index + 2]
    values[index + 2] += #wrap values[index + 3]
    values[index + 3] ^= values[index]
}

#[Swag.Optimize(true), Swag.NoInline]
func indexedAlias4(values, source: [*] u32, index: u64)
{
    values[index]     ^= source[0]
    values[index + 1] ^= source[1]
    values[index + 2] ^= source[2]
    values[index + 3] ^= source[3]
}

#[Swag.Optimize(true), Swag.NoInline]
func indexedMixedWidth4(values: [*] u32, index: u64, mask: u32)
{
    values[index] ^= mask
    let bytes = cast([*] u8, values)
    bytes[(index + 1) * 4] = 0xA7
    values[index + 1]      ^= mask
    values[index + 2]      ^= mask
    values[index + 3]      ^= mask
}

#test
{
    for offset in 5'u64
    {
        for mask in [0'u32, 1, 0x8000_0000, 0xFFFF_FFFF]
        {
            var actual: [12] u32
            for i in 12 do actual[i] = cast(u32, (i * 0x10001 + 17))
            var expected = actual
            indexedXor4(&actual[0], offset, mask)
            for i in 4 do expected[offset + i] ^= mask
            for i in 12 do Swag.assert(actual[i] == expected[i])

            indexedChain4(&actual[0], offset)
            expected[offset]     += #wrap expected[offset + 1]
            expected[offset + 1] ^= expected[offset + 2]
            expected[offset + 2] += #wrap expected[offset + 3]
            expected[offset + 3] ^= expected[offset]
            for i in 12 do Swag.assert(actual[i] == expected[i])

            indexedMixedWidth4(&actual[0], offset, mask)
            expected[offset]     ^= mask
            expected[offset + 1] = (expected[offset + 1] & 0xFFFF_FF00) | 0xA7
            for i in 3 do expected[offset + i + 1] ^= mask
            for i in 12 do Swag.assert(actual[i] == expected[i])
        }
    }

    for displacement in 5'u64
    {
        var actual: [12] u32
        for i in 12 do actual[i] = cast(u32, (i * 0x10001 + 17))
        var expected = actual
        indexedAlias4(&actual[0], &actual[displacement], 2)
        for i in 4 do expected[2 + i] ^= expected[displacement + i]
        for i in 12 do Swag.assert(actual[i] == expected[i])
    }
}

#test
{
    for offset in 5'u64
    {
        for mask in [0'u32, 1, 0x8000_0000, 0xFFFF_FFFF]
        {
            var actual: [24] u32
            for i in 24 do actual[i] = cast(u32, (i * 0x10001 + 17))
            var expected = actual
            indexedXor16(&actual[0], offset, mask)
            for i in 16 do expected[offset + i] ^= mask
            indexedAddImmediate4(&actual[0], offset)
            for i in 4 do expected[offset + i] += #wrap 3
            for i in 24 do Swag.assert(actual[i] == expected[i])
        }
    }
}

#[Swag.Optimize(true), Swag.NoInline]
func indexedXorBlocks(values: [*] u32, count: u64, mask: u32)
{
    var index = 0'u64
    while index < count
    {
        for i in 16 do values[index + i] ^= mask
        index += 16
    }
}

#[Swag.Optimize(true), Swag.NoInline]
func indexedCapturedBlocks(values: [*] u32, count: u64, mask: u32)
{
    var index = 0'u64
    while index < count
    {
        let saved = index
        index += 16
        for i in 16 do values[saved + i] ^= mask
    }
}

#[Swag.NoInline]
func indexedBorrow(values: [*] u32)->[*] u32 => values

#[Swag.Optimize(true), Swag.NoInline]
func indexedEscapedFrame(source: [*] u32, seed: u32)->[8] u32
{
    var local: [8] u32
    for i in 8 do local[i] = seed + cast(u32, i)
    var values = source
    for iteration in 2
    {
        values[0] ^= local[0]
        values[1] ^= local[1]
        values[2] ^= local[2]
        values[3] ^= local[3]
        values    = indexedBorrow(&local[1])
    }
    return local
}

#test
{
    for count in [0'u64, 16, 48]
    {
        var actual: [64] u32
        for i in 64 do actual[i] = cast(u32, (i * 0x10001 + 17))
        var expected = actual
        indexedXorBlocks(&actual[1], count, 0xAABB_CCDD)
        for i in count do expected[i + 1] ^= 0xAABB_CCDD
        for i in 64 do Swag.assert(actual[i] == expected[i])
        indexedCapturedBlocks(&actual[1], count, 0x1122_3344)
        for i in count do expected[i + 1] ^= 0x1122_3344
        for i in 64 do Swag.assert(actual[i] == expected[i])
    }
    for seed in [0'u32, 17, 0x8000_0000]
    {
        var source:   [4] u32 = [3, 9, 27, 81]
        var expectedSource    = source
        var expected: [8] u32
        for i in 8 do expected[i] = seed + cast(u32, i)
        for i in 4 do expectedSource[i] ^= expected[i]
        for i in 4 do expected[i + 1] ^= expected[i]
        let actual = indexedEscapedFrame(&source[0], seed)
        for i in 8 do Swag.assert(actual[i] == expected[i])
        for i in 4 do Swag.assert(source[i] == expectedSource[i])
    }
}

#[Swag.NoInline]
func indexedSummary(values: u32...)->u32
{
    var result = 0'u32
    for value in values do result += value
    return result
}

#[Swag.Optimize(true), Swag.NoInline]
func indexedCopiedState(input: [*] u32, count: u64, seed: u32)->u32
{
    Swag.assert(count % 16 == 0)
    let values = indexedBorrow(input)
    var initial: [16] u32
    for i in 16 do initial[i] = seed + cast(u32, i)
    var offset  = 0'u64
    var counter = 1'u32
    while offset < count
    {
        initial[12] = counter
        var state = initial
        for 10 do
            for i in 16 do state[i] = (state[i] + 1) ^ 0x10203
        for i in 16 do values[offset + i] ^= state[i] + initial[i]
        offset  += 16
        counter += 1
    }
    return indexedSummary(seed, cast(u32, count))
}

#test
{
    var actual: [64] u32
    for i in 64 do actual[i] = cast(u32, (i * 0x10001 + 17))
    var expected = actual
    Swag.assert(indexedCopiedState(&actual[0], 64, 37) == 101)
    for block in 4
    {
        for lane in 16
        {
            let initial = lane == 12 ? cast(u32, (block + 1)) : 37 + cast(u32, lane)
            var state   = initial
            for 10 do state = (state + 1) ^ 0x10203
            expected[block * 16 + lane] ^= state + initial
        }
    }
    for i in 64 do Swag.assert(actual[i] == expected[i])
}
