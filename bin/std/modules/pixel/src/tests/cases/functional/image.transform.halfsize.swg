#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10_u8, 20_u8, 30_u8, 40_u8, 50_u8, 60_u8, 70_u8, 80_u8, 90_u8, 100_u8, 110_u8, 120_u8, 130_u8, 140_u8, 150_u8, 160_u8,
        20_u8, 30_u8, 40_u8, 50_u8, 60_u8, 70_u8, 80_u8, 90_u8, 100_u8, 110_u8, 120_u8, 130_u8, 140_u8, 150_u8, 160_u8, 170_u8,
        30_u8, 40_u8, 50_u8, 60_u8, 70_u8, 80_u8, 90_u8, 100_u8, 110_u8, 120_u8, 130_u8, 140_u8, 150_u8, 160_u8, 170_u8, 180_u8,
        40_u8, 50_u8, 60_u8, 70_u8, 80_u8, 90_u8, 100_u8, 110_u8, 120_u8, 130_u8, 140_u8, 150_u8, 160_u8, 170_u8, 180_u8, 190_u8]

    let src = makeImage(4, 4, .RGBA8, pixels)
    let out = src.halved()
    assertImage(out, 2, 2, .RGBA8)

    assertPixel(out, 0, 1, Color.fromArgb(65_u8, 42_u8, 52_u8, 62_u8))
    assertPixel(out, 1, 1, Color.fromArgb(145_u8, 118_u8, 128_u8, 138_u8))
    assertPixel(out, 0, 0, Color.fromArgb(85_u8, 60_u8, 70_u8, 80_u8))
    assertPixel(out, 1, 0, Color.fromArgb(165_u8, 138_u8, 148_u8, 158_u8))
}

#test
{
    const pixels = [17_u8, 91, 203, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255]
    let straight      = Image.create(2, 2, .RGBA8, pixels)
    var premultiplied = Image.create(2, 2, .RGBA8, pixels)
    premultiplied.convertAlphaTo(.Premultiplied)

    let straightHalf = straight.halved()
    let premultHalf  = premultiplied.halved()
    Swag.require(straightHalf.alphaMode == .Straight)
    Swag.require(premultHalf.alphaMode == .Premultiplied)
    assertPixel(premultHalf, 0, 0, Color.fromArgb(191_u8, 255, 0, 0))
    assertPixel(straightHalf, 0, 0, premultHalf.pixelColor(0, 0))
}

// Both byte layouts preserve each channel's integer average for odd dimensions,
// including the final output pixel and the alpha channel.
#test
{
    for format in [PixelFormat.RGB8, .BGR8, .RGBA8, .BGRA8]
    {
        for width in [2, 3, 4, 5, 6, 7, 8, 9, 16, 17, 31, 32, 33]
        {
            for height in [2, 3, 6, 7]
            {
                var src = Image.create(width, height, format)
                for i in src.byteCount
                {
                    src.pixels.storage()[i] = cast(u8, ((i * 37 + width * 11 + height * 13) & 255))
                }

                if format.hasAlpha()
                {
                    src.convertAlphaTo(.Premultiplied)
                }

                let pixels = src.pixels.storage()
                let result = src.halved()
                Swag.require(result.width == width / 2 and result.height == height / 2)
                let out   = result.pixels.storage()
                let bytes = cast(u64, src.bytesPerPixel)
                for y in cast(u64, result.height)
                {
                    for x in cast(u64, result.width)
                    {
                        for channel in bytes
                        {
                            let index = 2 * y * src.rowStride + 2 * x * bytes + channel
                            let sum   = cast(u32, pixels[index]) + pixels[index + bytes] + pixels[index + src.rowStride] + pixels[index + src.rowStride + bytes]
                            Swag.require(out[y * result.rowStride + x * bytes + channel] == cast(u8, (sum >> 2)))
                        }
                    }
                }
            }
        }
    }
}

// Straight-alpha halving matches the logical pixels from a premultiplied reference.
#test
{
    let formats: [9] PixelFormat = [.RGBA8, .BGRA8, .RGBA16, .RGBAF16, .RGBAF32,
                                    .GrayAlpha8, .GrayAlpha16, .GrayAlphaF16, .GrayAlphaF32]
    let sizes: [3] [2] s32 = [[3, 3], [5, 3], [7, 5]]
    for format in formats
    {
        for size in sizes
        {
            let width  = size[0]
            let height = size[1]
            var rgba   = Image.create(width, height, .RGBA8)
            for pixelIndex in cast(u64, (width * height))
            {
                let pixel = rgba.pixels.storage() + pixelIndex * 4
                pixel[0] = cast(u8, ((pixelIndex * 37 + 11) & 255))
                pixel[1] = cast(u8, ((pixelIndex * 19 + 53) & 255))
                pixel[2] = cast(u8, ((pixelIndex * 13 + 97) & 255))
                pixel[3] = pixelIndex % 4 == 0 ? 0 : cast(u8, ((pixelIndex * 29 + 71) & 255))
            }

            let straight  = rgba.convertedTo(format)
            var reference = straight.convertedTo(.RGBAF32)
            reference.convertAlphaTo(.Premultiplied)
            var expected = reference.halved()
            expected.convertAlphaTo(.Straight)
            let actual = straight.halved()
            Swag.require(actual.alphaMode == .Straight and expected.alphaMode == .Straight)
            Swag.require(actual.width == width / 2 and actual.height == height / 2)
            for y in actual.height
            {
                for x in actual.width
                {
                    let actualColor   = actual.pixelColor(x, y)
                    let expectedColor = expected.pixelColor(x, y)
                    Swag.require(Math.abs(cast(s32, actualColor.r) - expectedColor.r) <= 1)
                    Swag.require(Math.abs(cast(s32, actualColor.g) - expectedColor.g) <= 1)
                    Swag.require(Math.abs(cast(s32, actualColor.b) - expectedColor.b) <= 1)
                    Swag.require(Math.abs(cast(s32, actualColor.a) - expectedColor.a) <= 1)
                }
            }
        }
    }
}
