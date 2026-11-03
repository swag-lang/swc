#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        100'u8, 50'u8, 0'u8, 77'u8, 10'u8, 90'u8, 200'u8, 88'u8]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.grayscale()
    assertImage(img, 2, 1, .RGBA8)

    assertPixel(img, 0, 0, Color.fromArgb(77'u8, 56'u8, 56'u8, 56'u8))
    assertPixel(img, 1, 0, Color.fromArgb(88'u8, 81'u8, 81'u8, 81'u8))
}

// Fractional blending uses the parallel scalar visitor in both channel orders.
#test
{
    var rgba = makeImage(1, 1, .RGBA8, [100'u8, 50, 0, 77])
    var bgra = makeImage(1, 1, .BGRA8, [0'u8, 50, 100, 77])
    rgba.grayscale(0.5)
    bgra.grayscale(0.5)

    let expected = Color.fromArgb(77'u8, 78'u8, 53'u8, 28'u8)
    assertPixel(rgba, 0, 0, expected)
    assertPixel(bgra, 0, 0, expected)
}
