#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    const pixels = [
        10'u8, 10'u8, 10'u8, 101'u8,     20'u8, 20'u8, 20'u8, 102'u8,     30'u8, 30'u8, 30'u8, 103'u8,
        40'u8, 40'u8, 40'u8, 104'u8,     50'u8, 50'u8, 50'u8, 105'u8,     60'u8, 60'u8, 60'u8, 106'u8,
        70'u8, 70'u8, 70'u8, 107'u8,     80'u8, 80'u8, 80'u8, 108'u8,     90'u8, 90'u8, 90'u8, 109'u8,
        ]

    let src = makeImage(3, 3, .RGBA8, pixels)
    let out = src.toApplyKernel(.BoxBlur3x3A)
    assertImage(out, 3, 3, .RGBA8)

    assertPixel(out, 0, 2, Color.fromArgb(101'u8, 23'u8, 23'u8, 23'u8))
    assertPixel(out, 1, 1, Color.fromArgb(105'u8, 50'u8, 50'u8, 50'u8))
    assertPixel(out, 2, 0, Color.fromArgb(109'u8, 76'u8, 76'u8, 76'u8))
}
