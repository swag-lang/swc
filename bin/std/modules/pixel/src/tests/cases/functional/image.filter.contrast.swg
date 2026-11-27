#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        40_u8, 80_u8, 120_u8, 91_u8, 150_u8, 200_u8, 240_u8, 92_u8]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.contrast(0.5)
    assertImage(img, 2, 1, .RGBA8)

    assertPixel(img, 0, 0, Color.fromArgb(91_u8, 0_u8, 56_u8, 116_u8))
    assertPixel(img, 1, 0, Color.fromArgb(92_u8, 161_u8, 236_u8, 255_u8))
}
