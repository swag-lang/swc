#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func psdAddU16(result: *ConcatBuffer, value: u16)
{
    result.addNative(cast(u8) ((value >> 8) & 0xFF))
    result.addNative(cast(u8) (value & 0xFF))
}

func psdAddU32(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8) ((value >> 24) & 0xFF))
    result.addNative(cast(u8) ((value >> 16) & 0xFF))
    result.addNative(cast(u8) ((value >> 8) & 0xFF))
    result.addNative(cast(u8) (value & 0xFF))
}

func psdHeader(channels: u16, width, height: u32, depth, colorMode: u16)->ConcatBuffer
{
    var result: retval
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
    Swag.assert(image.pixelColor(0, 0) == Color.fromRgb(1, 10, 100))
    Swag.assert(image.pixelColor(1, 1) == Color.fromRgb(4, 40, 130))
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
    Swag.assert(image.pixelColor(0, 0) == Color.fromArgb(40, 10, 10, 10))
    Swag.assert(image.pixelColor(2, 0) == Color.fromArgb(60, 30, 30, 30))
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
    let raw = cast(const [*] u16) image.pixels.buffer!
    Swag.assert(raw[0] == 0x1234 and raw[1] == 0x5678 and raw[2] == 0x9ABC and raw[3] == 0xDEF0)

    var options: DecodeOptions
    options.decodePixels = false
    let metadataOnly = expect Image.decode("deep.psd", nnBytes(bytes.toSlice()), options)
    Swag.assert(metadataOnly.width == 1 and metadataOnly.height == 1 and metadataOnly.pixelFormat == .RGBA16)
    Swag.assert(!metadataOnly.isValid())
}

#test
{
    var bytes = psdHeader(2, 1, 1, 16, 1)
    psdAddU16(&bytes, 0)
    psdAddU16(&bytes, 0x2468)
    psdAddU16(&bytes, 0xBEEF)
    let image = expect Image.decode("gray16.psd", nnBytes(bytes.toSlice()))
    assertImage(image, 1, 1, .GrayAlpha16)
    let raw = cast(const [*] u16) image.pixels.buffer!
    Swag.assert(raw[0] == 0x2468 and raw[1] == 0xBEEF)
}

#test
{
    const Invalid: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    discard catch Image.decode("bad.psd", Invalid) as short
    Swag.assert(short != null)

    var unsupported = psdHeader(4, 1, 1, 8, 4)
    discard catch Image.decode("cmyk.psd", nnBytes(unsupported.toSlice())) as cmyk
    Swag.assert(cmyk is UnsupportedFormatError)
}
