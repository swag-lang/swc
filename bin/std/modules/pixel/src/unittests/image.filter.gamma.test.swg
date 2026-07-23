#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        0'u8, 64'u8, 255'u8, 101'u8,    25'u8, 100'u8, 225'u8, 102'u8,
        ]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.gamma(2.0)
    assertImage(img, 2, 1, .RGBA8)
    assertPixel(img, 0, 0, Color.fromArgb(101'u8, 0'u8, 127'u8, 255'u8))
    assertPixel(img, 1, 0, Color.fromArgb(102'u8, 79'u8, 159'u8, 239'u8))

    var identity = makeImage(2, 1, .RGBA8, pixels)
    identity.gamma(1.0)
    assertImage(identity, 2, 1, .RGBA8)
    assertPixel(identity, 0, 0, Color.fromArgb(101'u8, 0'u8, 64'u8, 255'u8))
    assertPixel(identity, 1, 0, Color.fromArgb(102'u8, 25'u8, 100'u8, 225'u8))
}
