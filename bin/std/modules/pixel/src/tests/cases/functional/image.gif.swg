#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func assertGifPixelAt(img: Image, x, yFromBottom: s32, r, g, b, a: u8)
{
    let idx = cast(u64, (yFromBottom * img.width + x)) * img.bytesPerPixel
    Swag.require(img.pixels.storage()[idx] == r)
    Swag.require(img.pixels.storage()[idx + 1] == g)
    Swag.require(img.pixels.storage()[idx + 2] == b)
    if img.bytesPerPixel == 4
    {
        Swag.require(img.pixels.storage()[idx + 3] == a)
    }
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
        let a = withTransparency ? cast(u8, ((i * 53 + 7) & 0xFF)) : 255_u8
        pix[0] = blueFirst ? b : r
        pix[1] = g
        pix[2] = blueFirst ? r : b
        if source.bytesPerPixel == 4
        {
            pix[3] = a
        }

        pix += source.bytesPerPixel
    }

    var encoded = expect source.encode("memory.gif")
    encoded.makeLinear()
    let decoded = expect Image.decode("quantized.gif", nnBytes(encoded.toSlice()), {})
    Swag.require(decoded.pixelFormat == (withTransparency ? .RGBA8 : .RGB8))
    var error = 0_u64
    for i in Width
    {
        let r = cast(u8, (i & 0xFF))
        let g = cast(u8, ((i * 37 + 11) & 0xFF))
        let b = cast(u8, ((i * 73 + 19) & 0xFF))
        let a = withTransparency ? cast(u8, ((i * 53 + 7) & 0xFF)) : 255_u8
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
    Swag.require(bytes[bytes.count - 1] == 0x3B_u8)
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
    assertGifPixelAt(rgb, 0, 0, 183_u8, 107_u8, 3_u8, 255_u8)

    let rgba = expect Image.load(getTestDataPath("testa.gif"))
    Swag.require(rgba.isValid())
    Swag.require(rgba.width == 250)
    Swag.require(rgba.height == 261)
    Swag.require(rgba.pixelFormat == .RGBA8)
    assertGifPixelAt(rgba, 0, 0, 0_u8, 0_u8, 0_u8, 0_u8)
}

// Random GIF reads reuse only earlier opaque updates whose disposal is independent.
#test
{
    const Colors: [4, 3] u8 = [[0, 0, 0], [40, 70, 130], [180, 35, 65], [111, 189, 55]]
    const Header: [25] u8   = [
        'G', 'I', 'F', '8', '9', 'a', 2, 0, 1, 0, 0x81, 0, 0,
        0, 0, 0, 40, 70, 130, 180, 35, 65, 111, 189, 55]
    const PaletteIndices: [9] u8 = [1, 2, 3, 1, 0, 0, 1, 2, 3]
    for anchorDisposal in [1_u8, 2]
    {
        let disposals: [9] u8 = [1_u8, anchorDisposal, 3, 1, 3, 1, 2, 1, 1]
        var bytes:     Array!{u8}
        bytes.add(Header)
        for frameIndex in 9
        {
            let color = cast(u16, PaletteIndices[frameIndex])
            let width = frameIndex == 3 or frameIndex == 5 ? 1_u8 : 2_u8
            let left  = frameIndex == 3 ? 1_u8 : 0_u8
            let flags = (disposals[frameIndex] << 2) | cast(u8, frameIndex == 5)
            let codes = frameIndex == 7 ? 5 :
                        width == 1 ? (4 | color << 3 | 5 << 6) : (4 | color << 3 | color << 6 | 5 << 9)
            bytes.add([0x21_u8, 0xF9, 4, flags, 3, 0, 0, 0])
            bytes.add([0x2C_u8, left, 0, 0, 0, width, 0, 1, 0, 0, 2, 2])
            bytes.add([cast(u8, codes & 255), cast(u8, codes >> 8), 0])
        }

        bytes.add(0x3B_u8)
        var reader = expect ImageReader.decode("replayed.gif", nnBytes(bytes.toSlice()))
        discard expect reader.read(6)
        for frameIndex in [3_u32, 5, 0, 6, 3, 5]
        {
            let image = expect reader.read(frameIndex)
            let left  = frameIndex == 0 or frameIndex == 6 ? 1 : anchorDisposal == 1 ? 2 : 0
            assertGifPixelAt(image, 0, 0, Colors[left, 0], Colors[left, 1], Colors[left, 2], 255)
            assertGifPixelAt(image, 1, 0, Colors[1, 0], Colors[1, 1], Colors[1, 2], 255)
        }

        // Even when a later unopened frame covers the canvas, the invalid frame must fail the read.
        var errorOutcome: Swag.Error
        discard catch reader.read(8) as errorOutcome
        Swag.require(errorOutcome.value() is Errors.InvalidFormatError)
        let recovered = expect reader.read(3)
        let left      = anchorDisposal == 1 ? 2 : 0
        assertGifPixelAt(recovered, 0, 0, Colors[left, 0], Colors[left, 1], Colors[left, 2], 255)
    }
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
        if not next
        {
            break
        }

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
    for x in image.width
    {
        assertGifPixelAt(image, x, 0, 109, 151, 197, 255)
    }
}

