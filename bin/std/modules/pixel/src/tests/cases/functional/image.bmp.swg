#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private func checkBmp16Masks(masks: Bmp.Masks)
{
    // Every source word, unaligned pointers, the SIMD/tail boundary, and
    // untouched sentinels match the generic mask normalization exactly.
    const Pixels = 65536 + 1
    var source:   Array!{u8}
    var actual:   Array!{u8}
    var expected: Array!{u8}
    source.resize(1 + Pixels * 2)
    actual.resize(3 + Pixels * 3 + 1)
    expected.resize(actual.count)
    for i in actual.count
    {
        actual[i]   = 0xA5
        expected[i] = 0xA5
    }

    for i in Pixels
    {
        let value = cast(u16, (i & 0xFFFF))
        source[1 + 2 * i]       = cast(u8, (value & 0xFF))
        source[1 + 2 * i + 1]   = cast(u8, (value >> 8))
        expected[3 + 3 * i]     = Bmp.maskToByte(value, masks.b)
        expected[3 + 3 * i + 1] = Bmp.maskToByte(value, masks.g)
        expected[3 + 3 * i + 2] = Bmp.maskToByte(value, masks.r)
    }

    Bmp.decode16Row(source.storage() + 1, actual.storage() + 3, Pixels, masks)
    for i in actual.count
    {
        Swag.require(actual[i] == expected[i])
    }
}

#test
{
    checkBmp16Masks(Bmp.makeDefaultMasks(16, 0))

    var masks: Bmp.Masks
    masks.r = Bmp.readMask(0xF800)
    masks.g = Bmp.readMask(0x07E0)
    masks.b = Bmp.readMask(0x001F)
    checkBmp16Masks(masks)

    masks.r = Bmp.readMask(0x0F00)
    masks.g = Bmp.readMask(0x00F0)
    masks.b = Bmp.readMask(0x000F)
    checkBmp16Masks(masks)

    masks.r = Bmp.readMask(0x8000)
    masks.g = Bmp.readMask(0x7F00)
    masks.b = Bmp.readMask(0x00FF)
    checkBmp16Masks(masks)

    masks.r = Bmp.readMask(0x0003)
    masks.g = Bmp.readMask(0xFC00)
    masks.b = Bmp.readMask(0x00F0)
    checkBmp16Masks(masks)

    masks.r = Bmp.readMask(0x00E0)
    masks.g = Bmp.readMask(0x001F)
    masks.b = Bmp.readMask(0xF000)
    checkBmp16Masks(masks)

    // Cover every wide field width and test both low and high bit alignment.
    for bits in 9 until 15
    {
        let mask = (1_u32 << bits) - 1
        masks.r = Bmp.readMask(mask)
        masks.g = Bmp.readMask(1_u32 << bits)
        masks.b = Bmp.readMask(1_u32 << (bits + 1))
        checkBmp16Masks(masks)

        masks.r = Bmp.readMask(2)
        masks.g = Bmp.readMask(1)
        masks.b = Bmp.readMask(mask << (16 - bits))
        checkBmp16Masks(masks)
    }
}

// Create an image in memory and verify its metadata.
#test
{
    let img = Image.create(4, 4, .BGR8)
    Swag.require(img.isValid())
    Swag.require(img.width == 4)
    Swag.require(img.height == 4)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.bitsPerPixel == 24)
    Swag.require(img.bytesPerPixel == 3)
    Swag.require(img.pixels.count == 48)
}

// Verify getTestDataPath resolves the file path correctly.
#test
{
    let path = getTestDataPath("test.bmp")
    Swag.require(not path.isEmpty())
    Swag.require(File.exists(path))
}

// Read the BMP bytes from disk without decoding.
#test
{
    let path  = getTestDataPath("test.bmp")
    let bytes = expect File.readAllBytes(path)
    Swag.require(bytes.count == 102)
}

// Verify that the decoder registry is functional and finds the BMP decoder.
#test
{
    Swag.require(Image.canLoad("test.bmp"))
    Swag.require(not Image.canLoad("test.xyz"))
}

// Decode a BMP from pre-loaded bytes using Image.decode (same internal path as Image.load).
#test
{
    let path  = getTestDataPath("test.bmp")
    let bytes = expect File.readAllBytes(path)
    let img   = expect Image.decode(path, bytes.toSlice(), {})
    Swag.require(img.isValid())
    Swag.require(img.width == 4)
    Swag.require(img.height == 4)
    Swag.require(img.pixelFormat == .BGR8)
}

// Load a 4x4 24-bit BMP from disk and verify image metadata.
#test
{
    let path = getTestDataPath("test.bmp")
    let img  = expect Image.load(path)
    Swag.require(img.isValid())
    Swag.require(img.width == 4)
    Swag.require(img.height == 4)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.bitsPerPixel == 24)
    Swag.require(img.bytesPerPixel == 3)
    Swag.require(img.pixels.count == 48)
}

// Load larger RGB/RGBA fixtures copied from the historical pixel test data.
#test
{
    let rgb = expect Image.load(getTestDataPath("rgb.bmp"))
    Swag.require(rgb.isValid())
    Swag.require(rgb.width == 660)
    Swag.require(rgb.height == 441)
    Swag.require(rgb.pixelFormat == .BGR8)
    Swag.require(rgb.pixels.count == 873180)
    Swag.require(rgb.pixels.buffer != null)
    Swag.require(rgb.pixels.buffer[0] == 201_u8)
    Swag.require(rgb.pixels.buffer[1] == 205_u8)
    Swag.require(rgb.pixels.buffer[2] == 194_u8)

    let rgba = expect Image.load(getTestDataPath("rgba.bmp"))
    Swag.require(rgba.isValid())
    Swag.require(rgba.width == 660)
    Swag.require(rgba.height == 441)
    Swag.require(rgba.pixelFormat == .BGRA8)
    Swag.require(rgba.pixels.count == 1164240)
    Swag.require(rgba.pixels.buffer != null)
    Swag.require(rgba.pixels.buffer[0] == 201_u8)
    Swag.require(rgba.pixels.buffer[1] == 205_u8)
    Swag.require(rgba.pixels.buffer[2] == 194_u8)
    Swag.require(rgba.pixels.buffer[3] == 255_u8)
}

// Decode tests - various BMP formats.

