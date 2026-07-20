#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    const pixels = [
        10'u8, 20'u8, 30'u8, 40'u8,      50'u8, 60'u8, 70'u8, 80'u8,
        90'u8, 100'u8, 110'u8, 120'u8,   130'u8, 140'u8, 150'u8, 160'u8,
    ]

    let src     = makeImage(2, 2, .RGBA8, pixels)
    let bgColor = Color.fromArgb(255'u8, 1'u8, 2'u8, 3'u8)
    let grown   = src.toExpand(1, 1, 1, 0, bgColor)
    assertImage(grown, 4, 3, .RGBA8)

    assertPixel(grown, 0, 2, bgColor)
    assertPixel(grown, 1, 1, Color.fromArgb(40'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(grown, 2, 1, Color.fromArgb(80'u8, 50'u8, 60'u8, 70'u8))
    assertPixel(grown, 1, 0, Color.fromArgb(120'u8, 90'u8, 100'u8, 110'u8))
    assertPixel(grown, 2, 0, Color.fromArgb(160'u8, 130'u8, 140'u8, 150'u8))
    assertPixel(grown, 3, 0, bgColor)

    var trimmed = makeImage(2, 2, .RGBA8, pixels)
    trimmed.expand(-1, 0, 0, 0)
    assertImage(trimmed, 1, 2, .RGBA8)
    assertPixel(trimmed, 0, 1, Color.fromArgb(80'u8, 50'u8, 60'u8, 70'u8))
    assertPixel(trimmed, 0, 0, Color.fromArgb(160'u8, 130'u8, 140'u8, 150'u8))
}
