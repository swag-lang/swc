#global if #command == Swag.CompilerCommand.Test

using Swag, Core, Core.Errors

// Test-only mirrors of the private ICO on-disk structures.

#[Swag.Pack(1)]
struct IcoDir
{
    reserved: u16
    type:     u16
    count:    u16
}

#[Swag.Pack(1)]
struct IcoEntry
{
    width:       u8
    height:      u8
    colorCount:  u8
    reserved:    u8
    planes:      u16
    bitCount:    u16
    bytesInRes:  u32
    imageOffset: u32
}

#[Swag.Pack(1)]
struct IcoDib
{
    size:          u32
    width:         s32
    height:        s32
    planes:        u16
    bitCount:      u16
    compression:   u32
    sizeImage:     u32
    xPelsPerMeter: s32
    yPelsPerMeter: s32
    clrUsed:       u32
    clrImportant:  u32
}

// Build a single-image ICO from a DIB body (palette + XOR + AND, no BITMAPINFOHEADER).
func buildIco(width, height: s32, bitCount: u16, clrUsed: u32, dibBody: const [..] u8)->Array!{u8}
{
    var cb: ConcatBuffer
    let bodyLen = cast(u32, dibBody.count)

    var dir: IcoDir
    dir.type  = 1
    dir.count = 1
    cb.addStruct(dir)

    var e: IcoEntry
    e.width       = cast(u8, (width == 256 ? 0 : width))
    e.height      = cast(u8, (height == 256 ? 0 : height))
    e.planes      = 1
    e.bitCount    = bitCount
    e.bytesInRes  = 40 + bodyLen
    e.imageOffset = 22
    cb.addStruct(e)

    var dib: IcoDib
    dib.size     = 40
    dib.width    = width
    dib.height   = height * 2
    dib.planes   = 1
    dib.bitCount = bitCount
    dib.clrUsed  = clrUsed
    cb.addStruct(dib)

    cb.addBytes(dibBody)
    return cb.toArray()
}

func decodeIco(bytes: const [..] u8, opt: DecodeOptions = {})->Image fail
{
    var dec: Ico.Decoder
    let itf: IImageDecoder = &dec
    return try itf.decode(bytes, opt)
}

// The registries recognise .ico (and .cur for loading).
#test
{
    Swag.require(Image.canLoad("in.ico"))
    Swag.require(Image.canLoad("in.cur"))
    Swag.require(Image.canSave("out.ico"))
}

// Decode a 2x2 32-bit BGRA icon. XOR data is bottom-up, matching the buffer.
#test
{
    var body: ConcatBuffer

    // XOR row 0 (bottom)
    body.addNative(10_u8)
    body.addNative(20_u8)
    body.addNative(30_u8)
    body.addNative(40_u8)
    body.addNative(50_u8)
    body.addNative(60_u8)
    body.addNative(70_u8)
    body.addNative(80_u8)

    // XOR row 1 (top)
    body.addNative(90_u8)
    body.addNative(100_u8)
    body.addNative(110_u8)
    body.addNative(120_u8)
    body.addNative(130_u8)
    body.addNative(140_u8)
    body.addNative(150_u8)
    body.addNative(160_u8)

    // AND mask: 2 rows of 4 bytes, fully opaque
    for 8
    {
        body.addNative(0_u8)
    }

    let buf = buildIco(2, 2, 32, 0, nnBytes(body.toSlice()))
    let img = expect decodeIco(nnBytes(buf.toSlice()))
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10_u8)
    Swag.require(img.pixels.buffer[1] == 20_u8)
    Swag.require(img.pixels.buffer[2] == 30_u8)
    Swag.require(img.pixels.buffer[3] == 40_u8)
    Swag.require(img.pixels.buffer[4] == 50_u8)
    Swag.require(img.pixels.buffer[7] == 80_u8)
}

// Legacy 32-bit icons leave alpha at zero and use the AND mask instead.
#test
{
    var body: ConcatBuffer

    body.addNative(10_u8)
    body.addNative(20_u8)
    body.addNative(30_u8)
    body.addNative(0_u8)
    body.addNative(40_u8)
    body.addNative(50_u8)
    body.addNative(60_u8)
    body.addNative(0_u8)

    // x=1 is transparent; the row is padded to four bytes.
    body.addNative(0x40_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)

    let buf = buildIco(2, 1, 32, 0, nnBytes(body.toSlice()))
    let img = expect decodeIco(nnBytes(buf.toSlice()))
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[3] == 255_u8)
    Swag.require(img.pixels.buffer[7] == 0_u8)
}

