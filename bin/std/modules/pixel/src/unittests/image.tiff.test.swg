#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

// Low-level, endian-aware writers used to hand-build TIFF byte buffers.

func tw16(cb: *ConcatBuffer, le: bool, v: u16)
{
    if le
    {
        cb.addNative(cast(u8) (v & 0xFF))
        cb.addNative(cast(u8) (v >> 8))
    }
    else
    {
        cb.addNative(cast(u8) (v >> 8))
        cb.addNative(cast(u8) (v & 0xFF))
    }
}

func tw32(cb: *ConcatBuffer, le: bool, v: u32)
{
    if le
    {
        cb.addNative(cast(u8) (v & 0xFF))
        cb.addNative(cast(u8) ((v >> 8) & 0xFF))
        cb.addNative(cast(u8) ((v >> 16) & 0xFF))
        cb.addNative(cast(u8) ((v >> 24) & 0xFF))
    }
    else
    {
        cb.addNative(cast(u8) ((v >> 24) & 0xFF))
        cb.addNative(cast(u8) ((v >> 16) & 0xFF))
        cb.addNative(cast(u8) ((v >> 8) & 0xFF))
        cb.addNative(cast(u8) (v & 0xFF))
    }
}

// Single inline SHORT value (left-justified in the 4-byte field).
func entShort(cb: *ConcatBuffer, le: bool, tag, value: u16)
{
    tw16(cb, le, tag)
    tw16(cb, le, 3)
    tw32(cb, le, 1)
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

// Build a single-IFD TIFF. Pixel data is laid out top-down. When 'compression'
// is 1 (none), data is split into strips of 'rowsPerStrip' rows; otherwise a
// single strip is emitted holding 'pixelData' verbatim.
func buildTiff(le: bool, width, height, spp, photo, compression, rowsPerStrip, bps: u32, pixelData: const [..] u8, palette: const [..] u16, extraSamples: bool)->Array'u8
{
    var cb: ConcatBuffer

    let bytesPerSample = bps / 8
    let rowBytes       = width * spp * bytesPerSample
    let pixCount       = cast(u32) @countof(pixelData)
    let palCount       = cast(u32) @countof(palette)
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
    let numStrips = cast(u32) stripLens.count

    var numEntries = 9'u32
    if hasPalette do
        numEntries += 1
    if extraSamples do
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

    let bpsExternal = spp > 1
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
    tw16(&cb, le, cast(u16) numEntries)
    entLong(&cb, le, 256, width)
    entLong(&cb, le, 257, height)
    if bpsExternal do
        entOffset(&cb, le, 258, 3, spp, bpsOffset)
    else do
        entShort(&cb, le, 258, cast(u16) bps)
    entShort(&cb, le, 259, cast(u16) compression)
    entShort(&cb, le, 262, cast(u16) photo)
    if stripArraysExternal do
        entOffset(&cb, le, 273, 4, numStrips, stripOffArrayOffset)
    else do
        entLong(&cb, le, 273, stripOffs[0])
    entShort(&cb, le, 277, cast(u16) spp)
    entLong(&cb, le, 278, rowsPerStrip)
    if stripArraysExternal do
        entOffset(&cb, le, 279, 4, numStrips, stripCntArrayOffset)
    else do
        entLong(&cb, le, 279, stripLens[0])
    if hasPalette do
        entOffset(&cb, le, 320, 3, palCount, colorMapOffset)
    if extraSamples do
        entShort(&cb, le, 338, 2)
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
            tw16(&cb, le, cast(u16) bps)
    }
    if hasPalette
    {
        for i in palCount do
            tw16(&cb, le, palette[i])
    }

    // Pixel data
    cb.addBytes(pixelData)
    return cbToArray(&cb)
}

