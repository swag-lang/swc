#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

func pngCanEncode(fileName: string)->bool
{
    var enc: Png.Encoder
    let itf = @mkinterface(&enc, #typeof(Png.Encoder), IImageEncoder)
    return itf.canEncode(fileName)
}

func encodePng(result: *ConcatBuffer, image: Image, options: #null any = null) throw
{
    var enc: Png.Encoder
    let itf = @mkinterface(&enc, #typeof(Png.Encoder), IImageEncoder)
    itf.encode(result, image, options)
}

func assertPngPixelAt(img: Image, x, yFromBottom: s32, r, g, b, a: u8)
{
    let idx = cast(u64) (yFromBottom * img.width + x) * img.bpp8
    @assert(img.pixels.buffer[idx] == r)
    @assert(img.pixels.buffer[idx + 1] == g)
    @assert(img.pixels.buffer[idx + 2] == b)
    if img.bpp8 == 4 do
        @assert(img.pixels.buffer[idx + 3] == a)
}

func assertLoadedPng(fileName: string, width, height: s32, pf: PixelFormat, r, g, b, a: u8)
{
    var img: Image
    img = catch Image.load(getTestDataPath(fileName))
    @assert(@err == null)
    @assert(img.isValid())
    @assert(img.width == width)
    @assert(img.height == height)
    @assert(img.pf == pf)
    @assert(img.bpp == pf.bpp())
    @assert(img.bpp8 == pf.channels())
    @assert(img.pixels.count == cast(u64) width * height * img.bpp8)
    assertPngPixelAt(img, 0, 0, r, g, b, a)
}

func assertPngHasChunk(bytes: const [..] u8, c0, c1, c2, c3: u8)
{
    var i = 8'u64
    while i + 12 <= @countof(bytes)
    {
        if bytes[i + 4] == c0 and bytes[i + 5] == c1 and bytes[i + 6] == c2 and bytes[i + 7] == c3 do
            return

        let length = (cast(u64) bytes[i] << 24) | (cast(u64) bytes[i + 1] << 16) | (cast(u64) bytes[i + 2] << 8) | cast(u64) bytes[i + 3]
        i += length + 12
    }

    @assert(false)
}

func assertEncodedPngRoundtrip(src: Image, expectedPf: PixelFormat)
{
    var cb: ConcatBuffer
    catch encodePng(&cb, src)
    @assert(@err == null)

    let bytes = nnBytes(cb.toSlice())
    @assert(@countof(bytes) > 33)
    @assert(bytes[0] == 137'u8 and bytes[1] == 80'u8 and bytes[2] == 78'u8 and bytes[3] == 71'u8)
    assertPngHasChunk(bytes, 73'u8, 72'u8, 68'u8, 82'u8)
    assertPngHasChunk(bytes, 73'u8, 68'u8, 65'u8, 84'u8)
    assertPngHasChunk(bytes, 73'u8, 69'u8, 78'u8, 68'u8)

    var img: Image
    img = catch Image.decode("encoded.png", bytes, {})
    @assert(@err == null)
    @assert(img.width == src.width)
    @assert(img.height == src.height)
    @assert(img.pf == expectedPf)
    @assert(img.pixels.count == src.pixels.count)
    @assert(Memory.compare(src.pixels.buffer, img.pixels.buffer, src.pixels.count) == 0)
}

func fillSolidPngImage(img: *Image, r, g, b, a: u8)
{
    var pix = img.pixels.buffer
    for img.width * img.height
    {
        switch img.pf
        {
        case BGR8:
            pix[0] = b
            pix[1] = g
            pix[2] = r

        case RGB8:
            pix[0] = r
            pix[1] = g
            pix[2] = b

        case BGRA8:
            pix[0] = b
            pix[1] = g
            pix[2] = r
            pix[3] = a

        case RGBA8:
            pix[0] = r
            pix[1] = g
            pix[2] = b
            pix[3] = a
        }

        pix += img.bpp8
    }
}

// Decoder and encoder registries recognise PNG files.
#test
{
    @assert(Image.canLoad("in.png"))
    @assert(!Image.canLoad("in.pnm"))
    @assert(Image.canSave("out.png"))
    @assert(pngCanEncode("out.png"))
    @assert(!pngCanEncode("out.bmp"))
}

// Load real 24-bit and 32-bit PNG fixtures.
#test
{
    assertLoadedPng("rgb.png", 660, 441, .RGB8, 194'u8, 205'u8, 201'u8, 255'u8)
    assertLoadedPng("rgba.png", 660, 441, .RGBA8, 194'u8, 205'u8, 201'u8, 255'u8)
}

// Decode non-interlaced grayscale PNGs with packed bit depths.
#test
{
    assertLoadedPng("basn0g01.png", 32, 32, .RGB8, 0'u8, 0'u8, 0'u8, 255'u8)
    assertLoadedPng("basn0g02.png", 32, 32, .RGB8, 255'u8, 255'u8, 255'u8, 255'u8)
    assertLoadedPng("basn0g04.png", 32, 32, .RGB8, 119'u8, 119'u8, 119'u8, 255'u8)
    assertLoadedPng("basn4a08.png", 32, 32, .RGBA8, 0'u8, 0'u8, 0'u8, 0'u8)
}

// Decode Adam7-interlaced grayscale, true-color, and alpha PNGs.
#test
{
    assertLoadedPng("basi0g08.png", 32, 32, .RGB8, 28'u8, 28'u8, 28'u8, 255'u8)
    assertLoadedPng("basi2c08.png", 32, 32, .RGB8, 31'u8, 31'u8, 31'u8, 255'u8)
    assertLoadedPng("basi4a08.png", 32, 32, .RGBA8, 0'u8, 0'u8, 0'u8, 0'u8)
    assertLoadedPng("basi6a08.png", 32, 32, .RGBA8, 0'u8, 32'u8, 255'u8, 0'u8)
}

// Decode palette and tRNS transparency chunks.
#test
{
    var pal: Image
    pal = catch Image.load(getTestDataPath("paletted.png"))
    @assert(@err == null)
    @assert(pal.width == 34)
    @assert(pal.height == 24)
    @assert(pal.pf == .RGBA8)
    assertPngPixelAt(pal, 10, 0, 83'u8, 56'u8, 70'u8, 255'u8)

    var grayKey: Image
    grayKey = catch Image.load(getTestDataPath("tbbn0g04.png"))
    @assert(@err == null)
    @assert(grayKey.pf == .RGBA8)
    assertPngPixelAt(grayKey, 15, 1, 238'u8, 238'u8, 238'u8, 255'u8)

    var rgbKey: Image
    rgbKey = catch Image.load(getTestDataPath("tbrn2c08.png"))
    @assert(@err == null)
    @assert(rgbKey.pf == .RGBA8)
    assertPngPixelAt(rgbKey, 0, 0, 255'u8, 255'u8, 255'u8, 0'u8)
}

// Decode with decodePixels=false: metadata fields are populated but no pixel buffer is allocated.
#test
{
    let bytes = catch File.readAllBytes(getTestDataPath("rgb.png"))
    @assert(@err == null)

    var opts: DecodeOptions
    opts.decodePixels = false

    var img: Image
    img = catch Image.decode("meta.png", bytes.toSlice(), opts)
    @assert(@err == null)
    @assert(img.width == 660)
    @assert(img.height == 441)
    @assert(img.pf == .RGB8)
    @assert(!img.isValid())
}

// PNG text metadata must survive a normal decode with pixels enabled.
#test
{
    let path = makeTempPngPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var src = Image.create(2, 1, .RGB8)
    fillSolidPngImage(&src, 1'u8, 2'u8, 3'u8, 255'u8)

    var md: ImageMetaData
    md.tag   = "Captme.File"
    md.value = "capture.captme"
    src.metaDatas.add(md)

    catch src.save(path.toString())
    @assert(@err == null)

    let img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.isValid())
    @assert(img.metaDatas.count == 1)
    @assert(img.metaDatas[0].isTag("Captme.File"))
    @assert(cast(string) img.metaDatas[0].toSlice() == "capture.captme")
}

// Invalid and truncated buffers should fail without producing an image.
#test
{
    let bad: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    var img: Image
    img = catch Image.decode("bad.png", @mkslice(&bad[0], @countof(bad)), {})
    @assert(@err != null)

    let bytes = catch File.readAllBytes(getTestDataPath("rgb.png"))
    @assert(@err == null)
    img = catch Image.decode("truncated.png", @mkslice(bytes.buffer, 32), {})
    @assert(@err != null)
}

// Encode RGB8 and RGBA8 images and verify exact round-trips through the decoder.
#test
{
    var rgb = Image.create(2, 2, .RGB8)
    rgb.clear()
    rgb.pixels.buffer[0]  = 10'u8
    rgb.pixels.buffer[1]  = 20'u8
    rgb.pixels.buffer[2]  = 30'u8
    rgb.pixels.buffer[9]  = 100'u8
    rgb.pixels.buffer[10] = 110'u8
    rgb.pixels.buffer[11] = 120'u8
    assertEncodedPngRoundtrip(rgb, .RGB8)

    var rgba = Image.create(2, 2, .RGBA8)
    rgba.clear()
    rgba.pixels.buffer[0]  = 1'u8
    rgba.pixels.buffer[1]  = 2'u8
    rgba.pixels.buffer[2]  = 3'u8
    rgba.pixels.buffer[3]  = 4'u8
    rgba.pixels.buffer[12] = 200'u8
    rgba.pixels.buffer[13] = 201'u8
    rgba.pixels.buffer[14] = 202'u8
    rgba.pixels.buffer[15] = 203'u8
    assertEncodedPngRoundtrip(rgba, .RGBA8)
}

// Encode BGR/BGRA source images by swapping R/B into PNG's RGB component order.
#test
{
    var bgr = Image.create(1, 1, .BGR8)
    bgr.pixels.buffer[0] = 30'u8
    bgr.pixels.buffer[1] = 20'u8
    bgr.pixels.buffer[2] = 10'u8

    var cb: ConcatBuffer
    catch encodePng(&cb, bgr)
    @assert(@err == null)

    var img: Image
    img = catch Image.decode("bgr.png", nnBytes(cb.toSlice()), {})
    @assert(@err == null)
    @assert(img.pf == .RGB8)
    assertPngPixelAt(img, 0, 0, 10'u8, 20'u8, 30'u8, 255'u8)

    var bgra = Image.create(1, 1, .BGRA8)
    bgra.pixels.buffer[0] = 7'u8
    bgra.pixels.buffer[1] = 8'u8
    bgra.pixels.buffer[2] = 9'u8
    bgra.pixels.buffer[3] = 10'u8

    cb.clear()
    catch encodePng(&cb, bgra)
    @assert(@err == null)

    img = catch Image.decode("bgra.png", nnBytes(cb.toSlice()), {})
    @assert(@err == null)
    @assert(img.pf == .RGBA8)
    assertPngPixelAt(img, 0, 0, 9'u8, 8'u8, 7'u8, 10'u8)
}

// Encode with explicit PNG options and round-trip the written bytes through the decoder.
#test
{
    let path = makeTempPngPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var src = Image.create(3, 2, .RGB8)
    fillSolidPngImage(&src, 24'u8, 48'u8, 96'u8, 255'u8)

    var opts: Png.EncodeOptions
    opts.filtering        = false
    opts.compressionLevel = .NoCompression

    var cb: ConcatBuffer
    catch encodePng(&cb, src, opts)
    @assert(@err == null)
    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pf == .RGB8)
    @assert(Memory.compare(src.pixels.buffer, img.pixels.buffer, src.pixels.count) == 0)
}
