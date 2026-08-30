#global if #command == Swag.CompilerCommand.Test

using Swag, Core

const PackedFormats: [18] PixelFormat = [
    .Gray8, .GrayAlpha8, .Gray16, .GrayAlpha16, .GrayF16, .GrayAlphaF16, .GrayF32, .GrayAlphaF32,
    .BGR8, .BGRA8, .RGB8, .RGBA8, .RGB16, .RGBA16, .RGBF16, .RGBAF16, .RGBF32, .RGBAF32]

// ImageFormat.matches compares the extension only, case-insensitively, and a format
// declaring several spellings claims every one of them.
#test
{
    let png = ImageFormat{"PNG", ".png"}
    Swag.assert(png.matches("capture.png"))
    Swag.assert(png.matches("C:/a folder/CAPTURE.PNG"))
    Swag.assert(!png.matches("capture.jpg"))
    Swag.assert(!png.matches("png"))
    Swag.assert(!png.matches("capture"))
    Swag.assert(!png.matches(""))

    let jpeg = ImageFormat{"JPEG", ".jpg;.jpeg"}
    Swag.assert(jpeg.matches("photo.jpg"))
    Swag.assert(jpeg.matches("photo.jpeg"))
    Swag.assert(!jpeg.matches("photo.jpe"))
}

// Every packed format publishes exact storage geometry and alpha/sample traits.
#test
{
    Swag.assert(cast(u8) PixelFormat.BGR8 == 0 and cast(u8) PixelFormat.BGRA8 == 1)
    Swag.assert(cast(u8) PixelFormat.RGB8 == 2 and cast(u8) PixelFormat.RGBA8 == 3)
    Swag.assert(cast(u8) PixelFormat.Yuv420 == 4)

    const Bits:     [18] u8   = [8, 16, 16, 32, 16, 32, 32, 64, 24, 32, 24, 32, 48, 64, 48, 64, 96, 128]
    const Channels: [18] u8   = [1, 2, 1, 2, 1, 2, 1, 2, 3, 4, 3, 4, 3, 4, 3, 4, 3, 4]
    const Alpha:    [18] bool = [false, true, false, true, false, true, false, true, false, true, false, true, false, true, false, true, false, true]
    for format, index in PackedFormats
    {
        Swag.assert(format.isPacked())
        Swag.assert(format.bitsPerPixel() == Bits[index])
        Swag.assert(format.channels() == Channels[index])
        Swag.assert(format.hasAlpha() == Alpha[index])
    }

    Swag.assert(!PixelFormat.Yuv420.isPacked())
}

// Conversion preserves logical 8-bit colors through integer, half, full-float, and grayscale storage.
#test
{
    var source = Image.create(2, 1, .RGBA8)
    let pixels = source.pixels.buffer!
    pixels[0] = 12
    pixels[1] = 91
    pixels[2] = 203
    pixels[3] = 77
    pixels[4] = 240
    pixels[5] = 33
    pixels[6] = 8
    pixels[7] = 255

    for format in [PixelFormat.RGB16, PixelFormat.RGBA16, PixelFormat.RGBF16, PixelFormat.RGBAF16, PixelFormat.RGBF32, PixelFormat.RGBAF32]
    {
        let converted = source.convertedTo(format)
        let restored  = converted.convertedTo(.RGBA8)
        for x in 2
        {
            let expected = source.pixelColor(x, 0)
            let actual   = restored.pixelColor(x, 0)
            Swag.assert(actual.r == expected.r and actual.g == expected.g and actual.b == expected.b)
            Swag.assert(actual.a == (format.hasAlpha() ? expected.a : 255))
        }
    }

    let gray = source.convertedTo(.GrayAlpha8)
    Swag.assert(gray.pixelFormat == .GrayAlpha8 and gray.bytesPerPixel == 2)
    Swag.assert(gray.pixelColor(0, 0).a == 77)
    Swag.assert(gray.pixelColor(0, 0).r == gray.pixelColor(0, 0).g and gray.pixelColor(0, 0).g == gray.pixelColor(0, 0).b)
}