// GIF LZW can refer to a phrase being added and finish with fewer than four pixels.
#test
{
    const Bytes: [45] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        21, 0, 1, 0, 0x81, 0, 0,
        13, 17, 25, 49, 61, 79, 83, 103, 127, 149, 179, 197,
        0x2C, 0, 0, 0, 0, 21, 0, 1, 0, 0,
        2, 1, 0x8C, 4, 0x8F, 0x69, 0xB2, 5, 0, 0x3B]
    let image = expect Image.decode("packed-phrases.gif", Bytes)
    Swag.require(image.width == 21 and image.height == 1)
    for x in 21
    {
        if x == 17 or x == 20
        {
            assertGifPixelAt(image, x, 0, 83, 103, 127, 255)
        }
        else
        {
            assertGifPixelAt(image, x, 0, 49, 61, 79, 255)
        }
    }

    var tooShort = Bytes
    tooShort[6]  = 20
    tooShort[30] = 20
    var errorOutcome: Swag.Error
    discard catch Image.decode("packed-phrases-overflow.gif", tooShort) as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Paired short LZW phrases can be followed by self-references, longer phrases, and a clear.
#test
{
    const Bytes: [71] u8 = [
        'G', 'I', 'F', '8', '9', 'a', 88, 0, 1, 0, 0x81, 0, 0,
        14, 24, 34, 44, 54, 64, 74, 84, 94, 104, 114, 124,
        0x2C, 0, 0, 0, 0, 88, 0, 1, 0, 0, 2,
        4, 68, 52, 1, 50,
        8, 96, 135, 146, 57, 180, 218, 171, 152,
        2, 57, 40,
        15, 153, 67, 76, 1, 153, 128, 177, 67, 201, 28, 148, 204, 65, 169, 0,
        0, 0x3B]
    let image = expect Image.decode("paired-lzw-boundaries.gif", Bytes)
    Swag.require(image.width == 88 and image.height == 1 and image.pixelFormat == .RGB8)
    Swag.require(Hash.Crc32.compute(image.pixels.toSlice()) == 1112078511_u32)
}