// Test-only structs that mirror the private Bmp file-header types so we can
// build custom BMP byte buffers without depending on non-public internals.

#[Swag.Pack(1)]
struct BmpFH     // BITMAPFILEHEADER (14 bytes)
{
    bfType:    u16
    bfSize:    u32
    bfRes1:    u16
    bfRes2:    u16
    bfOffBits: u32
}

#[Swag.Pack(1)]
struct BmpCH     // BITMAPCOREHEADER legacy 12-byte header
{
    bcSize:     u32
    bcWidth:    u16
    bcHeight:   u16
    bcPlanes:   u16
    bcBitCount: u16
}

func addBmpPaletteColor(cb: *ConcatBuffer, b, g, r: u8)
{
    cb.addNative(b)
    cb.addNative(g)
    cb.addNative(r)
    cb.addNative(0_u8)
}

private func requireBmpDecodeFails(bytes: const [..] u8)
{
    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("invalid-index.bmp", bytes) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Decode a 2x2 32-bit BGRA8 BMP (standard DIB header, no row padding).
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 70_u32     // 14+40+16
    fh.bfOffBits = 54_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40_u32
    bh.biWidth     = 2
    bh.biHeight    = 2
    bh.biPlanes    = 1_u16
    bh.biBitCount  = 32_u16
    bh.biSizeImage = 16_u32
    cb.addStruct(bh)

    // 2x2 BGRA - 4 bytes per pixel, no padding needed
    cb.addNative(10_u8)
    cb.addNative(20_u8)
    cb.addNative(30_u8)
    cb.addNative(255_u8)
    cb.addNative(40_u8)
    cb.addNative(50_u8)
    cb.addNative(60_u8)
    cb.addNative(200_u8)
    cb.addNative(70_u8)
    cb.addNative(80_u8)
    cb.addNative(90_u8)
    cb.addNative(128_u8)
    cb.addNative(100_u8)
    cb.addNative(110_u8)
    cb.addNative(120_u8)
    cb.addNative(64_u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.bitsPerPixel == 32)
    Swag.require(img.bytesPerPixel == 4)
    Swag.require(img.pixels.count == 16)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10_u8)
    Swag.require(img.pixels.buffer[1] == 20_u8)
    Swag.require(img.pixels.buffer[2] == 30_u8)
    Swag.require(img.pixels.buffer[3] == 255_u8)
}

// Decode a 5x5 24-bit BGR8 BMP where each row has 1 byte of alignment padding on disk.
// Row stride on disk = 16 bytes (15 pixel bytes + 1 pad); decoded image has 75 bytes (no padding).
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 134_u32     // 14+40+80
    fh.bfOffBits = 54_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40_u32
    bh.biWidth     = 5
    bh.biHeight    = 5
    bh.biPlanes    = 1_u16
    bh.biBitCount  = 24_u16
    bh.biSizeImage = 80_u32
    cb.addStruct(bh)

    // Row 0: pixel(0,0)=B100 G150 R200, pixels 1-4 zero, 1 pad byte
    cb.addNative(100_u8)
    cb.addNative(150_u8)
    cb.addNative(200_u8)
    for 12
    {
        cb.addNative(0_u8)
    }     // pixels 1-4
    cb.addNative(0_u8)     // pad
    // Rows 1-4 all zeros (4 rows x 16 bytes)
    for 64
    {
        cb.addNative(0_u8)
    }

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 5)
    Swag.require(img.height == 5)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.bitsPerPixel == 24)
    Swag.require(img.pixels.count == 75)     // 5x5x3 = 75, no padding in decoded result
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 100_u8)
    Swag.require(img.pixels.buffer[1] == 150_u8)
    Swag.require(img.pixels.buffer[2] == 200_u8)
}

// Decode a 2x2 24-bit BMP written with the legacy 12-byte BITMAPCOREHEADER.
// The decoder converts CoreHeader fields and uses bfOffBits to find pixel data.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 42_u32     // 14+12+16
    fh.bfOffBits = 26_u32     // 14+12
    cb.addStruct(fh)

    var ch: BmpCH
    ch.bcSize     = 12_u32
    ch.bcWidth    = 2_u16
    ch.bcHeight   = 2_u16
    ch.bcPlanes   = 1_u16
    ch.bcBitCount = 24_u16
    cb.addStruct(ch)

    // 2x2 BGR8: row stride = 8 bytes (6 pixel bytes + 2 pad)
    cb.addNative(10_u8)
    cb.addNative(20_u8)
    cb.addNative(30_u8)     // row0 pix0
    cb.addNative(40_u8)
    cb.addNative(50_u8)
    cb.addNative(60_u8)     // row0 pix1
    cb.addNative(0_u8)
    cb.addNative(0_u8)     // row0 pad
    cb.addNative(70_u8)
    cb.addNative(80_u8)
    cb.addNative(90_u8)     // row1 pix0
    cb.addNative(100_u8)
    cb.addNative(110_u8)
    cb.addNative(120_u8)     // row1 pix1
    cb.addNative(0_u8)
    cb.addNative(0_u8)     // row1 pad

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.pixels.count == 12)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10_u8)
    Swag.require(img.pixels.buffer[1] == 20_u8)
    Swag.require(img.pixels.buffer[2] == 30_u8)
}

// Decode a 2x2 24-bit BMP with biCompression=BI_BITFIELDS (value 3).
// The decoder accepts BI_BITFIELDS and treats pixel data identically to BI_RGB.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 70_u32     // 14+40+16
    fh.bfOffBits = 54_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40_u32
    bh.biWidth       = 2
    bh.biHeight      = 2
    bh.biPlanes      = 1_u16
    bh.biBitCount    = 24_u16
    bh.biCompression = Bmp.BI_BITFIELDS
    bh.biSizeImage   = 16_u32
    cb.addStruct(bh)

    cb.addNative(55_u8)
    cb.addNative(66_u8)
    cb.addNative(77_u8)     // row0 pix0
    cb.addNative(88_u8)
    cb.addNative(99_u8)
    cb.addNative(110_u8)     // row0 pix1
    cb.addNative(0_u8)
    cb.addNative(0_u8)     // row0 pad
    cb.addNative(11_u8)
    cb.addNative(22_u8)
    cb.addNative(33_u8)     // row1 pix0
    cb.addNative(44_u8)
    cb.addNative(55_u8)
    cb.addNative(66_u8)     // row1 pix1
    cb.addNative(0_u8)
    cb.addNative(0_u8)     // row1 pad

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 55_u8)
    Swag.require(img.pixels.buffer[1] == 66_u8)
    Swag.require(img.pixels.buffer[2] == 77_u8)
}

