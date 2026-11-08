#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func assertGifPixelAt(img: Image, x, yFromBottom: s32, r, g, b, a: u8)
{
    let idx = cast(u64, (yFromBottom * img.width + x)) * img.bytesPerPixel
    Swag.require(img.pixels.storage()[idx] == r)
    Swag.require(img.pixels.storage()[idx + 1] == g)
    Swag.require(img.pixels.storage()[idx + 2] == b)
    if img.bytesPerPixel == 4 do
        Swag.require(img.pixels.storage()[idx + 3] == a)
}

func assertAdaptiveGif(pixelFormat: PixelFormat, withTransparency: bool) fail
{
    const Width = 523
    var source    = Image.create(Width, 1, pixelFormat)
    var pix       = source.pixels.storage()
    let blueFirst = pixelFormat == .BGR8 or pixelFormat == .BGRA8
    for i in Width
    {
        let r = cast(u8, (i & 0xFF))
        let g = cast(u8, ((i * 37 + 11) & 0xFF))
        let b = cast(u8, ((i * 73 + 19) & 0xFF))
        let a = withTransparency ? cast(u8, ((i * 53 + 7) & 0xFF)) : 255'u8
        pix[0] = blueFirst ? b : r
        pix[1] = g
        pix[2] = blueFirst ? r : b
        if source.bytesPerPixel == 4 do
            pix[3] = a
        pix += source.bytesPerPixel
    }

    var encoded = expect source.encode("memory.gif")
    encoded.makeLinear()
    let decoded = expect Image.decode("quantized.gif", nnBytes(encoded.toSlice()), {})
    Swag.require(decoded.pixelFormat == (withTransparency ? .RGBA8 : .RGB8))
    var error = 0'u64
    for i in Width
    {
        let r = cast(u8, (i & 0xFF))
        let g = cast(u8, ((i * 37 + 11) & 0xFF))
        let b = cast(u8, ((i * 73 + 19) & 0xFF))
        let a = withTransparency ? cast(u8, ((i * 53 + 7) & 0xFF)) : 255'u8
        if withTransparency and a < 128
        {
            assertGifPixelAt(decoded, i, 0, 0, 0, 0, 0)
        }
        else
        {
            let color = decoded.pixelColor(i, 0)
            error += cast(u64, Math.abs(cast(s32, color.r) - r))
            error += cast(u64, Math.abs(cast(s32, color.g) - g))
            error += cast(u64, Math.abs(cast(s32, color.b) - b))
        }
    }

    Swag.require(error < cast(u64, Width) * 3 * 16)
}

func assertGifHeader(bytes: const [..] u8, width, height: u16)
{
    Swag.require(bytes.count > 20)
    Swag.require(bytes[0] == 'G' and bytes[1] == 'I' and bytes[2] == 'F')
    Swag.require(bytes[3] == '8' and bytes[4] == '9' and bytes[5] == 'a')
    Swag.require(bytes[6] == cast(u8, (width & 0xFF)))
    Swag.require(bytes[7] == cast(u8, (width >> 8)))
    Swag.require(bytes[8] == cast(u8, (height & 0xFF)))
    Swag.require(bytes[9] == cast(u8, (height >> 8)))
    Swag.require(bytes[bytes.count - 1] == 0x3B'u8)
}

func assertEncodedGifRoundtrip(src: Image, expectedPf: PixelFormat)
{
    let cb    = expect src.encode("memory.gif")
    let bytes = nnBytes(cb.toSlice())
    assertGifHeader(bytes, cast(u16, src.width), cast(u16, src.height))

    let img = expect Image.decode("encoded.gif", bytes, {})
    Swag.require(img.width == src.width)
    Swag.require(img.height == src.height)
    Swag.require(img.pixelFormat == expectedPf)
    Swag.require(img.pixels.count == cast(u64, src.width) * src.height * img.bytesPerPixel)
}

// Decoder and encoder registries recognise GIF files.
#test
{
    Swag.require(Image.canLoad("in.gif"))
    Swag.require(Image.canSave("out.gif"))
}

// Load animated GIF fixtures and decode their first frames.
#test
{
    let rgb = expect Image.load(getTestDataPath("test.gif"))
    Swag.require(rgb.isValid())
    Swag.require(rgb.width == 439)
    Swag.require(rgb.height == 341)
    Swag.require(rgb.pixelFormat == .RGBA8)
    assertGifPixelAt(rgb, 0, 0, 183'u8, 107'u8, 3'u8, 255'u8)

    let rgba = expect Image.load(getTestDataPath("testa.gif"))
    Swag.require(rgba.isValid())
    Swag.require(rgba.width == 250)
    Swag.require(rgba.height == 261)
    Swag.require(rgba.pixelFormat == .RGBA8)
    assertGifPixelAt(rgba, 0, 0, 0'u8, 0'u8, 0'u8, 0'u8)
}

// Direct decoder exposes frame iteration metadata for animated GIFs.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("test.gif"))
    var dec: Gif.Decoder
    expect dec.open(nnBytes(bytes.toSlice()))
    let numFrames = expect dec.frameCount()
    Swag.require(numFrames == 21)

    var frame: Image
    var count = 0
    for
    {
        let next = expect dec.nextFrame(&frame)
        if not next do
            break
        count += 1
    }

    Swag.require(count == 21)
    Swag.require(frame.width == 439)
    Swag.require(frame.height == 341)
    Swag.require(frame.pixelFormat == .RGBA8)
}

