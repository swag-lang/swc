#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func assertNearByte(value, expected: u8, tolerance: u8)
{
    let diff = Math.abs(cast(s32) value - cast(s32) expected)
    @assert(diff <= tolerance)
}

func assertJpgPixelNear(img: Image, b, g, r: u8, tolerance: u8)
{
    @assert(img.isValid())
    @assert(img.pixels.buffer != null)
    assertNearByte(img.pixels.buffer[0], b, tolerance)
    assertNearByte(img.pixels.buffer[1], g, tolerance)
    assertNearByte(img.pixels.buffer[2], r, tolerance)
}

func assertLoadedJpg(fileName: string, width, height: s32, b, g, r: u8)
{
    let img = expect Image.load(getTestDataPath(fileName))
    @assert(img.isValid())
    @assert(img.width == width)
    @assert(img.height == height)
    @assert(img.pixelFormat == .BGR8)
    @assert(img.bitsPerPixel == 24)
    @assert(img.bytesPerPixel == 3)
    @assert(img.pixels.count == cast(u64) width * height * 3)
    assertJpgPixelNear(img, b, g, r, 8'u8)
}

func assertJpgHasMarker(bytes: const [..] u8, marker: u8)
{
    for [i] in @countof(bytes) - 1
    {
        if bytes[i] == 0xFF and bytes[i + 1] == marker do
            return
    }

    @assert(false)
}

func addAdobeRgbMarker(encoded: const [..] u8)->Array'u8
{
    @assert(@countof(encoded) >= 2)
    @assert(encoded[0] == 0xFF and encoded[1] == 0xD8)

    const app14: [16] u8 = [
        0xFF, 0xEE, 0, 14,
        'A', 'd', 'o', 'b', 'e',
        0, 100,
        0, 0,
        0, 0,
        0,]

    var result: ConcatBuffer
    result.addBytes(encoded[until 2])
    result.addBytes(app14)
    result.addBytes(encoded[2 to])
    return cbToArray(&result)
}

func fillSolidImage(img: *Image, b, g, r, a: u8)
{
    var pix = img.pixels.buffer!
    for img.width * img.height
    {
        switch img.pixelFormat
        {
        case .BGR8:
            pix[0] = b
            pix[1] = g
            pix[2] = r

        case .RGB8:
            pix[0] = r
            pix[1] = g
            pix[2] = b

        case .BGRA8:
            pix[0] = b
            pix[1] = g
            pix[2] = r
            pix[3] = a

        case .RGBA8:
            pix[0] = r
            pix[1] = g
            pix[2] = b
            pix[3] = a
        }

        pix += img.bytesPerPixel
    }
}

func assertEncodedJpgRoundtrip(src: Image, expectedB, expectedG, expectedR: u8, tolerance: u8, quality: u8 = 100'u8)
{
    var opt: Jpg.EncodeOptions
    opt.quality = quality

    let cb    = expect src.encode("memory.jpg", opt)
    let bytes = nnBytes(cb.toSlice())
    @assert(@countof(bytes) > 20)
    @assert(bytes[0] == 0xFF and bytes[1] == 0xD8)
    @assert(bytes[@countof(bytes) - 2] == 0xFF and bytes[@countof(bytes) - 1] == 0xD9)
    assertJpgHasMarker(bytes, 0xDB'u8)
    assertJpgHasMarker(bytes, 0xC0'u8)
    assertJpgHasMarker(bytes, 0xC4'u8)
    assertJpgHasMarker(bytes, 0xDA'u8)

    let img = expect Image.decode("encoded.jpg", bytes, {})
    @assert(img.width == src.width)
    @assert(img.height == src.height)
    @assert(img.pixelFormat == .BGR8)
    @assert(img.pixels.count == cast(u64) src.width * src.height * 3)
    assertJpgPixelNear(img, expectedB, expectedG, expectedR, tolerance)
}

// Decoder and encoder registries accept both JPEG extensions.
#test
{
    @assert(Image.canLoad("photo.jpg"))
    @assert(Image.canLoad("photo.jpeg"))
    @assert(!Image.canLoad("photo.jxl"))
    @assert(Image.canSave("photo.jpg"))
    @assert(Image.canSave("photo.jpeg"))
}

// Load real baseline JPEG fixtures with different sampling layouts.
#test
{
    assertLoadedJpg("h1v1.jpg", 660, 441, 201'u8, 205'u8, 194'u8)
    assertLoadedJpg("h2v1.jpg", 660, 441, 112'u8, 122'u8, 109'u8)
    assertLoadedJpg("h2v2.jpg", 1024, 768, 30'u8, 26'u8, 25'u8)
}

// Load grayscale-like, progressive, and larger JPEG fixtures.
#test
{
    assertLoadedJpg("gray.jpg", 660, 441, 202'u8, 202'u8, 202'u8)
    assertLoadedJpg("progh1v1.jpg", 660, 441, 202'u8, 206'u8, 195'u8)
    assertLoadedJpg("testA.jpg", 1200, 704, 30'u8, 30'u8, 30'u8)
}

// Decode from preloaded bytes and verify .jpeg extension routing.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("h1v1.jpg"))
    let img   = expect Image.decode("fixture.jpeg", bytes.toSlice(), {})
    @assert(img.width == 660)
    @assert(img.height == 441)
    @assert(img.pixelFormat == .BGR8)
    assertJpgPixelNear(img, 202'u8, 200'u8, 192'u8, 8'u8)
}

// Metadata-only decode must populate dimensions without allocating pixels.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("h2v2.jpg"))
    var opts: DecodeOptions
    opts.decodePixels = false

    let img = expect Image.decode("meta.jpg", bytes.toSlice(), opts)
    @assert(img.width == 1024)
    @assert(img.height == 768)
    @assert(img.pixelFormat == .BGR8)
    @assert(!img.isValid())
}

// Invalid and truncated buffers should fail without producing an image.
#test
{
    let bad: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    var img: Image
    img = catch Image.decode("bad.jpg", @mkslice(&bad[0], @countof(bad)), {}) as err8
    @assert(err8 != null)

    let bytes = expect File.readAllBytes(getTestDataPath("h1v1.jpg"))
    img = catch Image.decode("truncated.jpg", @mkslice(bytes.buffer, 32), {}) as err10
    @assert(err10 != null)
}

// Encode BGR8 and round-trip through the JPEG decoder.
#test
{
    var src = Image.create(8, 8, .BGR8)
    fillSolidImage(&src, 40'u8, 90'u8, 210'u8, 255'u8)
    assertEncodedJpgRoundtrip(src, 40'u8, 90'u8, 210'u8, 6'u8)
}

// Encode BGRA8; alpha is ignored by JPEG, while B/G/R survive the round-trip.
#test
{
    var src = Image.create(8, 8, .BGRA8)
    fillSolidImage(&src, 15'u8, 170'u8, 80'u8, 33'u8)
    assertEncodedJpgRoundtrip(src, 15'u8, 170'u8, 80'u8, 6'u8)
}

// Encode RGB8 by converting from RGB memory order to JPEG RGB components.
#test
{
    var src = Image.create(8, 8, .RGB8)
    fillSolidImage(&src, 25'u8, 60'u8, 230'u8, 255'u8)
    assertEncodedJpgRoundtrip(src, 25'u8, 60'u8, 230'u8, 6'u8)
}

// Encode RGBA8 by converting from RGBA memory order and dropping alpha.
#test
{
    var src = Image.create(8, 8, .RGBA8)
    fillSolidImage(&src, 190'u8, 40'u8, 70'u8, 11'u8)
    assertEncodedJpgRoundtrip(src, 190'u8, 40'u8, 70'u8, 6'u8)
}

// Encode dimensions that require MCU padding; the decoded image keeps original dimensions.
#test
{
    var src = Image.create(5, 7, .BGR8)
    fillSolidImage(&src, 120'u8, 30'u8, 200'u8, 255'u8)
    assertEncodedJpgRoundtrip(src, 120'u8, 30'u8, 200'u8, 8'u8, 95'u8)
}

// Adobe APP14 transform 0 marks three equally sampled components as direct RGB.
#test
{
    var src = Image.create(8, 8, .RGB8)
    fillSolidImage(&src, 0, 0, 255, 255)

    var options: Jpg.EncodeOptions
    options.quality = 100
    let encoded  = expect src.encode("memory.jpg", options)
    let adobeRgb = addAdobeRgbMarker(nnBytes(encoded.toSlice()))
    let decoded  = expect Image.decode("adobe-rgb.jpg", nnBytes(adobeRgb.toSlice()), {})
    @assert(decoded.width == 8 and decoded.height == 8)

    // The source encoder's Y, Cb and Cr component samples become direct R, G and B.
    assertJpgPixelNear(decoded, 255, 85, 76, 4)
}
