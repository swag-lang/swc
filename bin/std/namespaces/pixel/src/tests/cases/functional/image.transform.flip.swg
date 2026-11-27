#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10_u8, 11_u8, 12_u8, 13_u8, 20_u8, 21_u8, 22_u8, 23_u8,
        30_u8, 31_u8, 32_u8, 33_u8, 40_u8, 41_u8, 42_u8, 43_u8,
        50_u8, 51_u8, 52_u8, 53_u8, 60_u8, 61_u8, 62_u8, 63_u8]

    let src = makeImage(2, 3, .RGBA8, pixels)
    let out = src.flipped()
    assertImage(out, 2, 3, .RGBA8)

    assertPixel(out, 0, 2, Color.fromArgb(53_u8, 50_u8, 51_u8, 52_u8))
    assertPixel(out, 1, 2, Color.fromArgb(63_u8, 60_u8, 61_u8, 62_u8))
    assertPixel(out, 0, 1, Color.fromArgb(33_u8, 30_u8, 31_u8, 32_u8))
    assertPixel(out, 1, 1, Color.fromArgb(43_u8, 40_u8, 41_u8, 42_u8))
    assertPixel(out, 0, 0, Color.fromArgb(13_u8, 10_u8, 11_u8, 12_u8))
    assertPixel(out, 1, 0, Color.fromArgb(23_u8, 20_u8, 21_u8, 22_u8))
}
