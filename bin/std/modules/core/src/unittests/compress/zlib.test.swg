#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func fillCompressPattern(buffer: [..] u8)
{
    for [i] in @countof(buffer)
    {
        let repeated = (i / 17) & 0xFF
        buffer[i] = cast(u8) ((i * 31 + repeated + (i >> 3)) & 0xFF)
    }
}

func assertBytesEqual(actual: const [..] u8, expected: const [..] u8)->bool
{
    if @countof(actual) != @countof(expected) do
        return false

    for @countof(actual)
    {
        if actual[@index] != expected[@index] do
            return false
    }

    return true
}

func assertZLibRoundTrip(input: const [..] u8, level: Compress.Deflate.CompressionLevel)
{
    var zlib: Compress.ZLib
    let compressed = expect zlib.compress(input, level)
    @assert(compressed.count >= 6)
    @assert(compressed[0] == 0x78)
    @assert(compressed[1] == 0x9C)

    var reader: Compress.ZLib
    let decoded = expect reader.decompress(compressed.toSlice(), @countof(input))
    @assert(assertBytesEqual(decoded.toSlice(), input))
}

func assertDeflateRoundTrip(input: const [..] u8, level: Compress.Deflate.CompressionLevel, strategy: Compress.Deflate.CompressionStrategy)
{
    var deflater: Compress.Deflate
    deflater.init(level, strategy)

    var compressed: Array'u8
    expect deflater.compress(&compressed, input)
    @assert(compressed.count != 0)

    var inflater: Compress.Inflate
    var decoded:  Array'u8
    expect inflater.decompress(&decoded, compressed.toSlice())
    @assert(assertBytesEqual(decoded.toSlice(), input))
}

#test
{
    var empty:     Array'u8
    let small:     [13] u8 = [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144]
    var patterned: [4097] u8
    fillCompressPattern(patterned)

    assertZLibRoundTrip(empty.toSlice(), .NoCompression)
    assertZLibRoundTrip(small, .BestSpeed)
    assertZLibRoundTrip(patterned, .Default)
    assertZLibRoundTrip(patterned, .BestCompression)
}

#test
{
    var repeated: [2048] u8
    for [i] in @countof(repeated) do
        repeated[i] = cast(u8) ((i / 8) & 7)

    assertDeflateRoundTrip(repeated, .NoCompression, .Default)
    assertDeflateRoundTrip(repeated, .BestSpeed, .Fixed)
    assertDeflateRoundTrip(repeated, .Default, .HuffmanOnly)
    assertDeflateRoundTrip(repeated, .BestCompression, .Rle)
}

#test
{
    let tooSmall: [5] u8 = [0x78, 0x9C, 0, 0, 0]
    var reader:   Compress.ZLib
    let tooSmallResult   = catch reader.decompress(tooSmall) as errA
    @assert(tooSmallResult.count == 0)
    @assert(errA is Errors.InvalidFormatError)

    let badMethod:       [6] u8 = [0x79, 0x9C, 0, 0, 0, 0]
    var badMethodReader: Compress.ZLib
    let badMethodResult         = catch badMethodReader.decompress(badMethod) as errB
    @assert(badMethodResult.count == 0)
    @assert(errB is Errors.InvalidFormatError)

    let dictionary:       [6] u8 = [0x78, 0x20, 0, 0, 0, 0]
    var dictionaryReader: Compress.ZLib
    let dictionaryResult         = catch dictionaryReader.decompress(dictionary) as errC
    @assert(dictionaryResult.count == 0)
    @assert(errC is Errors.UnsupportedFormatError)
}

#test
{
    var input: [257] u8
    fillCompressPattern(input)

    var zlib: Compress.ZLib
    var compressed = expect zlib.compress(input)
    @assert(compressed.count > 6)

    compressed[compressed.count - 1] ^= 0x5A

    var reader: Compress.ZLib
    let decoded = catch reader.decompress(compressed.toSlice()) as err6
    @assert(decoded.count == 0)
    @assert(err6 is Errors.InvalidFormatError)
}
