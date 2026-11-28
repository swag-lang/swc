#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Appending compressed data preserves input borrowed from the output allocation.
#test
{
    var bytes: Array!{u8}
    bytes.add("borrowed input survives output growth")
    let original = bytes
    let start    = bytes.count
    var deflater: Compress.Deflate
    deflater.init(.NoCompression)
    expect deflater.compress(&bytes, bytes.toSlice())

    var inflater: Compress.Inflate
    var decoded:  Array!{u8}
    expect inflater.decompress(&decoded, bytes[start to])
    Swag.require(Slice.equals(decoded.toSlice(), original.toSlice()))
}

func fillRandom(buffer: [..] u8, seed: u32)
{
    var x = seed | 1
    for i in buffer.count
    {
        x         ^= x << 13
        x         ^= x >> 17
        x         ^= x << 5
        buffer[i] = cast(u8, (x & 0xFF))
    }
}

func fillText(buffer: [..] u8)
{
    const Words = "the quick brown fox jumps over the lazy dog while a swag compiler emits code "
    for i in buffer.count
    {
        buffer[i] = Words[(i * 7 + i / 97) % Words.count]
    }
}

// A compressed input slice may outlive output growth across several block flushes.
#test
{
    var bytes: Array!{u8}
    bytes.resize(96 * 1024 + 31)
    fillRandom(bytes.toSlice(), 991)
    fillText(bytes.toSlice()[45000 until 51000])

    let original = bytes
    let end = bytes.count
    var deflater: Compress.Deflate
    deflater.init(.Default)
    expect deflater.compress(&bytes, bytes.toSlice()[7 until end - 3])
    Swag.require(Slice.equals(bytes.toSlice()[until end], original.toSlice()))

    var inflater: Compress.Inflate
    var decoded:  Array!{u8}
    expect inflater.decompress(&decoded, bytes.toSlice()[end to])
    Swag.require(Slice.equals(decoded.toSlice(), original.toSlice()[7 until end - 3]))
}

// A slice into spare capacity is still borrowed, even before the array counts it as output.
#test
{
    for level in [Compress.Deflate.CompressionLevel.NoCompression, .Default]
    {
        let size = level == .NoCompression ? 37_u64 : 80_u64 * 1024 + 17
        var original: Array!{u8}
        original.resize(size)
        fillRandom(original.toSlice(), 173)

        var output: Array!{u8}
        if level == .Default
        {
            output.add("prefix")
        }

        let start = output.count
        output.reserve(start + size)
        let capacity = output.capacity
        let source = output.storage() + start
        Memory.copy(source, original.storage(), size)

        var deflater: Compress.Deflate
        deflater.init(level)
        expect deflater.compress(&output, Swag.makeSlice(source, size))
        Swag.require(output.capacity > capacity)
        if start
        {
            Swag.require(Slice.equals(output.toSlice()[until start], "prefix"))
        }

        var inflater: Compress.Inflate
        var decoded: Array!{u8}
        expect inflater.decompress(&decoded, output.toSlice()[start to])
        Swag.require(Slice.equals(decoded.toSlice(), original.toSlice()))

        var checksum: Hash.Adler32
        checksum.update(original.toSlice())
        Swag.require(deflater.adler.value() == checksum.value())
    }
}

func roundTrip(input: const [..] u8, level: Compress.Deflate.CompressionLevel, strategy: Compress.Deflate.CompressionStrategy)->bool
{
    var deflater: Compress.Deflate
    deflater.init(level, strategy)
    var compressed: Array!{u8}
    expect deflater.compress(&compressed, input)

    var inflater: Compress.Inflate
    var decoded:  Array!{u8}
    expect inflater.decompress(&decoded, compressed.toSlice())
    return Slice.equals(decoded.toSlice(), input)
}

