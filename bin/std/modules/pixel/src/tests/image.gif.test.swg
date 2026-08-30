#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func assertGifPixelAt(img: Image, x, yFromBottom: s32, r, g, b, a: u8)
{
    let idx = cast(u64) (yFromBottom * img.width + x) * img.bytesPerPixel
    Swag.assert(img.pixels.buffer![idx] == r)
    Swag.assert(img.pixels.buffer![idx + 1] == g)
    Swag.assert(img.pixels.buffer![idx + 2] == b)
    if img.bytesPerPixel == 4 do
        Swag.assert(img.pixels.buffer![idx + 3] == a)
}

func quantizedGifChannel(value: u8, maxLevel: u32)->u8
{
    let level = cast(u32) value * maxLevel / 255
    return cast(u8) ((level * 255 + maxLevel / 2) / maxLevel)
}

func assertQuantizedGif24(pixelFormat: PixelFormat) fail
{
    const Width = 523
    var source    = Image.create(Width, 1, pixelFormat)
    var pix       = source.pixels.buffer!
    let blueFirst = pixelFormat == .BGR8
    for i in Width
    {
        let r = cast(u8) (i & 0xFF)
        let g = cast(u8) ((i * 37 + 11) & 0xFF)
        let b = cast(u8) ((i * 73 + 19) & 0xFF)
        pix[0] = blueFirst ? b : r
        pix[1] = g
        pix[2] = blueFirst ? r : b
        pix    += 3
    }

    var encoded = expect source.encode("memory.gif")
    encoded.makeLinear()
    let decoded = expect Image.decode("quantized.gif", nnBytes(encoded.toSlice()), {})
    Swag.assert(decoded.pixelFormat == .RGB8)
    for i in Width
    {
        let r = cast(u8) (i & 0xFF)
        let g = cast(u8) ((i * 37 + 11) & 0xFF)
        let b = cast(u8) ((i * 73 + 19) & 0xFF)
        assertGifPixelAt(decoded, i, 0, quantizedGifChannel(r, 3), quantizedGifChannel(g, 7), quantizedGifChannel(b, 3), 255)
    }
}

func assertQuantizedGif32(pixelFormat: PixelFormat, withTransparency: bool) fail
{
    const Width = 523
    var source    = Image.create(Width, 1, pixelFormat)
    var pix       = source.pixels.buffer!
    let blueFirst = pixelFormat == .BGRA8
    for i in Width
    {
        let r = cast(u8) (i & 0xFF)
        let g = cast(u8) ((i * 37 + 11) & 0xFF)
        let b = cast(u8) ((i * 73 + 19) & 0xFF)
        let a = withTransparency ? cast(u8) ((i * 53 + 7) & 0xFF) : 255'u8
        pix[0] = blueFirst ? b : r
        pix[1] = g
        pix[2] = blueFirst ? r : b
        pix[3] = a
        pix    += 4
    }

    var encoded = expect source.encode("memory.gif")
    encoded.makeLinear()
    let decoded = expect Image.decode("quantized.gif", nnBytes(encoded.toSlice()), {})
    Swag.assert(decoded.pixelFormat == (withTransparency ? .RGBA8 : .RGB8))
    for i in Width
    {
        let r = cast(u8) (i & 0xFF)
        let g = cast(u8) ((i * 37 + 11) & 0xFF)
        let b = cast(u8) ((i * 73 + 19) & 0xFF)
        let a = withTransparency ? cast(u8) ((i * 53 + 7) & 0xFF) : 255'u8
        if withTransparency and a < 128
        {
            assertGifPixelAt(decoded, i, 0, 0, 0, 0, 0)
        }
        else
        {
            let rbLevels = withTransparency ? 4'u32 : 3'u32
            let gLevels  = withTransparency ? 4'u32 : 7'u32
            assertGifPixelAt(decoded, i, 0, quantizedGifChannel(r, rbLevels), quantizedGifChannel(g, gLevels), quantizedGifChannel(b, rbLevels), 255)
        }
    }
}

