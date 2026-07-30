#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func pngCanEncode(fileName: string)->bool
{
    var enc: Png.Encoder
    let itf = @mkinterface(&enc, #typeof(Png.Encoder), IImageEncoder)
    return itf.canEncode(fileName)
}

func encodePng(result: *ConcatBuffer, image: Image, options: #null any = null) fail
{
    var enc: Png.Encoder
    let itf = @mkinterface(&enc, #typeof(Png.Encoder), IImageEncoder)
    itf.encode(result, image, options)
}

func assertPngPixelAt(img: Image, x, yFromBottom: s32, r, g, b, a: u8)
{
    let idx = cast(u64) (yFromBottom * img.width + x) * img.bpp8
    @assert((notnull img.pixels.buffer)[idx] == r)
    @assert((notnull img.pixels.buffer)[idx + 1] == g)
    @assert((notnull img.pixels.buffer)[idx + 2] == b)
    if img.bpp8 == 4 do
        @assert((notnull img.pixels.buffer)[idx + 3] == a)
}

func assertLoadedPng(fileName: string, width, height: s32, pf: PixelFormat, r, g, b, a: u8)
{
    var img: Image
    img = catch Image.load(getTestDataPath(fileName)) as err
    @assert(err == null)
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

func assertEncodedPngRoundtrip(src: Image, expectedPf: PixelFormat, options: #null any = null)
{
    var cb: ConcatBuffer
    catch encodePng(&cb, src, options) as err2
    @assert(err2 == null)

    let bytes = nnBytes(cb.toSlice())
    @assert(@countof(bytes) > 33)
    @assert(bytes[0] == 137'u8 and bytes[1] == 80'u8 and bytes[2] == 78'u8 and bytes[3] == 71'u8)
    assertPngHasChunk(bytes, 73'u8, 72'u8, 68'u8, 82'u8)
    assertPngHasChunk(bytes, 73'u8, 68'u8, 65'u8, 84'u8)
    assertPngHasChunk(bytes, 73'u8, 69'u8, 78'u8, 68'u8)

    var img: Image
    img = catch Image.decode("encoded.png", bytes, {}) as err3
    @assert(err3 == null)
    @assert(img.width == src.width)
    @assert(img.height == src.height)
    @assert(img.pf == expectedPf)
    @assert(img.pixels.count == src.pixels.count)
    @assert(Memory.compare(src.pixels.buffer, img.pixels.buffer, src.pixels.count) == 0)
}

func fillSolidPngImage(img: *Image, r, g, b, a: u8)
{
    var pix = notnull img.pixels.buffer
    for img.width * img.height
    {
        switch img.pf
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

        pix += img.bpp8
    }
}

func addPngU16Be(result: *ConcatBuffer, value: u16)
{
    result.addNative(cast(u8) ((value >> 8) & 0xFF))
    result.addNative(cast(u8) (value & 0xFF))
}

func addPngU32Be(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8) ((value >> 24) & 0xFF))
    result.addNative(cast(u8) ((value >> 16) & 0xFF))
    result.addNative(cast(u8) ((value >> 8) & 0xFF))
    result.addNative(cast(u8) (value & 0xFF))
}

func addPngChunk(result: *ConcatBuffer, chunkType: string, data: const [..] u8)
{
    @assert(@countof(chunkType) == 4)
    addPngU32Be(result, cast(u32) @countof(data))
    result.addBytes(chunkType)
    result.addBytes(data)

    var crc: Hash.Crc32
    crc.update(chunkType)
    crc.update(data)
    addPngU32Be(result, crc.crc)
}

func addPngSignature(result: *ConcatBuffer)
{
    const signature: [8] u8 = [137, 80, 78, 71, 13, 10, 26, 10]
    result.addBytes(signature)
}

func addPngHeader(result: *ConcatBuffer, width, height: u32, bitDepth, colorType: u8)
{
    var ihdr: ConcatBuffer
    addPngU32Be(&ihdr, width)
    addPngU32Be(&ihdr, height)
    ihdr.addNative(bitDepth)
    ihdr.addNative(colorType)
    ihdr.addNative(0'u8)
    ihdr.addNative(0'u8)
    ihdr.addNative(0'u8)
    addPngChunk(result, "IHDR", nnBytes(ihdr.toSlice()))
}

func addPngImageData(result: *ConcatBuffer, raw: const [..] u8)
{
    var zlib: Compress.ZLib
    let compressed = catch zlib.compress(raw, .Default) as compressionError
    @assert(compressionError == null)
    addPngChunk(result, "IDAT", nnBytes(compressed.toSlice()))
}

func assertPngDecodeFails(fileName: string, encoded: *ConcatBuffer)
{
    let bytes = cbToArray(encoded)
    var image: Image
    image = catch Image.decode(fileName, nnBytes(bytes.toSlice()), {}) as decodeError
    @assert(decodeError != null)
}

func buildPng16(width, height: s32, colorType: u8, interlace: bool, samples: const [..] u16, transparency: #null const [..] u16 = null)->Array'u8
{
    var channels: s32
    switch colorType
    {
    case 0:  channels = 1
    case 2:  channels = 3
    case 4:  channels = 2
    case 6:  channels = 4
    default: unreachable
    }

    @assert(@countof(samples) == cast(u64) width * cast(u64) height * cast(u64) channels)

    var raw: ConcatBuffer
    if !interlace
    {
        for [y] in height
        {
            raw.addNative(0'u8)
            for [x] in width
            {
                let pixel = cast(u64) (y * width + x) * cast(u64) channels
                for [c] in channels do
                    addPngU16Be(&raw, samples[pixel + c])
            }
        }
    }
    else
    {
        let startX: [7] s32 = [0, 4, 0, 2, 0, 1, 0]
        let startY: [7] s32 = [0, 0, 4, 0, 2, 0, 1]
        let stepX:  [7] s32 = [8, 8, 4, 4, 2, 2, 1]
        let stepY:  [7] s32 = [8, 8, 8, 4, 4, 2, 2]

        for [pass] in 7
        {
            if startX[pass] >= width or startY[pass] >= height do
                continue

            for var y = startY[pass]; y < height; y += stepY[pass]
            {
                raw.addNative(0'u8)
                for var x = startX[pass]; x < width; x += stepX[pass]
                {
                    let pixel = cast(u64) (y * width + x) * cast(u64) channels
                    for [c] in channels do
                        addPngU16Be(&raw, samples[pixel + c])
                }
            }
        }
    }

    var zlib: Compress.ZLib
    let compressed = catch zlib.compress(nnBytes(raw.toSlice()), .Default) as compressionError
    @assert(compressionError == null)

    var result: ConcatBuffer
    addPngSignature(&result)

    var ihdr: ConcatBuffer
    addPngU32Be(&ihdr, cast(u32) width)
    addPngU32Be(&ihdr, cast(u32) height)
    ihdr.addNative(16'u8)
    ihdr.addNative(colorType)
    ihdr.addNative(0'u8)
    ihdr.addNative(0'u8)
    ihdr.addNative(interlace ? 1'u8 : 0'u8)
    addPngChunk(&result, "IHDR", nnBytes(ihdr.toSlice()))

    if transparency != null
    {
        var trns: ConcatBuffer
        for value in notnull transparency do
            addPngU16Be(&trns, value)
        addPngChunk(&result, "tRNS", nnBytes(trns.toSlice()))
    }

    addPngChunk(&result, "IDAT", nnBytes(compressed.toSlice()))
    addPngChunk(&result, "IEND", "")
    return cbToArray(&result)
}

// Reject structural errors before reading pixels or indexing palette data.
#test
{
    const trueColorRow: [4] u8 = [0, 10, 20, 30]
    const indexedRow:   [2] u8 = [0, 0]
    const palette:      [3] u8 = [10, 20, 30]
    const alpha:        [1] u8 = [127]

    var shortHeader: ConcatBuffer
    addPngSignature(&shortHeader)
    var shortIHDR: [12] u8
    addPngChunk(&shortHeader, "IHDR", shortIHDR)
    addPngChunk(&shortHeader, "IEND", "")
    assertPngDecodeFails("short-ihdr.png", &shortHeader)

    var truncatedChecksum: ConcatBuffer
    addPngSignature(&truncatedChecksum)
    addPngHeader(&truncatedChecksum, 1, 1, 8, 2)
    addPngU32Be(&truncatedChecksum, 1)
    truncatedChecksum.addBytes("IDAT")
    truncatedChecksum.addNative(0'u8)
    assertPngDecodeFails("truncated-checksum.png", &truncatedChecksum)

    var hugeImage: ConcatBuffer
    addPngSignature(&hugeImage)
    addPngHeader(&hugeImage, 0xFFFFFFFF, 1, 8, 2)
    addPngImageData(&hugeImage, trueColorRow)
    addPngChunk(&hugeImage, "IEND", "")
    assertPngDecodeFails("huge.png", &hugeImage)

    var unknownCritical: ConcatBuffer
    addPngSignature(&unknownCritical)
    addPngHeader(&unknownCritical, 1, 1, 8, 2)
    addPngChunk(&unknownCritical, "ABCD", "")
    addPngImageData(&unknownCritical, trueColorRow)
    addPngChunk(&unknownCritical, "IEND", "")
    assertPngDecodeFails("unknown-critical.png", &unknownCritical)

    var transparencyBeforePalette: ConcatBuffer
    addPngSignature(&transparencyBeforePalette)
    addPngHeader(&transparencyBeforePalette, 1, 1, 1, 3)
    addPngChunk(&transparencyBeforePalette, "tRNS", alpha)
    addPngChunk(&transparencyBeforePalette, "PLTE", palette)
    addPngImageData(&transparencyBeforePalette, indexedRow)
    addPngChunk(&transparencyBeforePalette, "IEND", "")
    assertPngDecodeFails("trns-before-plte.png", &transparencyBeforePalette)

    var duplicateTransparency: ConcatBuffer
    addPngSignature(&duplicateTransparency)
    addPngHeader(&duplicateTransparency, 1, 1, 1, 3)
    addPngChunk(&duplicateTransparency, "PLTE", palette)
    addPngChunk(&duplicateTransparency, "tRNS", alpha)
    addPngChunk(&duplicateTransparency, "tRNS", alpha)
    addPngImageData(&duplicateTransparency, indexedRow)
    addPngChunk(&duplicateTransparency, "IEND", "")
    assertPngDecodeFails("duplicate-trns.png", &duplicateTransparency)

    var emptyPalette: ConcatBuffer
    addPngSignature(&emptyPalette)
    addPngHeader(&emptyPalette, 1, 1, 1, 3)
    addPngChunk(&emptyPalette, "PLTE", "")
    addPngImageData(&emptyPalette, indexedRow)
    addPngChunk(&emptyPalette, "IEND", "")
    assertPngDecodeFails("empty-plte.png", &emptyPalette)

    var nonEmptyEnd: ConcatBuffer
    addPngSignature(&nonEmptyEnd)
    addPngHeader(&nonEmptyEnd, 1, 1, 8, 2)
    addPngImageData(&nonEmptyEnd, trueColorRow)
    addPngChunk(&nonEmptyEnd, "IEND", alpha)
    assertPngDecodeFails("non-empty-iend.png", &nonEmptyEnd)
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

// Decode 16-bit grayscale and RGBA samples by reducing the full 16-bit range
// to the module's 8-bit pixel formats.
#test
{
    var gray: Array'u16
    gray.add(0x0000)
    gray.add(0x8080)
    gray.add(0xFFFF)

    let grayPng = buildPng16(3, 1, 0, false, gray.toSlice())
    let grayImg = catch Image.decode("gray16.png", nnBytes(grayPng.toSlice()), {}) as err4
    @assert(err4 == null)
    @assert(grayImg.pf == .RGB8)
    assertPngPixelAt(grayImg, 0, 0, 0'u8, 0'u8, 0'u8, 255'u8)
    assertPngPixelAt(grayImg, 1, 0, 128'u8, 128'u8, 128'u8, 255'u8)
    assertPngPixelAt(grayImg, 2, 0, 255'u8, 255'u8, 255'u8, 255'u8)

    var rgba: Array'u16
    rgba.add(0x1234)
    rgba.add(0x8080)
    rgba.add(0xFFFF)
    rgba.add(0x0101)

    let rgbaPng = buildPng16(1, 1, 6, false, rgba.toSlice())
    let rgbaImg = catch Image.decode("rgba16.png", nnBytes(rgbaPng.toSlice()), {}) as err5
    @assert(err5 == null)
    @assert(rgbaImg.pf == .RGBA8)
    assertPngPixelAt(rgbaImg, 0, 0, 18'u8, 128'u8, 255'u8, 1'u8)
}

// A 16-bit tRNS key compares the original samples before reduction to 8 bits.
#test
{
    var samples: Array'u16
    samples.add(0x1234); samples.add(0x5678); samples.add(0x9ABC)
    samples.add(0x1235); samples.add(0x5678); samples.add(0x9ABC)

    var key: Array'u16
    key.add(0x1234)
    key.add(0x5678)
    key.add(0x9ABC)

    let png = buildPng16(2, 1, 2, false, samples.toSlice(), key.toSlice())
    let img = catch Image.decode("rgb16-trns.png", nnBytes(png.toSlice()), {}) as err6
    @assert(err6 == null)
    @assert(img.pf == .RGBA8)
    @assert((notnull img.pixels.buffer)[3] == 0'u8)
    @assert((notnull img.pixels.buffer)[7] == 255'u8)
}

// Decode every Adam7 pass for a 16-bit RGB image and preserve pixel placement.
#test
{
    const Width  = 5
    const Height = 5

    var samples: Array'u16
    for [y] in Height
    {
        for [x] in Width
        {
            samples.add(cast(u16) (10 + x + y * Width) * 257)
            samples.add(cast(u16) (50 + x * 2 + y) * 257)
            samples.add(cast(u16) (100 + x + y * 3) * 257)
        }
    }

    let png = buildPng16(Width, Height, 2, true, samples.toSlice())
    let img = catch Image.decode("rgb16-adam7.png", nnBytes(png.toSlice()), {}) as err7
    @assert(err7 == null)
    @assert(img.pf == .RGB8)

    for [y] in Height
    {
        for [x] in Width
        {
            assertPngPixelAt(img, x, Height - y - 1,
                             cast(u8) (10 + x + y * Width),
                             cast(u8) (50 + x * 2 + y),
                             cast(u8) (100 + x + y * 3),
                             255'u8)
        }
    }
}

// Decode palette and tRNS transparency chunks.
#test
{
    var pal: Image
    pal = catch Image.load(getTestDataPath("paletted.png")) as err4
    @assert(err4 == null)
    @assert(pal.width == 34)
    @assert(pal.height == 24)
    @assert(pal.pf == .RGBA8)
    assertPngPixelAt(pal, 10, 0, 83'u8, 56'u8, 70'u8, 255'u8)

    var grayKey: Image
    grayKey = catch Image.load(getTestDataPath("tbbn0g04.png")) as err5
    @assert(err5 == null)
    @assert(grayKey.pf == .RGBA8)
    assertPngPixelAt(grayKey, 15, 1, 238'u8, 238'u8, 238'u8, 255'u8)

    var rgbKey: Image
    rgbKey = catch Image.load(getTestDataPath("tbrn2c08.png")) as err6
    @assert(err6 == null)
    @assert(rgbKey.pf == .RGBA8)
    assertPngPixelAt(rgbKey, 0, 0, 255'u8, 255'u8, 255'u8, 0'u8)
}

// Decode with decodePixels=false: metadata fields are populated but no pixel buffer is allocated.
#test
{
    let bytes = catch File.readAllBytes(getTestDataPath("rgb.png")) as err7
    @assert(err7 == null)

    var opts: DecodeOptions
    opts.decodePixels = false

    var img: Image
    img = catch Image.decode("meta.png", bytes.toSlice(), opts) as err8
    @assert(err8 == null)
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

    catch src.save(path.toString()) as err9
    @assert(err9 == null)

    let img = catch Image.load(path.toString()) as err10
    @assert(err10 == null)
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
    img = catch Image.decode("bad.png", @mkslice(&bad[0], @countof(bad)), {}) as err11
    @assert(err11 != null)

    let bytes = catch File.readAllBytes(getTestDataPath("rgb.png")) as err12
    @assert(err12 == null)
    img = catch Image.decode("truncated.png", @mkslice(bytes.buffer, 32), {}) as err13
    @assert(err13 != null)
}

// Encode RGB8 and RGBA8 images and verify exact round-trips through the decoder.
#test
{
    var rgb = Image.create(2, 2, .RGB8)
    rgb.clear()
    let rgbBuf = notnull rgb.pixels.buffer
    rgbBuf[0]  = 10'u8
    rgbBuf[1]  = 20'u8
    rgbBuf[2]  = 30'u8
    rgbBuf[9]  = 100'u8
    rgbBuf[10] = 110'u8
    rgbBuf[11] = 120'u8
    assertEncodedPngRoundtrip(rgb, .RGB8)

    var rgba = Image.create(2, 2, .RGBA8)
    rgba.clear()
    let rgbaBuf = notnull rgba.pixels.buffer
    rgbaBuf[0]  = 1'u8
    rgbaBuf[1]  = 2'u8
    rgbaBuf[2]  = 3'u8
    rgbaBuf[3]  = 4'u8
    rgbaBuf[12] = 200'u8
    rgbaBuf[13] = 201'u8
    rgbaBuf[14] = 202'u8
    rgbaBuf[15] = 203'u8
    assertEncodedPngRoundtrip(rgba, .RGBA8)
}

// Encode BGR/BGRA source images by swapping R/B into PNG's RGB component order.
#test
{
    var bgr    = Image.create(1, 1, .BGR8)
    let bgrBuf = notnull bgr.pixels.buffer
    bgrBuf[0] = 30'u8
    bgrBuf[1] = 20'u8
    bgrBuf[2] = 10'u8

    var cb: ConcatBuffer
    catch encodePng(&cb, bgr) as err14
    @assert(err14 == null)

    var img: Image
    img = catch Image.decode("bgr.png", nnBytes(cb.toSlice()), {}) as err15
    @assert(err15 == null)
    @assert(img.pf == .RGB8)
    assertPngPixelAt(img, 0, 0, 10'u8, 20'u8, 30'u8, 255'u8)

    var bgra    = Image.create(1, 1, .BGRA8)
    let bgraBuf = notnull bgra.pixels.buffer
    bgraBuf[0] = 7'u8
    bgraBuf[1] = 8'u8
    bgraBuf[2] = 9'u8
    bgraBuf[3] = 10'u8

    cb.clear()
    catch encodePng(&cb, bgra) as err16
    @assert(err16 == null)

    img = catch Image.decode("bgra.png", nnBytes(cb.toSlice()), {}) as err17
    @assert(err17 == null)
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
    catch encodePng(&cb, src, opts) as err18
    @assert(err18 == null)
    discard catch File.writeAllBytes(path.toString(), cb) as err19
    @assert(err19 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err20
    @assert(err20 == null)
    @assert(img.pf == .RGB8)
    @assert(Memory.compare(src.pixels.buffer, img.pixels.buffer, src.pixels.count) == 0)
}

// Default options enable filtering and Deflate compression, unlike an explicit
// stored stream.
#test
{
    var src = Image.create(64, 64, .RGB8)
    fillSolidPngImage(&src, 24'u8, 48'u8, 96'u8, 255'u8)

    var compressed: ConcatBuffer
    catch encodePng(&compressed, src) as err
    @assert(err == null)

    var options: Png.EncodeOptions
    options.filtering        = false
    options.compressionLevel = .NoCompression

    var stored: ConcatBuffer
    catch encodePng(&stored, src, options) as storedErr
    @assert(storedErr == null)
    @assert(compressed.count() < stored.count())

    compressed.makeLinear()
    let decoded = catch Image.decode("default-options.png", nnBytes(compressed.toSlice()), {}) as decodeErr
    @assert(decodeErr == null)
    @assert(Memory.compare(src.pixels.buffer, decoded.pixels.buffer, src.pixels.count) == 0)
}

// Encode Adam7-interlaced RGB and BGRA images, including odd dimensions that
// exercise every pass, and round-trip them through the decoder.
#test
{
    var options: Png.EncodeOptions
    options.interlace = true

    var rgb    = Image.create(9, 7, .RGB8)
    let rgbBuf = notnull rgb.pixels.buffer
    for [y] in rgb.height
    {
        for [x] in rgb.width
        {
            let offset = cast(u64) (y * rgb.width + x) * 3
            rgbBuf[offset]     = cast(u8) (x * 17 + y)
            rgbBuf[offset + 1] = cast(u8) (x + y * 19)
            rgbBuf[offset + 2] = cast(u8) (x * 7 + y * 11)
        }
    }

    var cb: ConcatBuffer
    catch encodePng(&cb, rgb, options) as err20
    @assert(err20 == null)
    let rgbBytes = nnBytes(cb.toSlice())
    @assert(rgbBytes[28] == 1'u8)

    var decoded = catch Image.decode("adam7-rgb.png", rgbBytes, {}) as err21
    @assert(err21 == null)
    @assert(decoded.pf == .RGB8)
    @assert(Memory.compare(rgb.pixels.buffer, decoded.pixels.buffer, rgb.pixels.count) == 0)

    var bgra    = Image.create(9, 7, .BGRA8)
    let bgraBuf = notnull bgra.pixels.buffer
    for [y] in bgra.height
    {
        for [x] in bgra.width
        {
            let offset = cast(u64) (y * bgra.width + x) * 4
            bgraBuf[offset]     = cast(u8) (10 + x)
            bgraBuf[offset + 1] = cast(u8) (20 + y)
            bgraBuf[offset + 2] = cast(u8) (30 + x + y)
            bgraBuf[offset + 3] = cast(u8) (40 + x * 3 + y * 5)
        }
    }

    cb.clear()
    catch encodePng(&cb, bgra, options) as err22
    @assert(err22 == null)
    let bgraBytes = nnBytes(cb.toSlice())
    @assert(bgraBytes[28] == 1'u8)

    decoded = catch Image.decode("adam7-bgra.png", bgraBytes, {}) as err23
    @assert(err23 == null)
    @assert(decoded.pf == .RGBA8)
    let decodedBuf = notnull decoded.pixels.buffer
    for [i] in cast(u64) bgra.width * cast(u64) bgra.height
    {
        let offset = i * 4
        @assert(decodedBuf[offset] == bgraBuf[offset + 2])
        @assert(decodedBuf[offset + 1] == bgraBuf[offset + 1])
        @assert(decodedBuf[offset + 2] == bgraBuf[offset])
        @assert(decodedBuf[offset + 3] == bgraBuf[offset + 3])
    }
}
