#global if #command == Swag.CompilerCommand.Test
#global private

using Core.Compress

const Sample = "abcabcabcabcabcabcabcabcabcabcabcabcabcabcabc12345"

// Blocks emitted by LZ4_compress_default and snappy_compress, respectively.
const Lz4Block:    [?] u8 = [63, 'a', 'b', 'c', 3, 0, 23, 80, '1', '2', '3', '4', '5']
const SnappyBlock: [?] u8 = [50, 8, 'a', 'b', 'c', 166, 3, 0, 16, '1', '2', '3', '4', '5']

#test
{
    let expected      = cast(const [..] u8, Sample)
    let lz4Decoded    = expect Lz4.decompress(Lz4Block, expected.count)
    let snappyDecoded = expect Snappy.decompress(SnappyBlock)
    Swag.require(Slice.equals(lz4Decoded.toSlice(), expected))
    Swag.require(Slice.equals(snappyDecoded.toSlice(), expected))

    var output: [Sample.count + 2] u8
    output[0] = 0xA5
    output[Sample.count + 1] = 0xA5
    expect Lz4.decompressInto(output[1 until Sample.count + 1], Lz4Block)
    Swag.require(Slice.equals(output[1 until Sample.count + 1], expected))
    let written = expect Snappy.decompressInto(output[1 to], SnappyBlock)
    Swag.require(written == expected.count and Slice.equals(output[1 until written + 1], expected))
    Swag.require(output[0] == 0xA5 and output[Sample.count + 1] == 0xA5)
}

#test
{
    // The short-sequence copies can write ahead within the destination slice.
    const Block: [?] u8 = [0xC4, 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 8, 0,
                           0xF0, 1, '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F']
    const Expected = "abcdefghijklefghijkl0123456789ABCDEF"
    var output: [Expected.count + 2] u8
    output[0] = 0xA5
    output[Expected.count + 1] = 0xA5
    let target = output[1 until Expected.count + 1]
    expect Lz4.decompressInto(target, Block)
    Swag.require(Slice.equals(target, cast(const [..] u8, Expected)))
    Swag.require(output[0] == 0xA5 and output[Expected.count + 1] == 0xA5)
}

#test
{
    // Literal lengths, varint widths, and window boundaries all use different encodings.
    const Sizes = [0_u64, 1, 4, 5, 12, 13, 15, 19, 59, 60, 61, 63, 64, 65, 127, 128, 255, 256, 270, 65535, 65536, 65537, 131137]
    var data: Array!{u8}
    data.resize(131137)

    var random = 117_u32
    for index in data.count
    {
        random      ^= random << 13
        random      ^= random >> 17
        random      ^= random << 5
        data[index] = Math.byteAt(random, 0)
    }

    for size in Sizes
    {
        checkRoundTrip(data.toSlice()[until size])
    }

    for distance in 1 to 17
    {
        for index in data.count
        {
            data[index] = cast(u8, index % distance)
        }
        checkRoundTrip(data.toSlice())
    }
}

func checkRoundTrip(input: const [..] u8)
{
    let lz4Packed  = expect Lz4.compress(input)
    let lz4Decoded = expect Lz4.decompress(lz4Packed.toSlice(), input.count)
    Swag.require(Slice.equals(lz4Decoded.toSlice(), input))

    let snappyPacked  = expect Snappy.compress(input)
    let snappyDecoded = expect Snappy.decompress(snappyPacked.toSlice(), input.count)
    Swag.require(Slice.equals(snappyDecoded.toSlice(), input))
}

#test
{
    // Legal Snappy blocks may carry both short and 32-bit copy offsets.
    const ShortCopy: [?] u8 = [5, 0, 'x', 1, 1]
    let shortDecoded = expect Snappy.decompress(ShortCopy)
    Swag.require(Slice.equals(shortDecoded.toSlice(), cast(const [..] u8, "xxxxx")))

    var large: Array!{u8}
    const Header: [?] u8 = [0x82, 0x80, 4, 0xF8, 0, 0, 1]
    large.add(Header)
    large.resize(Header.count + 65537)
    large[Header.count] = 'x'
    const LongCopy: [?] u8 = [3, 1, 0, 1, 0]
    large.add(LongCopy)
    let largeDecoded = expect Snappy.decompress(large.toSlice())
    Swag.require(largeDecoded.count == 65538 and largeDecoded[0] == 'x' and largeDecoded[65537] == 'x')
}

#test
{
    for size in Lz4Block.count
    {
        var error: Swag.Error
        discard catch Lz4.decompress(Lz4Block[until size], Sample.count) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }

    for size in SnappyBlock.count
    {
        var error: Swag.Error
        discard catch Snappy.decompress(SnappyBlock[until size]) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }

    const Lz4ZeroOffset:      [?] u8 = [0x18, 'a', 0, 0, 0x50, 0, 0, 0, 0, 0]
    const Lz4ShortTail:       [?] u8 = [0x18, 'a', 1, 0, 0x40, 0, 0, 0, 0]
    const SnappyZeroOffset:   [?] u8 = [5, 0, 'x', 1, 0]
    const SnappySizeOverflow: [?] u8 = [0x80, 0x80, 0x80, 0x80, 0x10]
    const SnappyExtraToken:   [?] u8 = [0, 0, 'x']

    var zeroLz4, shortTail, zeroSnappy, overflow, extraToken, limit: Swag.Error
    discard catch Lz4.decompress(Lz4ZeroOffset, 18) as zeroLz4
    discard catch Lz4.decompress(Lz4ShortTail, 17) as shortTail
    discard catch Snappy.decompress(SnappyZeroOffset) as zeroSnappy
    discard catch Snappy.decompress(SnappySizeOverflow) as overflow
    discard catch Snappy.decompress(SnappyExtraToken) as extraToken
    discard catch Snappy.decompress(SnappyBlock, maxOutputSize: Sample.count - 1) as limit
    for &error in [zeroLz4, shortTail, zeroSnappy, overflow, extraToken]
    {
        Swag.require(error.value() is Errors.InvalidFormatError)
    }
    Swag.require(limit.value() is Errors.UnsupportedFormatError)
}

#test
{
    var output: [64] u8
    var lz4Error, snappyError: Swag.Error
    catch Lz4.decompressInto(output[until Sample.count], output[1 to]) as lz4Error
    discard catch Snappy.decompressInto(output[until Sample.count], output[1 to]) as snappyError
    Swag.require(lz4Error.value() is Errors.BadParameterError)
    Swag.require(snappyError.value() is Errors.BadParameterError)
}
