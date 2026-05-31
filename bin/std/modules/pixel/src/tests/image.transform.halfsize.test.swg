#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    const pixels = [
        10'u8, 20'u8, 30'u8, 40'u8,      50'u8, 60'u8, 70'u8, 80'u8,      90'u8, 100'u8, 110'u8, 120'u8,   130'u8, 140'u8, 150'u8, 160'u8,
        20'u8, 30'u8, 40'u8, 50'u8,      60'u8, 70'u8, 80'u8, 90'u8,      100'u8, 110'u8, 120'u8, 130'u8,  140'u8, 150'u8, 160'u8, 170'u8,
        30'u8, 40'u8, 50'u8, 60'u8,      70'u8, 80'u8, 90'u8, 100'u8,     110'u8, 120'u8, 130'u8, 140'u8,  150'u8, 160'u8, 170'u8, 180'u8,
        40'u8, 50'u8, 60'u8, 70'u8,      80'u8, 90'u8, 100'u8, 110'u8,    120'u8, 130'u8, 140'u8, 150'u8,  160'u8, 170'u8, 180'u8, 190'u8,
    ]

    let src = makeImage(4, 4, .RGBA8, pixels)
    let out = src.toHalfSize()
    assertImage(out, 2, 2, .RGBA8)

    assertPixel(out, 0, 1, Color.fromArgb(65'u8, 35'u8, 45'u8, 55'u8))
    assertPixel(out, 1, 1, Color.fromArgb(145'u8, 115'u8, 125'u8, 135'u8))
    assertPixel(out, 0, 0, Color.fromArgb(85'u8, 55'u8, 65'u8, 75'u8))
    assertPixel(out, 1, 0, Color.fromArgb(165'u8, 135'u8, 145'u8, 155'u8))
}
