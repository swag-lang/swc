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

// Loading the first GIF image still applies limits and validates the full container.
#test
{
    let path = getTestDataPath("test.gif")
    var limitError: Swag.Error
    discard catch Image.load(path, {maxFrames: 1}) as limitError
    Swag.require(limitError.value() is Errors.UnsupportedFormatError)

    let bytes     = expect File.readAllBytes(path)
    let truncated = Swag.makeSlice(bytes.storage(), bytes.count - 1)
    var formatError: Swag.Error
    discard catch Image.decode("missing-trailer.gif", truncated, {decodePixels: false}) as formatError
    Swag.require(formatError.value() is Errors.InvalidFormatError)
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

// A graphic control extension consumed by a plain-text block must not affect the next image.
#test
{
    const Bytes: [59] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        1, 0, 1, 0, 0x80, 0, 0,
        0, 0, 0, 255, 255, 255,
        0x21, 0xF9, 4, 0x09, 5, 0, 1, 0,
        0x21, 0x01, 12, 0, 0, 0, 0, 1, 0, 1, 0, 8, 8, 1, 0, 0,
        0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0,
        2, 2, 0x4C, 0x01, 0, 0x3B]

    var reader = expect ImageReader.decode("plain-text-control.gif", Bytes)
    Swag.require(reader.info.frames.count == 1)
    let frame = reader.info.frames[0]
    Swag.require(frame.pixelFormat == .RGB8 and
                 frame.durationSeconds == 0 and
                 frame.disposal == .Keep)
    assertGifPixelAt(expect reader.read(0), 0, 0, 255, 255, 255, 255)
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

#test
{
    const MissingEndCode: [34] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        1, 0, 1, 0, 0x80, 0, 0,
        0, 0, 0, 255, 255, 255,
        0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0,
        2, 1, 1, 0, 0x3B]
    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("missing-eoi.gif", MissingEndCode) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// GIF LZW streams begin with clear; the minimal clear/literal/end stream still decodes.
#test
{
    const ValidClearCode: [35] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        1, 0, 1, 0, 0x80, 0, 0,
        0, 0, 0, 255, 255, 255,
        0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0,
        2, 2, 0x4C, 0x01, 0, 0x3B]
    let image = expect Image.decode("initial-clear.gif", ValidClearCode)
    assertGifPixelAt(image, 0, 0, 255, 255, 255, 255)

    const MissingClearCode: [35] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        1, 0, 1, 0, 0x80, 0, 0,
        0, 0, 0, 255, 255, 255,
        0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0,
        2, 2, 0x49, 0x01, 0, 0x3B]
    var invalidImage: Image
    var errorOutcome: Swag.Error
    catch { invalidImage = try Image.decode("missing-initial-clear.gif", MissingClearCode) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Interlaced two-row GIFs skip empty passes without mapping a row outside the frame.
#test
{
    const Bytes: [35] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        1, 0, 2, 0, 0x80, 0, 0,
        0, 0, 0, 255, 255, 255,
        0x2C, 0, 0, 0, 0, 1, 0, 2, 0, 0x40,
        2, 2, 0x44, 0x0A, 0, 0x3B]
    let image = expect Image.decode("interlaced-two-row.gif", Bytes)
    Swag.require(image.width == 1 and image.height == 2)
    assertGifPixelAt(image, 0, 1, 0, 0, 0, 255)
    assertGifPixelAt(image, 0, 0, 255, 255, 255, 255)
}

// A short, dense LZW stream may reference the dictionary entry it is still constructing.
#test
{
    const Bytes: [38] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        3, 0, 1, 0, 0x80, 0, 0,
        19, 43, 71, 109, 151, 197,
        0x2C, 0, 0, 0, 0, 3, 0, 1, 0, 0,
        8,
        5, 0x00, 0x03, 0x08, 0x0C, 0x08,
        0, 0x3B]
    let image = expect Image.decode("dense-self-reference.gif", Bytes)
    Swag.require(image.width == 3 and image.height == 1)
    for x in image.width do
        assertGifPixelAt(image, x, 0, 109, 151, 197, 255)
}