func assertGifHeader(bytes: const [..] u8, width, height: u16)
{
    Swag.assert(bytes.count > 20)
    Swag.assert(bytes[0] == 'G' and bytes[1] == 'I' and bytes[2] == 'F')
    Swag.assert(bytes[3] == '8' and bytes[4] == '9' and bytes[5] == 'a')
    Swag.assert(bytes[6] == cast(u8) (width & 0xFF))
    Swag.assert(bytes[7] == cast(u8) (width >> 8))
    Swag.assert(bytes[8] == cast(u8) (height & 0xFF))
    Swag.assert(bytes[9] == cast(u8) (height >> 8))
    Swag.assert(bytes[bytes.count - 1] == 0x3B'u8)
}

func assertEncodedGifRoundtrip(src: Image, expectedPf: PixelFormat)
{
    let cb    = expect src.encode("memory.gif")
    let bytes = nnBytes(cb.toSlice())
    assertGifHeader(bytes, cast(u16) src.width, cast(u16) src.height)

    let img = expect Image.decode("encoded.gif", bytes, {})
    Swag.assert(img.width == src.width)
    Swag.assert(img.height == src.height)
    Swag.assert(img.pixelFormat == expectedPf)
    Swag.assert(img.pixels.count == cast(u64) src.width * src.height * img.bytesPerPixel)
}

// Decoder and encoder registries recognise GIF files.
#test
{
    Swag.assert(Image.canLoad("in.gif"))
    Swag.assert(Image.canSave("out.gif"))
}

// Load animated GIF fixtures and decode their first frames.
#test
{
    let rgb = expect Image.load(getTestDataPath("test.gif"))
    Swag.assert(rgb.isValid())
    Swag.assert(rgb.width == 439)
    Swag.assert(rgb.height == 341)
    Swag.assert(rgb.pixelFormat == .RGBA8)
    assertGifPixelAt(rgb, 0, 0, 183'u8, 107'u8, 3'u8, 255'u8)

    let rgba = expect Image.load(getTestDataPath("testa.gif"))
    Swag.assert(rgba.isValid())
    Swag.assert(rgba.width == 250)
    Swag.assert(rgba.height == 261)
    Swag.assert(rgba.pixelFormat == .RGBA8)
    assertGifPixelAt(rgba, 0, 0, 0'u8, 0'u8, 0'u8, 0'u8)
}

// Direct decoder exposes frame iteration metadata for animated GIFs.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("test.gif"))
    var dec: Gif.Decoder
    expect dec.open(nnBytes(bytes.toSlice()))
    let numFrames = expect dec.frameCount()
    Swag.assert(numFrames == 21)

    var frame: Image
    var count = 0
    for
    {
        let next = expect dec.nextFrame(&frame)
        if !next do
            break
        count += 1
    }

    Swag.assert(count == 21)
    Swag.assert(frame.width == 439)
    Swag.assert(frame.height == 341)
    Swag.assert(frame.pixelFormat == .RGBA8)
}

// Decode with decodePixels=false: metadata fields are populated but no pixel buffer is allocated.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("testa.gif"))
    var opts: DecodeOptions
    opts.decodePixels = false

    let img = expect Image.decode("meta.gif", bytes.toSlice(), opts)
    Swag.assert(img.width == 250)
    Swag.assert(img.height == 261)
    Swag.assert(img.pixelFormat == .RGBA8)
    Swag.assert(!img.isValid())
}

// Invalid and truncated buffers should fail without producing an image.
#test
{
    let bad: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    var img: Image
    img = catch Image.decode("bad.gif", Swag.makeSlice(&bad[0], bad.count), {}) as err11
    Swag.assert(err11 != null)

    let bytes = expect File.readAllBytes(getTestDataPath("test.gif"))
    img = catch Image.decode("truncated.gif", Swag.makeSlice(bytes.buffer, 32), {}) as err13
    Swag.assert(err13 != null)
}

// Encode RGB8 images with an exact palette and preserve the colors through the decoder.
#test
{
    var src    = Image.create(2, 2, .RGB8)
    let srcBuf = src.pixels.buffer!
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
    Swag.assert(img.pixelFormat == .RGB8)
    Swag.assert(Memory.compare(src.pixels.buffer, img.pixels.buffer, src.pixels.count) == 0)
}

// Encode RGBA8 with GIF's single transparent index.
#test
{
    var src    = Image.create(2, 1, .RGBA8)
    let srcBuf = src.pixels.buffer!
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
    let bgrBuf = bgr.pixels.buffer!
    bgrBuf[0] = 30'u8
    bgrBuf[1] = 20'u8
    bgrBuf[2] = 10'u8

    let bgrEncoded = expect bgr.encode("memory.gif")
    let bgrDecoded = expect Image.decode("bgr.gif", nnBytes(bgrEncoded.toSlice()), {})
    assertGifPixelAt(bgrDecoded, 0, 0, 10'u8, 20'u8, 30'u8, 255'u8)

    var bgra    = Image.create(1, 1, .BGRA8)
    let bgraBuf = bgra.pixels.buffer!
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
    var pix = src.pixels.buffer!
    for i in src.width * src.height
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
    Swag.assert(img.width == 17)
    Swag.assert(img.height == 17)
    Swag.assert(img.pixelFormat == .RGB8)
    assertGifPixelAt(img, 0, 0, 0'u8, 0'u8, 0'u8, 255'u8)
}

// Quantize red-first and blue-first sources with exact channel levels and scalar tails.
#test
{
    expect assertQuantizedGif24(.RGB8)
    expect assertQuantizedGif24(.BGR8)
    expect assertQuantizedGif32(.RGBA8, false)
    expect assertQuantizedGif32(.BGRA8, false)
    expect assertQuantizedGif32(.RGBA8, true)
    expect assertQuantizedGif32(.BGRA8, true)
}

// Encode to a file path and reload through the registry.
#test
{
    let path = makeTempGifPath()
    defer discard catch File.delete(path.toString())
    var src    = Image.create(1, 1, .RGB8)
    let srcBuf = src.pixels.buffer!
    srcBuf[0] = 12'u8
    srcBuf[1] = 34'u8
    srcBuf[2] = 56'u8

    let cb = expect src.encode("memory.gif")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    assertGifPixelAt(img, 0, 0, 12'u8, 34'u8, 56'u8, 255'u8)
}
