#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    const pixels = [
        0'u8, 64'u8, 255'u8, 101'u8,    25'u8, 100'u8, 225'u8, 102'u8,
        ]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.invert()
    assertImage(img, 2, 1, .RGBA8)
    assertPixel(img, 0, 0, Color.fromArgb(101'u8, 255'u8, 191'u8, 0'u8))
    assertPixel(img, 1, 0, Color.fromArgb(102'u8, 230'u8, 155'u8, 30'u8))
}
