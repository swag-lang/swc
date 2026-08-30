#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func ktx2Roundtrip(source: Image)->Image
{
    let encoded = expect source.encode("memory.ktx2")
    return expect Image.decode("roundtrip.ktx2", nnBytes(encoded.toSlice()))
}

#test
{
    const Formats: [18] PixelFormat = [.Gray8, .GrayAlpha8, .Gray16, .GrayAlpha16, .GrayF16, .GrayAlphaF16,
                                       .GrayF32, .GrayAlphaF32, .BGR8, .BGRA8, .RGB8, .RGBA8,
                                       .RGB16, .RGBA16, .RGBF16, .RGBAF16, .RGBF32, .RGBAF32]
    for format in Formats
    {
        var source = Image.create(5, 3, format)
        for i in source.byteCount do
            source.pixels.buffer![i] = cast(u8) ((i * 37 + 11) & 0xFF)
        let decoded = ktx2Roundtrip(source)
        assertImage(decoded, source.width, source.height, format)
        Swag.assert(Memory.compare(source.pixels.buffer, decoded.pixels.buffer, source.byteCount) == 0)
    }
}

// KTX2's standardized ZLIB supercompression is inflated before row reconstruction.
#test
{
    var source = Image.create(32, 32, .RGBA8)
    source.fill(Color.fromArgb(123, 17, 34, 51))
    var encoded = expect source.encode("plain.ktx2")
    encoded.makeLinear()
    var plain      = encoded.toSlice()!
    let dataOffset = (plain.buffer + 80)[as u64]
    let rawLength  = (plain.buffer + 96)[as u64]
    var zlib: Compress.ZLib
    let compressed = expect zlib.compress(plain[dataOffset until dataOffset + rawLength])

    plain[44] = 3
    (plain.buffer + 88)[as u64] = compressed.count
    var rebuilt: ConcatBuffer
    rebuilt.addBytes(plain[until dataOffset])
    rebuilt.addBytes(compressed.toSlice())

    let decoded = expect Image.decode("zlib.ktx2", nnBytes(rebuilt.toSlice()))
    assertImage(decoded, 32, 32, .RGBA8)
    Swag.assert(Memory.compare(source.pixels.buffer, decoded.pixels.buffer, source.byteCount) == 0)
}

#test
{
    var source = Image.create(3, 2, .RGB16)
    source.clear()
    let encoded = expect source.encode("probe.ktx2")
    var options: DecodeOptions
    options.decodePixels = false
    let header = expect Image.decode("probe.ktx2", nnBytes(encoded.toSlice()), options)
    Swag.assert(header.width == 3 and header.height == 2 and header.pixelFormat == .RGB16 and !header.isValid())

    const Invalid: [12] u8 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    discard catch Image.decode("bad.ktx2", Invalid) as error
    Swag.assert(error != null)
}
