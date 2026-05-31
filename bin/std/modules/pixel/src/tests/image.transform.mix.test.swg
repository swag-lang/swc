#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    const dstPixels = [
        10'u8, 20'u8, 30'u8, 200'u8,     40'u8, 50'u8, 60'u8, 201'u8,     70'u8, 80'u8, 90'u8, 202'u8,
        100'u8, 110'u8, 120'u8, 203'u8,  130'u8, 140'u8, 150'u8, 204'u8,  160'u8, 170'u8, 180'u8, 205'u8,
    ]

    const copyPixels = [
        1'u8, 2'u8, 3'u8, 4'u8,          5'u8, 6'u8, 7'u8, 8'u8,
    ]

    const blendPixels = [
        200'u8, 210'u8, 220'u8, 128'u8,  0'u8, 10'u8, 20'u8, 64'u8,
    ]

    let dst      = makeImage(3, 2, .RGBA8, dstPixels)
    let srcCopy  = makeImage(2, 1, .RGBA8, copyPixels)
    let copied   = dst.toMix(srcCopy, 1, 0, .Copy)
    assertImage(copied, 3, 2, .RGBA8)

    assertPixel(copied, 0, 1, Color.fromArgb(200'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(copied, 1, 1, Color.fromArgb(4'u8, 1'u8, 2'u8, 3'u8))
    assertPixel(copied, 2, 1, Color.fromArgb(8'u8, 5'u8, 6'u8, 7'u8))
    assertPixel(copied, 0, 0, Color.fromArgb(203'u8, 100'u8, 110'u8, 120'u8))

    let srcBlend = makeImage(2, 1, .RGBA8, blendPixels)
    let blended  = dst.toMix(srcBlend, 0, 1, .AlphaBlend)
    assertImage(blended, 3, 2, .RGBA8)

    assertPixel(blended, 0, 0, Color.fromArgb(203'u8, 150'u8, 160'u8, 170'u8))
    assertPixel(blended, 1, 0, Color.fromArgb(204'u8, 97'u8, 107'u8, 117'u8))
    assertPixel(blended, 2, 0, Color.fromArgb(205'u8, 160'u8, 170'u8, 180'u8))
}
