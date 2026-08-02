#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func assertGifPixelAt(img: Image, x, yFromBottom: s32, r, g, b, a: u8)
{
    let idx = cast(u64) (yFromBottom * img.width + x) * img.bytesPerPixel
    @assert((notnull img.pixels.buffer)[idx] == r)
    @assert((notnull img.pixels.buffer)[idx + 1] == g)
    @assert((notnull img.pixels.buffer)[idx + 2] == b)
    if img.bytesPerPixel == 4 do
        @assert((notnull img.pixels.buffer)[idx + 3] == a)
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
    let cb    = expect src.encode("memory.gif")
    let bytes = nnBytes(cb.toSlice())
    assertGifHeader(bytes, cast(u16) src.width, cast(u16) src.height)

    let img = expect Image.decode("encoded.gif", bytes, {})
    @assert(img.width == src.width)
    @assert(img.height == src.height)
    @assert(img.pixelFormat == expectedPf)
    @assert(img.pixels.count == cast(u64) src.width * src.height * img.bytesPerPixel)
}

// Decoder and encoder registries recognise GIF files.
#test
{
    @assert(Image.canLoad("in.gif"))
    @assert(Image.canSave("out.gif"))
}

// Load animated GIF fixtures and decode their first frames.
#test
{
    let rgb = expect Image.load(getTestDataPath("test.gif"))
    @assert(rgb.isValid())
    @assert(rgb.width == 439)
    @assert(rgb.height == 341)
    @assert(rgb.pixelFormat == .RGBA8)
    assertGifPixelAt(rgb, 0, 0, 183'u8, 107'u8, 3'u8, 255'u8)

    let rgba = expect Image.load(getTestDataPath("testa.gif"))
    @assert(rgba.isValid())
    @assert(rgba.width == 250)
    @assert(rgba.height == 261)
    @assert(rgba.pixelFormat == .RGBA8)
    assertGifPixelAt(rgba, 0, 0, 0'u8, 0'u8, 0'u8, 0'u8)
}

// Direct decoder exposes frame iteration metadata for animated GIFs.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("test.gif"))
    var dec: Gif.Decoder
    expect dec.open(nnBytes(bytes.toSlice()))
    let numFrames = expect dec.frameCount()
    @assert(numFrames == 21)

    var frame: Image
    var count = 0
    for
    {
        let next = expect dec.nextFrame(&frame)
        if !next do
            break
        count += 1
    }

    @assert(count == 21)
    @assert(frame.width == 439)
    @assert(frame.height == 341)
    @assert(frame.pixelFormat == .RGBA8)
}

// Decode with decodePixels=false: metadata fields are populated but no pixel buffer is allocated.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("testa.gif"))
    var opts: DecodeOptions
    opts.decodePixels = false

    let img = expect Image.decode("meta.gif", bytes.toSlice(), opts)
    @assert(img.width == 250)
    @assert(img.height == 261)
    @assert(img.pixelFormat == .RGBA8)
    @assert(!img.isValid())
}

// Invalid and truncated buffers should fail without producing an image.
#test
{
    let bad: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    var img: Image
    img = catch Image.decode("bad.gif", @mkslice(&bad[0], @countof(bad)), {}) as err11
    @assert(err11 != null)

    let bytes = expect File.readAllBytes(getTestDataPath("test.gif"))
    img = catch Image.decode("truncated.gif", @mkslice(bytes.buffer, 32), {}) as err13
    @assert(err13 != null)
}

// Encode RGB8 images with an exact palette and preserve the colors through the decoder.
#test
{
    var src    = Image.create(2, 2, .RGB8)
    let srcBuf = notnull src.pixels.buffer
    srcBuf[0]  = 10'u8
    srcBuf[1]  = 20'u8
    srcBuf[2]  = 30'u8
    srcBuf[3]  = 40'u8
    srcBuf[4]  = 50'u8
    srcBuf[5]  = 60'u8
    srcBuf[6]  = 70'u8
    srcBuf[7]  = 80'u8
    srcBuf[8]  = 90'u8
    srcBuf[9]  = 100'u8
    srcBuf[10] = 110'u8
    srcBuf[11] = 120'u8

    let cb  = expect src.encode("memory.gif")
    let img = expect Image.decode("rgb.gif", nnBytes(cb.toSlice()), {})
    @assert(img.pixelFormat == .RGB8)
    @assert(Memory.compare(src.pixels.buffer, img.pixels.buffer, src.pixels.count) == 0)
}

