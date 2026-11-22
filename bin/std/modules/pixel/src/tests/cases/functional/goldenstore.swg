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
            let delta = cast(u8,
                             Math.max(Math.abs(cast(s32, left.r) - right.r),
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
        Swag.require(result.sameSize == reference.sameSize)
        Swag.require(result.differentPixels == reference.differentPixels)
        Swag.require(result.maxChannelDelta == reference.maxChannelDelta)
        Swag.require(result.firstX == reference.firstX and result.firstY == reference.firstY)
        Swag.require(result.firstExpected == reference.firstExpected and result.firstActual == reference.firstActual)
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
            var changed = Image.create(expected.width, expected.height, format, Swag.makeSlice(expected.pixels.storage(), expected.pixels.count), association)
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

// A text golden cannot be recorded below a path occupied by a file.
#test
{
    var blockerName = String.from("pixel-golden-write-blocker-")
    blockerName += Guid64.random().toString()
    let blocker = Path.combine(Env.getSpecialDirectory(.Temp).toString(), blockerName)
    discard expect File.writeAllBytes(blocker.toString(), [0'u8])
    defer discard catch File.delete(blocker.toString())

    let missing = Path.combine(blocker, "missing.txt")
    Swag.require(not Testing.writeGoldenText(missing.toString(), "golden"))
}

func setGray(image: *Image, x, y: s32, level: u8)
{
    let pixel = image.pixels.storage() + cast(u64, y) * image.rowStride + cast(u64, x) * 4
    pixel[0] = level
    pixel[1] = level
    pixel[2] = level
    pixel[3] = 255
}

func grayAt(image: const *Image, x, y: s32)->u8
{
    return image.pixels.storage()[cast(u64, y) * image.rowStride + cast(u64, x) * 4]
}

// A dark ground carrying a bright box and a two-pixel rule, moved right by `shift` pixels.
func paintGpuScene(shift: s32 = 0, withRule = true)->Image
{
    var result = Image.create(32, 24, .RGBA8)
    for y in result.height
    {
        for x in result.width
        {
            let sourceX = x - shift
            var level   = 30'u8
            if withRule and sourceX >= 4 and sourceX < 28 and y >= 18 and y < 20 do
                level = 160
            if sourceX >= 8 and sourceX < 20 and y >= 4 and y < 14 do
                level = 200
            setGray(&result, x, y, level)
        }
    }

    return result
}

func gpuDifferences(reference, drawn: const *Image)->u64
{
    return Testing.compareGpuImage(reference, drawn, {maxChannelDelta: 3}).differentPixels
}

// What separates two graphics devices passes: rounding everywhere, a softer edge, a lone pixel.
#test
{
    let reference = paintGpuScene()

    var rounded = paintGpuScene()
    for y in rounded.height
    {
        for x in rounded.width do
            setGray(&rounded, x, y, grayAt(&reference, x, y) + 3)
    }

    Swag.require(gpuDifferences(&reference, &rounded) == 0)

    var softened = paintGpuScene()
    for y in 4 until 14
    {
        setGray(&softened, 7, y, 85)
        setGray(&softened, 8, y, 145)
    }

    Swag.require(gpuDifferences(&reference, &softened) == 0)

    var speck = paintGpuScene()
    setGray(&speck, 2, 2, 255)
    Swag.require(gpuDifferences(&reference, &speck) == 0)
}

// A shape that moved, disappeared or changed color stays a difference on any device.
#test
{
    let reference = paintGpuScene()

    let moved = paintGpuScene(shift: 1)
    Swag.require(gpuDifferences(&reference, &moved) != 0)

    let ruleless = paintGpuScene(withRule: false)
    Swag.require(gpuDifferences(&reference, &ruleless) != 0)

    var tinted = paintGpuScene()
    for y in 2 until 10
    {
        for x in 22 until 30 do
            setGray(&tinted, x, y, 36)
    }

    Swag.require(gpuDifferences(&reference, &tinted) != 0)

    let resized = Image.create(16, 24, .RGBA8)
    Swag.require(not Testing.compareGpuImage(&reference, &resized, {}).sameSize)
}

// Where a pixel centre meets a texel boundary each renderer picks a side, which moves one
// boundary by one pixel. The comparison accepts that when asked to, and nothing more: a boundary
// two pixels off and a missing rule are still differences.
#test
{
    let reference = paintGpuScene()

    func differences(reference, drawn: const *Image, acceptEdgeChoice: bool)->u64
    {
        return Testing.compareGpuImage(reference, drawn, {maxChannelDelta: 3, acceptEdgeChoice: acceptEdgeChoice}).differentPixels
    }

    // The box reaches one row lower.
    var grown = paintGpuScene()
    for x in 8 until 20 do
        setGray(&grown, x, 14, 200)
    Swag.require(differences(&reference, &grown, false) != 0)
    Swag.require(differences(&reference, &grown, true) == 0)

    // The box reaches two rows lower.
    var overgrown = paintGpuScene()
    for x in 8 until 20
    {
        setGray(&overgrown, x, 14, 200)
        setGray(&overgrown, x, 15, 200)
    }

    Swag.require(differences(&reference, &overgrown, true) != 0)

    // A one-pixel rule is added to the reference, then lost by the drawn image.
    var ruled = paintGpuScene()
    for x in 4 until 28 do
        setGray(&ruled, x, 22, 160)
    Swag.require(differences(&ruled, &reference, true) != 0)
}
