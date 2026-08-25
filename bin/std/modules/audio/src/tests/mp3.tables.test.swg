#global if #command == Swag.CompilerCommand.Test

using Core

// Walks one code of a Huffman table through its decoding tree and returns the symbol it reaches.
//
// Returns minus one when the walk falls off the tree, which is what a code that is not in it, or
// a tree that does not hold it, produces.
private func mp3WalkTree(tree: const [..] s16, length: u32, code: u32)->s32
{
    var node = 0's32
    for index in length
    {
        let bit  = (code >> (length - 1 - index)) & 1
        let slot = cast(u64) (node * 2) + cast(u64) bit
        if slot >= @countof(tree) do
            return -1

        let next = tree[slot]
        if next < 0
        {
            // A leaf before the last bit means the code passes through another code.
            if index != length - 1 do
                return -1
            return cast(s32) (-next - 1)
        }

        node = cast(s32) next
    }

    return -1
}

// Requires the decoding tree of one table to hold exactly the codes the normative arrays state.
//
// The tables are written twice on purpose: `Len`/`Cod` is Table B.7 as the standard prints it, and
// `Tree` is what the decoder walks. This is what keeps the second from drifting from the first.
private func mp3AssertTable(name: string, lengths: const [..] u8, codes: const [..] u16, tree: const [..] s16)
{
    @assert(@countof(lengths) == @countof(codes))

    var kraft = 0.0'f64
    for symbol in @countof(lengths)
    {
        let length = cast(u32) lengths[symbol]
        @assert(length > 0 and length <= 19)
        kraft += Math.pow(0.5'f64, cast(f64) length)

        // The code must fit the length it states.
        @assert(cast(u32) codes[symbol] < (1'u32 << length))

        let reached = mp3WalkTree(tree, length, cast(u32) codes[symbol])
        if reached != cast(s32) symbol do
            @print("mp3 table ", name, ": symbol ", symbol, " decodes to ", reached, "\n")
        @assert(reached == cast(s32) symbol)
    }

    // A complete prefix code has a Kraft sum of exactly one. Below one leaves bit patterns that
    // decode to nothing; above one is impossible without two codes sharing a path.
    @assert(Math.abs(kraft - 1.0'f64) < 1e-9)

    // Every branch of the tree must lead somewhere: a slot pointing at itself or past the end
    // would make the decoder loop or read out of bounds.
    for slot in @countof(tree)
    {
        let value = tree[slot]
        if value >= 0 do
            @assert(cast(u64) value * 2 + 1 < @countof(tree) and cast(u64) value * 2 > slot)
        else do
            @assert(cast(u64) (-value - 1) < @countof(lengths))
    }
}

// Every big-value code table of Table B.7.
#test
{
    mp3AssertTable("1", Mp3.Huff1Len, Mp3.Huff1Cod, Mp3.Huff1Tree)
    mp3AssertTable("2", Mp3.Huff2Len, Mp3.Huff2Cod, Mp3.Huff2Tree)
    mp3AssertTable("3", Mp3.Huff3Len, Mp3.Huff3Cod, Mp3.Huff3Tree)
    mp3AssertTable("5", Mp3.Huff5Len, Mp3.Huff5Cod, Mp3.Huff5Tree)
    mp3AssertTable("6", Mp3.Huff6Len, Mp3.Huff6Cod, Mp3.Huff6Tree)
    mp3AssertTable("7", Mp3.Huff7Len, Mp3.Huff7Cod, Mp3.Huff7Tree)
    mp3AssertTable("8", Mp3.Huff8Len, Mp3.Huff8Cod, Mp3.Huff8Tree)
    mp3AssertTable("9", Mp3.Huff9Len, Mp3.Huff9Cod, Mp3.Huff9Tree)
    mp3AssertTable("10", Mp3.Huff10Len, Mp3.Huff10Cod, Mp3.Huff10Tree)
    mp3AssertTable("11", Mp3.Huff11Len, Mp3.Huff11Cod, Mp3.Huff11Tree)
    mp3AssertTable("12", Mp3.Huff12Len, Mp3.Huff12Cod, Mp3.Huff12Tree)
    mp3AssertTable("13", Mp3.Huff13Len, Mp3.Huff13Cod, Mp3.Huff13Tree)
    mp3AssertTable("15", Mp3.Huff15Len, Mp3.Huff15Cod, Mp3.Huff15Tree)
    mp3AssertTable("16", Mp3.Huff16Len, Mp3.Huff16Cod, Mp3.Huff16Tree)
    mp3AssertTable("24", Mp3.Huff24Len, Mp3.Huff24Cod, Mp3.Huff24Tree)
}

// The two quadruple tables. Table B is the fixed four-bit code whose value is the complement of
// its code word, which is what makes it worth stating rather than deriving.
#test
{
    mp3AssertTable("count1 A", Mp3.Count1ALen, Mp3.Count1ACod, Mp3.Count1ATree)
    mp3AssertTable("count1 B", Mp3.Count1BLen, Mp3.Count1BCod, Mp3.Count1BTree)

    for symbol in 16'u32
    {
        @assert(Mp3.Count1BLen[symbol] == 4)
        @assert(cast(u32) Mp3.Count1BCod[symbol] == 15 - symbol)
    }
}

// A `table_select` value picks a code table and a number of escape bits. Seventeen through
// twenty-three share the codes of sixteen and twenty-five through thirty-one those of
// twenty-four, so only the escape width tells them apart.
#test
{
    const Expected: [32] u8 = [0, 1, 2, 3, 0, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0, 15,
                               16, 16, 16, 16, 16, 16, 16, 16, 24, 24, 24, 24, 24, 24, 24, 24]
    const Escapes:  [32] u8 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                               1, 2, 3, 4, 6, 8, 10, 13, 4, 5, 6, 7, 8, 9, 11, 13]
    for index in 32'u64
    {
        @assert(Mp3.HuffCodeTable[index] == Expected[index])
        @assert(Mp3.HuffLinbits[index] == Escapes[index])
    }
}

// Every scalefactor band list covers the 576 lines of a granule, and closes with a zero.
#test
{
    for rate in 8'u64
    {
        var total = 0'u32
        for band in 22'u64 do
            total += cast(u32) Mp3.ScfBandLong[rate, band]
        @assert(total == 576)
        @assert(Mp3.ScfBandLong[rate, 22] == 0)

        total = 0
        for band in 39'u64 do
            total += cast(u32) Mp3.ScfBandShort[rate, band]
        @assert(total == 576)
        @assert(Mp3.ScfBandShort[rate, 39] == 0)
    }
}
