#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func psdAddU16(result: *ConcatBuffer, value: u16)
{
    result.addNative(cast(u8, ((value >> 8) & 0xFF)))
    result.addNative(cast(u8, (value & 0xFF)))
}

func psdAddU32(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8, ((value >> 24) & 0xFF)))
    result.addNative(cast(u8, ((value >> 16) & 0xFF)))
    result.addNative(cast(u8, ((value >> 8) & 0xFF)))
    result.addNative(cast(u8, (value & 0xFF)))
}

func psdHeader(channels: u16, width, height: u32, depth, colorMode: u16)->ConcatBuffer
{
    var result: #returntype
    result.addBytes("8BPS")
    psdAddU16(&result, 1)
    for 6 do
        result.addNative(0'u8)
    psdAddU16(&result, channels)
    psdAddU32(&result, height)
    psdAddU32(&result, width)
    psdAddU16(&result, depth)
    psdAddU16(&result, colorMode)
    for 3 do
        psdAddU32(&result, 0)
    return result
}

#test
{
    var bytes = psdHeader(3, 2, 2, 8, 3)
    psdAddU16(&bytes, 0)
    const Planes: [12] u8 = [1, 2, 3, 4, 10, 20, 30, 40, 100, 110, 120, 130]
    bytes.addBytes(Planes)

    let image = expect Image.decode("raw.psd", nnBytes(bytes.toSlice()))
    assertImage(image, 2, 2, .RGB8)
    Swag.require(image.pixelColor(0, 0) == Color.fromRgb(1, 10, 100))
    Swag.require(image.pixelColor(1, 1) == Color.fromRgb(4, 40, 130))
}

#test
{
    var bytes = psdHeader(2, 3, 1, 8, 1)
    psdAddU16(&bytes, 1)
    psdAddU16(&bytes, 4)
    psdAddU16(&bytes, 4)
    const Rows: [8] u8 = [2, 10, 20, 30, 2, 40, 50, 60]
    bytes.addBytes(Rows)

    let image = expect Image.decode("packbits.psd", nnBytes(bytes.toSlice()))
    assertImage(image, 3, 1, .GrayAlpha8)
    Swag.require(image.pixelColor(0, 0) == Color.fromArgb(40, 10, 10, 10))
    Swag.require(image.pixelColor(2, 0) == Color.fromArgb(60, 30, 30, 30))
}

// Raw RGB and RGBA planes preserve channel order through packed blocks and the row tail.
#test
{
    for channels in [3'u16, 4'u16]
    {
        var bytes = psdHeader(channels, 33, 2, 8, 3)
        psdAddU16(&bytes, 0)
        for channel in channels do
            for index in 66 do
                bytes.addNative(cast(u8, (channel * 45 + index)))

        let image = expect Image.decode("raw-odd-width.psd", nnBytes(bytes.toSlice()))
        assertImage(image, 33, 2, channels == 3 ? .RGB8 : .RGBA8)
        for y in 2 do
            for x in 33
            {
                let sample = cast(u8, (y * 33 + x))
                assertPixel(image,
                            x,
                            y,
                            Color.fromArgb(channels == 3 ? 255'u8 : sample + 135,
                                           sample,
                                           sample + 45,
                                           sample + 90))
            }
    }
}

// A raw RGB composite uses its fourth plane for alpha and still validates extra planes.
#test
{
    var bytes = psdHeader(5, 1, 2, 8, 3)
    psdAddU16(&bytes, 0)
    const Planes: [10] u8 = [1, 2, 10, 20, 30, 40, 50, 60, 90, 100]
    bytes.addBytes(Planes)

    let source = nnBytes(bytes.toSlice())
    let image  = expect Image.decode("raw-extra.psd", source)
    assertImage(image, 1, 2, .RGBA8)
    Swag.require(image.pixelColor(0, 0) == Color.fromArgb(50, 1, 10, 30))
    Swag.require(image.pixelColor(0, 1) == Color.fromArgb(60, 2, 20, 40))

    var outcome: Swag.Error
    discard catch Image.decode("truncated-extra.psd", source[until source.count - 1]) as outcome
    Swag.require(outcome.value() != null)
}

// Raw 16-bit color and alpha preserve both sample bytes through a SIMD block and its tail.
#test
{
    for channels in [2'u16, 3'u16, 4'u16]
    {
        let format = channels == 2 ? PixelFormat.GrayAlpha16 : (channels == 3 ? PixelFormat.RGB16 : PixelFormat.RGBA16)
        var bytes  = psdHeader(channels, 11, 2, 16, channels == 2 ? 1 : 3)
        psdAddU16(&bytes, 0)
        for channel in channels do
            for index in 22 do
                psdAddU16(&bytes, cast(u16, (0x1234 + channel * 4099 + index * 257)))

        let image = expect Image.decode("raw-words-odd-width.psd", nnBytes(bytes.toSlice()))
        assertImage(image, 11, 2, format)
        let words = cast(const [*] u16, image.pixels.storage())
        for y in 2 do
            for x in 11 do
                for channel in channels do
                    Swag.require(words[((1 - y) * 11 + x) * channels + channel] == 0x1234 + channel * 4099 + (y * 11 + x) * 257)
    }
}

// Sixteen-bit gray rows keep both sample bytes and the last partial vector.
#test
{
    var bytes = psdHeader(1, 11, 2, 16, 1)
    psdAddU16(&bytes, 0)
    for index in 22 do
        psdAddU16(&bytes, cast(u16, (0x1234 + index * 257)))

    let image = expect Image.decode("gray-odd-width.psd", nnBytes(bytes.toSlice()))
    assertImage(image, 11, 2, .Gray16)
    let words = cast(const [*] u16, image.pixels.storage())
    for y in 2 do
        for x in 11 do
            Swag.require(words[(1 - y) * 11 + x] == 0x1234 + (y * 11 + x) * 257)
}

#test
{
    var bytes = psdHeader(4, 1, 1, 16, 3)
    psdAddU16(&bytes, 0)
    psdAddU16(&bytes, 0x1234)
    psdAddU16(&bytes, 0x5678)
    psdAddU16(&bytes, 0x9ABC)
    psdAddU16(&bytes, 0xDEF0)

    let image = expect Image.decode("deep.psd", nnBytes(bytes.toSlice()))
    assertImage(image, 1, 1, .RGBA16)
    let raw = cast(const [*] u16, image.pixels.storage())
    Swag.require(raw[0] == 0x1234 and raw[1] == 0x5678 and raw[2] == 0x9ABC and raw[3] == 0xDEF0)

    var options: DecodeOptions
    options.decodePixels = false
    let metadataOnly = expect Image.decode("deep.psd", nnBytes(bytes.toSlice()), options)
    Swag.require(metadataOnly.width == 1 and metadataOnly.height == 1 and metadataOnly.pixelFormat == .RGBA16)
    Swag.require(not metadataOnly.isValid())
}

#test
{
    var bytes = psdHeader(4, 600_000_000, 1, 8, 3)
    var options: DecodeOptions
    options.maxPixels       = 0
    options.maxDecodedBytes = 0
    options.decodePixels    = false

    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("wide-row.psd", nnBytes(bytes.toSlice()), options) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

#test
{
    var bytes = psdHeader(2, 1, 1, 16, 1)
    psdAddU16(&bytes, 0)
    psdAddU16(&bytes, 0x2468)
    psdAddU16(&bytes, 0xBEEF)
    let image = expect Image.decode("gray16.psd", nnBytes(bytes.toSlice()))
    assertImage(image, 1, 1, .GrayAlpha16)
    let raw = cast(const [*] u16, image.pixels.storage())
    Swag.require(raw[0] == 0x2468 and raw[1] == 0xBEEF)
}

#test
{
    const Invalid: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    var shortOutcome: Swag.Error
    discard catch Image.decode("bad.psd", Invalid) as shortOutcome
    let short = shortOutcome.value()
    Swag.require(short != null)

    var unsupported = psdHeader(4, 1, 1, 8, 4)
    var cmykOutcome: Swag.Error
    discard catch Image.decode("cmyk.psd", nnBytes(unsupported.toSlice())) as cmykOutcome
    let cmyk = cmykOutcome.value()
    Swag.require((cmyk is UnsupportedFormatError))
}
