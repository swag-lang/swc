#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const dstPixels = [
        10_u8, 20_u8, 30_u8, 200_u8, 40_u8, 50_u8, 60_u8, 201_u8, 70_u8, 80_u8, 90_u8, 202_u8,
        100_u8, 110_u8, 120_u8, 203_u8, 130_u8, 140_u8, 150_u8, 204_u8, 160_u8, 170_u8, 180_u8, 205_u8]

    const copyPixels = [
        1_u8, 2_u8, 3_u8, 4_u8, 5_u8, 6_u8, 7_u8, 8_u8]

    const blendPixels = [
        200_u8, 210_u8, 220_u8, 128_u8, 0_u8, 10_u8, 20_u8, 64_u8]

    let dst     = makeImage(3, 2, .RGBA8, dstPixels)
    let srcCopy = makeImage(2, 1, .RGBA8, copyPixels)
    let copied  = dst.mixed(srcCopy, 1, 0, .Copy)
    assertImage(copied, 3, 2, .RGBA8)

    assertPixel(copied, 0, 1, Color.fromArgb(200_u8, 10_u8, 20_u8, 30_u8))
    assertPixel(copied, 1, 1, Color.fromArgb(4_u8, 1_u8, 2_u8, 3_u8))
    assertPixel(copied, 2, 1, Color.fromArgb(8_u8, 5_u8, 6_u8, 7_u8))
    assertPixel(copied, 0, 0, Color.fromArgb(203_u8, 100_u8, 110_u8, 120_u8))

    let srcBlend = makeImage(2, 1, .RGBA8, blendPixels)
    let blended  = dst.mixed(srcBlend, 0, 1, .SourceOver)
    assertImage(blended, 3, 2, .RGBA8)

    assertPixel(blended, 0, 0, Color.fromArgb(229_u8, 156_u8, 166_u8, 176_u8))
    assertPixel(blended, 1, 0, Color.fromArgb(217_u8, 92_u8, 102_u8, 112_u8))
    assertPixel(blended, 2, 0, Color.fromArgb(205_u8, 160_u8, 170_u8, 180_u8))
}

#test
{
    const destination = [17_u8, 31, 47, 63]
    const source      = [101_u8, 103, 107, 109]
    let mixed = makeImage(1, 1, .RGBA8, destination).mixed(makeImage(1, 1, .RGBA8, source), Swag.S32.Max, 0)
    assertPixel(mixed, 0, 0, Color.fromArgb(63_u8, 17_u8, 31_u8, 47_u8))
}

#test
{
    const destination = [17_u8, 31, 47, 63]
    const source      = [101_u8, 103, 107, 109]
    var image   = makeImage(1, 1, .RGBA8, destination)
    let overlay = makeImage(1, 1, .RGBA8, source)

    image.mix(overlay, Swag.S32.Max, 0)
    assertPixel(image, 0, 0, Color.fromArgb(63_u8, 17_u8, 31_u8, 47_u8))
    image.mix(overlay, 0, Swag.S32.Min)
    assertPixel(image, 0, 0, Color.fromArgb(63_u8, 17_u8, 31_u8, 47_u8))
}

#test
{
    const destination = [17_u8, 31, 47, 63]
    const source      = [101_u8, 103, 107, 109]
    let mixed = makeImage(1, 1, .RGBA8, destination).mixed(makeImage(1, 1, .RGBA8, source), 0, Swag.S32.Max)
    assertPixel(mixed, 0, 0, Color.fromArgb(63_u8, 17_u8, 31_u8, 47_u8))
}

#test
{
    const destination = [17_u8, 31, 47, 63]
    const source      = [101_u8, 103, 107, 109]
    let mixed = makeImage(1, 1, .RGBA8, destination).mixed(makeImage(1, 1, .RGBA8, source), Swag.S32.Min, 0)
    assertPixel(mixed, 0, 0, Color.fromArgb(63_u8, 17_u8, 31_u8, 47_u8))
}

#test
{
    const destination = [17_u8, 31, 47, 63]
    const source      = [101_u8, 103, 107, 109]
    let mixed = makeImage(1, 1, .RGBA8, destination).mixed(makeImage(1, 1, .RGBA8, source), 0, Swag.S32.Min)
    assertPixel(mixed, 0, 0, Color.fromArgb(63_u8, 17_u8, 31_u8, 47_u8))
}

#test
{
    var dstPixels: [48] u8
    for index in dstPixels.count
    {
        dstPixels[index] = cast(u8, (index * 3 + 1))
    }

    var srcPixels: [24] u8
    for index in srcPixels.count
    {
        srcPixels[index] = cast(u8, (index * 5 + 7))
    }

    let dst = makeImage(4, 3, .RGBA8, dstPixels)
    let src = makeImage(3, 2, .RGBA8, srcPixels)

    var expected: Array!{u8}
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
    srcChannels[3] = 0.00000001_f32

    let mixed         = dst.mixed(src, 0, 0, .SourceOver)
    let mixedChannels = cast(const [*] f32, mixed.pixels.storage())
    Swag.require(mixedChannels[0] == 1.0_f32 and mixedChannels[3] == 0.00000001_f32)

    let copied         = dst.mixed(src, 0, 0, .Copy)
    let copiedChannels = cast(const [*] f32, copied.pixels.storage())
    Swag.require(copiedChannels[0] == 1.0_f32 and copiedChannels[3] == 0.00000001_f32)

    dst.mix(src, 0, 0, .SourceOver)
    let inPlaceChannels = cast(const [*] f32, dst.pixels.storage())
    Swag.require(inPlaceChannels[0] == 1.0_f32 and inPlaceChannels[3] == 0.00000001_f32)

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

    const dstBytes = [0_u8, 0, 0, 0]
    const srcBytes = [255_u8, 0, 0, 1]
    let byteMix = makeImage(1, 1, .RGBA8, dstBytes).mixed(makeImage(1, 1, .RGBA8, srcBytes), 0, 0, .SourceOver)
    assertPixel(byteMix, 0, 0, Color.fromArgb(1_u8, 255_u8, 0_u8, 0_u8))
}
