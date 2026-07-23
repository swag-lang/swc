#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        40'u8, 80'u8, 120'u8, 91'u8,     150'u8, 200'u8, 240'u8, 92'u8,
        ]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.contrast(0.5)
    assertImage(img, 2, 1, .RGBA8)

    assertPixel(img, 0, 0, Color.fromArgb(91'u8, 0'u8, 56'u8, 116'u8))
    assertPixel(img, 1, 0, Color.fromArgb(92'u8, 161'u8, 236'u8, 255'u8))
}