// Encode RGBA8 with GIF's single transparent index.
#test
{
    var src    = Image.create(2, 1, .RGBA8)
    let srcBuf = notnull src.pixels.buffer
    srcBuf[0] = 1'u8
    srcBuf[1] = 2'u8
    srcBuf[2] = 3'u8
    srcBuf[3] = 0'u8
    srcBuf[4] = 40'u8
    srcBuf[5] = 50'u8
    srcBuf[6] = 60'u8
    srcBuf[7] = 255'u8

    assertEncodedGifRoundtrip(src, .RGBA8)

    let cb  = expect src.encode("memory.gif")
    let img = expect Image.decode("rgba.gif", nnBytes(cb.toSlice()), {})
    assertGifPixelAt(img, 0, 0, 0'u8, 0'u8, 0'u8, 0'u8)
    assertGifPixelAt(img, 1, 0, 40'u8, 50'u8, 60'u8, 255'u8)
}

// Encode BGR/BGRA source images by reading their channel layout correctly.
#test
{
    var bgr    = Image.create(1, 1, .BGR8)
    let bgrBuf = notnull bgr.pixels.buffer
    bgrBuf[0] = 30'u8
    bgrBuf[1] = 20'u8
    bgrBuf[2] = 10'u8

    let bgrEncoded = expect bgr.encode("memory.gif")
    let bgrDecoded = expect Image.decode("bgr.gif", nnBytes(bgrEncoded.toSlice()), {})
    assertGifPixelAt(bgrDecoded, 0, 0, 10'u8, 20'u8, 30'u8, 255'u8)

    var bgra    = Image.create(1, 1, .BGRA8)
    let bgraBuf = notnull bgra.pixels.buffer
    bgraBuf[0] = 7'u8
    bgraBuf[1] = 8'u8
    bgraBuf[2] = 9'u8
    bgraBuf[3] = 10'u8

    let bgraEncoded = expect bgra.encode("memory.gif")
    let bgraDecoded = expect Image.decode("bgra.gif", nnBytes(bgraEncoded.toSlice()), {})
    assertGifPixelAt(bgraDecoded, 0, 0, 0'u8, 0'u8, 0'u8, 0'u8)
}

// Encode images with more than 256 colors by falling back to deterministic quantization.
#test
{
    var src = Image.create(17, 17, .RGB8)
    var pix = notnull src.pixels.buffer
    for [i] in src.width * src.height
    {
        let x = i % src.width
        let y = i / src.width
        pix[0] = cast(u8) (x * 15)
        pix[1] = cast(u8) (y * 15)
        pix[2] = cast(u8) ((x * 13 + y * 7) & 0xFF)
        pix    += 3
    }

    let cb  = expect src.encode("memory.gif")
    let img = expect Image.decode("quantized.gif", nnBytes(cb.toSlice()), {})
    @assert(img.width == 17)
    @assert(img.height == 17)
    @assert(img.pixelFormat == .RGB8)
    assertGifPixelAt(img, 0, 0, 0'u8, 0'u8, 0'u8, 255'u8)
}

// Encode to a file path and reload through the registry.
#test
{
    let path = makeTempGifPath()
    defer discard catch File.delete(path.toString())
    var src    = Image.create(1, 1, .RGB8)
    let srcBuf = notnull src.pixels.buffer
    srcBuf[0] = 12'u8
    srcBuf[1] = 34'u8
    srcBuf[2] = 56'u8

    let cb = expect src.encode("memory.gif")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    assertGifPixelAt(img, 0, 0, 12'u8, 34'u8, 56'u8, 255'u8)
}
