#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private func simdTailSeed(width, height: s32, pf: PixelFormat)->Array'u8
{
    let bytesPerPixel = cast(u64) (pf.bitsPerPixel() >> 3)
    var result: retval
    result.resize(cast(u64) (width * height) * bytesPerPixel)
    for index in result.count do
        result[index] = cast(u8) ((index * 37 + 11) & 0xFF)
    if pf.hasAlpha()
    {
        for pixel in cast(u64) (width * height) do
            result[pixel * 4 + 3] = pixel % 3 == 0 ? 0 : cast(u8) ((pixel * 13 + 17) & 0xFF)
    }

    return result
}

private func simdTailAssertBytes(image: const *Image, expected: const *Array'u8, stage: string, pf: PixelFormat, width: s32)
{
    @assert(image.byteCount == expected.count)
    if Memory.compare(image.pixels.buffer, expected.buffer, expected.count) != 0
    {
        for index in expected.count
        {
            if image.pixels.buffer![index] != expected[index]
            {
                Console.printf("SIMD tail mismatch: stage=%, format=%, width=%, byte=%, actual=%, expected=%\n", stage, cast(u32) pf, width, index, image.pixels.buffer![index], expected[index])
                break
            }
        }

        @assert(false)
    }
}

private func simdTailCheckFilters(pf: PixelFormat, width: s32)
{
    const Height = 3
    let bytesPerPixel = cast(u64) (pf.bitsPerPixel() >> 3)

    var expected = simdTailSeed(width, Height, pf)
    var image    = Image.create(width, Height, pf, expected.toSlice())
    for pixel in cast(u64) (width * Height)
    {
        for channel in 3 do
            expected[pixel * bytesPerPixel + channel] ^= 255
    }

    image.invert()
    simdTailAssertBytes(&image, &expected, "invert", pf, width)

    expected = simdTailSeed(width, Height, pf)
    image    = Image.create(width, Height, pf, expected.toSlice())
    for pixel in cast(u64) (width * Height)
    {
        for channel in 3
        {
            let offset = pixel * bytesPerPixel + channel
            expected[offset] = cast(u8) Math.min(cast(s32) expected[offset] + 51, 255)
        }
    }

    image.lightness(0.2)
    simdTailAssertBytes(&image, &expected, "lightness", pf, width)

    expected = simdTailSeed(width, Height, pf)
    image    = Image.create(width, Height, pf, expected.toSlice())
    let blueFirst = pf == .BGR8 or pf == .BGRA8
    let weight0   = blueFirst ? 19's32 : 54's32
    let weight2   = blueFirst ? 54's32 : 19's32
    for pixel in cast(u64) (width * Height)
    {
        let offset = pixel * bytesPerPixel
        let gray   = cast(u8) ((expected[offset] * weight0 + expected[offset + 1] * 183's32 + expected[offset + 2] * weight2) >> 8)
        expected[offset]     = gray
        expected[offset + 1] = gray
        expected[offset + 2] = gray
    }

    image.grayscale()
    simdTailAssertBytes(&image, &expected, "grayscale", pf, width)

    let source = simdTailSeed(width, Height, pf)
    expected.resize(source.count)
    for row in Height
    {
        for x in width
        {
            let srcOffset = (cast(u64) row * cast(u64) width + cast(u64) (width - x - 1)) * bytesPerPixel
            let dstOffset = (cast(u64) row * cast(u64) width + cast(u64) x) * bytesPerPixel
            Memory.copy(expected.buffer + dstOffset, source.buffer + srcOffset, bytesPerPixel)
        }
    }

    let mirrored = Image.create(width, Height, pf, source.toSlice()).mirrored()
    simdTailAssertBytes(&mirrored, &expected, "mirror", pf, width)

    expected = simdTailSeed(width, Height, pf)
    image    = Image.create(width, Height, pf, expected.toSlice())
    if pf == .BGR8 or pf == .BGRA8
    {
        for pixel in cast(u64) (width * Height)
        {
            let offset = pixel * bytesPerPixel
            expected[offset]     = 73
            expected[offset + 1] = 73
            expected[offset + 2] = 73
        }
    }

    image.setChannel(.RGB, .Color, 73)
    simdTailAssertBytes(&image, &expected, "setChannel", pf, width)

    if pf == .BGRA8
    {
        expected = simdTailSeed(width, Height, pf)
        image    = Image.create(width, Height, pf, expected.toSlice())
        for pixel in cast(u64) (width * Height) do
            expected[pixel * 4 + 3] = 91
        image.setAlpha(91)
        simdTailAssertBytes(&image, &expected, "setAlpha", pf, width)
    }

    if pf.hasAlpha()
    {
        expected = simdTailSeed(width, Height, pf)
        image    = Image.create(width, Height, pf, expected.toSlice())
        for pixel in cast(u64) (width * Height)
        {
            let offset = pixel * 4
            if expected[offset + 3] == 0
            {
                expected[offset]     = blueFirst ? 177 : 23
                expected[offset + 1] = 91
                expected[offset + 2] = blueFirst ? 23 : 177
            }
        }

        image.setTransparentColor(Color.fromRgb(23, 91, 177))
        simdTailAssertBytes(&image, &expected, "setTransparentColor", pf, width)
    }
}

private func simdTailCheckConversion(srcPf, dstPf: PixelFormat, width: s32)
{
    const Height = 3
    let sourceBytes = simdTailSeed(width, Height, srcPf)
    let srcBpp      = cast(u64) (srcPf.bitsPerPixel() >> 3)
    let dstBpp      = cast(u64) (dstPf.bitsPerPixel() >> 3)
    let srcBlue     = srcPf == .BGR8 or srcPf == .BGRA8
    let dstBlue     = dstPf == .BGR8 or dstPf == .BGRA8
    var expected: Array'u8
    expected.resize(cast(u64) (width * Height) * dstBpp)
    for pixel in cast(u64) (width * Height)
    {
        let source = sourceBytes.buffer! + pixel * srcBpp
        let target = expected.buffer! + pixel * dstBpp
        let red    = srcBlue ? source[2] : source[0]
        let blue   = srcBlue ? source[0] : source[2]
        target[0] = dstBlue ? blue : red
        target[1] = source[1]
        target[2] = dstBlue ? red : blue
        if dstBpp == 4 do
            target[3] = srcBpp == 4 ? source[3] : 255
    }

    let converted = Image.create(width, Height, srcPf, sourceBytes.toSlice()).convertedTo(dstPf)
    simdTailAssertBytes(&converted, &expected, "conversion", dstPf, width)
}

#test
{
    for bytesPerPixel in [3'u64, 4'u64]
    {
        for width in 20'u64
        {
            let pixelCount = width + 1
            var source:   Array'u8
            var actual:   Array'u8
            var expected: Array'u8
            source.resize(1 + pixelCount * bytesPerPixel + 1)
            actual.resize(3 + pixelCount * bytesPerPixel + 1)
            expected.resize(actual.count)
            for i in source.count do
                source[i] = cast(u8) ((i * 31 + 7) & 0xFF)
            for i in actual.count
            {
                actual[i]   = 0xA5
                expected[i] = 0xA5
            }

            for pixel in pixelCount
            {
                let srcOffset = 1 + pixel * bytesPerPixel
                let dstOffset = 3 + pixel * bytesPerPixel
                expected[dstOffset]     = source[srcOffset + 2]
                expected[dstOffset + 1] = source[srcOffset + 1]
                expected[dstOffset + 2] = source[srcOffset]
                if bytesPerPixel == 4 do
                    expected[dstOffset + 3] = source[srcOffset + 3]
            }

            if bytesPerPixel == 3 do
                PackedPixel.swapRedBlue24Row(source.buffer! + 1, actual.buffer! + 3, pixelCount)
            else do
                PackedPixel.swapRedBlue32Row(source.buffer! + 1, actual.buffer! + 3, pixelCount)
            for i in actual.count do
                @assert(actual[i] == expected[i])
        }
    }
}

#test
{
    for width in 19
    {
        let actualWidth = width + 1
        simdTailCheckFilters(.BGR8, actualWidth)
        simdTailCheckFilters(.RGB8, actualWidth)
        simdTailCheckFilters(.BGRA8, actualWidth)
        simdTailCheckFilters(.RGBA8, actualWidth)

        simdTailCheckConversion(.BGR8, .RGB8, actualWidth)
        simdTailCheckConversion(.BGR8, .BGRA8, actualWidth)
        simdTailCheckConversion(.BGR8, .RGBA8, actualWidth)
        simdTailCheckConversion(.RGB8, .BGR8, actualWidth)
        simdTailCheckConversion(.RGB8, .BGRA8, actualWidth)
        simdTailCheckConversion(.RGB8, .RGBA8, actualWidth)
        simdTailCheckConversion(.BGRA8, .BGR8, actualWidth)
        simdTailCheckConversion(.BGRA8, .RGB8, actualWidth)
        simdTailCheckConversion(.BGRA8, .RGBA8, actualWidth)
        simdTailCheckConversion(.RGBA8, .BGR8, actualWidth)
        simdTailCheckConversion(.RGBA8, .RGB8, actualWidth)
        simdTailCheckConversion(.RGBA8, .BGRA8, actualWidth)
    }
}