// Decode a top-down 2x2 24-bit BMP. The decoder stores pixels in the
// same bottom-up buffer convention as regular BMP files.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 70_u32
    fh.bfOffBits = 54_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40_u32
    bh.biWidth     = 2
    bh.biHeight    = -2
    bh.biPlanes    = 1_u16
    bh.biBitCount  = 24_u16
    bh.biSizeImage = 16_u32
    cb.addStruct(bh)

    cb.addNative(1_u8)
    cb.addNative(2_u8)
    cb.addNative(3_u8)
    cb.addNative(4_u8)
    cb.addNative(5_u8)
    cb.addNative(6_u8)
    cb.addNative(0_u8)
    cb.addNative(0_u8)
    cb.addNative(7_u8)
    cb.addNative(8_u8)
    cb.addNative(9_u8)
    cb.addNative(10_u8)
    cb.addNative(11_u8)
    cb.addNative(12_u8)
    cb.addNative(0_u8)
    cb.addNative(0_u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 7_u8)
    Swag.require(img.pixels.buffer[1] == 8_u8)
    Swag.require(img.pixels.buffer[2] == 9_u8)
    Swag.require(img.pixels.buffer[6] == 1_u8)
    Swag.require(img.pixels.buffer[7] == 2_u8)
    Swag.require(img.pixels.buffer[8] == 3_u8)
}

// Decode an 8-bit indexed BMP through its palette.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 74_u32
    fh.bfOffBits = 70_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40_u32
    bh.biWidth     = 4
    bh.biHeight    = 1
    bh.biPlanes    = 1_u16
    bh.biBitCount  = 8_u16
    bh.biClrUsed   = 4_u32
    bh.biSizeImage = 4_u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 10, 20, 30)
    addBmpPaletteColor(&cb, 40, 50, 60)
    addBmpPaletteColor(&cb, 70, 80, 90)
    cb.addNative(0_u8)
    cb.addNative(1_u8)
    cb.addNative(2_u8)
    cb.addNative(3_u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[3] == 10_u8)
    Swag.require(img.pixels.buffer[4] == 20_u8)
    Swag.require(img.pixels.buffer[5] == 30_u8)
    Swag.require(img.pixels.buffer[9] == 70_u8)
    Swag.require(img.pixels.buffer[10] == 80_u8)
    Swag.require(img.pixels.buffer[11] == 90_u8)
}

// Decode packed 1-bit indexed BMP rows.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 66_u32
    fh.bfOffBits = 62_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40_u32
    bh.biWidth     = 8
    bh.biHeight    = 1
    bh.biPlanes    = 1_u16
    bh.biBitCount  = 1_u16
    bh.biClrUsed   = 2_u32
    bh.biSizeImage = 4_u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 9, 8, 7)
    cb.addNative(0b10100000_u8)
    cb.addNative(0_u8)
    cb.addNative(0_u8)
    cb.addNative(0_u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 9_u8)
    Swag.require(img.pixels.buffer[1] == 8_u8)
    Swag.require(img.pixels.buffer[2] == 7_u8)
    Swag.require(img.pixels.buffer[3] == 0_u8)
    Swag.require(img.pixels.buffer[6] == 9_u8)
}

// Decode packed 4-bit indexed BMP rows.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 70_u32
    fh.bfOffBits = 66_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40_u32
    bh.biWidth     = 4
    bh.biHeight    = 1
    bh.biPlanes    = 1_u16
    bh.biBitCount  = 4_u16
    bh.biClrUsed   = 3_u32
    bh.biSizeImage = 4_u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 11, 12, 13)
    addBmpPaletteColor(&cb, 21, 22, 23)
    cb.addNative(0x12_u8)
    cb.addNative(0x10_u8)
    cb.addNative(0_u8)
    cb.addNative(0_u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 11_u8)
    Swag.require(img.pixels.buffer[1] == 12_u8)
    Swag.require(img.pixels.buffer[2] == 13_u8)
    Swag.require(img.pixels.buffer[3] == 21_u8)
    Swag.require(img.pixels.buffer[4] == 22_u8)
    Swag.require(img.pixels.buffer[5] == 23_u8)
}

// Decode 16-bit BI_RGB pixels using the default 5-5-5 masks.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 58_u32
    fh.bfOffBits = 54_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40_u32
    bh.biWidth     = 2
    bh.biHeight    = 1
    bh.biPlanes    = 1_u16
    bh.biBitCount  = 16_u16
    bh.biSizeImage = 4_u32
    cb.addStruct(bh)
    cb.addNative(0x7C00_u16)
    cb.addNative(0x03E0_u16)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 0_u8)
    Swag.require(img.pixels.buffer[1] == 0_u8)
    Swag.require(img.pixels.buffer[2] == 255_u8)
    Swag.require(img.pixels.buffer[3] == 0_u8)
    Swag.require(img.pixels.buffer[4] == 255_u8)
    Swag.require(img.pixels.buffer[5] == 0_u8)
}

// Decode 16-bit BI_BITFIELDS pixels using explicit 5-6-5 masks.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 70_u32
    fh.bfOffBits = 66_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40_u32
    bh.biWidth       = 2
    bh.biHeight      = 1
    bh.biPlanes      = 1_u16
    bh.biBitCount    = 16_u16
    bh.biCompression = Bmp.BI_BITFIELDS
    bh.biSizeImage   = 4_u32
    cb.addStruct(bh)
    cb.addNative(0xF800_u32)
    cb.addNative(0x07E0_u32)
    cb.addNative(0x001F_u32)
    cb.addNative(0x001F_u16)
    cb.addNative(0x07E0_u16)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 255_u8)
    Swag.require(img.pixels.buffer[1] == 0_u8)
    Swag.require(img.pixels.buffer[2] == 0_u8)
    Swag.require(img.pixels.buffer[3] == 0_u8)
    Swag.require(img.pixels.buffer[4] == 255_u8)
    Swag.require(img.pixels.buffer[5] == 0_u8)
}

