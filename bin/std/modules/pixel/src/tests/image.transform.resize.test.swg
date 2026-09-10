#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Run the existing scalar kernels directly so the reference never dispatches work.
private func serialFilteredResize(source: const *Image, width, height: s32, mode: Image.ResizeMode)->Image
{
    var intermediate   = Image.create(width, source.height, source.pixelFormat, alphaMode: source.alphaMode)
    var result: retval = Image.create(width, height, source.pixelFormat, alphaMode: source.alphaMode)
    let horizontal     = ResizeTools.calcContributions(width, source.width, cast(f64) width / source.width, mode)
    let vertical       = ResizeTools.calcContributions(height, source.height, cast(f64) height / source.height, mode)
    let format         = source.pixelFormat
    let legacy         = format == .RGB8 or format == .RGBA8 or format == .BGR8 or format == .BGRA8
    for row in source.height
    {
        if legacy do
            ResizeTools.scaleRow(&intermediate, source, row, &horizontal)
        else do
            ResizeTools.scaleRowGeneric(&intermediate, source, row, &horizontal)
    }

    for column in width
    {
        if legacy do
            ResizeTools.scaleCol(&result, &intermediate, column, &vertical)
        else do
            ResizeTools.scaleColGeneric(&result, &intermediate, column, &vertical)
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
        pattern.pixels[index] = cast(u8) ((index * 47 + index / 13 + 29) & 0xFF)
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
                Swag.assert(actual.alphaMode == source.alphaMode)
                Swag.assert(Memory.compare(actual.pixels.buffer, expected.pixels.buffer, expected.byteCount) == 0)
                var inPlace = source
                inPlace.resize(size[0], size[1], mode)
                Swag.assert(Memory.compare(inPlace.pixels.buffer, expected.pixels.buffer, expected.byteCount) == 0)
            }
        }

        Swag.assert(Memory.compare(source.pixels.buffer, unchanged.pixels.buffer, source.byteCount) == 0)
    }
}

#[Swag.TestTag("parallel")]
#test
{
    Swag.setWorkerCount(4)
    Swag.startWorkers()
    var source = Image.create(63, 65, .RGBA8)
    for index in source.byteCount do
        source.pixels[index] = cast(u8) ((index * 31 + 7) & 0xFF)
    let expected  = serialFilteredResize(&source, 97, 71, .Bicubic)
    let reference = &expected
    parallel for |&source, reference| iteration in 7
    {
        let actual = source.resized(97, 71, .Bicubic)
        Swag.assert(Memory.compare(actual.pixels.buffer, reference.pixels.buffer, reference.byteCount) == 0)
    }
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