func tiffCanEncode(fileName: string)->bool
{
    var enc: Tiff.Encoder
    let itf = @mkinterface(&enc, #typeof(Tiff.Encoder), IImageEncoder)
    return itf.canEncode(fileName)
}

func encodeTiff(result: *ConcatBuffer, image: Image) throw
{
    var enc: Tiff.Encoder
    let itf = @mkinterface(&enc, #typeof(Tiff.Encoder), IImageEncoder)
    itf.encode(result, image, null)
}

func decodeTiff(bytes: const [..] u8, opt: DecodeOptions = {})->Image throw
{
    var dec: Tiff.Decoder
    let itf = @mkinterface(&dec, #typeof(Tiff.Decoder), IImageDecoder)
    return itf.decode(bytes, opt)
}

// The decoder and encoder registries recognise .tif and .tiff files.
#test
{
    @assert(Image.canLoad("in.tif"))
    @assert(Image.canLoad("in.tiff"))
    @assert(Image.canSave("out.tif"))
    @assert(Image.canSave("out.tiff"))
    @assert(tiffCanEncode("out.tiff"))
    @assert(!tiffCanEncode("out.bmp"))
}

// Decode a little-endian 2x1 uncompressed RGB image.
#test
{
    var pix: ConcatBuffer
    pix.addNative(10'u8); pix.addNative(20'u8); pix.addNative(30'u8)
    pix.addNative(40'u8); pix.addNative(50'u8); pix.addNative(60'u8)

    let buf = buildTiff(true, 2, 1, 3, 2, 1, 1, 8, pix.toSlice(), null, false)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err == null)
    @assert(img.width == 2)
    @assert(img.height == 1)
    @assert(img.pf == .RGB8)
    @assert(img.pixels.buffer[0] == 10'u8)
    @assert(img.pixels.buffer[1] == 20'u8)
    @assert(img.pixels.buffer[2] == 30'u8)
    @assert(img.pixels.buffer[3] == 40'u8)
    @assert(img.pixels.buffer[4] == 50'u8)
    @assert(img.pixels.buffer[5] == 60'u8)
}

// Decode a big-endian (MM) image and confirm it matches the little-endian path.
#test
{
    var pix: ConcatBuffer
    pix.addNative(11'u8); pix.addNative(22'u8); pix.addNative(33'u8)
    pix.addNative(44'u8); pix.addNative(55'u8); pix.addNative(66'u8)

    let buf = buildTiff(false, 2, 1, 3, 2, 1, 1, 8, pix.toSlice(), null, false)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err == null)
    @assert(img.pf == .RGB8)
    @assert(img.pixels.buffer[0] == 11'u8)
    @assert(img.pixels.buffer[3] == 44'u8)
    @assert(img.pixels.buffer[5] == 66'u8)
}

// Decode an 8-bit grayscale (BlackIsZero) image into replicated BGR8 channels.
#test
{
    var pix: ConcatBuffer
    pix.addNative(5'u8); pix.addNative(10'u8); pix.addNative(15'u8)

    let buf = buildTiff(true, 3, 1, 1, 1, 1, 1, 8, pix.toSlice(), null, false)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err == null)
    @assert(img.pf == .BGR8)
    @assert(img.pixels.buffer[0] == 5'u8)
    @assert(img.pixels.buffer[1] == 5'u8)
    @assert(img.pixels.buffer[2] == 5'u8)
    @assert(img.pixels.buffer[3] == 10'u8)
    @assert(img.pixels.buffer[6] == 15'u8)
}

// Decode WhiteIsZero grayscale: sample values are inverted.
#test
{
    var pix: ConcatBuffer
    pix.addNative(5'u8); pix.addNative(250'u8)

    let buf = buildTiff(true, 2, 1, 1, 0, 1, 1, 8, pix.toSlice(), null, false)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err == null)
    @assert(img.pixels.buffer[0] == 250'u8)
    @assert(img.pixels.buffer[3] == 5'u8)
}

// Decode a palette (color-mapped) image via its 16-bit color map.
#test
{
    var pal: Array'u16
    pal.add(10 << 8); pal.add(40 << 8)    // red
    pal.add(20 << 8); pal.add(50 << 8)    // green
    pal.add(30 << 8); pal.add(60 << 8)    // blue

    var pix: ConcatBuffer
    pix.addNative(0'u8); pix.addNative(1'u8)

    let buf = buildTiff(true, 2, 1, 1, 3, 1, 1, 8, pix.toSlice(), pal.toSlice(), false)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err == null)
    @assert(img.pf == .RGB8)
    @assert(img.pixels.buffer[0] == 10'u8)
    @assert(img.pixels.buffer[1] == 20'u8)
    @assert(img.pixels.buffer[2] == 30'u8)
    @assert(img.pixels.buffer[3] == 40'u8)
    @assert(img.pixels.buffer[4] == 50'u8)
    @assert(img.pixels.buffer[5] == 60'u8)
}

// Decode an RGBA image (extra alpha sample) into RGBA8.
#test
{
    var pix: ConcatBuffer
    pix.addNative(1'u8); pix.addNative(2'u8); pix.addNative(3'u8); pix.addNative(4'u8)

    let buf = buildTiff(true, 1, 1, 4, 2, 1, 1, 8, pix.toSlice(), null, true)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err == null)
    @assert(img.pf == .RGBA8)
    @assert(img.pixels.buffer[0] == 1'u8)
    @assert(img.pixels.buffer[1] == 2'u8)
    @assert(img.pixels.buffer[2] == 3'u8)
    @assert(img.pixels.buffer[3] == 4'u8)
}

// Decode a PackBits-compressed RGB image (literal run).
#test
{
    var pix: ConcatBuffer
    pix.addNative(11'u8)   // literal header: 12 bytes follow
    pix.addNative(10'u8); pix.addNative(20'u8); pix.addNative(30'u8)
    pix.addNative(40'u8); pix.addNative(50'u8); pix.addNative(60'u8)
    pix.addNative(70'u8); pix.addNative(80'u8); pix.addNative(90'u8)
    pix.addNative(100'u8); pix.addNative(110'u8); pix.addNative(120'u8)

    let buf = buildTiff(true, 4, 1, 3, 2, 32773, 1, 8, pix.toSlice(), null, false)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err == null)
    @assert(img.pixels.buffer[0] == 10'u8)
    @assert(img.pixels.buffer[5] == 60'u8)
    @assert(img.pixels.buffer[9] == 100'u8)
    @assert(img.pixels.buffer[11] == 120'u8)
}

// Decode a PackBits repeat run.
#test
{
    var pix: ConcatBuffer
    pix.addNative(0xFE'u8)   // signed -2: repeat next byte 3 times
    pix.addNative(0xAB'u8)

    let buf = buildTiff(true, 1, 1, 3, 2, 32773, 1, 8, pix.toSlice(), null, false)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err == null)
    @assert(img.pixels.buffer[0] == 0xAB'u8)
    @assert(img.pixels.buffer[1] == 0xAB'u8)
    @assert(img.pixels.buffer[2] == 0xAB'u8)
}

// Decode a multi-strip image and verify the top-down to bottom-up flip.
#test
{
    var pix: ConcatBuffer
    pix.addNative(10'u8); pix.addNative(10'u8); pix.addNative(10'u8)    // file row 0 (top)
    pix.addNative(20'u8); pix.addNative(20'u8); pix.addNative(20'u8)    // file row 1
    pix.addNative(30'u8); pix.addNative(30'u8); pix.addNative(30'u8)    // file row 2
    pix.addNative(40'u8); pix.addNative(40'u8); pix.addNative(40'u8)    // file row 3 (bottom)

    let buf = buildTiff(true, 1, 4, 3, 2, 1, 2, 8, pix.toSlice(), null, false)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err == null)
    @assert(img.width == 1)
    @assert(img.height == 4)
    // Internal buffer is bottom-up: row 0 holds the file's bottom row.
    @assert(img.pixels.buffer[0] == 40'u8)
    @assert(img.pixels.buffer[3] == 30'u8)
    @assert(img.pixels.buffer[6] == 20'u8)
    @assert(img.pixels.buffer[9] == 10'u8)
}

// Decode metadata only: dimensions are populated but pixels are not allocated.
#test
{
    var pix: ConcatBuffer
    pix.addNative(0'u8); pix.addNative(0'u8); pix.addNative(0'u8)

    let buf = buildTiff(true, 1, 1, 3, 2, 1, 1, 8, pix.toSlice(), null, false)

    var opt: DecodeOptions
    opt.decodePixels = false
    var img = catch decodeTiff(buf.toSlice(), opt)
    @assert(@err == null)
    @assert(img.width == 1)
    @assert(img.height == 1)
    @assert(img.pf == .RGB8)
    @assert(!img.isValid())
}

// Error: bad byte-order signature.
#test
{
    var cb: ConcatBuffer
    cb.addNative(0x58'u8); cb.addNative(0x58'u8)
    cb.addNative(0'u8); cb.addNative(0'u8)
    cb.addNative(8'u32)

    var img = catch decodeTiff(cb.toSlice())
    @assert(@err != null)
}

// Error: unsupported compression scheme (LZW).
#test
{
    var pix: ConcatBuffer
    pix.addNative(0'u8); pix.addNative(0'u8); pix.addNative(0'u8)

    let buf = buildTiff(true, 1, 1, 3, 2, 5, 1, 8, pix.toSlice(), null, false)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err != null)
}

// Error: unsupported samples-per-pixel.
#test
{
    var pix: ConcatBuffer
    pix.addNative(0'u8); pix.addNative(0'u8)

    let buf = buildTiff(true, 1, 1, 2, 1, 1, 1, 8, pix.toSlice(), null, false)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err != null)
}

// Error: unsupported bit depth (16-bit).
#test
{
    var pix: ConcatBuffer
    pix.addNative(0'u8); pix.addNative(0'u8)

    let buf = buildTiff(true, 1, 1, 1, 1, 1, 1, 16, pix.toSlice(), null, false)
    var img = catch decodeTiff(buf.toSlice())
    @assert(@err != null)
}

// Encoder writes a little-endian header.
#test
{
    var src = Image.create(2, 2, .RGB8)
    src.clear()

    var cb: ConcatBuffer
    catch encodeTiff(&cb, src)
    @assert(@err == null)
    cb.makeLinear()
    let bytes = cb.toSlice()
    @assert(@dataof(bytes)[0] == 0x49'u8)
    @assert(@dataof(bytes)[1] == 0x49'u8)
    @assert(@dataof(bytes)[2] == 42'u8)
    @assert(@dataof(bytes)[3] == 0'u8)
}

// Encode an RGB8 image and round-trip it through the decoder unchanged.
#test
{
    var src = Image.create(2, 2, .RGB8)
    src.clear()
    src.pixels.buffer[0] = 11'u8    // bottom-left R
    src.pixels.buffer[1] = 22'u8
    src.pixels.buffer[2] = 33'u8
    src.pixels.buffer[9] = 99'u8    // top-right R (last pixel)

    var cb: ConcatBuffer
    catch encodeTiff(&cb, src)
    @assert(@err == null)

    var img = catch decodeTiff(cb.toSlice())
    @assert(@err == null)
    @assert(img.width == 2)
    @assert(img.height == 2)
    @assert(img.pf == .RGB8)
    @assert(img.pixels.buffer[0] == 11'u8)
    @assert(img.pixels.buffer[1] == 22'u8)
    @assert(img.pixels.buffer[2] == 33'u8)
    @assert(img.pixels.buffer[9] == 99'u8)
}

// Encode an RGBA8 image: alpha survives the round-trip.
#test
{
    var src = Image.create(1, 1, .RGBA8)
    src.pixels.buffer[0] = 1'u8
    src.pixels.buffer[1] = 2'u8
    src.pixels.buffer[2] = 3'u8
    src.pixels.buffer[3] = 200'u8

    var cb: ConcatBuffer
    catch encodeTiff(&cb, src)
    @assert(@err == null)

    var img = catch decodeTiff(cb.toSlice())
    @assert(@err == null)
    @assert(img.pf == .RGBA8)
    @assert(img.pixels.buffer[0] == 1'u8)
    @assert(img.pixels.buffer[1] == 2'u8)
    @assert(img.pixels.buffer[2] == 3'u8)
    @assert(img.pixels.buffer[3] == 200'u8)
}

// Encode a BGR8 image: channels are swapped to RGB on disk and decode as RGB8.
#test
{
    var src = Image.create(1, 1, .BGR8)
    src.pixels.buffer[0] = 10'u8    // B
    src.pixels.buffer[1] = 20'u8    // G
    src.pixels.buffer[2] = 30'u8    // R

    var cb: ConcatBuffer
    catch encodeTiff(&cb, src)
    @assert(@err == null)

    var img = catch decodeTiff(cb.toSlice())
    @assert(@err == null)
    @assert(img.pf == .RGB8)
    @assert(img.pixels.buffer[0] == 30'u8)
    @assert(img.pixels.buffer[1] == 20'u8)
    @assert(img.pixels.buffer[2] == 10'u8)
}

// Full registry round-trip through Image.save / Image.load on a temp file.
#test
{
    let path = makeTempTiffPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(3, 2, .RGB8)
    src.clear()
    src.pixels.buffer[0] = 123'u8
    src.pixels.buffer[1] = 45'u8
    src.pixels.buffer[2] = 67'u8

    catch src.save(path.toString())
    @assert(@err == null)

    var img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width == 3)
    @assert(img.height == 2)
    @assert(img.pf == .RGB8)
    @assert(img.pixels.buffer[0] == 123'u8)
    @assert(img.pixels.buffer[1] == 45'u8)
    @assert(img.pixels.buffer[2] == 67'u8)
}
