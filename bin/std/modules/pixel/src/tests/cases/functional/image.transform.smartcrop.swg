#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var samples: Array'f32
    samples.resize(5000)
    for i in 0 to 4095 do
        samples[i] = 0.1
    for i in 4096 to 4999 do
        samples[i] = 0.9

    let {a: low, b: high} = Image.estimatePercentiles(&samples, 5000, 0, 1)
    Swag.require(low == 0.1 and high == 0.9)

    for i in 0 to 903 do
        samples[i] = 0.9
    for i in 904 to 4999 do
        samples[i] = 0.1

    let {a: reversedLow, b: reversedHigh} = Image.estimatePercentiles(&samples, 5000, 0, 1)
    Swag.require(reversedLow == 0.1 and reversedHigh == 0.9)

    var smallSamples: Array'f32     = [0.8, 0.2, 0.5]
    let {a: smallLow, b: smallHigh} = Image.estimatePercentiles(&smallSamples, 3, 0, 1)
    Swag.require(smallLow == 0.2 and smallHigh == 0.8)
}

#test
{
    const pixels = [
        10'u8, 20'u8, 30'u8, 40'u8, 50'u8, 60'u8, 70'u8, 80'u8, 90'u8, 100'u8, 110'u8, 120'u8, 130'u8, 140'u8, 150'u8, 160'u8,
        170'u8, 180'u8, 190'u8, 200'u8, 210'u8, 220'u8, 230'u8, 240'u8, 15'u8, 25'u8, 35'u8, 45'u8, 55'u8, 65'u8, 75'u8, 85'u8]

    var src = makeImage(4, 2, .RGBA8, pixels)

    var opts: Image.SmartCropSearchOpts = {}
    opts.minCoverage = 1.0
    opts.maxSize     = 2

    var targetRect: Math.Rectangle = {}
    targetRect.width  = 4
    targetRect.height = 2

    src.smartCrop(targetRect, opts)
    assertImage(src, 4, 2, .RGBA8)
    assertPixel(src, 0, 1, Color.fromArgb(40'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(src, 3, 1, Color.fromArgb(160'u8, 130'u8, 140'u8, 150'u8))
    assertPixel(src, 0, 0, Color.fromArgb(200'u8, 170'u8, 180'u8, 190'u8))
    assertPixel(src, 3, 0, Color.fromArgb(85'u8, 55'u8, 65'u8, 75'u8))
}
