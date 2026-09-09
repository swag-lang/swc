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

// An output limit is enforced while decoding, including within a repeated match, so callers can
// reject expansion bombs before the destination grows beyond their policy.
#test
{
    var original: [4096] u8
    for &value in original do
        value[] = 0xA5

    var deflater: Compress.Deflate
    deflater.init(.BestCompression, flags: .Zero)
    var compressed: Array'u8
    expect deflater.compress(&compressed, original)

    var inflater: Compress.Inflate
    var decoded:  Array'u8
    catch inflater.decompress(&decoded, compressed.toSlice(), maxOutputSize: 128) as limitError
    Swag.assert(limitError is Errors.UnsupportedFormatError)
    Swag.assert(decoded.count <= 128)
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

func nextSeed(seed: *u32)->u32
{
    var value = seed[]
    value  ^= value << #wrap 13
    value  ^= value >> 17
    value  ^= value << #wrap 5
    seed[] = value
    return value
}

// Six hundred thousand bytes decoded without a size hint, so the destination grows repeatedly,
// and dominated by matches at the far end of the window with a length short enough to keep the
// extra bits of both codes. The existing round trips stop at forty thousand bytes and near
// distances, so nothing else here exercises a wide symbol group against a growing destination.
#test
{
    const Block  = 30_000'u64
    const Copies = 20'u64

    var seed = 0x12345678'u32
    var payload: Array'u8
    payload.reserve(Block * Copies)
    for index in Block do
        payload.add(cast #bit (u8) nextSeed(&seed))

    for copy in 1 until Copies
    {
        for index in Block
        {
            // A literal every two hundred bytes keeps each match well short of the longest one,
            // so its length code still carries extra bits.
            if index % 200 == 199 do
                payload.add(cast #bit (u8) nextSeed(&seed))
            else do
                payload.add(payload[index])
        }

        // One short back-reference per copy, of a length nothing else in the stream uses. Against
        // a hundred thousand matches of the same length, its code reaches the longest the format
        // allows, past the twelve bits the decoder's fast table covers, so the fast loop has to
        // hand this match to the careful path.
        let rare = 3 + copy % 6
        let from = payload.count - 4000
        for byte in rare do
            payload.add(payload[from + byte])
    }

    var writer: Compress.ZLib
    let compressed = expect writer.compress(payload.toSlice())

    var reader: Compress.ZLib
    let decoded = expect reader.decompress(compressed.toSlice())
    Swag.assert(decoded.count == payload.count)

    var ok = true
    for index in payload.count where decoded[index] != payload[index] do
        ok = false
    Swag.assert(ok)
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
