#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// The reference deliberately reads logical colors, including unassociated translucent pixels.
func referenceDifference(expected, actual: const *Image, tolerance: u8)->Testing.ImageDifference
{
    var result: #returntype
    result.sameSize = expected.width == actual.width and expected.height == actual.height
    if not result.sameSize do
        return result
    for y in actual.height
    {
        for x in actual.width
        {
            let left  = expected.pixelColor(x, y)
            let right = actual.pixelColor(x, y)
            let delta = cast(u8, Math.max(Math.abs(cast(s32, left.r) - right.r),
                                         Math.abs(cast(s32, left.g) - right.g),
                                         Math.abs(cast(s32, left.b) - right.b),
                                         Math.abs(cast(s32, left.a) - right.a)))
            result.maxChannelDelta = Math.max(result.maxChannelDelta, delta)
            if delta <= tolerance do
                continue
            result.differentPixels += 1
            if result.differentPixels == 1
            {
                result.firstX        = x
                result.firstY        = y
                result.firstExpected = left
                result.firstActual   = right
            }
        }
    }

    return result
}

func checkDifference(expected, actual: const *Image)
{
    for tolerance in [0'u8, 1'u8, 17'u8, 255'u8]
    {
        let reference = referenceDifference(expected, actual, tolerance)
        let result    = Testing.compareImages(expected, actual, {maxChannelDelta: tolerance})
        Swag.assert(result.sameSize == reference.sameSize)
        Swag.assert(result.differentPixels == reference.differentPixels)
        Swag.assert(result.maxChannelDelta == reference.maxChannelDelta)
        Swag.assert(result.firstX == reference.firstX and result.firstY == reference.firstY)
        Swag.assert(result.firstExpected == reference.firstExpected and result.firstActual == reference.firstActual)
    }
}

// Channel order, alpha association, transparent colors, non-byte formats, and every byte value
// must produce the same diagnostics and tolerance decisions as the general image reader.
#test
{
    var source = Image.create(256, 3, .RGBA8)
    for y in source.height
    {
        for x in source.width
        {
            let pixel = source.pixels.storage() + cast(u64, y) * source.rowStride + cast(u64, x) * 4
            pixel[0] = cast(u8, x)
            pixel[1] = cast(u8, 255 - x)
            pixel[2] = cast(u8, (x * 71) % 256)
            pixel[3] = y == 0 ? 255'u8 : cast(u8, x)
        }
    }

    for format in [PixelFormat.RGB8, .BGR8, .RGBA8, .BGRA8, .RGBA16, .RGBAF32]
    {
        for association in [AlphaMode.Straight, .Premultiplied]
        {
            if association == .Premultiplied and not format.hasAlpha() do
                continue
            var expected = source.convertedTo(format)
            if format.hasAlpha() do
                expected.convertAlphaTo(association)
            checkDifference(&expected, &expected)
            checkDifference(&source, &expected)
            var changed = Image.create(expected.width, expected.height, format,
                                       Swag.makeSlice(expected.pixels.storage(), expected.pixels.count), association)
            changed.pixels[17] = 35
            changed.pixels[changed.rowStride + 7] = 71
            checkDifference(&expected, &changed)
            checkDifference(&source, &changed)
        }
    }
}

#test
{
    let expected = Image.create(3, 2, .RGBA8)
    let actual   = Image.create(2, 3, .BGRA8)
    checkDifference(&expected, &actual)
}
