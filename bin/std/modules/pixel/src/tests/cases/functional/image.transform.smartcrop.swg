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

// Scoring prefers a crop containing contrast, and multiscale search returns the requested aspect.
#test
{
    var source = Image.create(64, 32, .Gray8)
    for y in 8
    {
        for x in 8
        {
            source.pixels.storage()[(y + 4) * source.width + (x + 4)] = 255
        }
    }

    var opts: Image.SmartCropSearchOpts = {}
    opts.thirdsWeight = 0
    opts.centerWeight = 0
    opts.shrinkPrior  = 0
    opts.edgePenalty  = 0
    opts.maxSize      = 32

    var focusedRect: Math.Rectangle = {width: 16, height: 16}
    var emptyRect:   Math.Rectangle = {x: 16, width: 16, height: 16}
    let focusedScore                = source.evaluateCropScore(focusedRect, opts)
    let emptyScore                  = source.evaluateCropScore(emptyRect, opts)
    Swag.require(focusedScore > emptyScore)

    opts.maxSearchSteps = 1     // Values below the documented range still produce a valid search.
    var target: Math.Rectangle = {width: 1, height: 1}
    var cropped = source
    cropped.smartCrop(target, opts)
    Swag.require(cropped.width == cropped.height)
    Swag.require(source.width == 64 and source.height == 32)
}

// A square cover retains the header of a portrait scan with a dark line at the bottom.
#test
{
    var source = Image.create(140, 160, .RGB8)
    source.visitPixels()
    {
        let row    = image.height - 1 - y
        let header = x >= 57 and x < 83 and (row == 7 or row == 9)
        let text   = x >= 35 and x < 105 and row >= 24 and row < 80 and row % 5 < 2
        let paper  = cast(u8, 250 - Math.max(row - 125, 0) / 2)
        let bottom = row == image.height - 1 and x >= 90
        let ink    = bottom ? 0'u8 : 80
        let dark   = text or bottom
        pix[0] = header ? 190 : dark ? ink : 253
        pix[1] = header ? 223 : dark ? ink : 250
        pix[2] = header ? 173 : dark ? ink : paper
    }

    let attention = source.smartCropRect(1)
    Swag.require(attention.width == 140 and attention.height == 140)
    Swag.require(attention.y <= 7 and attention.bottom() >= 80)
    Swag.require(source.smartCropRect(1, .Center) == Math.Rectangle{0, 10, 140, 140})
    Swag.require(source.smartCropRect(1, .None) == Math.Rectangle{0, 0, 140, 160})
    Swag.require(source.pixelColor(60, 7) == Color.fromRgb(190, 223, 173))
}

// Entropy follows textured strips and covers even a thin target without rounding its aspect.
#test
{
    var source = Image.create(80, 40, .Gray8)
    source.fill(Color.fromRgb(64, 64, 64))
    source.visitPixels()
    {
        if x >= 60 do
            pix[0] = cast(u8, (x + y) % 2 == 0 ? 20 : 220)
    }

    let entropy = source.smartCropRect(1, .Entropy)
    Swag.require(entropy.x > 20 and entropy.right() == 80)
    let thin = source.smartCropRect(0.01, .Center)
    Swag.require(Math.abs(thin.width - 0.4) < 0.001 and thin.height == 40)
}
