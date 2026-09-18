#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func transformImage(pf: PixelFormat)->Image
{
    // 3 x 2, every pixel distinct, built in RGBA8 then converted.
    var pixels: [24] u8
    for i in 6
    {
        pixels[i * 4 + 0] = cast(u8) (i * 40 + 10)
        pixels[i * 4 + 1] = cast(u8) (200 - i * 30)
        pixels[i * 4 + 2] = cast(u8) (i * 17 + 5)
        pixels[i * 4 + 3] = 255
    }

    let img = Image.create(3, 2, .RGBA8, pixels)
    return img.convertedTo(pf)
}

func sameImage(a, b: Image)->bool
{
    if a.width != b.width or a.height != b.height do
        return false
    for y in a.height
    {
        for x in a.width
        {
            if a.pixelColor(x, y) != b.pixelColor(x, y) do
                return false
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
        Swag.assert(r90.width == 2 and r90.height == 3)
        // Clockwise: the top-left pixel moves to the top-right corner.
        Swag.assert(r90.pixelColor(1, 0) == img.pixelColor(0, 0))

        Swag.assert(r270.pixelColor(0, 2) == img.pixelColor(0, 0))

        Swag.assert(sameImage(r90.rotated(.Clockwise270), img))
        Swag.assert(sameImage(img.rotated(.HalfTurn).rotated(.HalfTurn), img))
        Swag.assert(sameImage(img.mirrored().mirrored(), img))
        Swag.assert(sameImage(img.flipped().flipped(), img))
        Swag.assert(img.mirrored().pixelColor(0, 0) == img.pixelColor(2, 0))
        Swag.assert(img.flipped().pixelColor(0, 0) == img.pixelColor(0, 1))

        let crop = img.cropped(1, 1, 2, 1)
        Swag.assert(crop.width == 2 and crop.height == 1)
        Swag.assert(crop.pixelColor(0, 0) == img.pixelColor(1, 1))

        let wide = img.convertedTo(.RGBAF32).convertedTo(pf)
        Swag.assert(sameImage(wide, img))
    }
}

// Resizing a single pixel, cropping the whole image, and expanding it keep the pixels in place.
#test
{
    let one  = Image.create(1, 1, .RGBA8)
    let same = one.resized(1, 1, .Bilinear)
    Swag.assert(same.width == 1 and same.height == 1)

    let img = transformImage(.RGBA8)
    let big = img.resized(6, 4, .Nearest)
    Swag.assert(big.pixelColor(0, 0) == img.pixelColor(0, 0) and big.pixelColor(5, 3) == img.pixelColor(2, 1))

    let whole = img.cropped(0, 0, 3, 2)
    Swag.assert(sameImage(whole, img))

    let grown = img.expanded(1, 2, 3, 4, Color.fromArgb(Argb.Red))
    Swag.assert(grown.width == 7 and grown.height == 8)
    Swag.assert(grown.pixelColor(1, 2) == img.pixelColor(0, 0))
    Swag.assert(grown.pixelColor(0, 0) == Color.fromArgb(Argb.Red))
}
