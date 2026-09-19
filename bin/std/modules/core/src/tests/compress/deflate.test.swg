#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func fillRandom(buffer: [..] u8, seed: u32)
{
    var x = seed | 1
    for i in buffer.count
    {
        x         ^= x << 13
        x         ^= x >> 17
        x         ^= x << 5
        buffer[i] = cast(u8) (x & 0xFF)
    }
}

func fillText(buffer: [..] u8)
{
    const Words = "the quick brown fox jumps over the lazy dog while a swag compiler emits code "
    for i in buffer.count do
        buffer[i] = Words[(i * 7 + i / 97) % Words.count]
}

func roundTrip(input: const [..] u8, level: Compress.Deflate.CompressionLevel, strategy: Compress.Deflate.CompressionStrategy)->bool
{
    var deflater: Compress.Deflate
    deflater.init(level, strategy)
    var compressed: Array'u8
    expect deflater.compress(&compressed, input)

    var inflater: Compress.Inflate
    var decoded:  Array'u8
    expect inflater.decompress(&decoded, compressed.toSlice())
    return Slice.equals(decoded.toSlice(), input)
}

// Every level and strategy round-trips random, textual, and constant data whose sizes straddle
// the 258-byte match limit, the 32 KiB window, and the 64 KiB stored-block limit.
#test
{
    const Sizes = [1'u64, 2, 3, 257, 258, 259, 32767, 32768, 32769, 65535, 65536, 65537, 200003]
    var data: Array'u8
    data.resize(200003)

    for kind in 3
    {
        switch kind
        {
        case 0: fillRandom(data.toSlice(), 1234)
        case 1: fillText(data.toSlice())
        case 2: data.fill('z')
        }

        for size in Sizes
        {
            let input = data.toSlice()[until size]
            for level in [Compress.Deflate.CompressionLevel.NoCompression, .BestSpeed, .Default, .BestCompression, .UberCompression]
            {
                Swag.assert(roundTrip(input, level, .Default))
            }

            for strategy in [Compress.Deflate.CompressionStrategy.Filtered, .HuffmanOnly, .Rle, .Fixed]
            {
                Swag.assert(roundTrip(input, .Default, strategy))
            }
        }
    }
}

// One encoder and one decoder serve several streams in a row.
#test
{
    var a: [5000] u8
    var b: [70000] u8
    fillText(a)
    fillRandom(b, 99)

    var zlib: Compress.ZLib
    let ca = expect zlib.compress(a)
    let cb = expect zlib.compress(b, .BestCompression)
    let cc = expect zlib.compress(a, .BestSpeed)

    var reader: Compress.ZLib
    let da = expect reader.decompress(ca.toSlice())
    let db = expect reader.decompress(cb.toSlice())
    let dc = expect reader.decompress(cc.toSlice())
    Swag.assert(Slice.equals(da.toSlice(), a))
    Swag.assert(Slice.equals(db.toSlice(), b))
    Swag.assert(Slice.equals(dc.toSlice(), a))
}