// A non-zero 32-bit alpha channel takes precedence over the legacy AND mask.
#test
{
    var body: ConcatBuffer

    body.addNative(10_u8)
    body.addNative(20_u8)
    body.addNative(30_u8)
    body.addNative(128_u8)
    body.addNative(40_u8)
    body.addNative(50_u8)
    body.addNative(60_u8)
    body.addNative(0_u8)

    // Mark x=0 transparent in the AND mask; modern alpha must still win.
    body.addNative(0x80_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)

    let buf = buildIco(2, 1, 32, 0, nnBytes(body.toSlice()))
    let img = expect decodeIco(nnBytes(buf.toSlice()))
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[3] == 128_u8)
    Swag.require(img.pixels.buffer[7] == 0_u8)
}

// Decode a 2x2 24-bit icon, applying the AND mask as alpha.
#test
{
    var body: ConcatBuffer

    // XOR row 0 (bottom): 2 pixels BGR + 2 pad bytes (row stride = 8)
    body.addNative(10_u8)
    body.addNative(20_u8)
    body.addNative(30_u8)
    body.addNative(40_u8)
    body.addNative(50_u8)
    body.addNative(60_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)

    // XOR row 1 (top)
    for 8
    {
        body.addNative(0_u8)
    }

    // AND row 0 (bottom): bit for x=1 set -> pixel (1,0) transparent
    body.addNative(0x40_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)

    // AND row 1 (top)
    for 4
    {
        body.addNative(0_u8)
    }

    let buf = buildIco(2, 2, 24, 0, nnBytes(body.toSlice()))
    let img = expect decodeIco(nnBytes(buf.toSlice()))
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10_u8)
    Swag.require(img.pixels.buffer[1] == 20_u8)
    Swag.require(img.pixels.buffer[2] == 30_u8)
    Swag.require(img.pixels.buffer[3] == 255_u8)     // opaque
    Swag.require(img.pixels.buffer[4] == 40_u8)
    Swag.require(img.pixels.buffer[5] == 50_u8)
    Swag.require(img.pixels.buffer[6] == 60_u8)
    Swag.require(img.pixels.buffer[7] == 0_u8)     // transparent via AND mask
}