// LZW codes cross sub-blocks while interlaced rows are restored in all four passes.
#test
{
    const Bytes: [72] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        5, 0, 10, 0, 0x81, 0, 0,
        11, 31, 59, 83, 101, 127, 149, 167, 191, 211, 229, 251,
        0x2C, 0, 0, 0, 0, 5, 0, 10, 0, 0x40,
        2,
        1, 0x44,
        2, 0xA8, 0x11,
        1, 0x60,
        8, 0xC4, 0x81, 0x08, 0x35, 0x42, 0x1C, 0x18, 0x51,
        17, 0x23, 0x42, 0x85, 0x1A, 0x11, 0x0E, 0x8C, 0xB8, 0x50, 0x23, 0xC2, 0x81, 0x11, 0x17, 0x6A, 0x44, 0x0A,
        0, 0x3B]
    let image = expect Image.decode("interlaced-split-blocks.gif", Bytes)
    Swag.require(image.width == 5 and image.height == 10)
    const Colors: [4, 3] u8 = [[11, 31, 59], [83, 101, 127], [149, 167, 191], [211, 229, 251]]
    for y in image.height
    {
        for x in image.width
        {
            let index = (x + y) % 4
            assertGifPixelAt(image, x, image.height - y - 1, Colors[index, 0], Colors[index, 1], Colors[index, 2], 255)
        }
    }
}

// A single opaque frame still uses its logical screen if its rectangle is smaller.
#test
{
    const Bytes: [35] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        3, 0, 2, 0, 0x80, 0, 0,
        19, 43, 71, 109, 151, 197,
        0x2C, 2, 0, 1, 0, 1, 0, 1, 0, 0,
        2, 2, 0x4C, 0x01, 0, 0x3B]
    let image = expect Image.decode("opaque-partial-frame.gif", Bytes)
    Swag.require(image.width == 3 and image.height == 2)
    Swag.require(image.pixelFormat == .RGB8)
    assertGifPixelAt(image, 2, 0, 109, 151, 197, 255)
    assertGifPixelAt(image, 2, 1, 19, 43, 71, 255)
    assertGifPixelAt(image, 1, 0, 19, 43, 71, 255)
}

// A partial first frame uses its local palette and clears RGB under transparent GIF pixels.
#test
{
    const Bytes: [49] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        3, 0, 2, 0, 0x80, 0, 0,
        19, 43, 71, 109, 151, 197,
        0x21, 0xF9, 4, 1, 0, 0, 0, 0,
        0x2C, 1, 0, 1, 0, 2, 0, 1, 0, 0x80,
        29, 52, 84, 183, 214, 237,
        2, 2, 0x44, 0x0A, 0, 0x3B]
    let image = expect Image.decode("transparent-partial-frame.gif", Bytes)
    Swag.require(image.width == 3 and image.height == 2)
    Swag.require(image.pixelFormat == .RGBA8)
    assertGifPixelAt(image, 1, 0, 0, 0, 0, 0)
    assertGifPixelAt(image, 2, 0, 183, 214, 237, 255)
    assertGifPixelAt(image, 2, 1, 0, 0, 0, 0)

    var reader = expect ImageReader.decode("transparent-partial-frame.gif", Bytes)
    let canvas = expect reader.read(0)
    Swag.require(Memory.compare(image.pixels.storage(), canvas.pixels.storage(), image.byteCount) == 0)
}

