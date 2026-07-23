#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    const pixels = [
        10'u8, 20'u8, 30'u8, 40'u8,      50'u8, 60'u8, 70'u8, 80'u8,      90'u8, 100'u8, 110'u8, 120'u8,
        130'u8, 140'u8, 150'u8, 160'u8,  170'u8, 180'u8, 190'u8, 200'u8,  210'u8, 220'u8, 230'u8, 240'u8,
        ]

    let src = makeImage(3, 2, .RGBA8, pixels)
    let out = src.toCrop(1, 0, 2, 2)
    assertImage(out, 2, 2, .RGBA8)

    assertPixel(out, 0, 1, Color.fromArgb(80'u8, 50'u8, 60'u8, 70'u8))
    assertPixel(out, 1, 1, Color.fromArgb(120'u8, 90'u8, 100'u8, 110'u8))
    assertPixel(out, 0, 0, Color.fromArgb(200'u8, 170'u8, 180'u8, 190'u8))
    assertPixel(out, 1, 0, Color.fromArgb(240'u8, 210'u8, 220'u8, 230'u8))

    var inPlace = makeImage(3, 2, .RGBA8, pixels)
    inPlace.crop(0, 1, 2, 1)
    assertImage(inPlace, 2, 1, .RGBA8)
    assertPixel(inPlace, 0, 0, Color.fromArgb(40'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(inPlace, 1, 0, Color.fromArgb(80'u8, 50'u8, 60'u8, 70'u8))
}