// Decode 32-bit BI_BITFIELDS pixels using explicit masks and opaque alpha when absent.
#test
{
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 126_u32
    fh.bfOffBits = 122_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 108_u32
    bh.biWidth       = 1
    bh.biHeight      = 1
    bh.biPlanes      = 1_u16
    bh.biBitCount    = 32_u16
    bh.biCompression = Bmp.BI_BITFIELDS
    bh.biSizeImage   = 4_u32
    cb.addStruct(bh)
    cb.addNative(0x000000FF_u32)
    cb.addNative(0x0000FF00_u32)
    cb.addNative(0x00FF0000_u32)
    cb.addNative(0_u32)
    var extension: [52] u8
    for index in 0 until extension.count
    {
        extension[index] = 0
    }

    cb.addBytes(extension)
    cb.addNative(0x000000FF_u32)

    let img = expect Image.decode("masked32.bmp", nnBytes(cb.toSlice()))
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 0_u8)
    Swag.require(img.pixels.buffer[1] == 0_u8)
    Swag.require(img.pixels.buffer[2] == 255_u8)
    Swag.require(img.pixels.buffer[3] == 255_u8)
}

#test
{
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 70_u32
    fh.bfOffBits = 66_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40_u32
    bh.biWidth       = 1
    bh.biHeight      = 1
    bh.biPlanes      = 1_u16
    bh.biBitCount    = 16_u16
    bh.biCompression = Bmp.BI_BITFIELDS
    bh.biSizeImage   = 4_u32
    cb.addStruct(bh)
    cb.addNative(0x5000_u32)     // Red mask has separated bit runs.
    cb.addNative(0x03E0_u32)
    cb.addNative(0x001F_u32)
    cb.addNative(0x5000_u16)
    cb.addNative(0_u16)

    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("noncontiguous-mask.bmp", nnBytes(cb.toSlice())) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Exercise whole vector blocks and tails in byte, mixed-width and wide bitfields.
#test
{
    const Width  = 7
    const Height = 2
    const Bytes  = Width * Height * 4
    const Layouts: [5] [4] u32 = [[0x00FF0000, 0x0000FF00, 0x000000FF, 0],
                                  [0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000],
                                  [0x3FF00000, 0x000FFC00, 0x000003FF, 0xC0000000],
                                  [0x00FFFFFF, 0x0F000000, 0xF0000000, 0],
                                  [0x3FFFFFFF, 0x40000000, 0x80000000, 0]]

    func pixelWord(x, y: s32)->u32 => cast(u32, (y * Width + x + 1)) * #wrap 0x9E37_79B9_u32

    func scale(pixel, mask: u32)->u8
    {
        if not mask
        {
            return 255
        }

        let shift = Math.trailingZeros(mask)
        let max   = cast(u64, mask >> shift)
        let value = cast(u64, ((pixel & mask) >> shift))
        return cast(u8, ((value * 255 + max / 2) / max))
    }

    for layout in Layouts
    {
        var cb: ConcatBuffer
        cb.addStruct(BmpFH{bfType: 0x4D42, bfSize: 70 + Bytes, bfOffBits: 70})
        cb.addStruct(Bmp.Header{biSize: 56, biWidth: Width, biHeight: -Height, biPlanes: 1,
                                biBitCount: 32, biCompression: Bmp.BI_BITFIELDS, biSizeImage: Bytes})
        for mask in layout
        {
            cb.addNative(mask)
        }

        for y in Height
        {
            for x in Width
            {
                cb.addNative(pixelWord(cast(s32, x), cast(s32, y)))
            }
        }

        let image = expect Image.decode("masked-rows.bmp", nnBytes(cb.toSlice()))
        for y in Height
        {
            for x in Width
            {
                let word = pixelWord(cast(s32, x), cast(s32, y))
                let want = Color.fromArgb(scale(word, layout[3]), scale(word, layout[0]), scale(word, layout[1]), scale(word, layout[2]))
                Swag.require(image.pixelColor(cast(s32, x), cast(s32, y)) == want)
            }
        }
    }
}

// Check both sides of every rounding transition for low and high 32-bit fields.
#test
{
    const Samples = 510
    var words: [Samples] u32
    var image = Image.create(Samples, 1, .BGRA8)
    for bits in 1 until 31
    {
        let max = (1_u32 << bits) - 1
        for high in [false, true]
        {
            let shift = high ? 32 - bits : 0
            let masks = Bmp.Masks{r: Bmp.readMask(max << shift),
                                  g: Bmp.readMask(high ? 1_u32 : 1_u32 << bits),
                                  b: Bmp.readMask(high ? 2_u32 : 1_u32 << (bits + 1))}
            for level in 255
            {
                let boundary = cast(u32, ((cast(u64, max) * (2 * level + 1) + 509) / 510))
                words[2 * level]     = (boundary - 1) << shift
                words[2 * level + 1] = boundary << shift
            }

            let src = cast(const [*] u8, &words[0])
            expect Bmp.decode32(&image, src, src + #sizeof(#typeof(words)), masks, false)
            for i in Samples
            {
                let color = image.pixelColor(cast(s32, i), 0)
                Swag.require(color.r == Bmp.maskToByte(words[i], masks.r))
            }
        }
    }
}

// Packed palette rows drop padding and unused trailing bits in both full and short palettes.
#test
{
    const Width  = 33
    const Height = 17
    for depth in [1_u16, 4, 8]
    {
        let full          = 1_u32 << depth
        let short         = depth == 1 ? 1_u32 : (depth == 4 ? 7_u32 : 43_u32)
        let pixelsPerByte = 8_u32 / depth
        let dataBytes     = (cast(u32, Width) + pixelsPerByte - 1) / pixelsPerByte
        let stride        = (dataBytes + 3) & ~3_u32
        for paletteCount in [short, full]
        {
            let offset = 54 + 4 * paletteCount
            var cb: ConcatBuffer
            cb.addStruct(BmpFH{bfType: 0x4D42, bfSize: offset + stride * Height, bfOffBits: offset})
            cb.addStruct(Bmp.Header{biSize: 40, biWidth: Width, biHeight: -Height, biPlanes: 1,
                                    biBitCount: depth, biSizeImage: stride * Height, biClrUsed: paletteCount})
            for color in paletteCount
            {
                let index = cast(u8, color)
                addBmpPaletteColor(&cb, index, index ^ 0xA5, 255 - index)
            }

            for y in Height
            {
                for byte in dataBytes
                {
                    var packed: u8
                    for slot in pixelsPerByte
                    {
                        let x     = byte * pixelsPerByte + slot
                        let index = x < Width ? (x * 5 + cast(u32, y) * 17) % paletteCount : full - 1
                        packed |= cast(u8, (index << ((pixelsPerByte - slot - 1) * depth)))
                    }

                    cb.addNative(packed)
                }

                for stride - dataBytes
                {
                    cb.addNative(0xFD_u8)
                }
            }

            cb.makeLinear()
            let image = expect Image.decode("indexed-rows.bmp", nnBytes(cb.toSlice()))
            for y in Height
            {
                for x in Width
                {
                    let index = cast(u8, (cast(u32, x * 5 + y * 17) % paletteCount))
                    let want  = Color.fromArgb(255_u8, 255 - index, index ^ 0xA5, index)
                    Swag.require(image.pixelColor(cast(s32, x), cast(s32, y)) == want)
                }
            }
        }
    }
}

// Odd RLE4 runs and absolute packets leave deltas and unused low nibbles untouched.
#test
{
    const Packed: [18] u8 = [5, 0x01, 0, 2, 2, 0, 0, 5, 0x10, 0x10, 0x1F, 0xA5, 1, 0x0F, 0, 0, 0, 1]
    const First           = 0xFF020100_u32
    const Second          = 0xFF2C2B2A_u32
    const Clear           = 0xFF000000_u32
    const Expected        = [First, Second, First, Second, First, Clear, Clear, Second, First, Second, First, Second, First]
    var cb: ConcatBuffer
    cb.addStruct(BmpFH{bfType: 0x4D42, bfSize: 62 + cast(u32, Packed.count), bfOffBits: 62})
    cb.addStruct(Bmp.Header{biSize: 40, biWidth: 13, biHeight: 1, biPlanes: 1,
                            biBitCount: 4, biCompression: Bmp.BI_RLE4, biSizeImage: cast(u32, Packed.count), biClrUsed: 2})
    addBmpPaletteColor(&cb, 0, 1, 2)
    addBmpPaletteColor(&cb, 42, 43, 44)
    cb.addBytes(Packed)

    let image = expect Image.decode("rle4-mixed.bmp", nnBytes(cb.toSlice()))
    for color, x in Expected
    {
        Swag.require(image.pixelColor(cast(s32, x), 0).argb == color)
    }
}

// Error: BI_RLE8 stream ending without an end-of-bitmap marker must fail.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 64_u32
    fh.bfOffBits = 62_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40_u32
    bh.biWidth       = 1
    bh.biHeight      = 1
    bh.biPlanes      = 1_u16
    bh.biBitCount    = 8_u16
    bh.biCompression = Bmp.BI_RLE8
    bh.biClrUsed     = 2_u32
    bh.biSizeImage   = 2_u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 10, 20, 30)
    cb.addNative(1_u8)
    cb.addNative(1_u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    var img: Image
    var errorOutcome: Swag.Error
    catch { img = try Image.load(path.toString()) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Error: BI_RLE4 stream ending without an end-of-bitmap marker must fail.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 66_u32
    fh.bfOffBits = 62_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40_u32
    bh.biWidth       = 1
    bh.biHeight      = 1
    bh.biPlanes      = 1_u16
    bh.biBitCount    = 4_u16
    bh.biCompression = Bmp.BI_RLE4
    bh.biClrUsed     = 2_u32
    bh.biSizeImage   = 4_u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 40, 50, 60)
    cb.addNative(1_u8)
    cb.addNative(0x10_u8)
    cb.addNative(0_u8)
    cb.addNative(0_u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    var img: Image
    var errorOutcome: Swag.Error
    catch { img = try Image.load(path.toString()) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// A truncated command can occur before the first pixel or in the end marker.
#test
{
    for depth in [4_u16, 8]
    {
        let compression = depth == 4 ? Bmp.BI_RLE4 : Bmp.BI_RLE8
        let index       = depth == 4 ? 0x10_u8 : 1_u8
        for size in [1_u32, 3]
        {
            var cb: ConcatBuffer
            cb.addStruct(BmpFH{bfType: 0x4D42, bfSize: 62 + size, bfOffBits: 62})
            cb.addStruct(Bmp.Header{biSize: 40, biWidth: 1, biHeight: 1, biPlanes: 1, biBitCount: depth,
                                    biCompression: compression, biSizeImage: size, biClrUsed: 2})
            addBmpPaletteColor(&cb, 0, 0, 0)
            addBmpPaletteColor(&cb, 40, 50, 60)
            cb.addNative(1_u8)
            if size == 3
            {
                cb.addNative(index)
                cb.addNative(0_u8)
            }

            var image:   Image
            var outcome: Swag.Error
            catch { image = try Image.decode("short-rle-command.bmp", nnBytes(cb.toSlice())) } as outcome
            Swag.require(outcome.value() != null)
        }
    }
}

// Decode BI_RLE8 indexed data.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 82_u32
    fh.bfOffBits = 70_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40_u32
    bh.biWidth       = 4
    bh.biHeight      = 2
    bh.biPlanes      = 1_u16
    bh.biBitCount    = 8_u16
    bh.biCompression = Bmp.BI_RLE8
    bh.biClrUsed     = 4_u32
    bh.biSizeImage   = 12_u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 10, 0, 0)
    addBmpPaletteColor(&cb, 0, 20, 0)
    addBmpPaletteColor(&cb, 0, 0, 30)
    cb.addNative(4_u8)
    cb.addNative(1_u8)
    cb.addNative(0_u8)
    cb.addNative(0_u8)
    cb.addNative(0_u8)
    cb.addNative(4_u8)
    cb.addNative(2_u8)
    cb.addNative(3_u8)
    cb.addNative(0_u8)
    cb.addNative(1_u8)
    cb.addNative(0_u8)
    cb.addNative(1_u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10_u8)
    Swag.require(img.pixels.buffer[12] == 0_u8)
    Swag.require(img.pixels.buffer[13] == 20_u8)
    Swag.require(img.pixels.buffer[15] == 0_u8)
    Swag.require(img.pixels.buffer[16] == 0_u8)
    Swag.require(img.pixels.buffer[17] == 30_u8)
}

// Short RLE8 runs follow vertical deltas and keep skipped pixels clear.
#test
{
    const Packed: [14] u8 = [1, 1, 0, 2, 1, 1, 2, 2, 0, 0, 3, 3, 0, 1]
    var cb: ConcatBuffer
    cb.addStruct(BmpFH{bfType: 0x4D42, bfSize: 70 + cast(u32, Packed.count), bfOffBits: 70})
    cb.addStruct(Bmp.Header{biSize: 40, biWidth: 4, biHeight: 3, biPlanes: 1,
                            biBitCount: 8, biCompression: Bmp.BI_RLE8, biSizeImage: cast(u32, Packed.count), biClrUsed: 4})
    addBmpPaletteColor(&cb, 5, 6, 7)
    addBmpPaletteColor(&cb, 10, 0, 0)
    addBmpPaletteColor(&cb, 0, 20, 0)
    addBmpPaletteColor(&cb, 0, 0, 30)
    cb.addBytes(Packed)

    let image = expect Image.decode("rle8-delta.bmp", nnBytes(cb.toSlice()))
    Swag.require(image.pixelColor(0, 2).argb == 0xFF00000A)
    Swag.require(image.pixelColor(1, 2).argb == 0xFF000000)
    Swag.require(image.pixelColor(1, 1).argb == 0xFF000000)
    Swag.require(image.pixelColor(2, 1).argb == 0xFF001400)
    Swag.require(image.pixelColor(3, 1).argb == 0xFF001400)
    Swag.require(image.pixelColor(0, 0).argb == 0xFF1E0000)
    Swag.require(image.pixelColor(2, 0).argb == 0xFF1E0000)
    Swag.require(image.pixelColor(3, 0).argb == 0xFF000000)
}

// Decode BI_RLE4 indexed data.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 74_u32
    fh.bfOffBits = 70_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40_u32
    bh.biWidth       = 4
    bh.biHeight      = 1
    bh.biPlanes      = 1_u16
    bh.biBitCount    = 4_u16
    bh.biCompression = Bmp.BI_RLE4
    bh.biClrUsed     = 4_u32
    bh.biSizeImage   = 4_u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 11, 12, 13)
    addBmpPaletteColor(&cb, 21, 22, 23)
    addBmpPaletteColor(&cb, 31, 32, 33)
    cb.addNative(4_u8)
    cb.addNative(0x12_u8)
    cb.addNative(0_u8)
    cb.addNative(1_u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 11_u8)
    Swag.require(img.pixels.buffer[1] == 12_u8)
    Swag.require(img.pixels.buffer[2] == 13_u8)
    Swag.require(img.pixels.buffer[3] == 21_u8)
    Swag.require(img.pixels.buffer[4] == 22_u8)
    Swag.require(img.pixels.buffer[5] == 23_u8)
}

