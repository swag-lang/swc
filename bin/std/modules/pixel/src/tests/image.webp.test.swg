#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func webpExpectedChannel(value: s32)->u8
{
    return cast(u8) Math.clamp(value, 0, 255)
}

func webpMultiplyHigh(value, coefficient: s32)->s32
{
    return (value * coefficient) >> 8
}

func assertWebpPixelFromTop(image: Image, x, y, r, g, b, a: u8)
{
    let color = image.pixelColor(x, y)
    Swag.assert(color.r == r)
    Swag.assert(color.g == g)
    Swag.assert(color.b == b)
    Swag.assert(color.a == a)
}

func checkWebpAgainstPng(fileName, goldenName: string, width, height: s32)
{
    let decoded = expect Image.load(getTestDataPath(fileName))
    Swag.assert(decoded.isValid())
    Swag.assert(decoded.width == width)
    Swag.assert(decoded.height == height)
    Swag.assert(decoded.pixelFormat == .RGBA8)

    let golden = expect Image.load(getTestDataPath(goldenName))
    Swag.assert(golden.width == width)
    Swag.assert(golden.height == height)
    for y in height do
        for x in width
        {
            let got  = decoded.pixelColor(x, y)
            let want = golden.pixelColor(x, y)
            Swag.assert(got.r == want.r)
            Swag.assert(got.g == want.g)
            Swag.assert(got.b == want.b)
            Swag.assert(got.a == want.a)
        }
}

func checkLossyWebp(fileName, goldenName: string, width, height: s32, withAlpha: bool)
{
    let decoded = expect Image.load(getTestDataPath(fileName))
    Swag.assert(decoded.isValid())
    Swag.assert(decoded.width == width)
    Swag.assert(decoded.height == height)
    Swag.assert(decoded.pixelFormat == .RGBA8)

    let golden     = expect Image.load(getTestDataPath(goldenName))
    let halfWidth  = (width + 1) / 2
    let halfHeight = (height + 1) / 2
    Swag.assert(golden.width == 2 * halfWidth)
    Swag.assert(golden.height == height + halfHeight + (withAlpha ? height : 0))

    for y in height
    {
        for x in width
        {
            // Both decoded images use the module's bottom-up row convention, so the reference
            // planes are read at the same internal row as the result.
            let sourceY   = y
            let luma      = cast(s32) golden.pixelColor(x, sourceY).r
            let cb        = cast(s32) golden.pixelColor(x / 2, height + sourceY / 2).r
            let cr        = cast(s32) golden.pixelColor(halfWidth + x / 2, height + sourceY / 2).r
            let expectedR = webpExpectedChannel((webpMultiplyHigh(luma, 19077) + webpMultiplyHigh(cr, 26149) - 14234) >> 6)
            let expectedG = webpExpectedChannel((webpMultiplyHigh(luma, 19077) - webpMultiplyHigh(cb, 6419) - webpMultiplyHigh(cr, 13320) + 8708) >> 6)
            let expectedB = webpExpectedChannel((webpMultiplyHigh(luma, 19077) + webpMultiplyHigh(cb, 33050) - 17685) >> 6)
            let expectedA = withAlpha ? golden.pixelColor(x, height + halfHeight + sourceY).r : 0xFF
            let got       = decoded.pixelColor(x, y)
            Swag.assert(got.r == expectedR)
            Swag.assert(got.g == expectedG)
            Swag.assert(got.b == expectedB)
            Swag.assert(got.a == expectedA)
        }
    }
}

func assertEncodedWebpRoundtrip(source: Image)
{
    let buffer = expect source.encode("memory.webp")
    let bytes  = nnBytes(buffer.toSlice())
    Swag.assert(bytes.count >= 21)
    Swag.assert(bytes[0] == 'R' and bytes[1] == 'I' and bytes[2] == 'F' and bytes[3] == 'F')
    Swag.assert(bytes[8] == 'W' and bytes[9] == 'E' and bytes[10] == 'B' and bytes[11] == 'P')
    Swag.assert(bytes[12] == 'V' and bytes[13] == 'P' and bytes[14] == '8' and bytes[15] == 'L')
    let riffSize = cast(u32) bytes[4] | (cast(u32) bytes[5] << 8) |
                   (cast(u32) bytes[6] << 16) | (cast(u32) bytes[7] << 24)
    Swag.assert(cast(u64) riffSize + 8 == bytes.count)

    let decoded = expect Image.decode("encoded.webp", bytes, {})
    Swag.assert(decoded.width == source.width)
    Swag.assert(decoded.height == source.height)
    Swag.assert(decoded.pixelFormat == .RGBA8)
    for y in source.height do
        for x in source.width
        {
            let got  = decoded.pixelColor(x, y)
            let want = source.pixelColor(x, y)
            Swag.assert(got.r == want.r)
            Swag.assert(got.g == want.g)
            Swag.assert(got.b == want.b)
            Swag.assert(got.a == want.a)
        }
}

