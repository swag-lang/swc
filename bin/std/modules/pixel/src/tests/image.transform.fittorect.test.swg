#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    const pixels = [
        10'u8, 11'u8, 12'u8, 13'u8,      20'u8, 21'u8, 22'u8, 23'u8,      30'u8, 31'u8, 32'u8, 33'u8,      40'u8, 41'u8, 42'u8, 43'u8,
        50'u8, 51'u8, 52'u8, 53'u8,      60'u8, 61'u8, 62'u8, 63'u8,      70'u8, 71'u8, 72'u8, 73'u8,      80'u8, 81'u8, 82'u8, 83'u8,
    ]

    var src = makeImage(4, 2, .RGBA8, pixels)
    var rect: Math.Rectangle
    rect.width  = 2
    rect.height = 2
    src.fitToRect(rect)
    assertImage(src, 2, 2, .RGBA8)

    assertPixel(src, 0, 1, Color.fromArgb(23'u8, 20'u8, 21'u8, 22'u8))
    assertPixel(src, 1, 1, Color.fromArgb(33'u8, 30'u8, 31'u8, 32'u8))
    assertPixel(src, 0, 0, Color.fromArgb(63'u8, 60'u8, 61'u8, 62'u8))
    assertPixel(src, 1, 0, Color.fromArgb(73'u8, 70'u8, 71'u8, 72'u8))
}