// Decode with decodePixels=false: metadata fields are populated but no pixel buffer is allocated.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("testa.gif"))
    var opts: DecodeOptions
    opts.decodePixels = false

    let img = expect Image.decode("meta.gif", bytes.toSlice(), opts)
    Swag.require(img.width == 250)
    Swag.require(img.height == 261)
    Swag.require(img.pixelFormat == .RGBA8)
    Swag.require(not img.isValid())
}

// Invalid and truncated buffers should fail without producing an image.
#test
{
    let bad: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    var img: Image
    var err11Outcome: Swag.Error
    catch { img = try Image.decode("bad.gif", Swag.makeSlice(&bad[0], bad.count), {}) } as err11Outcome
    let err11 = err11Outcome.value()
    Swag.require(err11 != null)

    let bytes = expect File.readAllBytes(getTestDataPath("test.gif"))
    var err13Outcome: Swag.Error
    catch { img = try Image.decode("truncated.gif", Swag.makeSlice(bytes.buffer, 32), {}) } as err13Outcome
    let err13 = err13Outcome.value()
    Swag.require(err13 != null)
}

// Encode RGB8 images with an exact palette and preserve the colors through the decoder.
#test
{
    var src    = Image.create(2, 2, .RGB8)
    let srcBuf = src.pixels.storage()
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
    Swag.require(img.pixelFormat == .RGB8)
    Swag.require(Memory.compare(src.pixels.storage(), img.pixels.storage(), src.pixels.count) == 0)
}

// All 256 GIF colour slots remain exact, including the highest index.
#test
{
    var src    = Image.create(256, 1, .RGB8)
    let pixels = src.pixels.storage()
    for i in 256
    {
        pixels[i * 3]     = cast(u8, i)
        pixels[i * 3 + 1] = cast(u8, (i * 29) & 255)
        pixels[i * 3 + 2] = cast(u8, (i * 53) & 255)
    }

    let encoded = expect src.encodeToBytes("exact.gif")
    let decoded = expect Image.decode("exact.gif", encoded.toSlice())
    Swag.require(Memory.compare(src.pixels.storage(), decoded.pixels.storage(), src.pixels.count) == 0)
}

// Encode RGBA8 with GIF's single transparent index.
#test
{
    var src    = Image.create(2, 1, .RGBA8)
    let srcBuf = src.pixels.storage()
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
    let bgrBuf = bgr.pixels.storage()
    bgrBuf[0] = 30'u8
    bgrBuf[1] = 20'u8
    bgrBuf[2] = 10'u8

    let bgrEncoded = expect bgr.encode("memory.gif")
    let bgrDecoded = expect Image.decode("bgr.gif", nnBytes(bgrEncoded.toSlice()), {})
    assertGifPixelAt(bgrDecoded, 0, 0, 10'u8, 20'u8, 30'u8, 255'u8)

    var bgra    = Image.create(1, 1, .BGRA8)
    let bgraBuf = bgra.pixels.storage()
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
    var pix = src.pixels.storage()
    for i in src.width * src.height
    {
        let x = i % src.width
        let y = i / src.width
        pix[0] = cast(u8, (x * 15))
        pix[1] = cast(u8, (y * 15))
        pix[2] = cast(u8, ((x * 13 + y * 7) & 0xFF))
        pix    += 3
    }

    var cb = expect src.encode("memory.gif")
    cb.makeLinear()
    let img = expect Image.decode("quantized.gif", nnBytes(cb.toSlice()), {})
    Swag.require(img.width == 17)
    Swag.require(img.height == 17)
    Swag.require(img.pixelFormat == .RGB8)
}

// An adaptive palette preserves common screen colours and bounds the error of varied pixels.
#test
{
    expect assertAdaptiveGif(.RGB8, false)
    expect assertAdaptiveGif(.BGR8, false)
    expect assertAdaptiveGif(.RGBA8, false)
    expect assertAdaptiveGif(.BGRA8, false)
    expect assertAdaptiveGif(.RGBA8, true)
    expect assertAdaptiveGif(.BGRA8, true)
}

// Encode to a file path and reload through the registry.
#test
{
    let path = makeTempGifPath()
    defer discard catch File.delete(path.toString())
    var src    = Image.create(1, 1, .RGB8)
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 12'u8
    srcBuf[1] = 34'u8
    srcBuf[2] = 56'u8

    let cb = expect src.encode("memory.gif")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    assertGifPixelAt(img, 0, 0, 12'u8, 34'u8, 56'u8, 255'u8)
}