// The decoder and encoder registries recognise WebP files.
#test
{
    Swag.assert(Image.canLoad("image.webp"))
    Swag.assert(!Image.canLoad("image.webm"))
    Swag.assert(Image.canSave("image.webp"))
}

// Lossless encoding preserves every channel and the image row orientation.
#test
{
    const pixels = [
        11'u8, 22'u8, 33'u8, 44'u8, 55'u8, 66'u8, 77'u8, 88'u8,
        91'u8, 102'u8, 113'u8, 124'u8, 135'u8, 146'u8, 157'u8, 168'u8,
        179'u8, 190'u8, 201'u8, 212'u8, 223'u8, 234'u8, 245'u8, 17'u8]
    let rgba = makeImage(3, 2, .RGBA8, pixels)
    assertEncodedWebpRoundtrip(rgba)
    assertEncodedWebpRoundtrip(rgba.convertedTo(.BGRA8))
    assertEncodedWebpRoundtrip(rgba.convertedTo(.RGB8))
    assertEncodedWebpRoundtrip(rgba.convertedTo(.BGR8))
}

// Backward-distance runs can span the VP8L maximum length and start a new run.
#test
{
    var source = Image.create(5000, 1, .RGBA8)
    source.fill(Color.fromArgb(37'u8, 19'u8, 73'u8, 211'u8))

    let buffer = expect source.encode("memory.webp")
    Swag.assert(buffer.count() < 128)
    assertEncodedWebpRoundtrip(source)
}

// Empty images are rejected before a VP8L payload is created.
#test
{
    var source: Image
    discard catch source.encode("memory.webp") as encodeError
    Swag.assert(encodeError != null)
}

// Decode an official VP8L fixture and compare every pixel with its PNG golden image.
#test
{
    checkWebpAgainstPng("gopher-doc.lossless.webp", "gopher-doc.lossless.png", 75, 100)
    checkWebpAgainstPng("gopher-doc.with-alpha.lossless.webp", "gopher-doc.with-alpha.png", 75, 100)
}

// The VP8L color-cache hash wraps its multiplication to 32 bits.
#test
{
    let decoded = expect Image.load(getTestDataPath("color-cache.lossless.webp"))
    Swag.assert(decoded.isValid())
    Swag.assert(decoded.width == 32)
    Swag.assert(decoded.height == 32)
    Swag.assert(decoded.pixelFormat == .RGBA8)
    assertWebpPixelFromTop(decoded, 0, 0, 165, 0, 67, 255)
    assertWebpPixelFromTop(decoded, 16, 16, 173, 0, 123, 255)
}

// The VP8L predictor reconstructs each channel with modulo-256 addition.
#test
{
    let decoded = expect Image.load(getTestDataPath("transforms.lossless.webp"))
    Swag.assert(decoded.isValid())
    Swag.assert(decoded.width == 32)
    Swag.assert(decoded.height == 32)
    Swag.assert(decoded.pixelFormat == .RGBA8)
    assertWebpPixelFromTop(decoded, 31, 0, 217, 155, 147, 77)
    assertWebpPixelFromTop(decoded, 0, 31, 93, 85, 15, 201)
}

// VP8L stores signed cross-color coefficients in their raw eight-bit representation.
#test
{
    let decoded = expect Image.load(getTestDataPath("cross-color.lossless.webp"))
    Swag.assert(decoded.isValid())
    Swag.assert(decoded.width == 32)
    Swag.assert(decoded.height == 32)
    Swag.assert(decoded.pixelFormat == .RGBA8)
    assertWebpPixelFromTop(decoded, 0, 0, 255, 0, 255, 255)
    assertWebpPixelFromTop(decoded, 16, 16, 31, 224, 79, 255)
}

