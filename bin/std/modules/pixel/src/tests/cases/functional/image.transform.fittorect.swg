#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10_u8, 11_u8, 12_u8, 13_u8, 20_u8, 21_u8, 22_u8, 23_u8, 30_u8, 31_u8, 32_u8, 33_u8, 40_u8, 41_u8, 42_u8, 43_u8,
        50_u8, 51_u8, 52_u8, 53_u8, 60_u8, 61_u8, 62_u8, 63_u8, 70_u8, 71_u8, 72_u8, 73_u8, 80_u8, 81_u8, 82_u8, 83_u8]

    var src = makeImage(4, 2, .RGBA8, pixels)
    src.cover(2, 2)
    assertImage(src, 2, 2, .RGBA8)

    assertPixel(src, 0, 1, Color.fromArgb(23_u8, 20_u8, 21_u8, 22_u8))
    assertPixel(src, 1, 1, Color.fromArgb(33_u8, 30_u8, 31_u8, 32_u8))
    assertPixel(src, 0, 0, Color.fromArgb(63_u8, 60_u8, 61_u8, 62_u8))
    assertPixel(src, 1, 0, Color.fromArgb(73_u8, 70_u8, 71_u8, 72_u8))

    const tallPixels = [
        70_u8, 71_u8, 72_u8, 73_u8, 80_u8, 81_u8, 82_u8, 83_u8,
        50_u8, 51_u8, 52_u8, 53_u8, 60_u8, 61_u8, 62_u8, 63_u8,
        30_u8, 31_u8, 32_u8, 33_u8, 40_u8, 41_u8, 42_u8, 43_u8,
        10_u8, 11_u8, 12_u8, 13_u8, 20_u8, 21_u8, 22_u8, 23_u8]

    var tall    = makeImage(2, 4, .RGBA8, tallPixels)
    var covered = tall.covered(2, 2)
    assertImage(tall, 2, 4, .RGBA8)
    tall = #move covered
    assertImage(tall, 2, 2, .RGBA8)
    assertPixel(tall, 0, 1, Color.fromArgb(53_u8, 50_u8, 51_u8, 52_u8))
    assertPixel(tall, 1, 1, Color.fromArgb(63_u8, 60_u8, 61_u8, 62_u8))
    assertPixel(tall, 0, 0, Color.fromArgb(33_u8, 30_u8, 31_u8, 32_u8))
    assertPixel(tall, 1, 0, Color.fromArgb(43_u8, 40_u8, 41_u8, 42_u8))
}

#test
{
    const widePixels = [
        10_u8, 20_u8, 30_u8, 255_u8, 40_u8, 50_u8, 60_u8, 255_u8,
        70_u8, 80_u8, 90_u8, 255_u8, 100_u8, 110_u8, 120_u8, 255_u8,
        130_u8, 140_u8, 150_u8, 255_u8, 160_u8, 170_u8, 180_u8, 255_u8,
        190_u8, 200_u8, 210_u8, 255_u8, 220_u8, 230_u8, 240_u8, 255_u8]
    var wide   = makeImage(4, 2, .RGBA8, widePixels)
    let inside = wide.fittedInside(3, 1, .Nearest)
    assertImage(inside, 2, 1, .RGBA8)
    assertImage(wide, 4, 2, .RGBA8)

    var tall = makeImage(2, 4, .RGBA8, [
        10_u8, 20_u8, 30_u8, 255_u8, 40_u8, 50_u8, 60_u8, 255_u8,
        70_u8, 80_u8, 90_u8, 255_u8, 100_u8, 110_u8, 120_u8, 255_u8,
        130_u8, 140_u8, 150_u8, 255_u8, 160_u8, 170_u8, 180_u8, 255_u8,
        190_u8, 200_u8, 210_u8, 255_u8, 220_u8, 230_u8, 240_u8, 255_u8])
    tall.fitInside(3, 3, .Nearest)
    assertImage(tall, 1, 3, .RGBA8)
}