// Decode with decodePixels=false: metadata fields are populated but no pixel buffer is allocated.
#test
{
    let path  = getTestDataPath("test.bmp")
    let bytes = expect File.readAllBytes(path)
    var opts: DecodeOptions
    opts.decodePixels = false

    let img = expect Image.decode(path, bytes.toSlice(), opts)
    Swag.require(img.width == 4)
    Swag.require(img.height == 4)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(not img.isValid())
}

// Error: indexed BMP with no palette must fail.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 58_u32
    fh.bfOffBits = 54_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize     = 40_u32
    bh.biWidth    = 2
    bh.biHeight   = 1
    bh.biPlanes   = 1_u16
    bh.biBitCount = 8_u16
    cb.addStruct(bh)
    for 4
    {
        cb.addNative(0_u8)
    }

    discard expect File.writeAllBytes(path.toString(), cb)
    var img: Image
    var err34Outcome: Swag.Error
    catch { img = try Image.load(path.toString()) } as err34Outcome
    let err34 = err34Outcome.value()
    Swag.require(err34 != null)
}

// Reject packed and RLE pixels whose palette index has no declared color entry.
#test
{
    var packed: ConcatBuffer
    var file:   BmpFH
    file.bfType    = 0x4D42_u16
    file.bfSize    = 62_u32
    file.bfOffBits = 58_u32
    packed.addStruct(file)

    var header: Bmp.Header
    header.biSize     = 40_u32
    header.biWidth    = 1
    header.biHeight   = 1
    header.biPlanes   = 1_u16
    header.biBitCount = 1_u16
    header.biClrUsed  = 1_u32
    packed.addStruct(header)
    addBmpPaletteColor(&packed, 3, 2, 1)
    packed.addNative(0x80_u8)     // The first pixel indexes palette entry 1.
    packed.addNative(0_u8)
    packed.addNative(0_u8)
    packed.addNative(0_u8)
    requireBmpDecodeFails(nnBytes(packed.toSlice()))

    var rle8: ConcatBuffer
    file.bfSize = 62_u32
    rle8.addStruct(file)
    header.biBitCount    = 8_u16
    header.biCompression = Bmp.BI_RLE8
    header.biSizeImage   = 4_u32
    rle8.addStruct(header)
    addBmpPaletteColor(&rle8, 3, 2, 1)
    rle8.addNative(1_u8)     // One pixel using undeclared index 1.
    rle8.addNative(1_u8)
    rle8.addNative(0_u8)     // End of bitmap.
    rle8.addNative(1_u8)
    requireBmpDecodeFails(nnBytes(rle8.toSlice()))

    var rle4: ConcatBuffer
    rle4.addStruct(file)
    header.biBitCount    = 4_u16
    header.biCompression = Bmp.BI_RLE4
    rle4.addStruct(header)
    addBmpPaletteColor(&rle4, 3, 2, 1)
    rle4.addNative(1_u8)     // The high nibble indexes undeclared entry 1.
    rle4.addNative(0x10_u8)
    rle4.addNative(0_u8)
    rle4.addNative(1_u8)
    requireBmpDecodeFails(nnBytes(rle4.toSlice()))

    var rle8Absolute: ConcatBuffer
    file.bfSize = 66_u32
    rle8Absolute.addStruct(file)
    header.biWidth       = 3
    header.biBitCount    = 8_u16
    header.biCompression = Bmp.BI_RLE8
    header.biSizeImage   = 8_u32
    rle8Absolute.addStruct(header)
    addBmpPaletteColor(&rle8Absolute, 3, 2, 1)
    rle8Absolute.addNative(0_u8)     // Absolute packet of three indices.
    rle8Absolute.addNative(3_u8)
    rle8Absolute.addNative(0_u8)
    rle8Absolute.addNative(1_u8)
    rle8Absolute.addNative(0_u8)
    rle8Absolute.addNative(0_u8)     // Word padding.
    rle8Absolute.addNative(0_u8)     // End of bitmap.
    rle8Absolute.addNative(1_u8)
    requireBmpDecodeFails(nnBytes(rle8Absolute.toSlice()))

    var rle4Absolute: ConcatBuffer
    file.bfSize = 64_u32
    rle4Absolute.addStruct(file)
    header.biBitCount    = 4_u16
    header.biCompression = Bmp.BI_RLE4
    header.biSizeImage   = 6_u32
    rle4Absolute.addStruct(header)
    addBmpPaletteColor(&rle4Absolute, 3, 2, 1)
    rle4Absolute.addNative(0_u8)     // Absolute packet of three indices.
    rle4Absolute.addNative(3_u8)
    rle4Absolute.addNative(0x10_u8)     // Includes undeclared palette entry 1.
    rle4Absolute.addNative(0_u8)
    rle4Absolute.addNative(0_u8)     // End of bitmap.
    rle4Absolute.addNative(1_u8)
    requireBmpDecodeFails(nnBytes(rle4Absolute.toSlice()))
}