func wideGifPaletteFixture(withTransparency, invalidIndex: bool)->Array'u8
{
    const Header: [25] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        33, 0, 9, 0, 0x81, 0, 0,
        17, 103, 219, 255, 40, 13, 150, 235, 72, 249, 128, 213]
    const Control:    [8] u8  = [0x21, 0xF9, 4, 1, 0, 0, 1, 0]
    const Descriptor: [11] u8 = [0x2C, 0, 0, 0, 0, 33, 0, 9, 0, 0, 3]
    const PixelCount          = 33 * 9
    var bytes: #returntype
    bytes.add(Header)
    if withTransparency do
        bytes.add(Control)
    bytes.add(Descriptor)

    for offset in PixelCount
    {
        if offset == 0 do
            bytes.add(255'u8)
        elif offset == 255 do
            bytes.add(cast(u8, (PixelCount + 1 - 255)))

        // Each byte has a four-bit clear code followed by a literal.
        let paletteIndex = invalidIndex and offset == 16 ? 4 : (offset & 3)
        bytes.add(cast(u8, ((paletteIndex << 4) | 8)))
    }

    bytes.add(9'u8)        // LZW end code
    bytes.add(0'u8)        // Sub-block terminator
    bytes.add(0x3B'u8)     // GIF trailer
    return bytes
}

// A four-color palette decodes SIMD blocks and the scalar row tail in both RGB and RGBA.
#test
{
    const Palette: [12] u8 = [17, 103, 219, 255, 40, 13, 150, 235, 72, 249, 128, 213]
    for mode in 2
    {
        let withTransparency = mode == 1
        let bytes = wideGifPaletteFixture(withTransparency, false)
        let image = expect Image.decode("wide-palette.gif", nnBytes(bytes.toSlice()))
        Swag.require(image.width == 33 and image.height == 9)
        Swag.require(image.pixelFormat == (withTransparency ? .RGBA8 : .RGB8))
        for y in image.height
        {
            for x in image.width
            {
                let paletteIndex = (y * image.width + x) & 3
                let color        = paletteIndex * 3
                let row          = image.height - y - 1
                if withTransparency and paletteIndex == 1 do
                    assertGifPixelAt(image, x, row, 0, 0, 0, 0)
                else do
                    assertGifPixelAt(image, x, row, Palette[color], Palette[color + 1], Palette[color + 2], 255)
            }
        }
    }
}

// A lookup in the vector block still rejects a code outside the declared palette.
#test
{
    let bytes = wideGifPaletteFixture(true, true)
    var errorOutcome: Swag.Error
    discard catch Image.decode("wide-invalid-palette.gif", nnBytes(bytes.toSlice())) as errorOutcome
    Swag.require(errorOutcome.value() is Errors.InvalidFormatError)
}

// A literal allowed by LZW is still invalid when it has no palette entry.
#test
{
    const Bytes: [35] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        1, 0, 1, 0, 0x80, 0, 0,
        0, 0, 0, 255, 255, 255,
        0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0,
        2, 2, 0x54, 0x01, 0, 0x3B]
    var errorOutcome: Swag.Error
    discard catch Image.decode("invalid-palette-index.gif", Bytes) as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

#test
{
    var bytes = expect File.readAllBytes(getTestDataPath("test.gif"))
    var image:     Image
    var gceOffset: u64
    for i in bytes.count - 7
    {
        if bytes[i] == 0x21 and bytes[i + 1] == 0xF9 and bytes[i + 2] == 4
        {
            gceOffset = i
            break
        }
    }

    Swag.require(gceOffset != 0)
    bytes[gceOffset + 3] = bytes[gceOffset + 3] | 0x10     // Disposal methods 4..7 are reserved.
    var disposalError: Swag.Error
    catch { image = try Image.decode("bad-control.gif", bytes.toSlice()) } as disposalError
    Swag.require(disposalError.value() != null)

    bytes[gceOffset + 3] = bytes[gceOffset + 3] & 0xEF
    bytes[gceOffset + 7] = 1     // A graphic control extension must end with zero.

    var terminatorError: Swag.Error
    catch { image = try Image.decode("bad-control.gif", bytes.toSlice()) } as terminatorError
    Swag.require(terminatorError.value() != null)

    bytes[gceOffset + 7] = 0
    bytes[gceOffset + 2] = 3     // The payload contains exactly four bytes.
    var sizeError: Swag.Error
    catch { image = try Image.decode("bad-control.gif", bytes.toSlice()) } as sizeError
    Swag.require(sizeError.value() != null)
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

// Encode 8-bit grayscale images as neutral RGB colours and preserve grayscale transparency.
#test
{
    var gray    = Image.create(2, 1, .Gray8)
    let grayBuf = gray.pixels.storage()
    grayBuf[0] = 37'u8
    grayBuf[1] = 219'u8
    let grayBytes   = expect gray.encodeToBytes("gray.gif")
    let grayDecoded = expect Image.decode("gray.gif", grayBytes.toSlice())
    assertGifPixelAt(grayDecoded, 0, 0, 37'u8, 37'u8, 37'u8, 255'u8)
    assertGifPixelAt(grayDecoded, 1, 0, 219'u8, 219'u8, 219'u8, 255'u8)

    var grayAlpha = Image.create(2, 1, .GrayAlpha8)
    let alphaBuf  = grayAlpha.pixels.storage()
    alphaBuf[0] = 80'u8
    alphaBuf[1] = 0'u8
    alphaBuf[2] = 180'u8
    alphaBuf[3] = 255'u8
    let alphaBytes   = expect grayAlpha.encodeToBytes("gray-alpha.gif")
    let alphaDecoded = expect Image.decode("gray-alpha.gif", alphaBytes.toSlice())
    assertGifPixelAt(alphaDecoded, 0, 0, 0'u8, 0'u8, 0'u8, 0'u8)
    assertGifPixelAt(alphaDecoded, 1, 0, 180'u8, 180'u8, 180'u8, 255'u8)
}

// Higher precision and floating point formats must fail instead of silently encoding as black.
#test
{
    var src: Image
    src.init(1, 1, .Gray16)
    var errorOutcome: Swag.Error
    catch { discard try src.encodeToBytes("unsupported.gif") } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// A truncated public pixel array must be rejected before the encoder reads its storage.
#test
{
    var src = Image.create(1, 1, .RGB8)
    src.pixels.count = 0
    var errorOutcome: Swag.Error
    catch { discard try src.encodeToBytes("truncated.gif") } as errorOutcome
    Swag.require(errorOutcome.value() != null)
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
