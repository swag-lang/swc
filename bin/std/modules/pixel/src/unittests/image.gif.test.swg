#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

func gifCanEncode(fileName: string)->bool
{
    var enc: Gif.Encoder
    let itf = @mkinterface(&enc, #typeof(Gif.Encoder), IImageEncoder)
    return itf.canEncode(fileName)
}

func encodeGif(result: *ConcatBuffer, image: Image) throw
{
    var enc: Gif.Encoder
    let itf = @mkinterface(&enc, #typeof(Gif.Encoder), IImageEncoder)
    itf.encode(result, image, null)
}

func assertGifPixelAt(img: Image, x, yFromBottom: s32, r, g, b, a: u8)
{
    let idx = cast(u64) (yFromBottom * img.width + x) * img.bpp8
    @assert(img.pixels.buffer[idx] == r)
    @assert(img.pixels.buffer[idx + 1] == g)
    @assert(img.pixels.buffer[idx + 2] == b)
    if img.bpp8 == 4 do
        @assert(img.pixels.buffer[idx + 3] == a)
}

func assertGifHeader(bytes: const [..] u8, width, height: u16)
{
    @assert(@countof(bytes) > 20)
    @assert(bytes[0] == 'G' and bytes[1] == 'I' and bytes[2] == 'F')
    @assert(bytes[3] == '8' and bytes[4] == '9' and bytes[5] == 'a')
    @assert(bytes[6] == cast(u8) (width & 0xFF))
    @assert(bytes[7] == cast(u8) (width >> 8))
    @assert(bytes[8] == cast(u8) (height & 0xFF))
    @assert(bytes[9] == cast(u8) (height >> 8))
    @assert(bytes[@countof(bytes) - 1] == 0x3B'u8)
}

func assertEncodedGifRoundtrip(src: Image, expectedPf: PixelFormat)
{
    var cb: ConcatBuffer
    catch encodeGif(&cb, src)
    @assert(@err == null)

    let bytes = nnBytes(cb.toSlice())
    assertGifHeader(bytes, cast(u16) src.width, cast(u16) src.height)

    var img: Image
    img = catch Image.decode("encoded.gif", bytes, {})
    @assert(@err == null)
    @assert(img.width == src.width)
    @assert(img.height == src.height)
    @assert(img.pf == expectedPf)
    @assert(img.pixels.count == cast(u64) src.width * src.height * img.bpp8)
}

// Decoder and encoder registries recognise GIF files.
#test
{
    @assert(Image.canLoad("in.gif"))
    @assert(Image.canSave("out.gif"))
    @assert(gifCanEncode("out.gif"))
    @assert(!gifCanEncode("out.png"))
}

// Load animated GIF fixtures and decode their first frames.
#test
{
    var rgb: Image
    rgb = catch Image.load(getTestDataPath("test.gif"))
    @assert(@err == null)
    @assert(rgb.isValid())
    @assert(rgb.width == 439)
    @assert(rgb.height == 341)
    @assert(rgb.pf == .RGBA8)
    assertGifPixelAt(rgb, 0, 0, 183'u8, 107'u8, 3'u8, 255'u8)

    var rgba: Image
    rgba = catch Image.load(getTestDataPath("testa.gif"))
    @assert(@err == null)
    @assert(rgba.isValid())
    @assert(rgba.width == 250)
    @assert(rgba.height == 261)
    @assert(rgba.pf == .RGBA8)
    assertGifPixelAt(rgba, 0, 0, 0'u8, 0'u8, 0'u8, 0'u8)
}

// Direct decoder exposes frame iteration metadata for animated GIFs.
#test
{
    let bytes = catch File.readAllBytes(getTestDataPath("test.gif"))
    @assert(@err == null)

    var dec: Gif.Decoder
    catch dec.init(nnBytes(bytes.toSlice()), true)
    @assert(@err == null)

    let numFrames = catch dec.getNumFrames()
    @assert(@err == null)
    @assert(numFrames == 21)

    var frame: Image
    dec.getFrame(&frame)
    @assert(frame.width == 439)
    @assert(frame.height == 341)
    @assert(frame.pf == .RGBA8)

    var count = 0
    for
    {
        let next = catch dec.nextFrame(&frame)
        @assert(@err == null)
        if !next do
            break
        count += 1
    }

    @assert(@err == null)
    @assert(count == 21)
}

// Decode with decodePixels=false: metadata fields are populated but no pixel buffer is allocated.
#test
{
    let bytes = catch File.readAllBytes(getTestDataPath("testa.gif"))
    @assert(@err == null)

    var opts: DecodeOptions
    opts.decodePixels = false

    var img: Image
    img = catch Image.decode("meta.gif", bytes.toSlice(), opts)
    @assert(@err == null)
    @assert(img.width == 250)
    @assert(img.height == 261)
    @assert(img.pf == .RGBA8)
    @assert(!img.isValid())
}

// Invalid and truncated buffers should fail without producing an image.
#test
{
    let bad: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    var img: Image
    img = catch Image.decode("bad.gif", @mkslice(&bad[0], @countof(bad)), {})
    @assert(@err != null)

    let bytes = catch File.readAllBytes(getTestDataPath("test.gif"))
    @assert(@err == null)
    img = catch Image.decode("truncated.gif", @mkslice(bytes.buffer, 32), {})
    @assert(@err != null)
}

// Encode RGB8 images with an exact palette and preserve the colors through the decoder.
#test
{
    var src = Image.create(2, 2, .RGB8)
    src.pixels.buffer[0]  = 10'u8
    src.pixels.buffer[1]  = 20'u8
    src.pixels.buffer[2]  = 30'u8
    src.pixels.buffer[3]  = 40'u8
    src.pixels.buffer[4]  = 50'u8
    src.pixels.buffer[5]  = 60'u8
    src.pixels.buffer[6]  = 70'u8
    src.pixels.buffer[7]  = 80'u8
    src.pixels.buffer[8]  = 90'u8
    src.pixels.buffer[9]  = 100'u8
    src.pixels.buffer[10] = 110'u8
    src.pixels.buffer[11] = 120'u8

    var cb: ConcatBuffer
    catch encodeGif(&cb, src)
    @assert(@err == null)

    var img: Image
    img = catch Image.decode("rgb.gif", nnBytes(cb.toSlice()), {})
    @assert(@err == null)
    @assert(img.pf == .RGB8)
    @assert(Memory.compare(src.pixels.buffer, img.pixels.buffer, src.pixels.count) == 0)
}

// Encode RGBA8 with GIF's single transparent index.
#test
{
    var src = Image.create(2, 1, .RGBA8)
    src.pixels.buffer[0] = 1'u8
    src.pixels.buffer[1] = 2'u8
    src.pixels.buffer[2] = 3'u8
    src.pixels.buffer[3] = 0'u8
    src.pixels.buffer[4] = 40'u8
    src.pixels.buffer[5] = 50'u8
    src.pixels.buffer[6] = 60'u8
    src.pixels.buffer[7] = 255'u8

    assertEncodedGifRoundtrip(src, .RGBA8)

    var cb: ConcatBuffer
    catch encodeGif(&cb, src)
    @assert(@err == null)

    var img: Image
    img = catch Image.decode("rgba.gif", nnBytes(cb.toSlice()), {})
    @assert(@err == null)
    assertGifPixelAt(img, 0, 0, 0'u8, 0'u8, 0'u8, 0'u8)
    assertGifPixelAt(img, 1, 0, 40'u8, 50'u8, 60'u8, 255'u8)
}

// Encode BGR/BGRA source images by reading their channel layout correctly.
#test
{
    var bgr = Image.create(1, 1, .BGR8)
    bgr.pixels.buffer[0] = 30'u8
    bgr.pixels.buffer[1] = 20'u8
    bgr.pixels.buffer[2] = 10'u8

    var cb: ConcatBuffer
    catch encodeGif(&cb, bgr)
    @assert(@err == null)

    var img: Image
    img = catch Image.decode("bgr.gif", nnBytes(cb.toSlice()), {})
    @assert(@err == null)
    assertGifPixelAt(img, 0, 0, 10'u8, 20'u8, 30'u8, 255'u8)

    var bgra = Image.create(1, 1, .BGRA8)
    bgra.pixels.buffer[0] = 7'u8
    bgra.pixels.buffer[1] = 8'u8
    bgra.pixels.buffer[2] = 9'u8
    bgra.pixels.buffer[3] = 10'u8

    cb.clear()
    catch encodeGif(&cb, bgra)
    @assert(@err == null)

    img = catch Image.decode("bgra.gif", nnBytes(cb.toSlice()), {})
    @assert(@err == null)
    assertGifPixelAt(img, 0, 0, 0'u8, 0'u8, 0'u8, 0'u8)
}

// Encode images with more than 256 colors by falling back to deterministic quantization.
#test
{
    var src = Image.create(17, 17, .RGB8)
    var pix = src.pixels.buffer
    for i in src.width * src.height
    {
        let x = i % src.width
        let y = i / src.width
        pix[0] = cast(u8) (x * 15)
        pix[1] = cast(u8) (y * 15)
        pix[2] = cast(u8) ((x * 13 + y * 7) & 0xFF)
        pix += 3
    }

    var cb: ConcatBuffer
    catch encodeGif(&cb, src)
    @assert(@err == null)

    var img: Image
    img = catch Image.decode("quantized.gif", nnBytes(cb.toSlice()), {})
    @assert(@err == null)
    @assert(img.width == 17)
    @assert(img.height == 17)
    @assert(img.pf == .RGB8)
    assertGifPixelAt(img, 0, 0, 0'u8, 0'u8, 0'u8, 255'u8)
}

// Encode to a file path and reload through the registry.
#test
{
    let path = makeTempGifPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(1, 1, .RGB8)
    src.pixels.buffer[0] = 12'u8
    src.pixels.buffer[1] = 34'u8
    src.pixels.buffer[2] = 56'u8

    var cb: ConcatBuffer
    catch encodeGif(&cb, src)
    @assert(@err == null)
    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    assertGifPixelAt(img, 0, 0, 12'u8, 34'u8, 56'u8, 255'u8)
}
