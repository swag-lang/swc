#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        100_u8, 50_u8, 0_u8, 77_u8, 10_u8, 90_u8, 200_u8, 88_u8]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.grayscale()
    assertImage(img, 2, 1, .RGBA8)

    assertPixel(img, 0, 0, Color.fromArgb(77_u8, 56_u8, 56_u8, 56_u8))
    assertPixel(img, 1, 0, Color.fromArgb(88_u8, 81_u8, 81_u8, 81_u8))
}

// Fractional blending uses the parallel scalar visitor in both channel orders.
#test
{
    var rgba = makeImage(1, 1, .RGBA8, [100_u8, 50, 0, 77])
    var bgra = makeImage(1, 1, .BGRA8, [0_u8, 50, 100, 77])
    rgba.grayscale(0.5)
    bgra.grayscale(0.5)

    let expected = Color.fromArgb(77_u8, 78_u8, 53_u8, 28_u8)
    assertPixel(rgba, 0, 0, expected)
    assertPixel(bgra, 0, 0, expected)
}