// Odd-width indexed, BGR and legacy BGRA rows apply the AND mask across vector blocks and pixel tails.
#test
{
    const Width  = 13
    const Height = 3
    for bitCount in [1'u16, 4, 8, 24, 32]
    {
        let rowBytes     = ((Width * bitCount + 31) / 32) * 4
        let paletteCount = bitCount <= 8 ? 1'u32 << bitCount : 0'u32
        var body: ConcatBuffer
        for index in paletteCount
        {
            body.addNative(cast(u8, index))
            body.addNative(cast(u8, ((index ^ 0x65) & 0xFF)))
            body.addNative(cast(u8, ((index ^ 0x91) & 0xFF)))
            body.addNative(0xFA'u8)
        }

        for y in Height
        {
            var row: [52] u8
            for x in Width
            {
                let sample = x * 251 + y * 127 + 3
                if paletteCount
                {
                    let bit   = x * bitCount
                    let index = sample & (paletteCount - 1)
                    row[bit / 8] |= cast(u8, (index << (8 - bitCount - (bit & 7))))
                }
                else
                {
                    let at = x * (bitCount / 8)
                    row[at]     = cast(u8, (sample & 0xFF))
                    row[at + 1] = cast(u8, ((sample ^ 0x65) & 0xFF))
                    row[at + 2] = cast(u8, ((sample ^ 0x91) & 0xFF))
                }
            }

            body.addBytes(row[until rowBytes])
        }

        for y in Height
        {
            var mask: [4] u8
            for x in Width
            {
                if (x + y) % 3 == 0 do
                    mask[x / 8] |= cast(u8, (128 >> (x & 7)))
            }

            body.addBytes(mask)
        }

        body.makeLinear()
        let file   = buildIco(Width, Height, bitCount, paletteCount, nnBytes(body.toSlice()))
        let image  = expect decodeIco(nnBytes(file.toSlice()))
        let pixels = image.pixels.storage()
        for y in Height
        {
            for x in Width
            {
                let offset = (y * Width + x) * 4
                let sample = (x * 251 + y * 127 + 3) & (paletteCount ? paletteCount - 1 : 255)
                Swag.require(pixels[offset] == sample)
                Swag.require(pixels[offset + 1] == (sample ^ 0x65))
                Swag.require(pixels[offset + 2] == (sample ^ 0x91))
                Swag.require(pixels[offset + 3] == ((x + y) % 3 == 0 ? 0 : 255))
            }
        }
    }
}

// Partial palettes reject invalid indices in the SIMD block and in its scalar tail.
#test
{
    const Width = 13
    for bitCount in [4'u16, 8]
    {
        let rowBytes = ((Width * bitCount + 31) / 32) * 4
        for badPixel in [7, 12]
        {
            var body: [24] u8
            body[0] = 11
            body[1] = 22
            body[2] = 33
            let bit = badPixel * bitCount
            body[4 + bit / 8] = cast(u8, (1 << (8 - bitCount - (bit & 7))))
            let file = buildIco(Width, 1, bitCount, 1, body[until 4 + rowBytes + 4])
            var outcome: Swag.Error
            discard catch decodeIco(nnBytes(file.toSlice())) as outcome
            Swag.require(outcome.value() is Errors.InvalidFormatError)
        }
    }
}

// Decode a 2x2 8-bit indexed icon through its palette.
#test
{
    var body: ConcatBuffer

    // Palette (4 BGRA quads)
    body.addNative(0_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)     // idx 0
    body.addNative(10_u8)
    body.addNative(20_u8)
    body.addNative(30_u8)
    body.addNative(0_u8)     // idx 1
    body.addNative(40_u8)
    body.addNative(50_u8)
    body.addNative(60_u8)
    body.addNative(0_u8)     // idx 2
    body.addNative(70_u8)
    body.addNative(80_u8)
    body.addNative(90_u8)
    body.addNative(0_u8)     // idx 3
    // XOR row 0 (bottom): indices [1,2] + 2 pad (row stride = 4)
    body.addNative(1_u8)
    body.addNative(2_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)

    // XOR row 1 (top)
    body.addNative(3_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)

    // AND mask: 2 rows of 4 bytes, opaque
    for 8
    {
        body.addNative(0_u8)
    }

    let buf = buildIco(2, 2, 8, 4, nnBytes(body.toSlice()))
    let img = expect decodeIco(nnBytes(buf.toSlice()))
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10_u8)
    Swag.require(img.pixels.buffer[1] == 20_u8)
    Swag.require(img.pixels.buffer[2] == 30_u8)
    Swag.require(img.pixels.buffer[3] == 255_u8)
    Swag.require(img.pixels.buffer[4] == 40_u8)
    Swag.require(img.pixels.buffer[6] == 60_u8)
}

// Decode a 2x1 1-bit indexed icon.
#test
{
    var body: ConcatBuffer

    // Palette (2 BGRA quads)
    body.addNative(0_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)     // idx 0
    body.addNative(7_u8)
    body.addNative(8_u8)
    body.addNative(9_u8)
    body.addNative(0_u8)     // idx 1
    // XOR row 0 (only row): x0=1, x1=0 -> 0b10000000, + 3 pad (row stride = 4)
    body.addNative(0x80_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)
    body.addNative(0_u8)

    // AND mask: 1 row of 4 bytes
    for 4
    {
        body.addNative(0_u8)
    }

    let buf = buildIco(2, 1, 1, 2, nnBytes(body.toSlice()))
    let img = expect decodeIco(nnBytes(buf.toSlice()))
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 7_u8)
    Swag.require(img.pixels.buffer[1] == 8_u8)
    Swag.require(img.pixels.buffer[2] == 9_u8)
    Swag.require(img.pixels.buffer[3] == 255_u8)
    Swag.require(img.pixels.buffer[4] == 0_u8)     // idx 0 color
}

// With multiple entries, the decoder picks the largest image.
#test
{
    // Two 32-bit images: 1x1 and 2x2. Directory holds 2 entries.
    let body1Len = cast(u32, (40 + 4 + 4))      // 1x1: 4 XOR + 4 AND
    let body2Len = cast(u32, (40 + 16 + 8))     // 2x2: 16 XOR + 8 AND
    let off1     = 6 + 32_u32     // after dir + 2 entries
    let off2     = off1 + body1Len

    var cb: ConcatBuffer

    var dir: IcoDir
    dir.type  = 1
    dir.count = 2
    cb.addStruct(dir)

    var e1: IcoEntry
    e1.width       = 1
    e1.height      = 1
    e1.planes      = 1
    e1.bitCount    = 32
    e1.bytesInRes  = body1Len
    e1.imageOffset = off1
    cb.addStruct(e1)

    var e2: IcoEntry
    e2.width       = 2
    e2.height      = 2
    e2.planes      = 1
    e2.bitCount    = 32
    e2.bytesInRes  = body2Len
    e2.imageOffset = off2
    cb.addStruct(e2)

    // Image 1 (1x1)
    var d1: IcoDib
    d1.size     = 40
    d1.width    = 1
    d1.height   = 2
    d1.planes   = 1
    d1.bitCount = 32
    cb.addStruct(d1)
    cb.addNative(1_u8)
    cb.addNative(2_u8)
    cb.addNative(3_u8)
    cb.addNative(4_u8)     // XOR
    for 4
    {
        cb.addNative(0_u8)
    }     // AND

    // Image 2 (2x2)
    var d2: IcoDib
    d2.size     = 40
    d2.width    = 2
    d2.height   = 4
    d2.planes   = 1
    d2.bitCount = 32
    cb.addStruct(d2)
    cb.addNative(200_u8)
    cb.addNative(201_u8)
    cb.addNative(202_u8)
    cb.addNative(203_u8)
    for 12
    {
        cb.addNative(0_u8)
    }     // rest of XOR
    for 8
    {
        cb.addNative(0_u8)
    }     // AND

    let img = expect decodeIco(nnBytes(cb.toSlice()))
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 200_u8)
    Swag.require(img.pixels.buffer[3] == 203_u8)
}

