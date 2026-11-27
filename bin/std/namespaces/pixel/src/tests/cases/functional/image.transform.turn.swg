#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10_u8, 11_u8, 12_u8, 13_u8, 20_u8, 21_u8, 22_u8, 23_u8, 30_u8, 31_u8, 32_u8, 33_u8,
        40_u8, 41_u8, 42_u8, 43_u8, 50_u8, 51_u8, 52_u8, 53_u8, 60_u8, 61_u8, 62_u8, 63_u8]

    let src  = makeImage(3, 2, .RGBA8, pixels)
    let t90  = src.rotated(.Clockwise90)
    let t180 = src.rotated(.HalfTurn)
    let t270 = src.rotated(.Clockwise270)

    assertImage(t90, 2, 3, .RGBA8)
    assertPixel(t90, 0, 2, Color.fromArgb(33_u8, 30_u8, 31_u8, 32_u8))
    assertPixel(t90, 1, 2, Color.fromArgb(63_u8, 60_u8, 61_u8, 62_u8))
    assertPixel(t90, 0, 1, Color.fromArgb(23_u8, 20_u8, 21_u8, 22_u8))
    assertPixel(t90, 1, 1, Color.fromArgb(53_u8, 50_u8, 51_u8, 52_u8))
    assertPixel(t90, 0, 0, Color.fromArgb(13_u8, 10_u8, 11_u8, 12_u8))
    assertPixel(t90, 1, 0, Color.fromArgb(43_u8, 40_u8, 41_u8, 42_u8))

    assertImage(t180, 3, 2, .RGBA8)
    assertPixel(t180, 0, 1, Color.fromArgb(63_u8, 60_u8, 61_u8, 62_u8))
    assertPixel(t180, 1, 1, Color.fromArgb(53_u8, 50_u8, 51_u8, 52_u8))
    assertPixel(t180, 2, 1, Color.fromArgb(43_u8, 40_u8, 41_u8, 42_u8))
    assertPixel(t180, 0, 0, Color.fromArgb(33_u8, 30_u8, 31_u8, 32_u8))
    assertPixel(t180, 1, 0, Color.fromArgb(23_u8, 20_u8, 21_u8, 22_u8))
    assertPixel(t180, 2, 0, Color.fromArgb(13_u8, 10_u8, 11_u8, 12_u8))

    assertImage(t270, 2, 3, .RGBA8)
    assertPixel(t270, 0, 2, Color.fromArgb(43_u8, 40_u8, 41_u8, 42_u8))
    assertPixel(t270, 1, 2, Color.fromArgb(13_u8, 10_u8, 11_u8, 12_u8))
    assertPixel(t270, 0, 1, Color.fromArgb(53_u8, 50_u8, 51_u8, 52_u8))
    assertPixel(t270, 1, 1, Color.fromArgb(23_u8, 20_u8, 21_u8, 22_u8))
    assertPixel(t270, 0, 0, Color.fromArgb(63_u8, 60_u8, 61_u8, 62_u8))
    assertPixel(t270, 1, 0, Color.fromArgb(33_u8, 30_u8, 31_u8, 32_u8))
}
