#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func webpExpectedChannel(value: s32)->u8
{
    return cast(u8) Math.clamp(value, 0, 255)
}

func checkWebpAgainstPng(fileName, goldenName: string, width, height: s32)
{
    let decoded = catch Image.load(getTestDataPath(fileName)) as decodeError
    @assert(decodeError == null)
    @assert(decoded.isValid())
    @assert(decoded.width == width)
    @assert(decoded.height == height)
    @assert(decoded.pf == .RGBA8)

    let golden = catch Image.load(getTestDataPath(goldenName)) as goldenError
    @assert(goldenError == null)
    @assert(golden.width == width)
    @assert(golden.height == height)
    for [y] in height do
        for [x] in width
        {
            let got  = decoded.getPixelColor(x, y)
            let want = golden.getPixelColor(x, y)
            @assert(got.r == want.r)
            @assert(got.g == want.g)
            @assert(got.b == want.b)
            @assert(got.a == want.a)
        }
}

func checkLossyWebp(fileName, goldenName: string, width, height: s32, withAlpha: bool)
{
    let decoded = catch Image.load(getTestDataPath(fileName)) as decodeError
    @assert(decodeError == null)
    @assert(decoded.isValid())
    @assert(decoded.width == width)
    @assert(decoded.height == height)
    @assert(decoded.pf == .RGBA8)

    let golden = catch Image.load(getTestDataPath(goldenName)) as goldenError
    @assert(goldenError == null)
    let halfWidth  = (width + 1) / 2
    let halfHeight = (height + 1) / 2
    @assert(golden.width == 2 * halfWidth)
    @assert(golden.height == height + halfHeight + (withAlpha ? height : 0))

    for [y] in height
    {
        for [x] in width
        {
            let luma = cast(s32) golden.getPixelColor(x, y).r
            let cb   = cast(s32) golden.getPixelColor(x / 2, height + y / 2).r - 128
            let cr   = cast(s32) golden.getPixelColor(halfWidth + x / 2, height + y / 2).r - 128
            let scaledLuma = luma * 0x10101
            let expectedR  = webpExpectedChannel((scaledLuma + 91881 * cr) >> 16)
            let expectedG  = webpExpectedChannel((scaledLuma - 22554 * cb - 46802 * cr) >> 16)
            let expectedB  = webpExpectedChannel((scaledLuma + 116130 * cb) >> 16)
            let expectedA  = withAlpha ? golden.getPixelColor(x, height + halfHeight + y).r : 0xFF
            let got = decoded.getPixelColor(x, y)
            @assert(got.r == expectedR)
            @assert(got.g == expectedG)
            @assert(got.b == expectedB)
            @assert(got.a == expectedA)
        }
    }
}

// The decoder registry recognises WebP files.
#test
{
    @assert(Image.canLoad("image.webp"))
    @assert(!Image.canLoad("image.webm"))
}

// Decode an official VP8L fixture and compare every pixel with its PNG golden image.
#test
{
    checkWebpAgainstPng("gopher-doc.lossless.webp", "gopher-doc.lossless.png", 75, 100)
    checkWebpAgainstPng("gopher-doc.with-alpha.lossless.webp", "gopher-doc.with-alpha.png", 75, 100)
}

// Metadata-only decoding reads dimensions without allocating the pixel buffer.
#test
{
    let bytes = catch File.readAllBytes(getTestDataPath("gopher-doc.lossless.webp")) as err3
    @assert(err3 == null)

    var options: DecodeOptions
    options.decodePixels = false
    let decoded = catch Image.decode("metadata.webp", bytes.toSlice(), options) as err4
    @assert(err4 == null)
    @assert(decoded.width == 75)
    @assert(decoded.height == 100)
    @assert(decoded.pf == .RGBA8)
    @assert(!decoded.isValid())
}

// Invalid and truncated RIFF data fails before allocating an image.
#test
{
    let bad: [12] u8 = [
        'R', 'I', 'F', 'F', 4, 0, 0, 0, 'N', 'O', 'P', 'E',
    ]
    var decoded: Image
    decoded = catch Image.decode("bad.webp", @mkslice(&bad[0], @countof(bad)), {}) as err5
    @assert(err5 != null)

    let bytes = catch File.readAllBytes(getTestDataPath("gopher-doc.lossless.webp")) as err6
    @assert(err6 == null)
    decoded = catch Image.decode("truncated.webp", @mkslice(bytes.buffer, 32), {}) as err7
    @assert(err7 != null)
}

// Decode a VP8 fixture and compare it with the official split-plane YCbCr golden image.
#test
{
    checkLossyWebp("blue-purple-pink.lossy.webp", "blue-purple-pink.lossy.webp.ycbcr.png", 150, 100, false)
}

// Decode VP8 with a compressed ALPH chunk and verify color and alpha planes.
#test
{
    checkLossyWebp("yellow_rose.lossy-with-alpha.webp", "yellow_rose.lossy-with-alpha.webp.nycbcra.png", 400, 301, true)
}

// Exercise no, simple and normal VP8 loop filters against official golden planes.
#test
{
    checkLossyWebp("blue-purple-pink-large.no-filter.lossy.webp",
                   "blue-purple-pink-large.no-filter.lossy.webp.ycbcr.png", 600, 400, false)
    checkLossyWebp("blue-purple-pink-large.simple-filter.lossy.webp",
                   "blue-purple-pink-large.simple-filter.lossy.webp.ycbcr.png", 600, 400, false)
    checkLossyWebp("blue-purple-pink-large.normal-filter.lossy.webp",
                   "blue-purple-pink-large.normal-filter.lossy.webp.ycbcr.png", 600, 400, false)
}

// Multiple VP8 coefficient partitions decode independently.
#test
{
    checkLossyWebp("video-001.lossy.webp", "video-001.lossy.webp.ycbcr.png", 150, 103, false)
}

// VP8 metadata-only decoding reads the frame header without allocating pixels.
#test
{
    let bytes = catch File.readAllBytes(getTestDataPath("blue-purple-pink.lossy.webp")) as readError
    @assert(readError == null)
    var options: DecodeOptions
    options.decodePixels = false
    let decoded = catch Image.decode("metadata.webp", bytes.toSlice(), options) as decodeError
    @assert(decodeError == null)
    @assert(decoded.width == 150)
    @assert(decoded.height == 100)
    @assert(decoded.pf == .RGBA8)
    @assert(!decoded.isValid())
}

// Animated WebP is rejected because Image represents one static image.
#test
{
    let animated: [30] u8 = [
        'R', 'I', 'F', 'F', 22, 0, 0, 0, 'W', 'E', 'B', 'P',
        'V', 'P', '8', 'X', 10, 0, 0, 0,
        2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ]
    var decoded: Image
    decoded = catch Image.decode("animated.webp", @mkslice(&animated[0], @countof(animated)), {}) as decodeError
    @assert(decodeError != null)
}
