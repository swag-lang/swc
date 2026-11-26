#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func ddsAddU32(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8, (value & 0xFF)))
    result.addNative(cast(u8, ((value >> 8) & 0xFF)))
    result.addNative(cast(u8, ((value >> 16) & 0xFF)))
    result.addNative(cast(u8, ((value >> 24) & 0xFF)))
}

func ddsBc1Fixture(height: u32 = 4)->ConcatBuffer
{
    var result: #returntype
    ddsAddU32(&result, 0x20534444)
    ddsAddU32(&result, 124)
    ddsAddU32(&result, 0x00081007)
    ddsAddU32(&result, height)
    ddsAddU32(&result, 4)
    ddsAddU32(&result, ((height + 3) / 4) * 8)
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
    if height > 4
    {
        ddsAddU32(&result, 0x0000001F)
        ddsAddU32(&result, 0)
    }

    return result
}

func ddsMaskedRgbaFixture(pixelFlags: u32, alpha: u8)->ConcatBuffer
{
    var result: #returntype
    ddsAddU32(&result, 0x20534444)
    ddsAddU32(&result, 124)
    ddsAddU32(&result, 0x0000100F)
    ddsAddU32(&result, 1)     // Height.
    ddsAddU32(&result, 1)     // Width.
    ddsAddU32(&result, 4)     // Pitch.
    ddsAddU32(&result, 0)     // Depth.
    ddsAddU32(&result, 0)     // Mip count.
    for 11 do
        ddsAddU32(&result, 0)
    ddsAddU32(&result, 32)     // Pixel format size.
    ddsAddU32(&result, pixelFlags)
    ddsAddU32(&result, 0)      // FourCC.
    ddsAddU32(&result, 32)     // Bits per pixel.
    ddsAddU32(&result, 0x000000FF)
    ddsAddU32(&result, 0x0000FF00)
    ddsAddU32(&result, 0x00FF0000)
    ddsAddU32(&result, 0xFF000000)
    ddsAddU32(&result, 0x1000)     // Texture caps.
    for 4 do
        ddsAddU32(&result, 0)
    result.addNative(10'u8)
    result.addNative(20'u8)
    result.addNative(30'u8)
    result.addNative(alpha)
    return result
}

func ddsRoundtrip(source: Image)->Image
{
    let encoded = expect source.encode("memory.dds")
    return expect Image.decode("roundtrip.dds", nnBytes(encoded.toSlice()))
}

// BC3 packs interpolated alpha over a full block and clips the neighboring partial block.
#test
{
    const Blocks: [32] u8 = [
        255, 0, 0x88, 0xC6, 0xFA, 0, 0, 0, 0, 0xF8, 0, 0xF8, 0, 0, 0, 0,
        0, 255, 6, 0x70, 0, 0, 0, 0, 0, 0xF8, 0, 0xF8, 0, 0, 0, 0]
    const ExpectedAlpha: [8] u8 = [255, 0, 218, 182, 145, 109, 72, 36]
    var image = Image.create(5, 2, .RGBA8)
    for topDown in [true, false]
    {
        expect TextureBlocks.decode(&image, Blocks, .BC3, topDown)
        for alpha, index in ExpectedAlpha
        {
            let y     = cast(s32, (index / 4))
            let pixel = image.pixelColor(cast(s32, (index % 4)), topDown ? y : 1 - y)
            Swag.require(pixel.r == 255 and pixel.g == 0 and pixel.b == 0 and pixel.a == alpha)
        }

        Swag.require(image.pixelColor(4, topDown ? 0 : 1).a == 0)
        Swag.require(image.pixelColor(4, topDown ? 1 : 0).a == 255)
    }
}

// The alpha mask is meaningful only when DDPF_ALPHAPIXELS is declared.
#test
{
    for hasAlpha in 2
    {
        let pixelFlags = 0x40'u32 | (hasAlpha ? 0x1'u32 : 0'u32)
        let bytes      = ddsMaskedRgbaFixture(pixelFlags, 0)
        let image      = expect Image.decode("alpha-flag.dds", nnBytes(bytes.toSlice()))
        assertImage(image, 1, 1, .RGBA8)
        Swag.require(image.pixels[0] == 10 and image.pixels[1] == 20 and image.pixels[2] == 30)
        Swag.require(image.pixels[3] == (hasAlpha ? 0'u8 : 255'u8))
    }
}

#test
{
    var rgba = Image.create(2, 2, .RGBA8)
    for i in rgba.byteCount do
        rgba.pixels.storage()[i] = cast(u8, (i * 13))
    let decoded = ddsRoundtrip(rgba)
    assertImage(decoded, 2, 2, .RGBA8)
    Swag.require(Memory.compare(rgba.pixels.storage(), decoded.pixels.storage(), rgba.byteCount) == 0)

    var grayAlpha = Image.create(3, 2, .GrayAlpha8)
    for i in grayAlpha.byteCount do
        grayAlpha.pixels.storage()[i] = cast(u8, (i * 17))
    let decodedGray = ddsRoundtrip(grayAlpha)
    assertImage(decodedGray, 3, 2, .GrayAlpha8)
    Swag.require(Memory.compare(grayAlpha.pixels.storage(), decodedGray.pixels.storage(), grayAlpha.byteCount) == 0)
}

#test
{
    var deep    = Image.create(2, 2, .RGBA16)
    let samples = cast([*] u16, deep.pixels.storage())
    for i in 16 do
        samples[i] = cast(u16, (i * 4001))
    let decoded = ddsRoundtrip(deep)
    assertImage(decoded, 2, 2, .RGBA16)
    Swag.require(Memory.compare(deep.pixels.storage(), decoded.pixels.storage(), deep.byteCount) == 0)

    var hdr    = Image.create(2, 1, .RGBAF32)
    let values = cast([*] f32, hdr.pixels.storage())
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
    Swag.require(Memory.compare(hdr.pixels.storage(), decodedHdr.pixels.storage(), hdr.byteCount) == 0)

    for format in [PixelFormat.Gray16, PixelFormat.GrayAlpha16, PixelFormat.GrayF16,
                   PixelFormat.GrayAlphaF16, PixelFormat.GrayF32, PixelFormat.GrayAlphaF32]
    {
        var gray = Image.create(3, 2, format)
        for i in gray.byteCount do
            gray.pixels.storage()[i] = cast(u8, ((i * 31 + 9) & 0xFF))
        let decodedGray = ddsRoundtrip(gray)
        assertImage(decodedGray, 3, 2, format)
        Swag.require(Memory.compare(gray.pixels.storage(), decodedGray.pixels.storage(), gray.byteCount) == 0)
    }
}

#test
{
    let bytes = ddsBc1Fixture()
    let image = expect Image.decode("block.dds", nnBytes(bytes.toSlice()))
    assertImage(image, 4, 4, .RGBA8)
    Swag.require(image.pixelColor(0, 0) == Color.fromRgb(255, 0, 0))
    Swag.require(image.pixelColor(1, 0) == Color.fromRgb(0, 255, 0))
    Swag.require(image.pixelColor(2, 0) == Color.fromRgb(170, 85, 0))
    Swag.require(image.pixelColor(3, 0) == Color.fromRgb(85, 170, 0))

    var options: DecodeOptions
    options.decodePixels = false
    let header = expect Image.decode("block.dds", nnBytes(bytes.toSlice()), options)
    Swag.require(header.width == 4 and
                 header.height == 4 and
                 header.pixelFormat == .RGBA8 and
                 not header.isValid())
}

// The final partial block row starts at its own position in the compressed level.
#test
{
    let bytes = ddsBc1Fixture(height: 5)
    let image = expect Image.decode("block-rows.dds", nnBytes(bytes.toSlice()))
    assertImage(image, 4, 5, .RGBA8)
    Swag.require(image.pixelColor(0, 3) == Color.fromRgb(255, 0, 0))
    Swag.require(image.pixelColor(0, 4) == Color.fromRgb(0, 0, 255))
}

#test
{
    const Invalid: [12] u8 = ['D', 'D', 'S', ' ', 0, 0, 0, 0, 0, 0, 0, 0]
    var errorOutcome: Swag.Error
    discard catch Image.decode("bad.dds", Invalid) as errorOutcome
    let error = errorOutcome.value()
    Swag.require(error != null)
}

// Padded BGR rows cover a vector group and an odd tail without reading
// row padding as pixels or borrowing the unused alpha mask.
#test
{
    const Width  = 9
    const Height = 2
    const Pitch  = 32
    const Header: [32] u32 = [
        0x20534444, 124, 0x100F, Height, Width, Pitch, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        32, 0x40, 0, 24, 0xFF0000, 0xFF00, 0xFF, 0,
        0x1000, 0, 0, 0, 0]
    var encoded: ConcatBuffer
    for field in Header do
        ddsAddU32(&encoded, field)

    for y in Height
    {
        for x in Width
        {
            encoded.addNative(cast(u8, x + 8))
            encoded.addNative(cast(u8, y + 20))
            encoded.addNative(cast(u8, x + y + 30))
        }

        for Pitch - 3 * Width do
            encoded.addNative(173'u8)
    }

    let image = expect Image.decode("padded-bgr.dds", nnBytes(encoded.toSlice()))
    assertImage(image, Width, Height, .RGBA8)
    for y in Height
    {
        for x in Width
        {
            let pixel = image.pixelColor(cast(s32, x), cast(s32, y))
            Swag.require(pixel.r == x + y + 30 and pixel.g == y + 20 and pixel.b == x + 8 and pixel.a == 255)
        }
    }
}
