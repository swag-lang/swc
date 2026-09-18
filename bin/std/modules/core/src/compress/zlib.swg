#global public
#global namespace Compress

using Core.Errors

// Compresses and decompresses zlib streams (RFC 1950).
//
// A zlib stream is Deflate data framed by a two-byte header and a big-endian Adler-32
// checksum of the uncompressed bytes. One `ZLib` keeps a [[Core.Compress.Deflate]] and an
// [[Core.Compress.Inflate]] and reuses them across calls.
//
// ```swag
// var zlib: Compress.ZLib
// let packed   = try zlib.compress(cast(const [..] u8) "hello, hello, hello")
// let unpacked = try zlib.decompress(packed.toSlice())
// ```
#[Swag.Opaque]
struct ZLib
{
    private
    {
        decoder: Inflate     // Decompressor used by 'decompress'.
        encoder: Deflate     // Compressor used by 'compress'.
    }
}

impl ZLib
{
    // Compresses `buffer` into a new zlib stream.
    //
    // The header always announces the default level, whatever `level` is; decoders ignore it.
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

    // Decompresses the zlib stream in `buffer` and returns its content.
    //
    // A non-zero `hintSize` reserves that many output bytes up front, which avoids reallocations
    // when the uncompressed size is known. Fails with [[Core.Errors.InvalidFormatError]] for a
    // malformed stream or a checksum mismatch, and with [[Core.Errors.UnsupportedFormatError]]
    // for a preset dictionary or a window larger than 32 KiB.
    mtd decompress(buffer: const [..] u8, hintSize: u64 = 0)->Array'u8 fail
    {
        var bs = ByteStream.openRead(buffer)
        if bs.length() < 6 do
            fail InvalidFormatError{"invalid format"}

        // CMF: the compression method (8 is Deflate) and the base-2 logarithm of the window size.
        let cmf = bs.readU8()
        if cmf & 0xF != 8 do
            fail InvalidFormatError{"invalid compression method"}

        let cinfo = (cmf >> 4) & 0xF
        if cinfo > 7 do
            fail UnsupportedFormatError{"unsupported window size"}
        let winSize = 1'u32 << (cinfo + 8)

        // FLG: the header check bits, the preset dictionary flag, and the informative level.
        let flg   = bs.readU8()
        let fdict = (flg >> 5) & 1
        if fdict do
            fail UnsupportedFormatError{"unsupported dictionary"}

        var result: retval
        if hintSize do
            result.grow(hintSize)
        try .decoder.decompress(&result, bs.remainingBytes(), winSize)

        // The Adler-32 trailer follows the Deflate data at the next byte boundary.
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
