#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10_u8, 20_u8, 30_u8, 40_u8, 50_u8, 60_u8, 70_u8, 80_u8, 90_u8, 100_u8, 110_u8, 120_u8,
        130_u8, 140_u8, 150_u8, 160_u8, 170_u8, 180_u8, 190_u8, 200_u8, 210_u8, 220_u8, 230_u8, 240_u8]

    let src = makeImage(3, 2, .RGBA8, pixels)
    let out = src.cropped(1, 0, 2, 2)
    assertImage(out, 2, 2, .RGBA8)

    assertPixel(out, 0, 1, Color.fromArgb(80_u8, 50_u8, 60_u8, 70_u8))
    assertPixel(out, 1, 1, Color.fromArgb(120_u8, 90_u8, 100_u8, 110_u8))
    assertPixel(out, 0, 0, Color.fromArgb(200_u8, 170_u8, 180_u8, 190_u8))
    assertPixel(out, 1, 0, Color.fromArgb(240_u8, 210_u8, 220_u8, 230_u8))

    var inPlace = makeImage(3, 2, .RGBA8, pixels)
    inPlace.crop(0, 1, 2, 1)
    assertImage(inPlace, 2, 1, .RGBA8)
    assertPixel(inPlace, 0, 0, Color.fromArgb(40_u8, 10_u8, 20_u8, 30_u8))
    assertPixel(inPlace, 1, 0, Color.fromArgb(80_u8, 50_u8, 60_u8, 70_u8))
}
