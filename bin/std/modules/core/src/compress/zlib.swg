#global public
#global namespace Compress

using Core.Errors

// Represents z lib.
#[Swag.Opaque]
struct ZLib
{
    // One codec of each direction, reused across calls.

    private
    {
        decoder: Inflate     // Decompressor used by 'decompress'.
        encoder: Deflate     // Compressor used by 'compress'.
    }
}

impl ZLib
{
    // Decompress stream
    mtd compress(buffer: const [..] u8, level = Deflate.CompressionLevel.Default)->Array'u8 fail
    {
        var result: retval

        result.add(0x78)
        result.add(0x9C)

        .encoder.init(level)
        try .encoder.compress(&result, buffer)

        let checksum = .encoder.adler.value()
        result.add(cast(u8) ((checksum >> 24) & 0xFF))
        result.add(cast(u8) ((checksum >> 16) & 0xFF))
        result.add(cast(u8) ((checksum >> 8) & 0xFF))
        result.add(cast(u8) (checksum & 0xFF))

        return result
    }

    // Decompress stream. hintSize pre-reserves the output buffer to avoid realloc churn.
    mtd decompress(buffer: const [..] u8, hintSize: u64 = 0)->Array'u8 fail
    {
        var bs = ByteStream.openRead(buffer)
        if bs.length() < 6 do
            fail InvalidFormatError{"invalid format"}

        // Compression mtd (8 is "deflate")
        let cmf = bs.readU8()
        if cmf & 0xF != 8 do
            fail InvalidFormatError{"invalid compression mtd"}

        // Window size
        let cinfo = (cmf >> 4) & 0xF
        if cinfo > 7 do
            fail UnsupportedFormatError{"unsupported window size"}
        let winSize = 1'u32 << (cinfo + 8)

        // Check
        let flg = bs.readU8()

        // Dict
        let fdict = (flg >> 5) & 1
        if fdict do
            fail UnsupportedFormatError{"unsupported dictionnary"}

        // Compression level
        // var flevel = (flg >> 6) & 3

        var result: Array'u8
        if hintSize do
            result.grow(hintSize)
        try .decoder.decompress(&result, bs.remainingBytes()!, winSize)

        // Now we should have the checksum
        .decoder.stream.discardToNextByte()
        let adler32 = .decoder.stream.readBits(8) << 24 |
                      .decoder.stream.readBits(8) << 16 |
                      .decoder.stream.readBits(8) << 8 |
                      .decoder.stream.readBits(8)
        if adler32 != .decoder.adler.value() do
            fail InvalidFormatError{"invalid checksum"}

        return result
    }
}
