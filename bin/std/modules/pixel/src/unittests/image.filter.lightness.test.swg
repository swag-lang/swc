#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10'u8, 20'u8, 250'u8, 77'u8,    0'u8, 100'u8, 200'u8, 88'u8,
        ]

    var bright = makeImage(2, 1, .RGBA8, pixels)
    bright.lightness(0.2)
    assertImage(bright, 2, 1, .RGBA8)
    assertPixel(bright, 0, 0, Color.fromArgb(77'u8, 61'u8, 71'u8, 255'u8))
    assertPixel(bright, 1, 0, Color.fromArgb(88'u8, 51'u8, 151'u8, 251'u8))

    var dark = makeImage(2, 1, .RGBA8, pixels)
    dark.lightness(-1.0)
    assertImage(dark, 2, 1, .RGBA8)
    assertPixel(dark, 0, 0, Color.fromArgb(77'u8, 0'u8, 0'u8, 0'u8))
    assertPixel(dark, 1, 0, Color.fromArgb(88'u8, 0'u8, 0'u8, 0'u8))
}
