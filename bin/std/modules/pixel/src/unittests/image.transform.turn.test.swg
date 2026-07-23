#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10'u8, 11'u8, 12'u8, 13'u8,      20'u8, 21'u8, 22'u8, 23'u8,      30'u8, 31'u8, 32'u8, 33'u8,
        40'u8, 41'u8, 42'u8, 43'u8,      50'u8, 51'u8, 52'u8, 53'u8,      60'u8, 61'u8, 62'u8, 63'u8,
        ]

    let src  = makeImage(3, 2, .RGBA8, pixels)
    let t90  = src.toTurn(.T90)
    let t180 = src.toTurn(.T180)
    let t270 = src.toTurn(.T270)

    assertImage(t90, 2, 3, .RGBA8)
    assertPixel(t90, 0, 2, Color.fromArgb(33'u8, 30'u8, 31'u8, 32'u8))
    assertPixel(t90, 1, 2, Color.fromArgb(63'u8, 60'u8, 61'u8, 62'u8))
    assertPixel(t90, 0, 1, Color.fromArgb(23'u8, 20'u8, 21'u8, 22'u8))
    assertPixel(t90, 1, 1, Color.fromArgb(53'u8, 50'u8, 51'u8, 52'u8))
    assertPixel(t90, 0, 0, Color.fromArgb(13'u8, 10'u8, 11'u8, 12'u8))
    assertPixel(t90, 1, 0, Color.fromArgb(43'u8, 40'u8, 41'u8, 42'u8))

    assertImage(t180, 3, 2, .RGBA8)
    assertPixel(t180, 0, 1, Color.fromArgb(63'u8, 60'u8, 61'u8, 62'u8))
    assertPixel(t180, 1, 1, Color.fromArgb(53'u8, 50'u8, 51'u8, 52'u8))
    assertPixel(t180, 2, 1, Color.fromArgb(43'u8, 40'u8, 41'u8, 42'u8))
    assertPixel(t180, 0, 0, Color.fromArgb(33'u8, 30'u8, 31'u8, 32'u8))
    assertPixel(t180, 1, 0, Color.fromArgb(23'u8, 20'u8, 21'u8, 22'u8))
    assertPixel(t180, 2, 0, Color.fromArgb(13'u8, 10'u8, 11'u8, 12'u8))

    assertImage(t270, 2, 3, .RGBA8)
    assertPixel(t270, 0, 2, Color.fromArgb(43'u8, 40'u8, 41'u8, 42'u8))
    assertPixel(t270, 1, 2, Color.fromArgb(13'u8, 10'u8, 11'u8, 12'u8))
    assertPixel(t270, 0, 1, Color.fromArgb(53'u8, 50'u8, 51'u8, 52'u8))
    assertPixel(t270, 1, 1, Color.fromArgb(23'u8, 20'u8, 21'u8, 22'u8))
    assertPixel(t270, 0, 0, Color.fromArgb(63'u8, 60'u8, 61'u8, 62'u8))
    assertPixel(t270, 1, 0, Color.fromArgb(33'u8, 30'u8, 31'u8, 32'u8))
}