// A PNG-compressed icon entry is delegated to the PNG decoder.
#test
{
    var src = Image.create(3, 2, .RGBA8)
    src.clear()
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 11_u8
    srcBuf[1] = 22_u8
    srcBuf[2] = 33_u8
    srcBuf[3] = 255_u8

    let png = expect src.encode("memory.png")
    png.makeLinear()
    let pngBytes = nnBytes(png.toSlice())
    let pngLen   = cast(u32, pngBytes.count)

    var cb:  ConcatBuffer
    var dir: IcoDir
    dir.type  = 1
    dir.count = 1
    cb.addStruct(dir)

    var e: IcoEntry
    e.width       = 3
    e.height      = 2
    e.planes      = 1
    e.bitCount    = 32
    e.bytesInRes  = pngLen
    e.imageOffset = 22
    cb.addStruct(e)
    cb.addBytes(pngBytes)

    let img = expect decodeIco(nnBytes(cb.toSlice()))
    Swag.require(img.width == 3)
    Swag.require(img.height == 2)

    var mismatched = cb.toArray()
    let entry      = cast(*IcoEntry, mismatched.storage() + #sizeof(IcoDir))
    entry[].width = 4
    var errorOutcome:    Swag.Error
    var mismatchedImage: Image
    catch { mismatchedImage = try decodeIco(nnBytes(mismatched.toSlice())) } as errorOutcome
    Swag.require(errorOutcome.value() != null)

    var registryError: Swag.Error
    discard catch Image.decode("png-dimension-mismatch.ico", nnBytes(mismatched.toSlice())) as registryError
    Swag.require(registryError.value() is Errors.InvalidFormatError)

    var limitError: Swag.Error
    discard catch Image.decode("limited.ico", nnBytes(cb.toSlice()), {maxPixels: 1}) as limitError
    Swag.require(limitError.value() is Errors.UnsupportedFormatError)
}

// Decode metadata only: dimensions populated, no pixels allocated.
#test
{
    var body: ConcatBuffer
    for 24
    {
        body.addNative(0_u8)
    }     // 16 XOR + 8 AND

    let buf = buildIco(2, 2, 32, 0, nnBytes(body.toSlice()))

    var opt: DecodeOptions
    opt.decodePixels = false
    let img = expect decodeIco(nnBytes(buf.toSlice()), opt)
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(not img.isValid())
}

// The directory dimensions must match a DIB image's dimensions.
#test
{
    var body: ConcatBuffer
    for 8
    {
        body.addNative(0_u8)
    }     // 1x1 32-bit XOR and AND masks.
    var bytes = buildIco(1, 1, 32, 0, nnBytes(body.toSlice()))
    let entry = cast(*IcoEntry, bytes.storage() + #sizeof(IcoDir))
    entry[].width = 2

    var decodeOutcome: Swag.Error
    var image:         #decltype(expect decodeIco(nnBytes(bytes.toSlice())))
    catch { image = try decodeIco(nnBytes(bytes.toSlice())) } as decodeOutcome
    Swag.require(decodeOutcome.value() != null)

    var readerOutcome: Swag.Error
    var reader:        ImageReader
    catch { reader = try ImageReader.decode("dimension-mismatch.ico", nnBytes(bytes.toSlice())) } as readerOutcome
    Swag.require(readerOutcome.value() != null)
}

// An icon DIB uses BITMAPINFOHEADER and requires exactly one color plane.
#test
{
    var body: ConcatBuffer
    for 8
    {
        body.addNative(0_u8)
    }     // 1x1 32-bit XOR and AND masks.
    var bytes = buildIco(1, 1, 32, 0, nnBytes(body.toSlice()))
    let dib   = cast(*IcoDib, bytes.storage() + #sizeof(IcoDir) + #sizeof(IcoEntry))
    dib[].planes = 2

    var errorOutcome: Swag.Error
    var image:        Image
    catch { image = try decodeIco(nnBytes(bytes.toSlice())) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Error: directory type is neither icon (1) nor cursor (2).
#test
{
    var cb:  ConcatBuffer
    var dir: IcoDir
    dir.type  = 7
    dir.count = 1
    cb.addStruct(dir)

    var err9Outcome: Swag.Error
    var img:         #decltype(expect decodeIco(nnBytes(cb.toSlice())))
    catch { img = try decodeIco(nnBytes(cb.toSlice())) } as err9Outcome
    let err9 = err9Outcome.value()
    Swag.require(err9 != null)
}

// Error: empty directory.
#test
{
    var cb:  ConcatBuffer
    var dir: IcoDir
    dir.type  = 1
    dir.count = 0
    cb.addStruct(dir)

    var err10Outcome: Swag.Error
    var img: #decltype(expect decodeIco(nnBytes(cb.toSlice())))
    catch { img = try decodeIco(nnBytes(cb.toSlice())) } as err10Outcome
    let err10 = err10Outcome.value()
    Swag.require(err10 != null)
}

// Encode a 2x2 BGRA8 image and round-trip it unchanged.
#test
{
    var src = Image.create(2, 2, .BGRA8)
    src.clear()
    let srcBuf = src.pixels.storage()
    srcBuf[0]  = 10_u8
    srcBuf[1]  = 20_u8
    srcBuf[2]  = 30_u8
    srcBuf[3]  = 128_u8
    srcBuf[12] = 200_u8     // last pixel B

    let cb  = expect src.encode("memory.ico")
    let img = expect decodeIco(nnBytes(cb.toSlice()))
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10_u8)
    Swag.require(img.pixels.buffer[1] == 20_u8)
    Swag.require(img.pixels.buffer[2] == 30_u8)
    Swag.require(img.pixels.buffer[3] == 128_u8)
    Swag.require(img.pixels.buffer[12] == 200_u8)
}

// Encode a BGR8 image: alpha is filled opaque.
#test
{
    var src    = Image.create(1, 1, .BGR8)
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 10_u8
    srcBuf[1] = 20_u8
    srcBuf[2] = 30_u8

    let cb  = expect src.encode("memory.ico")
    let img = expect decodeIco(nnBytes(cb.toSlice()))
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10_u8)
    Swag.require(img.pixels.buffer[1] == 20_u8)
    Swag.require(img.pixels.buffer[2] == 30_u8)
    Swag.require(img.pixels.buffer[3] == 255_u8)
}

// Encode an RGBA8 image: channels are swapped to BGRA on disk.
#test
{
    var src    = Image.create(1, 1, .RGBA8)
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 30_u8     // R
    srcBuf[1] = 20_u8     // G
    srcBuf[2] = 10_u8     // B
    srcBuf[3] = 99_u8     // A

    let cb  = expect src.encode("memory.ico")
    let img = expect decodeIco(nnBytes(cb.toSlice()))
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10_u8)     // B
    Swag.require(img.pixels.buffer[1] == 20_u8)     // G
    Swag.require(img.pixels.buffer[2] == 30_u8)     // R
    Swag.require(img.pixels.buffer[3] == 99_u8)     // A
}

// Mixed layouts and odd rows keep their exact DIB bytes in a multi-image icon.
#test
{
    const DirectorySize = 6'u64
    const EntrySize     = 16'u64
    const HeaderSize    = 40'u64
    var images: Array'Image
    for height in [1, 3]
    {
        for width in [1, 5, 6, 7, 8, 9, 31, 33]
        {
            for format in [PixelFormat.RGB8, .BGR8, .RGBA8, .BGRA8]
            {
                var image = Image.create(width, height, format)
                for i in image.pixels.count do
                    image.pixels[i] = cast(u8, ((i * 59 + cast(u64, width) * 41) & 255))
                images.add(#move image)
            }
        }
    }

    var encoded = expect Ico.encodeAll(images.toSlice())
    let bytes   = encoded.moveToArray()
    var offset  = DirectorySize + EntrySize * images.count
    for i in images.count
    {
        let image     = &images[i]
        let count     = cast(u64, image.width) * image.height
        let xorSize   = count * 4
        let andSize   = ((cast(u64, image.width) + 31) / 32) * 4 * image.height
        let entrySize = HeaderSize + xorSize + andSize
        let entry     = bytes.storage() + DirectorySize + i * EntrySize
        let directory = cast(const [*] u32, entry + 8)
        Swag.require(entry[0] == image.width and entry[1] == image.height)
        Swag.require(directory[0] == entrySize and directory[1] == offset)
        Swag.require(offset + entrySize <= bytes.count)

        let bgr  = image.pixelFormat == .BGR8 or image.pixelFormat == .BGRA8
        let red  = bgr ? 2 : 0
        let blue = 2 - red
        let xor  = bytes.storage() + offset + HeaderSize
        for pixel in count
        {
            let src = image.pixels.storage() + pixel * image.bytesPerPixel
            let dst = xor + pixel * 4
            Swag.require(dst[0] == src[blue] and dst[1] == src[1] and dst[2] == src[red])
            Swag.require(dst[3] == (image.bytesPerPixel == 4 ? src[3] : 255))
        }

        for padding in andSize do
            Swag.require(xor[xorSize + padding] == 0)
        offset += entrySize
    }

    Swag.require(offset == bytes.count)
}

// Error: dimensions above 256 cannot be encoded.
#test
{
    var src = Image.create(300, 8, .BGRA8)
    src.clear()

    var err17Outcome: Swag.Error
    discard catch src.encode("memory.ico") as err17Outcome
    let err17 = err17Outcome.value()
    Swag.require(err17 != null)
}

// Full registry round-trip through Image.save / Image.load on a temp file.
#test
{
    let path = makeTempIcoPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(4, 4, .BGRA8)
    src.clear()
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 77_u8
    srcBuf[1] = 88_u8
    srcBuf[2] = 99_u8
    srcBuf[3] = 255_u8

    expect src.save(path.toString())
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 4)
    Swag.require(img.height == 4)
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 77_u8)
    Swag.require(img.pixels.buffer[1] == 88_u8)
    Swag.require(img.pixels.buffer[2] == 99_u8)
}

// An icon can carry several sizes; the decoder picks the largest of them back.
#test
{
    var small = Image.create(4, 4, .BGRA8)
    small.clear()
    small.pixels.storage()[0] = 11_u8

    var large = Image.create(8, 8, .BGRA8)
    large.clear()
    large.pixels.storage()[0] = 22_u8

    let entries: [2] Image = [small, large]

    let cb = expect Ico.encodeAll(entries)

    let img = expect decodeIco(nnBytes(cb.toSlice()))
    Swag.require(img.width == 8)
    Swag.require(img.height == 8)
    Swag.require(img.pixels.storage()[0] == 22_u8)
}

// Every entry keeps its own offset, so a later one is still readable on its own.
#test
{
    var first = Image.create(2, 2, .BGRA8)
    first.clear()
    var second = Image.create(4, 4, .BGRA8)
    second.clear()

    let entries: [2] Image = [first, second]

    let cb = expect Ico.encodeAll(entries)

    let bytes = nnBytes(cb.toSlice())
    Swag.require(bytes[4] == 2_u8)     // ICONDIR.count
}

// An icon needs at least one image.
#test
{
    var empty: Array!{Image}
    empty.reserve(1)

    var errNoneOutcome: Swag.Error
    discard catch Ico.encodeAll(empty.toSlice()) as errNoneOutcome
    let errNone = errNoneOutcome.value()
    Swag.require(errNone != null)
}

#test
{
    var grayscale = Image.create(1, 1, .Gray8)
    var encodeError: Swag.Error
    discard catch grayscale.encode("grayscale.ico") as encodeError
    Swag.require(encodeError.value() != null)

    let entries:  [1] Image = [grayscale]
    var setError: Swag.Error
    discard catch Ico.encodeAll(entries) as setError
    Swag.require(setError.value() != null)
}

// The multi-image encoder accepts only complete buffers, just like Image.encode.
#test
{
    var truncated = Image.create(1, 1, .BGRA8)
    truncated.pixels.resize(3)
    let entries: [1] Image = [truncated]

    var errorOutcome: Swag.Error
    discard catch Ico.encodeAll(entries) as errorOutcome
    Swag.require(errorOutcome.value() is InvalidFormatError)
}

// ICO DIB pixels carry straight alpha, including when the source image is premultiplied.
#test
{
    var source = Image.create(1, 1, .RGBA8, alphaMode: .Premultiplied)
    source.pixels.storage()[0] = 64_u8
    source.pixels.storage()[1] = 0_u8
    source.pixels.storage()[2] = 0_u8
    source.pixels.storage()[3] = 128_u8
    let entries: [1] Image = [source]

    let encoded = expect Ico.encodeAll(entries)
    let bytes   = nnBytes(encoded.toSlice())
    Swag.require(bytes[64] == 128_u8)     // Red, un-premultiplied.
    Swag.require(bytes[65] == 128_u8)     // Alpha.
}

// Writing premultiplied ICO pixels matches the normal straight-alpha conversion.
#test
{
    for format in [PixelFormat.RGBA8, .BGRA8]
    {
        let source = Image.create(256, 256, format, alphaMode: .Premultiplied)
        for alpha in 256
        {
            for sample in 256
            {
                let p = source.pixels.storage() + (alpha * 256 + sample) * 4
                p[0] = cast(u8, sample)
                p[1] = cast(u8, 255 - sample)
                p[2] = cast #wrap(u8, sample * 73)
                p[3] = cast(u8, alpha)
            }
        }

        let expected = source.convertedAlphaTo(.Straight)
        let entries: [1] Image = [source]
        var encoded  = expect Ico.encodeAll(entries)
        let bytes    = encoded.moveToArray()
        Swag.require(bytes.count == 270398)
        let output = bytes.storage() + 62
        let first  = format == .BGRA8 ? 0 : 2
        let last   = 2 - first
        for index in 256 * 256
        {
            let actual = output + index * 4
            let ref    = expected.pixels.storage() + index * 4
            Swag.require(actual[0] == ref[first] and
                         actual[1] == ref[1] and
                         actual[2] == ref[last] and
                         actual[3] == ref[3])
        }
    }
}

// The whole set reaches a file through the namespace entry point.
#test
{
    let path = makeTempIcoPath()
    defer discard catch File.delete(path.toString())
    var small = Image.create(4, 4, .BGRA8)
    small.clear()
    var large = Image.create(16, 16, .BGRA8)
    large.clear()
    large.pixels.storage()[2] = 77_u8

    let entries: [2] Image = [small, large]
    expect Ico.save(path.toString(), entries)
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 16)
    Swag.require(img.pixels.storage()[2] == 77_u8)
}