// Dense literals can cross both LZW code widths and GIF sub-block boundaries.
#test
{
    const RunLength       = 530
    const Width           = 2 * RunLength
    const WidthLow        = cast(u8, Width & 255)
    const WidthHigh       = cast(u8, Width >> 8)
    const Header: [13] u8 = ['G', 'I', 'F', '8', '9', 'a', WidthLow, WidthHigh, 1, 0, 0x87, 0, 0]
    const Frame:  [11] u8 = [0x2C, 0, 0, 0, 0, WidthLow, WidthHigh, 1, 0, 0, 8]
    var bytes: Array!{u8}
    bytes.add(Header)
    for color in 256
    {
        let channel = cast(u8, color)
        bytes.add([channel, channel, channel])
    }

    let frameOffset = bytes.count
    bytes.add(Frame)
    var payload:   Array!{u8}
    var bits:      u32
    var available: u32
    for i in 2 * (RunLength + 1) + 1
    {
        let offset = i % (RunLength + 1)
        let code   = i == 2 * (RunLength + 1) ? 257 : offset == 0 ? 256 : (offset * 73 + 19) & 255
        let size   = i == 0 or (offset > 0 and offset <= 255) ? 9 : 10
        bits      |= cast(u32, code) << available
        available += size
        while available >= 8
        {
            payload.add(cast(u8, bits & 255))
            bits      >>= 8
            available -= 8
        }
    }

    if available
    {
        payload.add(cast(u8, bits))
    }

    var remaining = payload.toSlice()
    while remaining.count
    {
        let length = Math.min(11_u64, remaining.count)
        bytes.add(cast(u8, length))
        bytes.add(Swag.makeSlice(remaining.buffer, length))
        remaining = Swag.makeSlice(remaining.buffer + length, remaining.count - length)
    }

    bytes.add([0_u8, 0x3B])
    let image = expect Image.decode("dense-literal-pairs.gif", nnBytes(bytes.toSlice()))
    Swag.require(image.width == Width and image.height == 1)
    for pixel in Width
    {
        let expected = cast(u8, (((pixel % RunLength + 1) * 73 + 19) & 255))
        assertGifPixelAt(image, pixel, 0, expected, expected, expected, 255)
    }

    bytes[6] = WidthLow - 1
    bytes[frameOffset + 5] = WidthLow - 1
    var errorOutcome: Swag.Error
    discard catch Image.decode("dense-literal-overflow.gif", nnBytes(bytes.toSlice())) as errorOutcome
    Swag.require(errorOutcome.value() is Errors.InvalidFormatError)
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

func wideGifPaletteFixture(withTransparency, invalidIndex: bool, width: u8 = 33, height: u8 = 9)->Array!{u8}
{
    const Header: [25] u8 = [
        'G', 'I', 'F', '8', '9', 'a',
        33, 0, 9, 0, 0x81, 0, 0,
        17, 103, 219, 255, 40, 13, 150, 235, 72, 249, 128, 213]
    const Control: [8] u8 = [0x21, 0xF9, 4, 1, 0, 0, 1, 0]
    let descriptor: [11] u8 = [0x2C, 0, 0, 0, 0, width, 0, height, 0, 0, 3]
    var header = Header
    header[6] = width
    header[8] = height
    let pixelCount = cast(u32, width) * height
    var bytes: #returntype
    bytes.add(header)
    if withTransparency
    {
        bytes.add(Control)
    }

    bytes.add(descriptor)

    for offset in pixelCount
    {
        if offset == 0
        {
            bytes.add(255_u8)
        }
        else if offset == 255
        {
            bytes.add(cast(u8, (pixelCount + 1 - 255)))
        }

        // Each byte has a four-bit clear code followed by a literal.
        let paletteIndex = invalidIndex and offset == 16 ? 4 : (offset & 3)
        bytes.add(cast(u8, ((paletteIndex << 4) | 8)))
    }

    bytes.add(9_u8)        // LZW end code
    bytes.add(0_u8)        // Sub-block terminator
    bytes.add(0x3B_u8)     // GIF trailer
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
                if withTransparency and paletteIndex == 1
                {
                    assertGifPixelAt(image, x, row, 0, 0, 0, 0)
                }
                else
                {
                    assertGifPixelAt(image, x, row, Palette[color], Palette[color + 1], Palette[color + 2], 255)
                }
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

    let canvasBytes = wideGifPaletteFixture(true, true, width: 99, height: 3)
    var reader      = expect ImageReader.decode("wide-invalid-palette.gif", nnBytes(canvasBytes.toSlice()))
    var canvasError: Swag.Error
    discard catch reader.read(0) as canvasError
    Swag.require(canvasError.value() is Errors.InvalidFormatError)
}

func gifPalette32Fixture(withAlpha: bool, invalidOffset: s32 = -1)->Array!{u8}
{
    const Header:  [13] u8 = ['G', 'I', 'F', '8', '9', 'a', 79, 0, 4, 0, 0x84, 0, 0]
    const Control: [8] u8  = [0x21, 0xF9, 4, 1, 0, 0, 17, 0]
    const Frame:   [11] u8 = [0x2C, 0, 0, 0, 0, 79, 0, 4, 0, 0, 6]
    var bytes: #returntype
    bytes.add(Header)
    for index in 32
    {
        bytes.add([cast(u8, index * 7 + 4), cast(u8, 191 - index * 5), cast(u8, index * 3 + 17)])
    }

    if withAlpha
    {
        bytes.add(Control)
    }

    bytes.add(Frame)
    var payload:   Array!{u8}
    var bits:      u32
    var available: u32
    for pixel in 79 * 4 + 1
    {
        let colorIndex = pixel == invalidOffset ? 32 : pixel & 31
        let finalCode  = pixel == 79 * 4
        bits      |= cast(u32, finalCode ? 65 : (64 | colorIndex << 7)) << available
        available += finalCode ? 7 : 14
        while available >= 8
        {
            payload.add(cast(u8, bits & 255))
            bits      >>= 8
            available -= 8
        }
    }

    if available
    {
        payload.add(cast(u8, bits))
    }

    bytes.add(255_u8)
    bytes.add(Swag.makeSlice(payload.storage(), 255))
    bytes.add(255_u8)
    bytes.add(Swag.makeSlice(payload.storage() + 255, 255))
    bytes.add(cast(u8, payload.count - 510))
    bytes.add(Swag.makeSlice(payload.storage() + 510, payload.count - 510))
    bytes.add([0_u8, 0x3B])
    return bytes
}

// A 32-entry palette handles both shuffle banks, RGB and RGBA, and the right edge.
#test
{
    for withAlpha in [false, true]
    {
        let bytes = gifPalette32Fixture(withAlpha)
        let image = expect Image.decode("palette32.gif", nnBytes(bytes.toSlice()))
        Swag.require(image.width == 79 and image.height == 4)
        Swag.require(image.pixelFormat == (withAlpha ? .RGBA8 : .RGB8))
        for y in 4
        {
            for x in 79
            {
                let index = (y * 79 + x) & 31
                if withAlpha and index == 17
                {
                    assertGifPixelAt(image, x, 3 - y, 0, 0, 0, 0)
                }
                else
                {
                    assertGifPixelAt(image, x, 3 - y, cast(u8, index * 7 + 4), cast(u8, 191 - index * 5), cast(u8, index * 3 + 17), 255)
                }
            }
        }
    }

    for offset in [22, 78]
    {
        let bytes = gifPalette32Fixture(true, offset)
        var errorOutcome: Swag.Error
        discard catch Image.decode("palette32-invalid.gif", nnBytes(bytes.toSlice())) as errorOutcome
        Swag.require(errorOutcome.value() is Errors.InvalidFormatError)
    }
}

func paddedGifPaletteFixture(paletteSize: u32, lastIndex: u16, withTransparency: bool, firstIndex: u8 = 5)->Array!{u8}
{
    const Header:  [13] u8 = ['G', 'I', 'F', '8', '9', 'a', 129, 0, 64, 0, 0x87, 0, 0]
    const Control: [8] u8  = [0x21, 0xF9, 4, 1, 0, 0, 5, 0]
    const Frame:   [11] u8 = [0x2C, 0, 0, 0, 0, 129, 0, 64, 0, 0, 8]
    var header = Header
    header[10] = paletteSize == 256 ? 0x87_u8 : 0x84_u8
    var bytes: #returntype
    bytes.add(header)
    for index in paletteSize
    {
        bytes.add([cast(u8, index), cast(u8, 255 - index), cast(u8, index ^ 131)])
    }

    if withTransparency
    {
        var control = Control
        control[6] = firstIndex
        bytes.add(control)
    }

    bytes.add(Frame)
    bytes.add(149_u8)
    var bits:      u32
    var available: u32
    for i in 132
    {
        // A run of 8,255 indices followed by a clear and the last literal.
        let key = i == 0 or i == 129 ? 256_u32 : i == 1 ? cast(u32, firstIndex) :
                  i < 128 ? cast(u32, 256 + i) : i == 128 ? 383 : i == 130 ? cast(u32, lastIndex) : 257
        bits      |= key << available
        available += 9
        while available >= 8
        {
            bytes.add(cast(u8, bits & 255))
            bits      >>= 8
            available -= 8
        }
    }

    bytes.add(cast(u8, bits))
    bytes.add([0_u8, 0x3B])
    return bytes
}

// Padded palettes may still need a late high index, even after an LZW clear.
#test
{
    for key in [13_u16, 25, 129]
    {
        for transparent in [false, true]
        {
            let bytes = paddedGifPaletteFixture(256, key, transparent)
            let image = expect Image.decode("padded-palette.gif", nnBytes(bytes.toSlice()))
            Swag.require(image.width == 129 and image.height == 64)
            assertGifPixelAt(image, 128, 0, cast(u8, key), cast(u8, 255 - key), cast(u8, key ^ 131), 255)
            if transparent
            {
                assertGifPixelAt(image, 127, 0, 0, 0, 0, 0)
            }
            else
            {
                assertGifPixelAt(image, 127, 0, 5, 250, 134, 255)
            }

            var reader = expect ImageReader.decode("padded-palette.gif", nnBytes(bytes.toSlice()))
            let frame  = expect reader.read(0)
            if transparent
            {
                assertGifPixelAt(frame, 127, 0, 0, 0, 0, 0)
            }

            assertGifPixelAt(frame, 128, 0, cast(u8, key), cast(u8, 255 - key), cast(u8, key ^ 131), 255)
        }
    }

    let invalid = paddedGifPaletteFixture(32, 129, false)
    var errorOutcome: Swag.Error
    discard catch Image.decode("padded-palette-invalid.gif", nnBytes(invalid.toSlice())) as errorOutcome
    Swag.require(errorOutcome.value() is Errors.InvalidFormatError)
}

// Skipping a transparent SIMD block still rejects indices outside its palette.
#test
{
    let bytes  = paddedGifPaletteFixture(32, 13, true, firstIndex: 129)
    var reader = expect ImageReader.decode("invalid-transparent-palette.gif", nnBytes(bytes.toSlice()))
    var errorOutcome: Swag.Error
    discard catch reader.read(0) as errorOutcome
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
    srcBuf[0]  = 10_u8
    srcBuf[1]  = 20_u8
    srcBuf[2]  = 30_u8
    srcBuf[3]  = 40_u8
    srcBuf[4]  = 50_u8
    srcBuf[5]  = 60_u8
    srcBuf[6]  = 70_u8
    srcBuf[7]  = 80_u8
    srcBuf[8]  = 90_u8
    srcBuf[9]  = 100_u8
    srcBuf[10] = 110_u8
    srcBuf[11] = 120_u8

    let cb  = expect src.encode("memory.gif")
    let img = expect Image.decode("rgb.gif", nnBytes(cb.toSlice()), {})
    Swag.require(img.pixelFormat == .RGB8)
    Swag.require(Memory.compare(src.pixels.storage(), img.pixels.storage(), src.pixels.count) == 0)
}

// The first occurrence of each gray still determines palette order across narrow rows.
#test
{
    const Width  = 97
    const Height = 1031
    let source = Image.create(Width, Height, .Gray8)
    let pixels = source.pixels.storage()
    for y in Height
    {
        let row = pixels + cast(u64, y) * Width
        for x in Width
        {
            row[x] = cast #wrap(u8, ((Height - 1 - y) * Width + x) * 73)
        }
    }

    let encoded = expect source.encodeToBytes("gray-across-rows.gif")
    Swag.require(Hash.Crc32.compute(encoded.toSlice()) == 4260205349_u32)
    let decoded = expect Image.decode("gray-across-rows.gif", encoded.toSlice())
    Swag.require(decoded.width == Width and decoded.height == Height and decoded.pixelFormat == .RGB8)
    let output = decoded.pixels.storage()
    for pixel in Width * Height
    {
        let gray = pixels[pixel]
        Swag.require(output[3 * pixel] == gray and
                     output[3 * pixel + 1] == gray and
                     output[3 * pixel + 2] == gray)
    }
}

// GIF uniform fills use the same transparency threshold when source samples differ.
#test
{
    for alpha in [127_u8, 128]
    {
        var source = Image.create(7, 37, .BGRA8)
        source.fill(Color.fromArgb(alpha, 92, 174, 227))
        let pixels = source.pixels.storage()
        pixels[3] = alpha == 127 ? 42 : 199
        if alpha == 127
        {
            pixels[0] = 35
        }

        let encoded = expect source.encodeToBytes("uniform-bgra.gif")
        let decoded = expect Image.decode("uniform-bgra.gif", encoded.toSlice())
        Swag.require(decoded.width == source.width and decoded.height == source.height)
        if alpha == 127
        {
            assertGifPixelAt(decoded, 6, 36, 0, 0, 0, 0)
        }
        else
        {
            assertGifPixelAt(decoded, 6, 36, 92, 174, 227, 255)
        }
    }
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
    grayBuf[0] = 37_u8
    grayBuf[1] = 219_u8
    let grayBytes   = expect gray.encodeToBytes("gray.gif")
    let grayDecoded = expect Image.decode("gray.gif", grayBytes.toSlice())
    assertGifPixelAt(grayDecoded, 0, 0, 37_u8, 37_u8, 37_u8, 255_u8)
    assertGifPixelAt(grayDecoded, 1, 0, 219_u8, 219_u8, 219_u8, 255_u8)

    var grayAlpha = Image.create(2, 1, .GrayAlpha8)
    let alphaBuf  = grayAlpha.pixels.storage()
    alphaBuf[0] = 80_u8
    alphaBuf[1] = 0_u8
    alphaBuf[2] = 180_u8
    alphaBuf[3] = 255_u8
    let alphaBytes   = expect grayAlpha.encodeToBytes("gray-alpha.gif")
    let alphaDecoded = expect Image.decode("gray-alpha.gif", alphaBytes.toSlice())
    assertGifPixelAt(alphaDecoded, 0, 0, 0_u8, 0_u8, 0_u8, 0_u8)
    assertGifPixelAt(alphaDecoded, 1, 0, 180_u8, 180_u8, 180_u8, 255_u8)
}

// A full grayscale ramp in the first row fixes the palette order across dictionary resets.
#test
{
    let source = Image.create(263, 277, .Gray8)
    for y in source.height
    {
        for x in source.width
        {
            source.pixels.storage()[y * source.rowStride + x] = cast(u8, (x * 73 + y * 61) & 255)
        }
    }

    let encoded = expect source.encodeToBytes("full-gray.gif")
    let decoded = expect Image.decode("full-gray.gif", encoded.toSlice())
    Swag.require(decoded.width == source.width and decoded.height == source.height)
    Swag.require(decoded.pixelFormat == .RGB8)
    for i in source.pixels.count
    {
        let gray  = source.pixels[i]
        let pixel = decoded.pixels.storage() + 3 * i
        Swag.require(pixel[0] == gray and pixel[1] == gray and pixel[2] == gray)
    }
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
    srcBuf[0] = 1_u8
    srcBuf[1] = 2_u8
    srcBuf[2] = 3_u8
    srcBuf[3] = 0_u8
    srcBuf[4] = 40_u8
    srcBuf[5] = 50_u8
    srcBuf[6] = 60_u8
    srcBuf[7] = 255_u8

    assertEncodedGifRoundtrip(src, .RGBA8)

    let cb  = expect src.encode("memory.gif")
    let img = expect Image.decode("rgba.gif", nnBytes(cb.toSlice()), {})
    assertGifPixelAt(img, 0, 0, 0_u8, 0_u8, 0_u8, 0_u8)
    assertGifPixelAt(img, 1, 0, 40_u8, 50_u8, 60_u8, 255_u8)
}

// Encode BGR/BGRA source images by reading their channel layout correctly.
#test
{
    var bgr    = Image.create(1, 1, .BGR8)
    let bgrBuf = bgr.pixels.storage()
    bgrBuf[0] = 30_u8
    bgrBuf[1] = 20_u8
    bgrBuf[2] = 10_u8

    let bgrEncoded = expect bgr.encode("memory.gif")
    let bgrDecoded = expect Image.decode("bgr.gif", nnBytes(bgrEncoded.toSlice()), {})
    assertGifPixelAt(bgrDecoded, 0, 0, 10_u8, 20_u8, 30_u8, 255_u8)

    var bgra    = Image.create(1, 1, .BGRA8)
    let bgraBuf = bgra.pixels.storage()
    bgraBuf[0] = 7_u8
    bgraBuf[1] = 8_u8
    bgraBuf[2] = 9_u8
    bgraBuf[3] = 10_u8

    let bgraEncoded = expect bgra.encode("memory.gif")
    let bgraDecoded = expect Image.decode("bgra.gif", nnBytes(bgraEncoded.toSlice()), {})
    assertGifPixelAt(bgraDecoded, 0, 0, 0_u8, 0_u8, 0_u8, 0_u8)
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
    srcBuf[0] = 12_u8
    srcBuf[1] = 34_u8
    srcBuf[2] = 56_u8

    let cb = expect src.encode("memory.gif")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    assertGifPixelAt(img, 0, 0, 12_u8, 34_u8, 56_u8, 255_u8)
}

// Direct palette lookups stay valid across repeated dictionary epochs at both table sizes.
#test
{
    for colorCount in [32_u8, 128]
    {
        let source = Image.create(colorCount == 32 ? 641 : 769, colorCount == 32 ? 321 : 349, .RGB8)
        var pixels = source.pixels.storage()
        var state  = 0x8F01943C_u32
        for cast(u64, source.width) * source.height
        {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            let index = cast #wrap(u8, state) & (colorCount - 1)
            pixels[0] = index * #wrap 23_u8
            pixels[1] = index * #wrap 39_u8
            pixels[2] = index * #wrap 97_u8
            pixels    += 3
        }

        let encoded = expect source.encodeToBytes("direct-palette-epochs.gif")
        let crc     = colorCount == 32 ? 1974264148_u32 : 839454945_u32
        Swag.require(Hash.Crc32.compute(encoded.toSlice()) == crc)
        let decoded = expect Image.decode("direct-palette-epochs.gif", encoded.toSlice())
        Swag.require(decoded.pixelFormat == .RGB8 and decoded.pixels.count == source.pixels.count)
        Swag.require(Memory.compare(source.pixels.storage(), decoded.pixels.storage(), source.pixels.count) == 0)
    }
}

// A dense palette crosses enough dictionary clears to reuse its literal-pair epochs.
#test
{
    let source = Image.create(433, 181, .RGB8)
    var pixels = source.pixels.storage()
    var state  = 0x985842A1_u32
    for cast(u64, source.width) * source.height
    {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        let color = cast #wrap(u8, state)
        pixels[0] = color
        pixels[1] = color * #wrap 37_u8
        pixels[2] = color * #wrap 73_u8
        pixels    += 3
    }

    let encoded = expect source.encodeToBytes("dense-pairs.gif")
    Swag.require(Hash.Crc32.compute(encoded.toSlice()) == 3227398783_u32)
    let decoded = expect Image.decode("dense-pairs.gif", encoded.toSlice())
    Swag.require(decoded.pixelFormat == .RGB8 and decoded.pixels.count == source.pixels.count)
    Swag.require(Memory.compare(source.pixels.storage(), decoded.pixels.storage(), source.pixels.count) == 0)
}

// A uniform palette's LZW run codes cross several code widths and clear the dictionary.
#test
{
    let source = Image.create(4097, 2201, .Gray8)
    Memory.set(source.pixels.storage(), 137, source.pixels.count)
    let encoded = expect source.encodeToBytes("long-run.gif")
    let decoded = expect Image.decode("long-run.gif", encoded.toSlice())
    Swag.require(decoded.width == source.width and decoded.height == source.height)
    Swag.require(decoded.pixelFormat == .RGB8)
    Swag.require(Hash.Crc32.compute(decoded.pixels.toSlice()) == 3791399009_u32)
}