// Uniform runs cross the dictionary and stored position boundaries before
// ordinary match searches resume.
#test
{
    var data: Array!{u8}
    data.resize(80000)
    fillRandom(data.toSlice()[until 32644], 1337)
    fillRandom(data.toSlice()[66212 to], 17)
    for value in [0_u8, 219]
    {
        for index in 32644 until 66212
        {
            data[index] = value
        }
        for level in [Compress.Deflate.CompressionLevel.BestSpeed, .Default, .BestCompression]
        {
            Swag.require(roundTrip(data.toSlice(), level, .Default))
        }
    }
}

// Probe batches preserve candidate order and the search limit across dictionary wraps.
#test
{
    const RowBytes = 1025_u64
    const Rows     = 132
    var data: Array!{u8}
    data.resize(RowBytes * Rows)
    for row in Rows
    {
        let start = row * RowBytes
        data[start] = cast(u8, row % 5)
        if row % 5 == 0
        {
            fillRandom(data.toSlice()[start + 1 until start + RowBytes], cast(u32, row + 1))
        }
    }

    var deflater: Compress.Deflate
    deflater.init(.Default)
    var compressed: Array!{u8}
    expect deflater.compress(&compressed, data.toSlice())
    Swag.require(Hash.Crc64.compute(compressed.toSlice()) == 0x4FE2E238BFEA4C70)
}

// Every level and strategy round-trips random, textual, and constant data whose sizes straddle
// the match limit, the stored writer's block split, the 32 KiB window, and the 64 KiB format limit.
#test
{
    const Sizes = [1_u64, 2, 3, 257, 258, 259, 21838, 21839, 21840, 32767, 32768, 32769, 65535, 65536, 65537, 200003]
    var data: Array!{u8}
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
                Swag.require(roundTrip(input, level, .Default))
            }

            for strategy in [Compress.Deflate.CompressionStrategy.Filtered, .HuffmanOnly, .Rle, .Fixed]
            {
                Swag.require(roundTrip(input, .Default, strategy))
            }
        }
    }
}

// Reusing the match index preserves results across small streams and ring boundaries.
#test
{
    var data: Array!{u8}
    data.resize(66001)
    fillText(data.toSlice()[until 33000])
    fillRandom(data.toSlice()[33000 to], 479)

    var reused: Compress.Deflate
    for size in [66001_u64, 3, 32770, 37, 32771, 2048, 66000, 512, 0, 2049]
    {
        let source = data.toSlice()[data.count - size to]
        reused.init(.Default)
        var actual: Array!{u8}
        expect reused.compress(&actual, source)

        var fresh: Compress.Deflate
        fresh.init(.Default)
        var expected: Array!{u8}
        expect fresh.compress(&expected, source)
        Swag.require(Slice.equals(actual.toSlice(), expected.toSlice()))

        var inflater: Compress.Inflate
        var decoded: Array!{u8}
        expect inflater.decompress(&decoded, actual.toSlice())
        Swag.require(Slice.equals(decoded.toSlice(), source))
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
    Swag.require(Slice.equals(da.toSlice(), a))
    Swag.require(Slice.equals(db.toSlice(), b))
    Swag.require(Slice.equals(dc.toSlice(), a))
}

// Deflate.init resets a direct encoder for a new stream while preserving the
// already appended stream in the caller's result buffer.
#test
{
    let first:  [7] u8 = [1, 3, 5, 7, 9, 11, 13]
    let second: [9] u8 = [2, 4, 6, 8, 10, 12, 14, 16, 18]

    var deflater:   Compress.Deflate
    var compressed: Array!{u8}
    deflater.init(.NoCompression)
    expect deflater.compress(&compressed, first)
    let secondStart = compressed.count

    deflater.init(.BestCompression)
    expect deflater.compress(&compressed, second)

    var inflater:     Compress.Inflate
    var decodedFirst: Array!{u8}
    expect inflater.decompress(&decodedFirst, compressed.toSlice()[until secondStart])
    Swag.require(Slice.equals(decodedFirst.toSlice(), first))

    var decodedSecond: Array!{u8}
    expect inflater.decompress(&decodedSecond, compressed.toSlice()[secondStart to])
    Swag.require(Slice.equals(decodedSecond.toSlice(), second))
}
