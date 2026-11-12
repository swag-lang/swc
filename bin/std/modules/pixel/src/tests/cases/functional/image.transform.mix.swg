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
    const destination = [17'u8, 31, 47, 63]
    const source      = [101'u8, 103, 107, 109]
    let mixed = makeImage(1, 1, .RGBA8, destination).mixed(makeImage(1, 1, .RGBA8, source), Swag.S32.Max, 0)
    assertPixel(mixed, 0, 0, Color.fromArgb(63'u8, 17'u8, 31'u8, 47'u8))
}

#test
{
    const destination = [17'u8, 31, 47, 63]
    const source      = [101'u8, 103, 107, 109]
    var image   = makeImage(1, 1, .RGBA8, destination)
    let overlay = makeImage(1, 1, .RGBA8, source)

    image.mix(overlay, Swag.S32.Max, 0)
    assertPixel(image, 0, 0, Color.fromArgb(63'u8, 17'u8, 31'u8, 47'u8))
    image.mix(overlay, 0, Swag.S32.Min)
    assertPixel(image, 0, 0, Color.fromArgb(63'u8, 17'u8, 31'u8, 47'u8))
}

#test
{
    const destination = [17'u8, 31, 47, 63]
    const source      = [101'u8, 103, 107, 109]
    let mixed = makeImage(1, 1, .RGBA8, destination).mixed(makeImage(1, 1, .RGBA8, source), 0, Swag.S32.Max)
    assertPixel(mixed, 0, 0, Color.fromArgb(63'u8, 17'u8, 31'u8, 47'u8))
}

#test
{
    const destination = [17'u8, 31, 47, 63]
    const source      = [101'u8, 103, 107, 109]
    let mixed = makeImage(1, 1, .RGBA8, destination).mixed(makeImage(1, 1, .RGBA8, source), Swag.S32.Min, 0)
    assertPixel(mixed, 0, 0, Color.fromArgb(63'u8, 17'u8, 31'u8, 47'u8))
}

#test
{
    const destination = [17'u8, 31, 47, 63]
    const source      = [101'u8, 103, 107, 109]
    let mixed = makeImage(1, 1, .RGBA8, destination).mixed(makeImage(1, 1, .RGBA8, source), 0, Swag.S32.Min)
    assertPixel(mixed, 0, 0, Color.fromArgb(63'u8, 17'u8, 31'u8, 47'u8))
}

#test
{
    var dstPixels: [48] u8
    for index in dstPixels.count do
        dstPixels[index] = cast(u8, (index * 3 + 1))
    var srcPixels: [24] u8
    for index in srcPixels.count do
        srcPixels[index] = cast(u8, (index * 5 + 7))

    let dst = makeImage(4, 3, .RGBA8, dstPixels)
    let src = makeImage(3, 2, .RGBA8, srcPixels)

    var expected: Array'u8
    expected.resize(dstPixels.count)
    Memory.copy(expected.storage(), dstPixels.buffer, expected.count)
    for row in 2
    {
        let target = expected.storage() + cast(u64, (row + 1)) * 16
        let source = srcPixels.buffer + cast(u64, row) * 12 + 4
        Memory.copy(target, source, 8)
    }

    let clipped = dst.mixed(src, -1, 1, .Copy)
    Swag.require(Memory.compare(clipped.pixels.storage(), expected.storage(), expected.count) == 0)

    let outside = dst.mixed(src, 8, -5, .Copy)
    Swag.require(Memory.compare(outside.pixels.storage(), dstPixels.buffer, dstPixels.count) == 0)
}

// SourceOver keeps small positive floating alpha values; only an exactly transparent result has
// no color to unassociate.
#test
{
    var dst         = Image.create(1, 1, .RGBAF32)
    var src         = Image.create(1, 1, .RGBAF32)
    var dstChannels = cast([*] f32, dst.pixels.storage())
    var srcChannels = cast([*] f32, src.pixels.storage())
    for channel in 4
    {
        dstChannels[channel] = 0
        srcChannels[channel] = 0
    }

    srcChannels[0] = 1
    srcChannels[3] = 0.00000001'f32

    let mixed         = dst.mixed(src, 0, 0, .SourceOver)
    let mixedChannels = cast(const [*] f32, mixed.pixels.storage())
    Swag.require(mixedChannels[0] == 1.0'f32 and mixedChannels[3] == 0.00000001'f32)

    let copied         = dst.mixed(src, 0, 0, .Copy)
    let copiedChannels = cast(const [*] f32, copied.pixels.storage())
    Swag.require(copiedChannels[0] == 1.0'f32 and copiedChannels[3] == 0.00000001'f32)

    dst.mix(src, 0, 0, .SourceOver)
    let inPlaceChannels = cast(const [*] f32, dst.pixels.storage())
    Swag.require(inPlaceChannels[0] == 1.0'f32 and inPlaceChannels[3] == 0.00000001'f32)

    var transparent         = Image.create(1, 1, .RGBAF32)
    let transparentChannels = cast([*] f32, transparent.pixels.storage())
    transparentChannels[0] = 0.7
    transparentChannels[1] = 0.6
    transparentChannels[2] = 0.5
    transparentChannels[3] = 0
    srcChannels[3]         = 0
    let zeroResult   = transparent.mixed(src, 0, 0, .SourceOver)
    let zeroChannels = cast(const [*] f32, zeroResult.pixels.storage())
    Swag.require(zeroChannels[0] == 0 and zeroChannels[1] == 0 and zeroChannels[2] == 0 and zeroChannels[3] == 0)

    const dstBytes = [0'u8, 0, 0, 0]
    const srcBytes = [255'u8, 0, 0, 1]
    let byteMix = makeImage(1, 1, .RGBA8, dstBytes).mixed(makeImage(1, 1, .RGBA8, srcBytes), 0, 0, .SourceOver)
    assertPixel(byteMix, 0, 0, Color.fromArgb(1'u8, 255'u8, 0'u8, 0'u8))
}