// Error: buffer too small to hold the full DIB header must fail.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())

    // FileHeader (14 bytes) + only 4 bytes of DIB header (biSize = 40, non-CoreHeader path).
    // The decoder will see size=40 != 12 and then check dataof+sizeof(Header) > last, then fail.
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 18_u32
    fh.bfOffBits = 54_u32
    cb.addStruct(fh)
    cb.addNative(40_u32)     // biSize only - rest of DIB header missing

    discard expect File.writeAllBytes(path.toString(), cb)
    var img: Image
    var err36Outcome: Swag.Error
    catch { img = try Image.load(path.toString()) } as err36Outcome
    let err36 = err36Outcome.value()
    Swag.require(err36 != null)
}

// Error: unknown compression value (not BI_RGB, BI_RLE8, BI_RLE4, or BI_BITFIELDS) must fail.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42_u16
    fh.bfSize    = 58_u32
    fh.bfOffBits = 54_u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40_u32
    bh.biWidth       = 2
    bh.biHeight      = 1
    bh.biPlanes      = 1_u16
    bh.biBitCount    = 24_u16
    bh.biCompression = 4_u32     // value 4 is not a recognised compression type
    cb.addStruct(bh)
    for 4
    {
        cb.addNative(0_u8)
    }

    discard expect File.writeAllBytes(path.toString(), cb)
    var img: Image
    var err38Outcome: Swag.Error
    catch { img = try Image.load(path.toString()) } as err38Outcome
    let err38 = err38Outcome.value()
    Swag.require(err38 != null)
}

