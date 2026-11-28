#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func transformImage(pf: PixelFormat)->Image
{
    // 3 x 2, every pixel distinct, built in RGBA8 then converted.
    var pixels: [24] u8
    for i in 6
    {
        pixels[i * 4 + 0] = cast(u8, (i * 40 + 10))
        pixels[i * 4 + 1] = cast(u8, (200 - i * 30))
        pixels[i * 4 + 2] = cast(u8, (i * 17 + 5))
        pixels[i * 4 + 3] = 255
    }

    let img = Image.create(3, 2, .RGBA8, pixels)
    return img.convertedTo(pf)
}

func sameImage(a, b: Image)->bool
{
    if a.width != b.width or
       a.height != b.height or
       a.pixelFormat != b.pixelFormat or
       a.alphaMode != b.alphaMode
    {
        return false
    }

    for y in a.height
    {
        for x in a.width
        {
            if a.pixelColor(x, y) != b.pixelColor(x, y)
            {
                return false
            }
        }
    }

    return true
}

// Rotations, mirrors, flips, crops, and a float round trip keep every pixel where it belongs, in
// every packed format.
#test
{
    for pf in [PixelFormat.RGBA8, PixelFormat.BGRA8, PixelFormat.RGB8, PixelFormat.BGR8, PixelFormat.RGBA16, PixelFormat.RGBAF32, PixelFormat.RGB16]
    {
        let img = transformImage(pf)

        let r90  = img.rotated(.Clockwise90)
        let r270 = img.rotated(.Clockwise270)
        Swag.require(r90.width == 2 and r90.height == 3)

        // Clockwise: the top-left pixel moves to the top-right corner.
        Swag.require(r90.pixelColor(1, 0) == img.pixelColor(0, 0))

        Swag.require(r270.pixelColor(0, 2) == img.pixelColor(0, 0))

        Swag.require(sameImage(r90.rotated(.Clockwise270), img))
        Swag.require(sameImage(img.rotated(.HalfTurn).rotated(.HalfTurn), img))
        Swag.require(sameImage(img.mirrored().mirrored(), img))
        Swag.require(sameImage(img.flipped().flipped(), img))
        Swag.require(img.mirrored().pixelColor(0, 0) == img.pixelColor(2, 0))
        Swag.require(img.flipped().pixelColor(0, 0) == img.pixelColor(0, 1))

        var turned = img
        turned.rotate(.Clockwise90)
        Swag.require(sameImage(turned, r90))
        turned.rotate(.Clockwise270)
        Swag.require(sameImage(turned, img))

        var halfTurned = img
        halfTurned.rotate(.HalfTurn)
        Swag.require(sameImage(halfTurned, img.rotated(.HalfTurn)))
        halfTurned.rotate(.HalfTurn)
        Swag.require(sameImage(halfTurned, img))

        var mirrored = img
        mirrored.mirror()
        Swag.require(sameImage(mirrored, img.mirrored()))
        mirrored.mirror()
        Swag.require(sameImage(mirrored, img))

        var flipped = img
        flipped.flip()
        Swag.require(sameImage(flipped, img.flipped()))
        flipped.flip()
        Swag.require(sameImage(flipped, img))

        let crop = img.cropped(1, 1, 2, 1)
        Swag.require(crop.width == 2 and crop.height == 1)
        Swag.require(crop.pixelColor(0, 0) == img.pixelColor(1, 1))

        let wide = img.convertedTo(.RGBAF32).convertedTo(pf)
        Swag.require(sameImage(wide, img))
    }
}

// Resizing a single pixel, cropping the whole image, and expanding it keep the pixels in place.
#test
{
    let one  = Image.create(1, 1, .RGBA8)
    let same = one.resized(1, 1, .Bilinear)
    Swag.require(same.width == 1 and same.height == 1)

    let img = transformImage(.RGBA8)
    let big = img.resized(6, 4, .Nearest)
    Swag.require(big.pixelColor(0, 0) == img.pixelColor(0, 0) and big.pixelColor(5, 3) == img.pixelColor(2, 1))

    let whole = img.cropped(0, 0, 3, 2)
    Swag.require(sameImage(whole, img))

    let grown = img.expanded(1, 2, 3, 4, Color.fromArgb(Argb.Red))
    Swag.require(grown.width == 7 and grown.height == 8)
    Swag.require(grown.pixelColor(1, 2) == img.pixelColor(0, 0))
    Swag.require(grown.pixelColor(0, 0) == Color.fromArgb(Argb.Red))
}

// Adding opaque alpha keeps integer and float samples at their original precision.
#test
{
    const Width  = 257
    const Height = 256
    const Count  = Width * Height
    for sourceFormat in [PixelFormat.RGB16, PixelFormat.RGBF16]
    {
        var source = Image.create(Width, Height, sourceFormat)
        let input  = cast([*] u16, source.pixels.storage())
        for i in 3 * Count
        {
            input[i] = cast #wrap(u16, i)
        }

        let half   = sourceFormat == .RGBF16
        let result = source.convertedTo(half ? .RGBAF16 : .RGBA16)
        let output = cast(const [*] u16, result.pixels.storage())
        for i in Count
        {
            for channel in 3
            {
                let value = input[3 * i + channel]
                Swag.require(output[4 * i + channel] == (half ? floatToHalf(halfToFloat(value)) : value))
            }

            Swag.require(output[4 * i + 3] == (half ? 0x3C00_u16 : 0xFFFF_u16))
        }
    }

    const Words: [9] u32 = [0, 0x8000_0000, 0x7F80_0000, 0xFF80_0000, 0x7FC0_ABCD, 0xFFC0_EFAB, 1, 0x4000_0000, 0xBF80_0000]
    let bytes  = Swag.makeSlice(cast(const [*] u8, &Words[0]), #sizeof(Words))
    let source = Image.create(3, 1, .RGBF32, bytes)
    let result = source.convertedTo(.RGBAF32)
    let output = cast(const [*] u32, result.pixels.storage())
    for i in 3
    {
        for channel in 3
        {
            Swag.require(output[4 * i + channel] == Words[3 * i + channel])
        }

        Swag.require(output[4 * i + 3] == 0x3F80_0000)
    }
}
