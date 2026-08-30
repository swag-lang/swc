#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Round-trip through Deflate -> Inflate (with the zlib header + adler32 trailer).
// Exercises the bulk-refill fast path and the post-stream checksum read.
#test
{
    var original: [4000] u8
    for i in 4000 do
        original[i] = cast #bit (u8) (i * 7 + (i >> 2) + (i & 13))

    var zl:  Compress.ZLib
    let compressed   = expect zl.compress(original)
    var zl2: Compress.ZLib
    let decompressed = expect zl2.decompress(compressed.toSlice())
    Swag.assert(decompressed.count == 4000)

    var ok = true
    for i in 4000 do
        if decompressed[i] != original[i] do
            ok = false
    Swag.assert(ok)
}

// Match distances and lengths around the 8/16-byte copy boundaries round-trip
// through the exact Deflate producer consumed by Inflate.
#test
{
    var input: Array'u8
    for distance in 1 to 33
    {
        input.clear()
        for i in distance do
            input.add(cast(u8) ((i * 19 + distance) & 0xFF))
        for repeat in 300
        {
            discard repeat
            for i in distance do
                input.add(input[i])
        }

        roundTrip(input.toSlice(), .Default)
    }
}

func roundTrip(input: const [..] u8, level: Compress.Deflate.CompressionLevel)
{
    var zl: Compress.ZLib
    let compressed = expect zl.compress(input, level)

    var reader: Compress.ZLib
    let decoded = expect reader.decompress(compressed.toSlice())
    Swag.assert(decoded.count == input.count)
    for i in input.count do
        Swag.assert(decoded[i] == input[i])

    // Again with the decoded size known up front: that path pre-sizes the output,
    // so the block loop never grows it and takes different branches.
    var hinted: Compress.ZLib
    let sized = expect hinted.decompress(compressed.toSlice(), input.count)
    Swag.assert(sized.count == input.count)
    for i in input.count do
        Swag.assert(sized[i] == input[i])
}

// Every length in a window around the eight-byte step of the block loop, at every
// compression level. The bit cursor refills eight source bytes at a time and the
// block loop copies matches eight output bytes at a time, so a stream is only
// really exercised when its blocks stop at each of those offsets in turn.
#test
{
    var buffer: [80] u8
    for i in 80 do
        buffer[i] = cast #bit (u8) (i * 29 + (i >> 1))

    for n in 80
    {
        roundTrip(buffer[0 until n], .BestSpeed)
        roundTrip(buffer[0 until n], .Default)
        roundTrip(buffer[0 until n], .NoCompression)
    }
}

// Back-references of every distance class the block loop distinguishes: a run of
// one byte, the short distances it has to copy byte by byte, and the distances it
// copies in whole words, including matches that end right at the buffer.
#test
{
    for distance in 1 to 12
    {
        var buffer: Array'u8
        for i in 64 do
            buffer.add(cast #bit (u8) (i * 13))
        for i in 512 do
            buffer.add(buffer[buffer.count - distance])

        roundTrip(buffer.toSlice(), .BestSpeed)
        roundTrip(buffer.toSlice(), .BestCompression)
    }
}

// A payload that does not compress: the block loop then runs once per output byte
// and spends its time in the literal path, which is the shape a stored photograph
// produces. The counterpart is a payload that is one long match.
#test
{
    var noisy: Array'u8
    var seed = 0x2545F491'u32
    for i in 40000
    {
        seed ^= seed << #wrap 13
        seed ^= seed >> 17
        seed ^= seed << #wrap 5
        noisy.add(cast #bit (u8) seed)
    }

    roundTrip(noisy.toSlice(), .BestSpeed)
    roundTrip(noisy.toSlice(), .Default)

    var flat: Array'u8
    for i in 40000 do
        flat.add(0xA5)
    roundTrip(flat.toSlice(), .BestSpeed)
    roundTrip(flat.toSlice(), .BestCompression)
}