// Encode / roundtrip tests.

// The encoder is called directly (not through Image.save) to test BMP encoding
// logic independently of the encoder registry.

// Encode full SIMD blocks and tails from RGB/RGBA, including 24-bit row padding.
#test
{
    const Width  = 19
    const Height = 2
    for pixelFormat in [PixelFormat.RGB8, PixelFormat.RGBA8]
    {
        var src = Image.create(Width, Height, pixelFormat)
        for i in src.pixels.count
        {
            src.pixels.storage()[i] = cast(u8, ((i * 37 + 19) & 0xFF))
        }

        var cb       = expect src.encode("memory.bmp")
        let rowBytes = cast(u64, Width) * src.bytesPerPixel
        let stride   = Bmp.rowStride(Width, src.bitsPerPixel)
        Swag.require(cb.count() == #sizeof(BmpFH) + #sizeof(Bmp.Header) + stride * Height)
        cb.makeLinear()
        let bytes = nnBytes(cb.toSlice())
        if pixelFormat == .RGB8
        {
            for y in Height
            {
                for offset in rowBytes until stride
                {
                    Swag.require(bytes[#sizeof(BmpFH) + #sizeof(Bmp.Header) + cast(u64, y) * stride + offset] == 0)
                }
            }
        }

        let img = expect Image.decode("memory.bmp", bytes, {})
        let bytesPerPixel = cast(u64, src.bytesPerPixel)
        Swag.require(img.pixelFormat == (bytesPerPixel == 3 ? .BGR8 : .BGRA8))
        for pixel in cast(u64, Width) * Height
        {
            let offset = pixel * bytesPerPixel
            Swag.require(img.pixels.storage()[offset] == src.pixels.storage()[offset + 2])
            Swag.require(img.pixels.storage()[offset + 1] == src.pixels.storage()[offset + 1])
            Swag.require(img.pixels.storage()[offset + 2] == src.pixels.storage()[offset])
            if bytesPerPixel == 4
            {
                Swag.require(img.pixels.storage()[offset + 3] == src.pixels.storage()[offset + 3])
            }
        }
    }
}

// Encode a BGR8 4x4 image (row stride 12 bytes - already 4-byte aligned, no padding needed).
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(4, 4, .BGR8)
    src.clear()

    let cb = expect src.encode("memory.bmp")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 4)
    Swag.require(img.height == 4)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.bitsPerPixel == 24)
    Swag.require(img.bytesPerPixel == 3)
    Swag.require(img.pixels.count == 48)
}

// Encode a BGR8 5x5 image (row stride 15 bytes - encoder pads to 16, decoder strips padding).
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(5, 5, .BGR8)
    src.clear()

    let cb = expect src.encode("memory.bmp")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 5)
    Swag.require(img.height == 5)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.pixels.count == 75)
}

