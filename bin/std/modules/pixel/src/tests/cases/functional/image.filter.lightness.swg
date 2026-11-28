#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10_u8, 20_u8, 250_u8, 77_u8, 0_u8, 100_u8, 200_u8, 88_u8]

    var bright = makeImage(2, 1, .RGBA8, pixels)
    bright.lightness(0.2)
    assertImage(bright, 2, 1, .RGBA8)
    assertPixel(bright, 0, 0, Color.fromArgb(77_u8, 61_u8, 71_u8, 255_u8))
    assertPixel(bright, 1, 0, Color.fromArgb(88_u8, 51_u8, 151_u8, 251_u8))

    var dark = makeImage(2, 1, .RGBA8, pixels)
    dark.lightness(-1.0)
    assertImage(dark, 2, 1, .RGBA8)
    assertPixel(dark, 0, 0, Color.fromArgb(77_u8, 0_u8, 0_u8, 0_u8))
    assertPixel(dark, 1, 0, Color.fromArgb(88_u8, 0_u8, 0_u8, 0_u8))
}
