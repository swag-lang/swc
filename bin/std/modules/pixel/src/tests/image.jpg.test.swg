#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

func assertNearByte(value, expected: u8, tolerance: u8)
{
    let diff = Math.abs(cast(s32) value - cast(s32) expected)
    @assert(diff <= tolerance)
}

func assertJpgPixelNear(img: Image, b, g, r: u8, tolerance: u8)
{
    @assert(img.isValid())
    assertNearByte(img.pixels.buffer[0], b, tolerance)
    assertNearByte(img.pixels.buffer[1], g, tolerance)
    assertNearByte(img.pixels.buffer[2], r, tolerance)
}

func assertLoadedJpg(fileName: string, width, height: s32, b, g, r: u8)
{
    var img: Image
    img = catch Image.load(getTestDataPath(fileName))
    @assert(@err == null)
    @assert(img.isValid())
    @assert(img.width == width)
    @assert(img.height == height)
    @assert(img.pf == .BGR8)
    @assert(img.bpp == 24)
    @assert(img.bpp8 == 3)
    @assert(img.pixels.count == cast(u64) width * height * 3)
    assertJpgPixelNear(img, b, g, r, 8'u8)
}

// Decoder registry accepts both JPEG extensions.
#test
{
    @assert(Image.canLoad("photo.jpg"))
    @assert(Image.canLoad("photo.jpeg"))
    @assert(!Image.canLoad("photo.jxl"))
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
    let bytes = catch File.readAllBytes(getTestDataPath("h1v1.jpg"))
    @assert(@err == null)

    var img: Image
    img = catch Image.decode("fixture.jpeg", bytes.toSlice(), {})
    @assert(@err == null)
    @assert(img.width == 660)
    @assert(img.height == 441)
    @assert(img.pf == .BGR8)
    assertJpgPixelNear(img, 202'u8, 200'u8, 192'u8, 8'u8)
}

// Metadata-only decode must populate dimensions without allocating pixels.
#test
{
    let bytes = catch File.readAllBytes(getTestDataPath("h2v2.jpg"))
    @assert(@err == null)

    var opts: DecodeOptions
    opts.decodePixels = false

    var img: Image
    img = catch Image.decode("meta.jpg", bytes.toSlice(), opts)
    @assert(@err == null)
    @assert(img.width == 1024)
    @assert(img.height == 768)
    @assert(img.pf == .BGR8)
    @assert(!img.isValid())
}

// Invalid and truncated buffers should fail without producing an image.
#test
{
    let bad: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    var img: Image
    img = catch Image.decode("bad.jpg", @mkslice(&bad[0], @countof(bad)), {})
    @assert(@err != null)

    let bytes = catch File.readAllBytes(getTestDataPath("h1v1.jpg"))
    @assert(@err == null)
    img = catch Image.decode("truncated.jpg", @mkslice(bytes.buffer, 32), {})
    @assert(@err != null)
}
