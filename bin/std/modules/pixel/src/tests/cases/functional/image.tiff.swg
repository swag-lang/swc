#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Low-level, endian-aware writers used to hand-build TIFF byte buffers.

func tw16(cb: *ConcatBuffer, le: bool, v: u16)
{
    if le
    {
        cb.addNative(cast(u8, (v & 0xFF)))
        cb.addNative(cast(u8, (v >> 8)))
    }
    else
    {
        cb.addNative(cast(u8, (v >> 8)))
        cb.addNative(cast(u8, (v & 0xFF)))
    }
}

func tw32(cb: *ConcatBuffer, le: bool, v: u32)
{
    if le
    {
        cb.addNative(cast(u8, (v & 0xFF)))
        cb.addNative(cast(u8, ((v >> 8) & 0xFF)))
        cb.addNative(cast(u8, ((v >> 16) & 0xFF)))
        cb.addNative(cast(u8, ((v >> 24) & 0xFF)))
    }
    else
    {
        cb.addNative(cast(u8, ((v >> 24) & 0xFF)))
        cb.addNative(cast(u8, ((v >> 16) & 0xFF)))
        cb.addNative(cast(u8, ((v >> 8) & 0xFF)))
        cb.addNative(cast(u8, (v & 0xFF)))
    }
}

// Single inline SHORT value (left-justified in the 4-byte field).
func entShort(cb: *ConcatBuffer, le: bool, tag, value: u16, type: u16 = 3, count: u32 = 1)
{
    tw16(cb, le, tag)
    tw16(cb, le, type)
    tw32(cb, le, count)
    tw16(cb, le, value)
    tw16(cb, le, 0)
}

// Single inline LONG value.
func entLong(cb: *ConcatBuffer, le: bool, tag: u16, value: u32)
{
    tw16(cb, le, tag)
    tw16(cb, le, 4)
    tw32(cb, le, 1)
    tw32(cb, le, value)
}

// Entry whose values live at an external offset.
func entOffset(cb: *ConcatBuffer, le: bool, tag, type: u16, count, offset: u32)
{
    tw16(cb, le, tag)
    tw16(cb, le, type)
    tw32(cb, le, count)
    tw32(cb, le, offset)
}

struct TestTiffLzwWriter
{
    bytes:       Array'u8
    pending:     u64
    pendingBits: u32
}

