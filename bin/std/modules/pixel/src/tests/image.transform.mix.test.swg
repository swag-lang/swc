#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const dstPixels = [
        10'u8, 20'u8, 30'u8, 200'u8, 40'u8, 50'u8, 60'u8, 201'u8, 70'u8, 80'u8, 90'u8, 202'u8,
        100'u8, 110'u8, 120'u8, 203'u8, 130'u8, 140'u8, 150'u8, 204'u8, 160'u8, 170'u8, 180'u8, 205'u8]

    const copyPixels = [
        1'u8, 2'u8, 3'u8, 4'u8, 5'u8, 6'u8, 7'u8, 8'u8]

    const blendPixels = [
        200'u8, 210'u8, 220'u8, 128'u8, 0'u8, 10'u8, 20'u8, 64'u8]

    let dst     = makeImage(3, 2, .RGBA8, dstPixels)
    let srcCopy = makeImage(2, 1, .RGBA8, copyPixels)
    let copied  = dst.mixed(srcCopy, 1, 0, .Copy)
    assertImage(copied, 3, 2, .RGBA8)

    assertPixel(copied, 0, 1, Color.fromArgb(200'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(copied, 1, 1, Color.fromArgb(4'u8, 1'u8, 2'u8, 3'u8))
    assertPixel(copied, 2, 1, Color.fromArgb(8'u8, 5'u8, 6'u8, 7'u8))
    assertPixel(copied, 0, 0, Color.fromArgb(203'u8, 100'u8, 110'u8, 120'u8))

    let srcBlend = makeImage(2, 1, .RGBA8, blendPixels)
    let blended  = dst.mixed(srcBlend, 0, 1, .SourceOver)
    assertImage(blended, 3, 2, .RGBA8)

    assertPixel(blended, 0, 0, Color.fromArgb(229'u8, 156'u8, 166'u8, 176'u8))
    assertPixel(blended, 1, 0, Color.fromArgb(217'u8, 92'u8, 102'u8, 112'u8))
    assertPixel(blended, 2, 0, Color.fromArgb(205'u8, 160'u8, 170'u8, 180'u8))
}

#test
{
    var dstPixels: [48] u8 = undefined
    for index in dstPixels.count do
        dstPixels[index] = cast(u8) (index * 3 + 1)
    var srcPixels: [24] u8 = undefined
    for index in srcPixels.count do
        srcPixels[index] = cast(u8) (index * 5 + 7)

    let dst = makeImage(4, 3, .RGBA8, dstPixels)
    let src = makeImage(3, 2, .RGBA8, srcPixels)

    var expected: Array'u8
    expected.resize(dstPixels.count)
    Memory.copy(expected.buffer, dstPixels.buffer, expected.count)
    for row in 2
    {
        let target = expected.buffer! + cast(u64) (row + 1) * 16
        let source = srcPixels.buffer + cast(u64) row * 12 + 4
        Memory.copy(target, source, 8)
    }

    let clipped = dst.mixed(src, -1, 1, .Copy)
    Swag.assert(Memory.compare(clipped.pixels.buffer, expected.buffer, expected.count) == 0)

    let outside = dst.mixed(src, 8, -5, .Copy)
    Swag.assert(Memory.compare(outside.pixels.buffer, dstPixels.buffer, dstPixels.count) == 0)
}
