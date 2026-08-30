#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func ddsAddU32(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8) (value & 0xFF))
    result.addNative(cast(u8) ((value >> 8) & 0xFF))
    result.addNative(cast(u8) ((value >> 16) & 0xFF))
    result.addNative(cast(u8) ((value >> 24) & 0xFF))
}

func ddsBc1Fixture()->ConcatBuffer
{
    var result: retval
    ddsAddU32(&result, 0x20534444)
    ddsAddU32(&result, 124)
    ddsAddU32(&result, 0x00081007)
    ddsAddU32(&result, 4)
    ddsAddU32(&result, 4)
    ddsAddU32(&result, 8)
    ddsAddU32(&result, 0)
    ddsAddU32(&result, 0)
    for 11 do
        ddsAddU32(&result, 0)
    ddsAddU32(&result, 32)
    ddsAddU32(&result, 4)
    ddsAddU32(&result, 0x31545844)
    for 5 do
        ddsAddU32(&result, 0)
    ddsAddU32(&result, 0x1000)
    for 4 do
        ddsAddU32(&result, 0)

    result.addNative(0x00'u8)
    result.addNative(0xF8'u8)
    result.addNative(0xE0'u8)
    result.addNative(0x07'u8)
    ddsAddU32(&result, 0xE4E4E4E4)
    return result
}

func ddsRoundtrip(source: Image)->Image
{
    let encoded = expect source.encode("memory.dds")
    return expect Image.decode("roundtrip.dds", nnBytes(encoded.toSlice()))
}

#test
{
    var rgba = Image.create(2, 2, .RGBA8)
    for i in rgba.byteCount do
        rgba.pixels.buffer![i] = cast(u8) (i * 13)
    let decoded = ddsRoundtrip(rgba)
    assertImage(decoded, 2, 2, .RGBA8)
    Swag.assert(Memory.compare(rgba.pixels.buffer, decoded.pixels.buffer, rgba.byteCount) == 0)

    var grayAlpha = Image.create(3, 2, .GrayAlpha8)
    for i in grayAlpha.byteCount do
        grayAlpha.pixels.buffer![i] = cast(u8) (i * 17)
    let decodedGray = ddsRoundtrip(grayAlpha)
    assertImage(decodedGray, 3, 2, .GrayAlpha8)
    Swag.assert(Memory.compare(grayAlpha.pixels.buffer, decodedGray.pixels.buffer, grayAlpha.byteCount) == 0)
}

#test
{
    var deep    = Image.create(2, 2, .RGBA16)
    let samples = cast([*] u16) deep.pixels.buffer!
    for i in 16 do
        samples[i] = cast(u16) (i * 4001)
    let decoded = ddsRoundtrip(deep)
    assertImage(decoded, 2, 2, .RGBA16)
    Swag.assert(Memory.compare(deep.pixels.buffer, decoded.pixels.buffer, deep.byteCount) == 0)

    var hdr    = Image.create(2, 1, .RGBAF32)
    let values = cast([*] f32) hdr.pixels.buffer!
    values[0] = -0.25
    values[1] = 0.5
    values[2] = 4.0
    values[3] = 1.0
    values[4] = 100.0
    values[5] = -2.0
    values[6] = 0.0
    values[7] = 0.75
    let decodedHdr = ddsRoundtrip(hdr)
    assertImage(decodedHdr, 2, 1, .RGBAF32)
    Swag.assert(Memory.compare(hdr.pixels.buffer, decodedHdr.pixels.buffer, hdr.byteCount) == 0)

    for format in [PixelFormat.Gray16, PixelFormat.GrayAlpha16, PixelFormat.GrayF16,
                   PixelFormat.GrayAlphaF16, PixelFormat.GrayF32, PixelFormat.GrayAlphaF32]
    {
        var gray = Image.create(3, 2, format)
        for i in gray.byteCount do
            gray.pixels.buffer![i] = cast(u8) ((i * 31 + 9) & 0xFF)
        let decodedGray = ddsRoundtrip(gray)
        assertImage(decodedGray, 3, 2, format)
        Swag.assert(Memory.compare(gray.pixels.buffer, decodedGray.pixels.buffer, gray.byteCount) == 0)
    }
}

#test
{
    let bytes = ddsBc1Fixture()
    let image = expect Image.decode("block.dds", nnBytes(bytes.toSlice()))
    assertImage(image, 4, 4, .RGBA8)
    Swag.assert(image.pixelColor(0, 0) == Color.fromRgb(255, 0, 0))
    Swag.assert(image.pixelColor(1, 0) == Color.fromRgb(0, 255, 0))
    Swag.assert(image.pixelColor(2, 0) == Color.fromRgb(170, 85, 0))
    Swag.assert(image.pixelColor(3, 0) == Color.fromRgb(85, 170, 0))

    var options: DecodeOptions
    options.decodePixels = false
    let header = expect Image.decode("block.dds", nnBytes(bytes.toSlice()), options)
    Swag.assert(header.width == 4 and header.height == 4 and header.pixelFormat == .RGBA8 and !header.isValid())
}

#test
{
    const Invalid: [12] u8 = ['D', 'D', 'S', ' ', 0, 0, 0, 0, 0, 0, 0, 0]
    discard catch Image.decode("bad.dds", Invalid) as error
    Swag.assert(error != null)
}
