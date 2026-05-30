#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

// Create an image in memory and verify its metadata.
#test
{
    let img = Image.create(4, 4, .BGR8)
    @assert(img.isValid())
    @assert(img.width == 4)
    @assert(img.height == 4)
    @assert(img.pf == .BGR8)
    @assert(img.bpp == 24)
    @assert(img.bpp8 == 3)
    @assert(img.pixels.count == 48)
}

// Verify getTestDataPath resolves the file path correctly.
#test
{
    let path = getTestDataPath("test.bmp")
    @assert(@countof(path) > 0)
    @assert(File.exists(path))
}

// Read the BMP bytes from disk without decoding.
#test
{
    let path  = getTestDataPath("test.bmp")
    let bytes = catch File.readAllBytes(path)
    @assert(@err == null)
    @assert(bytes.count == 102)
}

// Verify that the decoder registry is functional and finds the BMP decoder.
#test
{
    @assert(Image.canLoad("test.bmp"))
    @assert(!Image.canLoad("test.xyz"))
}

// Decode a BMP from pre-loaded bytes using Image.decode (same internal path as Image.load).
#test
{
    let path  = getTestDataPath("test.bmp")
    let bytes = catch File.readAllBytes(path)
    @assert(@err == null)
    var img: Image
    trycatch { img = Image.decode(path, bytes.toSlice(), {}) }
    @assert(@err == null)
    @assert(img.isValid())
    @assert(img.width == 4)
    @assert(img.height == 4)
    @assert(img.pf == .BGR8)
}

// Load a 4x4 24-bit BMP from disk and verify image metadata.
#test
{
    let path = getTestDataPath("test.bmp")
    var img: Image
    trycatch { img = Image.load(path) }
    @assert(@err == null)
    @assert(img.isValid())
    @assert(img.width == 4)
    @assert(img.height == 4)
    @assert(img.pf == .BGR8)
    @assert(img.bpp == 24)
    @assert(img.bpp8 == 3)
    @assert(img.pixels.count == 48)
}