impl TestTiffLzwWriter
{
    mtd write(code, width: u32)
    {
        .pending     = (.pending << width) | code
        .pendingBits += width
        while .pendingBits >= 8
        {
            .pendingBits -= 8
            .bytes.add(cast(u8, (.pending >> .pendingBits)))
            .pending &= (1'u64 << .pendingBits) - 1
        }
    }

    mtd finish()
    {
        if .pendingBits do
            .bytes.add(cast(u8, (.pending << (8 - .pendingBits))))
    }
}

// Emit only literal LZW codes. This deliberately independent fixture writer
// exercises TIFF's early 9-to-12-bit transitions without sharing the encoder.
func packLiteralTiffLzw(data: const [..] u8)->Array'u8
{
    var writer: TestTiffLzwWriter
    writer.bytes       = {}
    writer.pending     = 0
    writer.pendingBits = 0
    var width    = 9'u32
    var nextCode = 258'u32
    writer.write(256, width)

    for i in data.count
    {
        writer.write(data.buffer[i], width)
        if i
        {
            nextCode += 1
            if width < 12 and nextCode == (1'u32 << width) - 1 do
                width += 1
        }
    }

    writer.write(257, width)
    writer.finish()
    return #move writer.bytes
}

// Build a single-IFD TIFF. Pixel data is laid out top-down. When 'compression'
// is 1 (none), data is split into strips of 'rowsPerStrip' rows; otherwise a
// single strip is emitted holding 'pixelData' verbatim.
func buildTiff(le: bool, width, height, spp, photo, compression, rowsPerStrip, bps: u32, pixelData: const [..] u8, palette: const [..] u16?, extraSamples: bool, predictor: u32 = 1, extraSampleType: u32 = 2, extraSamplesType: u16 = 3, extraSamplesCount: u32 = 1, includeBitsPerSample: bool = true)->Array'u8
{
    var cb: ConcatBuffer

    let bytesPerSample = bps / 8
    let rowBytes       = width * spp * bytesPerSample
    let pixCount       = cast(u32, pixelData.count)
    let palCount       = cast(u32, palette.count)
    let hasPalette     = palCount > 0

    // Strip lengths
    var stripLens: Array'u32
    if compression == 1
    {
        var rows = height
        while rows > 0
        {
            let r = rows < rowsPerStrip ? rows : rowsPerStrip
            stripLens.add(r * rowBytes)
            rows -= r
        }
    }
    else
    {
        stripLens.add(pixCount)
    }

    let numStrips = cast(u32, stripLens.count)

    var numEntries = includeBitsPerSample ? 9'u32 : 8'u32
    if hasPalette do
        numEntries += 1
    if extraSamples do
        numEntries += 1
    if predictor != 1 do
        numEntries += 1

    let ifdSize = 2 + numEntries * 12 + 4
    var cursor  = 8 + ifdSize

    let stripArraysExternal = numStrips > 1
    let stripOffArrayOffset = cursor
    if stripArraysExternal do
        cursor += numStrips * 4
    let stripCntArrayOffset = cursor
    if stripArraysExternal do
        cursor += numStrips * 4

    let bpsExternal = spp > 1 and includeBitsPerSample
    let bpsOffset   = cursor
    if bpsExternal do
        cursor += spp * 2

    let colorMapOffset = cursor
    if hasPalette do
        cursor += palCount * 2

    let dataStart = cursor

    var stripOffs: Array'u32
    var acc = dataStart
    for i in numStrips
    {
        stripOffs.add(acc)
        acc += stripLens[i]
    }

    // Header
    tw16(&cb, le, le ? 0x4949'u16 : 0x4D4D'u16)
    tw16(&cb, le, 42)
    tw32(&cb, le, 8)

    // IFD
    tw16(&cb, le, cast(u16, numEntries))
    entLong(&cb, le, 256, width)
    entLong(&cb, le, 257, height)
    if includeBitsPerSample
    {
        if bpsExternal do
            entOffset(&cb, le, 258, 3, spp, bpsOffset)
        else do
            entShort(&cb, le, 258, cast(u16, bps))
    }

    entShort(&cb, le, 259, cast(u16, compression))
    entShort(&cb, le, 262, cast(u16, photo))
    if stripArraysExternal do
        entOffset(&cb, le, 273, 4, numStrips, stripOffArrayOffset)
    else do
        entLong(&cb, le, 273, stripOffs[0])
    entShort(&cb, le, 277, cast(u16, spp))
    entLong(&cb, le, 278, rowsPerStrip)
    if stripArraysExternal do
        entOffset(&cb, le, 279, 4, numStrips, stripCntArrayOffset)
    else do
        entLong(&cb, le, 279, stripLens[0])
    if predictor != 1 do
        entShort(&cb, le, 317, cast(u16, predictor))
    if hasPalette do
        entOffset(&cb, le, 320, 3, palCount, colorMapOffset)
    if extraSamples do
        entShort(&cb, le, 338, cast(u16, extraSampleType), extraSamplesType, extraSamplesCount)
    tw32(&cb, le, 0)

    // External arrays
    if stripArraysExternal
    {
        for i in numStrips do
            tw32(&cb, le, stripOffs[i])
        for i in numStrips do
            tw32(&cb, le, stripLens[i])
    }

    if bpsExternal
    {
        for spp do
            tw16(&cb, le, cast(u16, bps))
    }

    if hasPalette
    {
        let pal = unwrap palette
        for i in palCount do
            tw16(&cb, le, pal[i])
    }

    // Pixel data
    cb.addBytes(pixelData)
    return cb.toArray()
}

func decodeTiff(bytes: const [..] u8, opt: DecodeOptions = {})->Image fail
{
    var dec: Tiff.Decoder
    let itf: IImageDecoder = &dec
    return try itf.decode(bytes, opt)
}

func tiffDecodeFails(bytes: const [..] u8)->bool
{
    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try decodeTiff(bytes) } as errorOutcome
    return errorOutcome.value() != null
}

// The decoder and encoder registries recognise .tif and .tiff files.
#test
{
    Swag.require(Image.canLoad("in.tif"))
    Swag.require(Image.canLoad("in.tiff"))
    Swag.require(Image.canSave("out.tif"))
    Swag.require(Image.canSave("out.tiff"))
}

// Decode a little-endian 2x1 uncompressed RGB image.
#test
{
    var pix: ConcatBuffer
    pix.addNative(10'u8)
    pix.addNative(20'u8)
    pix.addNative(30'u8)
    pix.addNative(40'u8)
    pix.addNative(50'u8)
    pix.addNative(60'u8)

    let buf = buildTiff(true, 2, 1, 3, 2, 1, 1, 8, nnBytes(pix.toSlice()), null, false)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    Swag.require(img.width == 2)
    Swag.require(img.height == 1)
    Swag.require(img.pixelFormat == .RGB8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10'u8)
    Swag.require(img.pixels.buffer[1] == 20'u8)
    Swag.require(img.pixels.buffer[2] == 30'u8)
    Swag.require(img.pixels.buffer[3] == 40'u8)
    Swag.require(img.pixels.buffer[4] == 50'u8)
    Swag.require(img.pixels.buffer[5] == 60'u8)
}

// Decode a big-endian (MM) image and confirm it matches the little-endian path.
#test
{
    var pix: ConcatBuffer
    pix.addNative(11'u8)
    pix.addNative(22'u8)
    pix.addNative(33'u8)
    pix.addNative(44'u8)
    pix.addNative(55'u8)
    pix.addNative(66'u8)

    let buf = buildTiff(false, 2, 1, 3, 2, 1, 1, 8, nnBytes(pix.toSlice()), null, false)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    Swag.require(img.pixelFormat == .RGB8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 11'u8)
    Swag.require(img.pixels.buffer[3] == 44'u8)
    Swag.require(img.pixels.buffer[5] == 66'u8)
}

// Decode an 8-bit grayscale (BlackIsZero) image into replicated BGR8 channels.
#test
{
    var pix: ConcatBuffer
    pix.addNative(5'u8)
    pix.addNative(10'u8)
    pix.addNative(15'u8)

    let buf = buildTiff(true, 3, 1, 1, 1, 1, 1, 8, nnBytes(pix.toSlice()), null, false)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 5'u8)
    Swag.require(img.pixels.buffer[1] == 5'u8)
    Swag.require(img.pixels.buffer[2] == 5'u8)
    Swag.require(img.pixels.buffer[3] == 10'u8)
    Swag.require(img.pixels.buffer[6] == 15'u8)
}

// Decode WhiteIsZero grayscale: sample values are inverted.
#test
{
    var pix: ConcatBuffer
    pix.addNative(5'u8)
    pix.addNative(250'u8)

    let buf = buildTiff(true, 2, 1, 1, 0, 1, 1, 8, nnBytes(pix.toSlice()), null, false)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 250'u8)
    Swag.require(img.pixels.buffer[3] == 5'u8)
}

// Decode a palette (color-mapped) image via its 16-bit color map.
#test
{
    var pal: Array'u16
    pal.add(10 << 8)
    pal.add(40 << 8)     // red
    pal.add(20 << 8)
    pal.add(50 << 8)     // green
    pal.add(30 << 8)
    pal.add(60 << 8)     // blue

    var pix: ConcatBuffer
    pix.addNative(0'u8)
    pix.addNative(1'u8)

    let buf = buildTiff(true, 2, 1, 1, 3, 1, 1, 8, nnBytes(pix.toSlice()), pal.toSlice(), false)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    Swag.require(img.pixelFormat == .RGB8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10'u8)
    Swag.require(img.pixels.buffer[1] == 20'u8)
    Swag.require(img.pixels.buffer[2] == 30'u8)
    Swag.require(img.pixels.buffer[3] == 40'u8)
    Swag.require(img.pixels.buffer[4] == 50'u8)
    Swag.require(img.pixels.buffer[5] == 60'u8)
}

// Decode an RGBA image (extra alpha sample) into RGBA8.
#test
{
    var pix: ConcatBuffer
    pix.addNative(1'u8)
    pix.addNative(2'u8)
    pix.addNative(3'u8)
    pix.addNative(4'u8)

    let buf = buildTiff(true, 1, 1, 4, 2, 1, 1, 8, nnBytes(pix.toSlice()), null, true)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    Swag.require(img.pixelFormat == .RGBA8)
    Swag.require(img.alphaMode == .Straight)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 1'u8)
    Swag.require(img.pixels.buffer[1] == 2'u8)
    Swag.require(img.pixels.buffer[2] == 3'u8)
    Swag.require(img.pixels.buffer[3] == 4'u8)
}

// TIFF associated alpha is retained as premultiplied pixel storage.
#test
{
    var pix: ConcatBuffer
    pix.addNative(64'u8)
    pix.addNative(32'u8)
    pix.addNative(16'u8)
    pix.addNative(128'u8)

    let buf = buildTiff(true, 1, 1, 4, 2, 1, 1, 8, nnBytes(pix.toSlice()), null, true, extraSampleType: 1)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    const Expected: [4] u8 = [64, 32, 16, 128]
    Swag.require(img.pixelFormat == .RGBA8 and img.alphaMode == .Premultiplied)
    Swag.require(Memory.compare(img.pixels.storage(), Expected.buffer, Expected.count) == 0)
}

// Reject ExtraSamples values and entry layouts outside the supported TIFF alpha contract.
#test
{
    const PixelData: [4] u8 = [64, 32, 16, 128]
    let badAssociation = buildTiff(true, 1, 1, 4, 2, 1, 1, 8, PixelData, null, true, extraSampleType: 3)
    let badType        = buildTiff(true, 1, 1, 4, 2, 1, 1, 8, PixelData, null, true, extraSamplesType: 4)
    let badCount       = buildTiff(true, 1, 1, 4, 2, 1, 1, 8, PixelData, null, true, extraSamplesCount: 2)
    Swag.require(tiffDecodeFails(nnBytes(badAssociation.toSlice())))
    Swag.require(tiffDecodeFails(nnBytes(badType.toSlice())))
    Swag.require(tiffDecodeFails(nnBytes(badCount.toSlice())))
}

// RGB sample layouts require the RGB photometric interpretation.
#test
{
    const PixelData: [3] u8 = [10, 20, 30]
    for photometric in [5'u32, 6'u32]
    {
        let unsupported = buildTiff(true, 1, 1, 3, photometric, 1, 1, 8, PixelData, null, false)
        Swag.require(tiffDecodeFails(nnBytes(unsupported.toSlice())))
    }

    let valid = buildTiff(true, 1, 1, 3, 2, 1, 1, 8, PixelData, null, false)
    let image = expect decodeTiff(nnBytes(valid.toSlice()))
    const Expected: [3] u8 = [10, 20, 30]
    Swag.require(image.pixelFormat == .RGB8)
    Swag.require(Memory.compare(image.pixels.storage(), Expected.buffer, Expected.count) == 0)
}

// TIFF omits BitsPerSample by defaulting to one bit; this decoder accepts only explicit 8-bit samples.
#test
{
    const PixelData: [1] u8 = [0x80]
    let omitted = buildTiff(true, 1, 1, 1, 0, 1, 1, 8, PixelData, null, false, includeBitsPerSample: false)
    Swag.require(tiffDecodeFails(nnBytes(omitted.toSlice())))

    let explicit = buildTiff(true, 1, 1, 1, 0, 1, 1, 8, PixelData, null, false)
    let image    = expect decodeTiff(nnBytes(explicit.toSlice()))
    Swag.require(image.pixelFormat == .BGR8)
    Swag.require(image.pixels.storage()[0] == 127'u8)
}

// Decode a PackBits-compressed RGB image (literal run).
#test
{
    var pix: ConcatBuffer
    pix.addNative(11'u8)     // literal header: 12 bytes follow
    pix.addNative(10'u8)
    pix.addNative(20'u8)
    pix.addNative(30'u8)
    pix.addNative(40'u8)
    pix.addNative(50'u8)
    pix.addNative(60'u8)
    pix.addNative(70'u8)
    pix.addNative(80'u8)
    pix.addNative(90'u8)
    pix.addNative(100'u8)
    pix.addNative(110'u8)
    pix.addNative(120'u8)

    let buf = buildTiff(true, 4, 1, 3, 2, 32773, 1, 8, nnBytes(pix.toSlice()), null, false)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10'u8)
    Swag.require(img.pixels.buffer[5] == 60'u8)
    Swag.require(img.pixels.buffer[9] == 100'u8)
    Swag.require(img.pixels.buffer[11] == 120'u8)
}

// Decode a PackBits repeat run.
#test
{
    var pix: ConcatBuffer
    pix.addNative(0xFE'u8)     // signed -2: repeat next byte 3 times
    pix.addNative(0xAB'u8)

    let buf = buildTiff(true, 1, 1, 3, 2, 32773, 1, 8, nnBytes(pix.toSlice()), null, false)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 0xAB'u8)
    Swag.require(img.pixels.buffer[1] == 0xAB'u8)
    Swag.require(img.pixels.buffer[2] == 0xAB'u8)
}

// Decode a multi-strip image and verify the top-down to bottom-up flip.
#test
{
    var pix: ConcatBuffer
    pix.addNative(10'u8)
    pix.addNative(10'u8)
    pix.addNative(10'u8)     // file row 0 (top)
    pix.addNative(20'u8)
    pix.addNative(20'u8)
    pix.addNative(20'u8)     // file row 1
    pix.addNative(30'u8)
    pix.addNative(30'u8)
    pix.addNative(30'u8)     // file row 2
    pix.addNative(40'u8)
    pix.addNative(40'u8)
    pix.addNative(40'u8)     // file row 3 (bottom)

    let buf = buildTiff(true, 1, 4, 3, 2, 1, 2, 8, nnBytes(pix.toSlice()), null, false)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    Swag.require(img.width == 1)
    Swag.require(img.height == 4)

    // Internal buffer is bottom-up: row 0 holds the file's bottom row.
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 40'u8)
    Swag.require(img.pixels.buffer[3] == 30'u8)
    Swag.require(img.pixels.buffer[6] == 20'u8)
    Swag.require(img.pixels.buffer[9] == 10'u8)
}

// Decode metadata only: dimensions are populated but pixels are not allocated.
#test
{
    var pix: ConcatBuffer
    pix.addNative(0'u8)
    pix.addNative(0'u8)
    pix.addNative(0'u8)

    let buf = buildTiff(true, 1, 1, 3, 2, 1, 1, 8, nnBytes(pix.toSlice()), null, false)

    var opt: DecodeOptions
    opt.decodePixels = false
    let img = expect decodeTiff(nnBytes(buf.toSlice()), opt)
    Swag.require(img.width == 1)
    Swag.require(img.height == 1)
    Swag.require(img.pixelFormat == .RGB8)
    Swag.require(not img.isValid())
}

#test
{
    const PixelData: [1] u8 = [0]
    let buf = buildTiff(true, 600_000_000, 1, 4, 2, 1, 1, 8, PixelData, null, false)

    var options: DecodeOptions
    options.maxPixels       = 0
    options.maxDecodedBytes = 0
    options.decodePixels    = false

    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try decodeTiff(nnBytes(buf.toSlice()), options) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Error: bad byte-order signature.
#test
{
    var cb: ConcatBuffer
    cb.addNative(0x58'u8)
    cb.addNative(0x58'u8)
    cb.addNative(0'u8)
    cb.addNative(0'u8)
    cb.addNative(8'u32)

    var err11Outcome: Swag.Error
    var img: #decltype(expect decodeTiff(nnBytes(cb.toSlice())))
    catch { img = try decodeTiff(nnBytes(cb.toSlice())) } as err11Outcome
    let err11 = err11Outcome.value()
    Swag.require(err11 != null)
}

// Decode a hand-built MSB-first LZW stream.
#test
{
    var raw: Array'u8
    raw.add(10)
    raw.add(20)
    raw.add(30)
    raw.add(40)
    raw.add(50)
    raw.add(60)
    let packed = packLiteralTiffLzw(nnBytes(raw.toSlice()))

    let buf = buildTiff(true, 2, 1, 3, 2, 5, 1, 8, nnBytes(packed.toSlice()), null, false)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10'u8)
    Swag.require(img.pixels.buffer[1] == 20'u8)
    Swag.require(img.pixels.buffer[2] == 30'u8)
    Swag.require(img.pixels.buffer[3] == 40'u8)
    Swag.require(img.pixels.buffer[4] == 50'u8)
    Swag.require(img.pixels.buffer[5] == 60'u8)
}

#test
{
    var writer: TestTiffLzwWriter
    writer.bytes       = {}
    writer.pending     = 0
    writer.pendingBits = 0
    writer.write(256, 9)
    writer.write(65, 9)
    writer.finish()

    let buf = buildTiff(true, 1, 1, 1, 1, 5, 1, 8, nnBytes(writer.bytes.toSlice()), null, false)
    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try decodeTiff(nnBytes(buf.toSlice())) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

#test
{
    var writer: TestTiffLzwWriter
    writer.bytes       = {}
    writer.pending     = 0
    writer.pendingBits = 0
    writer.write(256, 9)
    writer.write(65, 9)
    writer.write(66, 9)
    writer.write(257, 9)
    writer.finish()

    let buf = buildTiff(true, 1, 1, 1, 1, 5, 1, 8, nnBytes(writer.bytes.toSlice()), null, false)
    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try decodeTiff(nnBytes(buf.toSlice())) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Decode horizontal differencing (Predictor=2) after LZW expansion.
#test
{
    var predicted: Array'u8
    predicted.add(10)
    predicted.add(20)
    predicted.add(30)
    predicted.add(5)
    predicted.add(5)
    predicted.add(5)
    let packed = packLiteralTiffLzw(nnBytes(predicted.toSlice()))

    let buf = buildTiff(true, 2, 1, 3, 2, 5, 1, 8, nnBytes(packed.toSlice()), null, false, 2)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10'u8)
    Swag.require(img.pixels.buffer[1] == 20'u8)
    Swag.require(img.pixels.buffer[2] == 30'u8)
    Swag.require(img.pixels.buffer[3] == 15'u8)
    Swag.require(img.pixels.buffer[4] == 25'u8)
    Swag.require(img.pixels.buffer[5] == 35'u8)
}

// Decode the LZW KwKwK case, where a code refers to the dictionary entry that
// is being defined by that same code.
#test
{
    var writer: TestTiffLzwWriter
    writer.bytes       = {}
    writer.pending     = 0
    writer.pendingBits = 0
    writer.write(256, 9)
    writer.write(65, 9)
    writer.write(258, 9)
    writer.write(259, 9)
    writer.write(257, 9)
    writer.finish()

    let buf = buildTiff(true, 6, 1, 1, 1, 5, 1, 8, nnBytes(writer.bytes.toSlice()), null, false)
    let img = expect decodeTiff(nnBytes(buf.toSlice()))
    for i in img.pixels.count do
        Swag.require(img.pixels.storage()[i] == 65'u8)
}

// Exercise independent literal streams across every TIFF LZW code-width edge.
#test
{
    var raw: Array'u8
    for index in 4096 do
        raw.add(cast(u8, ((index * 73 + 19) & 0xFF)))
    let packed = packLiteralTiffLzw(nnBytes(raw.toSlice()))

    let buf    = buildTiff(true, 64, 64, 1, 1, 5, 64, 8, nnBytes(packed.toSlice()), null, false)
    let img    = expect decodeTiff(nnBytes(buf.toSlice()))
    let pixels = img.pixels.storage()
    for y in 64
    {
        for x in 64
        {
            let expected = raw[cast(u64, (63 - y)) * 64 + x]
            let offset   = cast(u64, (y * 64 + x)) * 3
            Swag.require(pixels[offset] == expected)
            Swag.require(pixels[offset + 1] == expected)
            Swag.require(pixels[offset + 2] == expected)
        }
    }
}

// Error: unsupported samples-per-pixel.
#test
{
    var pix: ConcatBuffer
    pix.addNative(0'u8)
    pix.addNative(0'u8)

    let buf = buildTiff(true, 1, 1, 2, 1, 1, 1, 8, nnBytes(pix.toSlice()), null, false)
    var err13Outcome: Swag.Error
    var img: #decltype(expect decodeTiff(nnBytes(buf.toSlice())))
    catch { img = try decodeTiff(nnBytes(buf.toSlice())) } as err13Outcome
    let err13 = err13Outcome.value()
    Swag.require(err13 != null)
}

// Error: unsupported bit depth (16-bit).
#test
{
    var pix: ConcatBuffer
    pix.addNative(0'u8)
    pix.addNative(0'u8)

    let buf = buildTiff(true, 1, 1, 1, 1, 1, 1, 16, nnBytes(pix.toSlice()), null, false)
    var err14Outcome: Swag.Error
    var img: #decltype(expect decodeTiff(nnBytes(buf.toSlice())))
    catch { img = try decodeTiff(nnBytes(buf.toSlice())) } as err14Outcome
    let err14 = err14Outcome.value()
    Swag.require(err14 != null)
}

// Encoder writes a little-endian header.
#test
{
    var src = Image.create(2, 2, .RGB8)
    src.clear()

    let cb = expect src.encode("memory.tiff")
    cb.makeLinear()
    let bytes = nnBytes(cb.toSlice())
    Swag.require(bytes.buffer[0] == 0x49'u8)
    Swag.require(bytes.buffer[1] == 0x49'u8)
    Swag.require(bytes.buffer[2] == 42'u8)
    Swag.require(bytes.buffer[3] == 0'u8)
}

// Encode an RGB8 image and round-trip it through the decoder unchanged.
#test
{
    var src = Image.create(2, 2, .RGB8)
    src.clear()
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 11'u8     // bottom-left R
    srcBuf[1] = 22'u8
    srcBuf[2] = 33'u8
    srcBuf[9] = 99'u8     // top-right R (last pixel)

    let cb  = expect src.encode("memory.tiff")
    let img = expect decodeTiff(nnBytes(cb.toSlice()))
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .RGB8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 11'u8)
    Swag.require(img.pixels.buffer[1] == 22'u8)
    Swag.require(img.pixels.buffer[2] == 33'u8)
    Swag.require(img.pixels.buffer[9] == 99'u8)
}

// Encode 8-bit grayscale using TIFF's single-sample BlackIsZero representation.
#test
{
    var src    = Image.create(3, 1, .Gray8)
    let pixels = src.pixels.storage()
    pixels[0] = 17'u8
    pixels[1] = 91'u8
    pixels[2] = 233'u8

    let cb  = expect src.encode("memory.tiff")
    let img = expect decodeTiff(nnBytes(cb.toSlice()))
    Swag.require(img.pixelFormat == .BGR8)
    let decoded = unwrap img.pixels.buffer
    Swag.require(decoded[0] == 17'u8 and decoded[1] == 17'u8 and decoded[2] == 17'u8)
    Swag.require(decoded[3] == 91'u8 and decoded[4] == 91'u8 and decoded[5] == 91'u8)
    Swag.require(decoded[6] == 233'u8 and decoded[7] == 233'u8 and decoded[8] == 233'u8)

    var unsupported = Image.create(1, 1, .GrayAlpha8)
    var errorOutcome: Swag.Error
    catch { discard try unsupported.encodeToBytes("unsupported.tiff") } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// A truncated public pixel array is rejected before TIFF row conversion.
#test
{
    var src = Image.create(1, 1, .RGB8)
    src.pixels.count = 0
    var errorOutcome: Swag.Error
    catch { discard try src.encodeToBytes("truncated.tiff") } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Encode an RGBA8 image: alpha survives the round-trip.
#test
{
    var src    = Image.create(1, 1, .RGBA8)
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 1'u8
    srcBuf[1] = 2'u8
    srcBuf[2] = 3'u8
    srcBuf[3] = 200'u8

    let cb  = expect src.encode("memory.tiff")
    let img = expect decodeTiff(nnBytes(cb.toSlice()))
    Swag.require(img.pixelFormat == .RGBA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 1'u8)
    Swag.require(img.pixels.buffer[1] == 2'u8)
    Swag.require(img.pixels.buffer[2] == 3'u8)
    Swag.require(img.pixels.buffer[3] == 200'u8)
}

// Encode a BGR8 image: channels are swapped to RGB on disk and decode as RGB8.
#test
{
    var src    = Image.create(1, 1, .BGR8)
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 10'u8     // B
    srcBuf[1] = 20'u8     // G
    srcBuf[2] = 30'u8     // R

    let cb  = expect src.encode("memory.tiff")
    let img = expect decodeTiff(nnBytes(cb.toSlice()))
    Swag.require(img.pixelFormat == .RGB8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 30'u8)
    Swag.require(img.pixels.buffer[1] == 20'u8)
    Swag.require(img.pixels.buffer[2] == 10'u8)
}

// Full registry round-trip through Image.save / Image.load on a temp file.
#test
{
    let path = makeTempTiffPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(3, 2, .RGB8)
    src.clear()
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 123'u8
    srcBuf[1] = 45'u8
    srcBuf[2] = 67'u8

    expect src.save(path.toString())
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 3)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .RGB8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 123'u8)
    Swag.require(img.pixels.buffer[1] == 45'u8)
    Swag.require(img.pixels.buffer[2] == 67'u8)
}

// Encode PackBits-compressed RGBA rows and round-trip them exactly. Repeated
// pixels make the compressed stream smaller than the uncompressed TIFF.
#test
{
    var src    = Image.create(32, 3, .RGBA8)
    let srcBuf = src.pixels.storage()
    for y in src.height
    {
        for x in src.width
        {
            let offset = cast(u64, (y * src.width + x)) * 4
            srcBuf[offset]     = cast(u8, (10 + y))
            srcBuf[offset + 1] = cast(u8, (10 + y))
            srcBuf[offset + 2] = cast(u8, (10 + y))
            srcBuf[offset + 3] = cast(u8, (10 + y))
        }
    }

    let uncompressed = expect src.encode("memory.tiff")
    var options: Tiff.EncodeOptions
    options.compression = .PackBits

    let packed = expect src.encode("memory.tiff", options)
    Swag.require((packed.toSlice()).count < (uncompressed.toSlice()).count)

    let img = expect decodeTiff(nnBytes(packed.toSlice()))
    Swag.require(img.pixelFormat == .RGBA8)
    Swag.require(img.width == src.width)
    Swag.require(img.height == src.height)
    Swag.require(Memory.compare(src.pixels.storage(), img.pixels.storage(), src.pixels.count) == 0)
}

// PackBits also preserves BGR input after conversion to TIFF's RGB component order.
#test
{
    var src    = Image.create(5, 1, .BGR8)
    let srcBuf = src.pixels.storage()
    for x in src.width
    {
        let offset = cast(u64, x) * 3
        srcBuf[offset]     = 3'u8
        srcBuf[offset + 1] = 2'u8
        srcBuf[offset + 2] = 1'u8
    }

    var options: Tiff.EncodeOptions
    options.compression = .PackBits

    let cb  = expect src.encode("memory.tiff", options)
    let img = expect decodeTiff(nnBytes(cb.toSlice()))
    Swag.require(img.pixelFormat == .RGB8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 1'u8)
    Swag.require(img.pixels.buffer[1] == 2'u8)
    Swag.require(img.pixels.buffer[2] == 3'u8)
}

// LZW encoding uses horizontal differencing and survives dictionary growth,
// including a full-table clear, without changing RGBA pixels.
#test
{
    var src    = Image.create(128, 40, .RGBA8)
    let srcBuf = src.pixels.storage()
    var state  = 0x12345678'u32
    for i in src.pixels.count
    {
        state     *= #wrap 1664525
        state     += #wrap 1013904223
        srcBuf[i] = cast(u8, (state >> 24))
    }

    var options: Tiff.EncodeOptions
    options.compression = .Lzw

    let cb = expect src.encode("memory.tiff", options)
    cb.makeLinear()

    let img = expect decodeTiff(nnBytes(cb.toSlice()))
    Swag.require(img.pixelFormat == .RGBA8)
    Swag.require(img.width == src.width)
    Swag.require(img.height == src.height)
    Swag.require(Memory.compare(src.pixels.storage(), img.pixels.storage(), src.pixels.count) == 0)
}
