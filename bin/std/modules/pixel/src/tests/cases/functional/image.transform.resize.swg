#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Run the existing scalar kernels directly so the reference never dispatches work.
private func serialFilteredResize(source: const *Image, width, height: s32, mode: Image.ResizeMode)->Image
{
    var convertedSource: Image
    var workSource       = source
    let needsPremultiply = source.pixelFormat.hasAlpha() and source.alphaMode == .Straight
    if needsPremultiply
    {
        convertedSource = source[].convertedTo(.RGBAF32)
        convertedSource.convertAlphaTo(.Premultiplied)
        workSource = &convertedSource
    }

    let outputAlphaMode     = needsPremultiply ? AlphaMode.Premultiplied : source.alphaMode
    let outputFormat        = needsPremultiply ? PixelFormat.RGBAF32 : source.pixelFormat
    var intermediate        = Image.create(width, source.height, outputFormat, alphaMode: outputAlphaMode)
    var result: #returntype = Image.create(width, height, outputFormat, alphaMode: outputAlphaMode)
    let horizontal          = ResizeTools.calcContributions(width, source.width, cast(f64, width) / source.width, mode)
    let vertical            = ResizeTools.calcContributions(height, source.height, cast(f64, height) / source.height, mode)
    let format              = workSource.pixelFormat
    let legacy              = format == .RGB8 or format == .RGBA8 or format == .BGR8 or format == .BGRA8
    for row in source.height
    {
        if legacy do
            ResizeTools.scaleRow(&intermediate, workSource, row, &horizontal)
        else do
            ResizeTools.scaleRowGeneric(&intermediate, workSource, row, &horizontal)
    }

    for column in width
    {
        if legacy do
            ResizeTools.scaleCol(&result, &intermediate, column, &vertical)
        else do
            ResizeTools.scaleColGeneric(&result, &intermediate, column, &vertical)
    }

    if needsPremultiply
    {
        result.convertAlphaTo(.Straight)
        return result.convertedTo(source.pixelFormat)
    }

    return result
}

#[Swag.TestTag("parallel")]
#test
{
    Swag.setWorkerCount(4)
    Swag.startWorkers()
    let formats:    [6] PixelFormat      = [.RGB8, .RGBA8, .BGRA8, .Gray8, .RGBA16, .RGBAF32]
    let modes:      [7] Image.ResizeMode = [.Bilinear, .Bicubic, .Gaussian, .Quadratic, .Hermite, .Hamming, .CatmullRom]
    let dimensions: [6] [2] s32          = [[31, 33], [32, 32], [33, 33], [1, 1031], [1031, 1], [97, 71]]
    var pattern = Image.create(67, 69, .RGBA8)
    for index in pattern.byteCount do
        pattern.pixels[index] = cast(u8, ((index * 47 + index / 13 + 29) & 0xFF))
    for format in formats
    {
        let source    = pattern.convertedTo(format)
        let unchanged = source
        for mode in modes
        {
            for size in dimensions
            {
                let expected = serialFilteredResize(&source, size[0], size[1], mode)
                let actual   = source.resized(size[0], size[1], mode)
                assertImage(actual, size[0], size[1], format)
                Swag.require(actual.alphaMode == source.alphaMode)
                Swag.require(Memory.compare(actual.pixels.storage(), expected.pixels.storage(), expected.byteCount) == 0)
                var inPlace = source
                inPlace.resize(size[0], size[1], mode)
                Swag.require(Memory.compare(inPlace.pixels.storage(), expected.pixels.storage(), expected.byteCount) == 0)
            }
        }

        Swag.require(Memory.compare(source.pixels.storage(), unchanged.pixels.storage(), source.byteCount) == 0)
    }
}

#[Swag.TestTag("parallel")]
#test
{
    Swag.setWorkerCount(4)
    Swag.startWorkers()
    var source = Image.create(63, 65, .RGBA8)
    for index in source.byteCount do
        source.pixels[index] = cast(u8, ((index * 31 + 7) & 0xFF))
    let expected  = serialFilteredResize(&source, 97, 71, .Bicubic)
    let reference = &expected
    parallel for |&source, reference| 7
    {
        let actual = source.resized(97, 71, .Bicubic)
        Swag.require(Memory.compare(actual.pixels.storage(), reference.pixels.storage(), reference.byteCount) == 0)
    }
}

