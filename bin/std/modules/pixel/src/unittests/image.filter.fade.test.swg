#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10'u8, 20'u8, 30'u8, 101'u8,     200'u8, 150'u8, 100'u8, 102'u8,
        ]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.fade(Color.fromArgb(255'u8, 110'u8, 210'u8, 10'u8), 0.25)
    assertImage(img, 2, 1, .RGBA8)

    assertPixel(img, 0, 0, Color.fromArgb(101'u8, 35'u8, 67'u8, 25'u8))
    assertPixel(img, 1, 0, Color.fromArgb(102'u8, 177'u8, 165'u8, 77'u8))
}