// Encode BGR8: pixel byte values survive the encode/decode round-trip unchanged.
// The encoder copies raw BGR bytes when stride is already 4-byte aligned.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(4, 4, .BGR8)
    src.clear()
    let srcBuf = src.pixels.storage()
    srcBuf[0]  = 200_u8     // pixel(0,0) B
    srcBuf[1]  = 128_u8     //             G
    srcBuf[2]  = 64_u8      //             R
    srcBuf[45] = 33_u8      // last row, pixel 3, B channel

    let cb = expect src.encode("memory.bmp")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 200_u8)
    Swag.require(img.pixels.buffer[1] == 128_u8)
    Swag.require(img.pixels.buffer[2] == 64_u8)
    Swag.require(img.pixels.buffer[45] == 33_u8)
}

// Encode a BGRA8 2x2 image: raw 32-bit bytes are copied directly by the encoder.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(2, 2, .BGRA8)
    src.clear()

    let cb = expect src.encode("memory.bmp")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.bitsPerPixel == 32)
    Swag.require(img.bytesPerPixel == 4)
    Swag.require(img.pixels.count == 16)
}

// Encode BGRA8: pixel byte values survive the encode/decode round-trip unchanged.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(2, 2, .BGRA8)
    src.clear()
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 10_u8      // pixel(0,0) B
    srcBuf[1] = 20_u8      //             G
    srcBuf[2] = 30_u8      //             R
    srcBuf[3] = 200_u8     //             A
    srcBuf[4] = 50_u8      // pixel(1,0) B
    srcBuf[7] = 128_u8     // pixel(1,0) A

    let cb = expect src.encode("memory.bmp")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10_u8)
    Swag.require(img.pixels.buffer[1] == 20_u8)
    Swag.require(img.pixels.buffer[2] == 30_u8)
    Swag.require(img.pixels.buffer[3] == 200_u8)
    Swag.require(img.pixels.buffer[4] == 50_u8)
    Swag.require(img.pixels.buffer[7] == 128_u8)
}

// Encode an RGB8 4x4 image: encoder swaps R/B to write BGR bytes into the BMP file,
// so the loaded image is BGR8 with channels in reversed order relative to the source.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(4, 4, .RGB8)
    src.clear()
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 100_u8     // pixel(0,0) R
    srcBuf[1] = 150_u8     //             G
    srcBuf[2] = 200_u8     //             B

    let cb = expect src.encode("memory.bmp")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 4)
    Swag.require(img.height == 4)
    Swag.require(img.pixelFormat == .BGR8)     // RGB8 saved as 24-bit BGR, loads as BGR8
    // Encoder writes [B=200, G=150, R=100]; decoder stores as BGR8 bytes verbatim
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 200_u8)     // B
    Swag.require(img.pixels.buffer[1] == 150_u8)     // G
    Swag.require(img.pixels.buffer[2] == 100_u8)     // R
}

// Encode an RGBA8 2x2 image: encoder swaps R/B to write BGRA bytes,
// so the loaded image is BGRA8 with channels in reversed R/B order relative to the source.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(2, 2, .RGBA8)
    src.clear()
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 10_u8      // pixel(0,0) R
    srcBuf[1] = 20_u8      //             G
    srcBuf[2] = 30_u8      //             B
    srcBuf[3] = 255_u8     //             A

    let cb = expect src.encode("memory.bmp")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .BGRA8)     // RGBA8 saved as 32-bit BGRA, loads as BGRA8
    // Encoder writes [B=30, G=20, R=10, A=255]; decoder stores as BGRA8 bytes verbatim
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 30_u8)      // B
    Swag.require(img.pixels.buffer[1] == 20_u8)      // G
    Swag.require(img.pixels.buffer[2] == 10_u8)      // R
    Swag.require(img.pixels.buffer[3] == 255_u8)     // A
}

// Encode BGR8 5x5 with row padding: pixel values survive despite the on-disk stride difference.
// Verifies encoder pads correctly and decoder strips the padding (file = 134 bytes, decoded = 75 bytes).
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(5, 5, .BGR8)
    src.clear()
    let srcBuf = src.pixels.storage()
    srcBuf[0]  = 77_u8     // pixel(0,0) B
    srcBuf[1]  = 88_u8     //             G
    srcBuf[2]  = 99_u8     //             R
    srcBuf[72] = 42_u8     // row4 pixel(0) B

    let cb = expect src.encode("memory.bmp")

    // File must contain alignment padding: 5 rows x 16 bytes = 80 bytes pixel data
    Swag.require(cb.count() == 134)     // 14+40+80
    cb.makeLinear()
    let bytes = nnBytes(cb.toSlice())
    Swag.require(bytes != null)
    let fh = cast(const *BmpFH, bytes.buffer)
    let bh = cast(const *Bmp.Header, (bytes.buffer + #sizeof(BmpFH)))
    Swag.require(fh.bfSize == cast(u32, cb.count()))
    Swag.require(fh.bfOffBits == 54_u32)
    Swag.require(bh.biSizeImage == 80_u32)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixels.count == 75)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 77_u8)
    Swag.require(img.pixels.buffer[1] == 88_u8)
    Swag.require(img.pixels.buffer[2] == 99_u8)
    Swag.require(img.pixels.buffer[72] == 42_u8)
}

// Packed DIB output shares the file encoder's channel conversion and odd-width row padding.
#test
{
    let formats = [PixelFormat.RGB8, .BGR8, .RGBA8, .BGRA8]
    for format in formats
    {
        var source = Image.create(3, 2, format)
        for i in source.pixels.count
        {
            source.pixels[i] = cast(u8, (17 + i * 3))
        }

        if source.bytesPerPixel == 4
        {
            for i in 6
            {
                source.pixels[i * 4 + 3] = 255
            }
        }

        let bmp = expect source.encodeToBytes("image.bmp")
        let dib = expect source.encodeToBytes("image.bmp", Bmp.EncodeOptions{fileHeader: false})
        Swag.require(bmp.count == dib.count + #sizeof(Bmp.FileHeader))
        Swag.require(Memory.compare(bmp.storage() + #sizeof(Bmp.FileHeader), dib.storage(), dib.count) == 0)
        Swag.require(dib.count == #sizeof(Bmp.Header) + 24)
        Swag.require(Image.canLoad("image.DIB"))
        let decoded = expect Image.decode("image.DIB", dib.toSlice())
        for y in source.height
        {
            for x in source.width
            {
                Swag.require(decoded.pixelColor(x, y) == source.pixelColor(x, y))
            }
        }
    }
}