#test
{
    let tall     = Image.create(1, 3, .RGB8)
    let tallCopy = tall.resized(0, 2, .Nearest)
    assertImage(tallCopy, 1, 2, .RGB8)
    var tallInPlace = tall
    tallInPlace.resize(0, 2, .Nearest)
    assertImage(tallInPlace, 1, 2, .RGB8)

    let wide     = Image.create(3, 1, .RGB8)
    let wideCopy = wide.resized(2, 0, .Nearest)
    assertImage(wideCopy, 2, 1, .RGB8)
    var wideInPlace = wide
    wideInPlace.resize(2, 0, .Nearest)
    assertImage(wideInPlace, 2, 1, .RGB8)
}

#test
{
    const rawPixels = [
        10'u8, 20'u8, 30'u8, 40'u8, 50'u8, 60'u8, 70'u8, 80'u8,
        90'u8, 100'u8, 110'u8, 120'u8, 130'u8, 140'u8, 150'u8, 160'u8]

    let rawSrc = makeImage(2, 2, .RGBA8, rawPixels)
    let rawOut = rawSrc.resized(4, 0, .Nearest)
    assertImage(rawOut, 4, 4, .RGBA8)

    assertPixel(rawOut, 0, 3, Color.fromArgb(40'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(rawOut, 1, 3, Color.fromArgb(40'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(rawOut, 2, 3, Color.fromArgb(80'u8, 50'u8, 60'u8, 70'u8))
    assertPixel(rawOut, 3, 3, Color.fromArgb(80'u8, 50'u8, 60'u8, 70'u8))
    assertPixel(rawOut, 0, 0, Color.fromArgb(120'u8, 90'u8, 100'u8, 110'u8))
    assertPixel(rawOut, 1, 0, Color.fromArgb(120'u8, 90'u8, 100'u8, 110'u8))
    assertPixel(rawOut, 2, 0, Color.fromArgb(160'u8, 130'u8, 140'u8, 150'u8))
    assertPixel(rawOut, 3, 0, Color.fromArgb(160'u8, 130'u8, 140'u8, 150'u8))

    const filteredPixels = [
        7'u8, 17'u8, 27'u8, 37'u8]

    let filteredSrc = makeImage(1, 1, .RGBA8, filteredPixels)
    let filteredOut = filteredSrc.resized(3, 2, .Bicubic)
    assertImage(filteredOut, 3, 2, .RGBA8)
    assertPixel(filteredOut, 0, 1, Color.fromArgb(37'u8, 7'u8, 17'u8, 27'u8))
    assertPixel(filteredOut, 2, 1, Color.fromArgb(37'u8, 7'u8, 17'u8, 27'u8))
    assertPixel(filteredOut, 0, 0, Color.fromArgb(37'u8, 7'u8, 17'u8, 27'u8))
    assertPixel(filteredOut, 2, 0, Color.fromArgb(37'u8, 7'u8, 17'u8, 27'u8))
}

#test
{
    const edgePixels = [17'u8, 91, 203, 0, 255, 0, 0, 255]
    let straight      = Image.create(2, 1, .RGBA8, edgePixels)
    var premultiplied = Image.create(2, 1, .RGBA8, edgePixels)
    premultiplied.convertAlphaTo(.Premultiplied)

    for mode in [Image.ResizeMode.Bilinear, Image.ResizeMode.Bicubic]
    {
        let straightResize = straight.resized(1, 1, mode)
        let premultResize  = premultiplied.resized(1, 1, mode)
        let expected       = premultResize.pixelColor(0, 0)

        Swag.require(straightResize.alphaMode == .Straight)
        Swag.require(premultResize.alphaMode == .Premultiplied)
        Swag.require(expected.r == 255 and expected.g == 0 and expected.b == 0)
        Swag.require(expected.a > 0 and expected.a < 255)
        if mode == .Bilinear do
            Swag.require(expected.a == 85)
        assertPixel(straightResize, 0, 0, expected)
    }

    let nearest = straight.resized(4, 1, .Nearest)
    Swag.require(nearest.alphaMode == .Straight)
    Swag.require(Memory.compare(nearest.pixels.storage(), edgePixels.buffer, 4) == 0)
    assertPixel(nearest, 3, 0, Color.fromArgb(255'u8, 255, 0, 0))
    Swag.require(Memory.compare(straight.pixels.storage(), edgePixels.buffer, edgePixels.count) == 0)

    let single = Image.create(1, 1, .RGBA8, [7'u8, 17, 27, 37]).resized(3, 2, .Bicubic)
    assertPixel(single, 0, 1, Color.fromArgb(37'u8, 7, 17, 27))
}