// Binary16 conversion keeps normal, subnormal, signed-zero, infinity, and NaN classes.
#test
{
    for value in [0.0'f32, -0.0'f32, 1.0'f32, -2.0'f32, 0.00006103515625'f32, 0.000000059604645'f32, 65504.0'f32]
    {
        let restored = halfToFloat(floatToHalf(value))
        Swag.assert(cast #bit (u32) restored == cast #bit (u32) value)
    }

    let positiveInfinity = cast #bit (f32) 0x7F800000'u32
    let nan              = cast #bit (f32) 0x7FC01234'u32
    Swag.assert(cast #bit (u32) halfToFloat(floatToHalf(positiveInfinity)) == 0x7F800000)
    Swag.assert(halfToFloat(floatToHalf(nan)) != halfToFloat(floatToHalf(nan)))
}

// Alpha association is explicit and converts stored samples while preserving logical color.
#test
{
    const Bytes: [4] u8 = [200, 100, 50, 128]
    let straight      = Image.create(1, 1, .RGBA8, Bytes)
    let premultiplied = straight.convertedAlphaTo(.Premultiplied)
    Swag.assert(straight.alphaMode == .Straight)
    Swag.assert(premultiplied.alphaMode == .Premultiplied)
    Swag.assert(Math.abs(cast(s32) premultiplied.pixels.buffer![0] - 100) <= 1)
    Swag.assert(Math.abs(cast(s32) premultiplied.pixels.buffer![1] - 50) <= 1)
    Swag.assert(Math.abs(cast(s32) premultiplied.pixels.buffer![2] - 25) <= 1)
    let logical = premultiplied.pixelColor(0, 0)
    Swag.assert(Math.abs(cast(s32) logical.r - 200) <= 1)
    Swag.assert(Math.abs(cast(s32) logical.g - 100) <= 1)
    Swag.assert(Math.abs(cast(s32) logical.b - 50) <= 1)
    Swag.assert(logical.a == 128)

    let restored = premultiplied.convertedAlphaTo(.Straight)
    Swag.assert(restored.alphaMode == .Straight)
    Swag.assert(Math.abs(cast(s32) restored.pixels.buffer![0] - 200) <= 1)
    Swag.assert(Math.abs(cast(s32) restored.pixels.buffer![1] - 100) <= 1)
    Swag.assert(Math.abs(cast(s32) restored.pixels.buffer![2] - 50) <= 1)
    Swag.assert(restored.pixels.buffer![3] == 128)
}

// Every registered encoder and decoder declares a usable format, and the declared
// extensions are exactly what canSave/canLoad accept: the registry has one source of
// truth, so a format list built for a file dialog cannot offer an unwritable filter.
#test
{
    let encodable = Image.encodableFormats()
    Swag.assert(encodable.count >= 12)
    for &format in encodable
    {
        Swag.assert(format.name.count != 0)
        for ext in Tokenize.split(format.extensions, ';'rune)
        {
            Swag.assert(Utf8.startsWith(ext, "."))
            Swag.assert(Image.canSave(Format.toString("image%", ext)))
        }
    }

    let decodable = Image.decodableFormats()
    Swag.assert(decodable.count >= 13)
    for &format in decodable
    {
        Swag.assert(format.name.count != 0)
        for ext in Tokenize.split(format.extensions, ';'rune)
        {
            Swag.assert(Utf8.startsWith(ext, "."))
            Swag.assert(Image.canLoad(Format.toString("image%", ext)))
        }
    }
}

// An extension no registered codec claims is rejected by both halves of the registry,
// and the matching encode/decode entry points fail rather than picking an arbitrary codec.
#test
{
    Swag.assert(!Image.canSave("capture.unknown"))
    Swag.assert(!Image.canLoad("capture.unknown"))
    Swag.assert(!Image.canSave("capture"))

    var img = Image.create(2, 2, .RGBA8)
    img.clear()
    discard catch img.encode("capture.unknown") as errEncode
    Swag.assert(errEncode != null)

    discard catch Image.decode("capture.unknown", img.pixels.toSlice()) as errDecode
    Swag.assert(errDecode != null)
}

// Packed formats participate in the same geometric transforms without assuming a
// three- or four-byte pixel. Reversible transforms must preserve every storage bit.
#test
{
    for format in PackedFormats
    {
        var source = Image.create(4, 4, format)
        for i in source.byteCount do
            source.pixels.buffer![i] = cast(u8) ((i * 29 + 7) & 0xFF)

        let mirrored = source.mirrored().mirrored()
        let flipped  = source.flipped().flipped()
        let turned   = source.rotated(.Clockwise90).rotated(.Clockwise270)
        Swag.assert(Memory.compare(source.pixels.buffer, mirrored.pixels.buffer, source.byteCount) == 0)
        Swag.assert(Memory.compare(source.pixels.buffer, flipped.pixels.buffer, source.byteCount) == 0)
        Swag.assert(Memory.compare(source.pixels.buffer, turned.pixels.buffer, source.byteCount) == 0)

        let nearest = source.resized(7, 5, .Nearest)
        let smooth  = source.resized(3, 3, .Bilinear)
        let half    = source.halved()
        assertImage(nearest, 7, 5, format)
        assertImage(smooth, 3, 3, format)
        assertImage(half, 2, 2, format)
    }
}

// Every packed representation can convert to every other packed representation.
// Alpha association survives when both sides can express alpha and otherwise resets
// to the only meaningful straight representation.
#test
{
    for sourceFormat in PackedFormats
    {
        var source = Image.create(3, 2, sourceFormat)
        source.fill(Color.fromArgb(137, 31, 109, 223))
        if sourceFormat.hasAlpha() do
            source.convertAlphaTo(.Premultiplied)
        for destinationFormat in PackedFormats
        {
            let converted = source.convertedTo(destinationFormat)
            assertImage(converted, 3, 2, destinationFormat)
            let expectedAlphaMode = sourceFormat.hasAlpha() and destinationFormat.hasAlpha() ? AlphaMode.Premultiplied : AlphaMode.Straight
            Swag.assert(converted.alphaMode == expectedAlphaMode)
        }
    }
}

// Filters use a precision-aware scalar path outside their optimized 8-bit cases.
// This exercises grayscale, integer, HDR, and premultiplied-alpha storage through
// every color/filter family and verifies that the format contract stays intact.
#test
{
    for format in PackedFormats
    {
        var image = Image.create(4, 4, format)
        image.fillGradient(Color.fromArgb(64, 10, 40, 90), Color.fromArgb(220, 230, 170, 30))
        image.fillGradient(Color.fromArgb(10, 20, 30, 40), Color.fromArgb(50, 60, 70, 80), Color.fromArgb(90, 100, 110, 120), Color.fromArgb(130, 140, 150, 160))
        image.fillHsl(.HueSaturation)
        image.invert()
        image.fade(Color.fromRgb(20, 80, 140), 0.25)
        image.contrast(0.2)
        image.gamma(1.8)
        image.lightness(0.1)
        image.grayscale(0.4)
        image.colorize(0.7, 0.6, 0.5)
        image.setChannel(.Green, .MeanRGB)
        image.applyKernel(.GaussianBlur3x3Light)
        assertImage(image, 4, 4, format)

        if format.hasAlpha()
        {
            image.convertAlphaTo(.Premultiplied)
            image.fade(Color.fromArgb(100, 30, 60, 90), 0.3)
            image.keyOutGround(Color.fromRgb(0, 0, 0), Color.fromRgb(255, 255, 255))
            image.setAlpha(96)
            Swag.assert(image.alphaMode == .Premultiplied)
            image.setTransparentColor(Color.fromRgb(12, 34, 56))
            Swag.assert(image.alphaMode == .Straight)
        }
    }
}

// Region mixing converts compatible packed formats and alpha associations on the fly.
#test
{
    var source = Image.create(2, 2, .RGBAF32)
    source.fill(Color.fromArgb(128, 240, 80, 20))
    source.convertAlphaTo(.Premultiplied)

    for format in [PixelFormat.Gray8, PixelFormat.GrayAlpha8, PixelFormat.BGR8, PixelFormat.BGRA8,
                   PixelFormat.RGB16, PixelFormat.RGBA16, PixelFormat.RGBF16, PixelFormat.RGBAF32]
    {
        var destination = Image.create(3, 3, format)
        destination.fill(Color.fromArgb(200, 10, 30, 50))
        destination.mix(source, 1, 1, .Copy)
        destination.mix(source, 0, 0, .SourceOver)
        assertImage(destination, 3, 3, format)
    }
}