// Metadata-only decoding reads dimensions without allocating the pixel buffer.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("gopher-doc.lossless.webp"))
    var options: DecodeOptions
    options.decodePixels = false
    let decoded = expect Image.decode("metadata.webp", bytes.toSlice(), options)
    Swag.assert(decoded.width == 75)
    Swag.assert(decoded.height == 100)
    Swag.assert(decoded.pixelFormat == .RGBA8)
    Swag.assert(!decoded.isValid())
}

// Invalid and truncated RIFF data fails before allocating an image.
#test
{
    let bad: [12] u8 = [
        'R', 'I', 'F', 'F', 4, 0, 0, 0, 'N', 'O', 'P', 'E']
    var decoded: Image
    decoded = catch Image.decode("bad.webp", Swag.makeSlice(&bad[0], bad.count), {}) as err5
    Swag.assert(err5 != null)

    let bytes = expect File.readAllBytes(getTestDataPath("gopher-doc.lossless.webp"))
    decoded = catch Image.decode("truncated.webp", Swag.makeSlice(bytes.buffer, 32), {}) as err7
    Swag.assert(err7 != null)
}

// Decode a VP8 fixture and compare it with the official split-plane YCbCr golden image.
#test
{
    checkLossyWebp("blue-purple-pink.lossy.webp", "blue-purple-pink.lossy.webp.ycbcr.png", 150, 100, false)

    let decoded = expect Image.load(getTestDataPath("blue-purple-pink.lossy.webp"))

    // Reference samples produced by libwebp 1.6.0 dwebp with -nofancy.
    assertWebpPixelFromTop(decoded, 0, 0, 16, 19, 15, 255)
    assertWebpPixelFromTop(decoded, 112, 58, 232, 107, 160, 255)
    assertWebpPixelFromTop(decoded, 32, 41, 38, 70, 151, 255)
    assertWebpPixelFromTop(decoded, 79, 36, 255, 219, 255, 255)
}

// Decode VP8 with a compressed ALPH chunk and verify color and alpha planes.
#test
{
    checkLossyWebp("yellow_rose.lossy-with-alpha.webp", "yellow_rose.lossy-with-alpha.webp.nycbcra.png", 400, 301, true)

    let decoded = expect Image.load(getTestDataPath("yellow_rose.lossy-with-alpha.webp"))

    // Reference samples produced by libwebp 1.6.0 dwebp with -nofancy.
    assertWebpPixelFromTop(decoded, 106, 81, 241, 146, 3, 255)
    assertWebpPixelFromTop(decoded, 128, 47, 255, 90, 151, 255)
    assertWebpPixelFromTop(decoded, 160, 40, 255, 212, 232, 255)
    assertWebpPixelFromTop(decoded, 78, 0, 255, 221, 165, 0)
}

// Exercise no, simple and normal VP8 loop filters against official golden planes.
#test
{
    checkLossyWebp("blue-purple-pink-large.no-filter.lossy.webp",
                   "blue-purple-pink-large.no-filter.lossy.webp.ycbcr.png",
                   600,
                   400,
                   false)
    checkLossyWebp("blue-purple-pink-large.simple-filter.lossy.webp",
                   "blue-purple-pink-large.simple-filter.lossy.webp.ycbcr.png",
                   600,
                   400,
                   false)
    checkLossyWebp("blue-purple-pink-large.normal-filter.lossy.webp",
                   "blue-purple-pink-large.normal-filter.lossy.webp.ycbcr.png",
                   600,
                   400,
                   false)
}

// Multiple VP8 coefficient partitions decode independently.
#test
{
    checkLossyWebp("video-001.lossy.webp", "video-001.lossy.webp.ycbcr.png", 150, 103, false)
}

// VP8 metadata-only decoding reads the frame header without allocating pixels.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("blue-purple-pink.lossy.webp"))
    var options: DecodeOptions
    options.decodePixels = false
    let decoded = expect Image.decode("metadata.webp", bytes.toSlice(), options)
    Swag.assert(decoded.width == 150)
    Swag.assert(decoded.height == 100)
    Swag.assert(decoded.pixelFormat == .RGBA8)
    Swag.assert(!decoded.isValid())
}

// Animated WebP is rejected because Image represents one static image.
#test
{
    let animated: [30] u8 = [
        'R', 'I', 'F', 'F', 22, 0, 0, 0, 'W', 'E', 'B', 'P',
        'V', 'P', '8', 'X', 10, 0, 0, 0,
        2, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var decoded: Image
    decoded = catch Image.decode("animated.webp", Swag.makeSlice(&animated[0], animated.count), {}) as decodeError
    Swag.assert(decodeError != null)
}
