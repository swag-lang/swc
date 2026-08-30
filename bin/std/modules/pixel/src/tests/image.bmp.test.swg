#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private func checkBmp16Masks(masks: Bmp.Masks)
{
    // Every source word, unaligned pointers, the SIMD/tail boundary, and
    // untouched sentinels match the generic mask normalization exactly.
    const Pixels = 65536 + 1
    var source:   Array'u8
    var actual:   Array'u8
    var expected: Array'u8
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
        let value = cast(u16) (i & 0xFFFF)
        source[1 + 2 * i]       = cast(u8) (value & 0xFF)
        source[1 + 2 * i + 1]   = cast(u8) (value >> 8)
        expected[3 + 3 * i]     = Bmp.maskToByte(value, masks.b)
        expected[3 + 3 * i + 1] = Bmp.maskToByte(value, masks.g)
        expected[3 + 3 * i + 2] = Bmp.maskToByte(value, masks.r)
    }

    Bmp.decode16Row(source.buffer! + 1, actual.buffer! + 3, Pixels, masks)
    for i in actual.count do
        Swag.assert(actual[i] == expected[i])
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

    // A channel wider than eight bits must retain the scalar fallback.
    masks.r = Bmp.readMask(0x01FF)
    masks.g = Bmp.readMask(0x3E00)
    masks.b = Bmp.readMask(0xC000)
    checkBmp16Masks(masks)
}

// Create an image in memory and verify its metadata.
#test
{
    let img = Image.create(4, 4, .BGR8)
    Swag.assert(img.isValid())
    Swag.assert(img.width == 4)
    Swag.assert(img.height == 4)
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.bitsPerPixel == 24)
    Swag.assert(img.bytesPerPixel == 3)
    Swag.assert(img.pixels.count == 48)
}

// Verify getTestDataPath resolves the file path correctly.
#test
{
    let path = getTestDataPath("test.bmp")
    Swag.assert(path.count > 0)
    Swag.assert(File.exists(path))
}

// Read the BMP bytes from disk without decoding.
#test
{
    let path  = getTestDataPath("test.bmp")
    let bytes = expect File.readAllBytes(path)
    Swag.assert(bytes.count == 102)
}

// Verify that the decoder registry is functional and finds the BMP decoder.
#test
{
    Swag.assert(Image.canLoad("test.bmp"))
    Swag.assert(!Image.canLoad("test.xyz"))
}

// Decode a BMP from pre-loaded bytes using Image.decode (same internal path as Image.load).
#test
{
    let path  = getTestDataPath("test.bmp")
    let bytes = expect File.readAllBytes(path)
    let img   = expect Image.decode(path, bytes.toSlice(), {})
    Swag.assert(img.isValid())
    Swag.assert(img.width == 4)
    Swag.assert(img.height == 4)
    Swag.assert(img.pixelFormat == .BGR8)
}

// Load a 4x4 24-bit BMP from disk and verify image metadata.
#test
{
    let path = getTestDataPath("test.bmp")
    let img  = expect Image.load(path)
    Swag.assert(img.isValid())
    Swag.assert(img.width == 4)
    Swag.assert(img.height == 4)
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.bitsPerPixel == 24)
    Swag.assert(img.bytesPerPixel == 3)
    Swag.assert(img.pixels.count == 48)
}

// Load larger RGB/RGBA fixtures copied from the historical pixel test data.
#test
{
    let rgb = expect Image.load(getTestDataPath("rgb.bmp"))
    Swag.assert(rgb.isValid())
    Swag.assert(rgb.width == 660)
    Swag.assert(rgb.height == 441)
    Swag.assert(rgb.pixelFormat == .BGR8)
    Swag.assert(rgb.pixels.count == 873180)
    Swag.assert(rgb.pixels.buffer != null)
    Swag.assert(rgb.pixels.buffer[0] == 201'u8)
    Swag.assert(rgb.pixels.buffer[1] == 205'u8)
    Swag.assert(rgb.pixels.buffer[2] == 194'u8)

    let rgba = expect Image.load(getTestDataPath("rgba.bmp"))
    Swag.assert(rgba.isValid())
    Swag.assert(rgba.width == 660)
    Swag.assert(rgba.height == 441)
    Swag.assert(rgba.pixelFormat == .BGRA8)
    Swag.assert(rgba.pixels.count == 1164240)
    Swag.assert(rgba.pixels.buffer != null)
    Swag.assert(rgba.pixels.buffer[0] == 201'u8)
    Swag.assert(rgba.pixels.buffer[1] == 205'u8)
    Swag.assert(rgba.pixels.buffer[2] == 194'u8)
    Swag.assert(rgba.pixels.buffer[3] == 255'u8)
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
    cb.addNative(0'u8)
}

// Decode a 2x2 32-bit BGRA8 BMP (standard DIB header, no row padding).
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 70'u32     // 14+40+16
    fh.bfOffBits = 54'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40'u32
    bh.biWidth     = 2
    bh.biHeight    = 2
    bh.biPlanes    = 1'u16
    bh.biBitCount  = 32'u16
    bh.biSizeImage = 16'u32
    cb.addStruct(bh)

    // 2x2 BGRA - 4 bytes per pixel, no padding needed
    cb.addNative(10'u8)
    cb.addNative(20'u8)
    cb.addNative(30'u8)
    cb.addNative(255'u8)
    cb.addNative(40'u8)
    cb.addNative(50'u8)
    cb.addNative(60'u8)
    cb.addNative(200'u8)
    cb.addNative(70'u8)
    cb.addNative(80'u8)
    cb.addNative(90'u8)
    cb.addNative(128'u8)
    cb.addNative(100'u8)
    cb.addNative(110'u8)
    cb.addNative(120'u8)
    cb.addNative(64'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.width == 2)
    Swag.assert(img.height == 2)
    Swag.assert(img.pixelFormat == .BGRA8)
    Swag.assert(img.bitsPerPixel == 32)
    Swag.assert(img.bytesPerPixel == 4)
    Swag.assert(img.pixels.count == 16)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 10'u8)
    Swag.assert(img.pixels.buffer[1] == 20'u8)
    Swag.assert(img.pixels.buffer[2] == 30'u8)
    Swag.assert(img.pixels.buffer[3] == 255'u8)
}

// Decode a 5x5 24-bit BGR8 BMP where each row has 1 byte of alignment padding on disk.
// Row stride on disk = 16 bytes (15 pixel bytes + 1 pad); decoded image has 75 bytes (no padding).
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 134'u32     // 14+40+80
    fh.bfOffBits = 54'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40'u32
    bh.biWidth     = 5
    bh.biHeight    = 5
    bh.biPlanes    = 1'u16
    bh.biBitCount  = 24'u16
    bh.biSizeImage = 80'u32
    cb.addStruct(bh)

    // Row 0: pixel(0,0)=B100 G150 R200, pixels 1-4 zero, 1 pad byte
    cb.addNative(100'u8)
    cb.addNative(150'u8)
    cb.addNative(200'u8)
    for 12 do
        cb.addNative(0'u8)     // pixels 1-4
    cb.addNative(0'u8)     // pad
    // Rows 1-4 all zeros (4 rows x 16 bytes)
    for 64 do
        cb.addNative(0'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.width == 5)
    Swag.assert(img.height == 5)
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.bitsPerPixel == 24)
    Swag.assert(img.pixels.count == 75)     // 5x5x3 = 75, no padding in decoded result
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 100'u8)
    Swag.assert(img.pixels.buffer[1] == 150'u8)
    Swag.assert(img.pixels.buffer[2] == 200'u8)
}

// Decode a 2x2 24-bit BMP written with the legacy 12-byte BITMAPCOREHEADER.
// The decoder converts CoreHeader fields and uses bfOffBits to find pixel data.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 42'u32     // 14+12+16
    fh.bfOffBits = 26'u32     // 14+12
    cb.addStruct(fh)

    var ch: BmpCH
    ch.bcSize     = 12'u32
    ch.bcWidth    = 2'u16
    ch.bcHeight   = 2'u16
    ch.bcPlanes   = 1'u16
    ch.bcBitCount = 24'u16
    cb.addStruct(ch)

    // 2x2 BGR8: row stride = 8 bytes (6 pixel bytes + 2 pad)
    cb.addNative(10'u8)
    cb.addNative(20'u8)
    cb.addNative(30'u8)     // row0 pix0
    cb.addNative(40'u8)
    cb.addNative(50'u8)
    cb.addNative(60'u8)     // row0 pix1
    cb.addNative(0'u8)
    cb.addNative(0'u8)     // row0 pad
    cb.addNative(70'u8)
    cb.addNative(80'u8)
    cb.addNative(90'u8)     // row1 pix0
    cb.addNative(100'u8)
    cb.addNative(110'u8)
    cb.addNative(120'u8)     // row1 pix1
    cb.addNative(0'u8)
    cb.addNative(0'u8)     // row1 pad

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.width == 2)
    Swag.assert(img.height == 2)
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.pixels.count == 12)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 10'u8)
    Swag.assert(img.pixels.buffer[1] == 20'u8)
    Swag.assert(img.pixels.buffer[2] == 30'u8)
}

// Decode a 2x2 24-bit BMP with biCompression=BI_BITFIELDS (value 3).
// The decoder accepts BI_BITFIELDS and treats pixel data identically to BI_RGB.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 70'u32     // 14+40+16
    fh.bfOffBits = 54'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40'u32
    bh.biWidth       = 2
    bh.biHeight      = 2
    bh.biPlanes      = 1'u16
    bh.biBitCount    = 24'u16
    bh.biCompression = Bmp.BI_BITFIELDS
    bh.biSizeImage   = 16'u32
    cb.addStruct(bh)

    cb.addNative(55'u8)
    cb.addNative(66'u8)
    cb.addNative(77'u8)     // row0 pix0
    cb.addNative(88'u8)
    cb.addNative(99'u8)
    cb.addNative(110'u8)     // row0 pix1
    cb.addNative(0'u8)
    cb.addNative(0'u8)     // row0 pad
    cb.addNative(11'u8)
    cb.addNative(22'u8)
    cb.addNative(33'u8)     // row1 pix0
    cb.addNative(44'u8)
    cb.addNative(55'u8)
    cb.addNative(66'u8)     // row1 pix1
    cb.addNative(0'u8)
    cb.addNative(0'u8)     // row1 pad

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.width == 2)
    Swag.assert(img.height == 2)
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 55'u8)
    Swag.assert(img.pixels.buffer[1] == 66'u8)
    Swag.assert(img.pixels.buffer[2] == 77'u8)
}

// Decode a top-down 2x2 24-bit BMP. The decoder stores pixels in the
// same bottom-up buffer convention as regular BMP files.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 70'u32
    fh.bfOffBits = 54'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40'u32
    bh.biWidth     = 2
    bh.biHeight    = -2
    bh.biPlanes    = 1'u16
    bh.biBitCount  = 24'u16
    bh.biSizeImage = 16'u32
    cb.addStruct(bh)

    cb.addNative(1'u8)
    cb.addNative(2'u8)
    cb.addNative(3'u8)
    cb.addNative(4'u8)
    cb.addNative(5'u8)
    cb.addNative(6'u8)
    cb.addNative(0'u8)
    cb.addNative(0'u8)
    cb.addNative(7'u8)
    cb.addNative(8'u8)
    cb.addNative(9'u8)
    cb.addNative(10'u8)
    cb.addNative(11'u8)
    cb.addNative(12'u8)
    cb.addNative(0'u8)
    cb.addNative(0'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.width == 2)
    Swag.assert(img.height == 2)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 7'u8)
    Swag.assert(img.pixels.buffer[1] == 8'u8)
    Swag.assert(img.pixels.buffer[2] == 9'u8)
    Swag.assert(img.pixels.buffer[6] == 1'u8)
    Swag.assert(img.pixels.buffer[7] == 2'u8)
    Swag.assert(img.pixels.buffer[8] == 3'u8)
}

// Decode an 8-bit indexed BMP through its palette.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 74'u32
    fh.bfOffBits = 70'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40'u32
    bh.biWidth     = 4
    bh.biHeight    = 1
    bh.biPlanes    = 1'u16
    bh.biBitCount  = 8'u16
    bh.biClrUsed   = 4'u32
    bh.biSizeImage = 4'u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 10, 20, 30)
    addBmpPaletteColor(&cb, 40, 50, 60)
    addBmpPaletteColor(&cb, 70, 80, 90)
    cb.addNative(0'u8)
    cb.addNative(1'u8)
    cb.addNative(2'u8)
    cb.addNative(3'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[3] == 10'u8)
    Swag.assert(img.pixels.buffer[4] == 20'u8)
    Swag.assert(img.pixels.buffer[5] == 30'u8)
    Swag.assert(img.pixels.buffer[9] == 70'u8)
    Swag.assert(img.pixels.buffer[10] == 80'u8)
    Swag.assert(img.pixels.buffer[11] == 90'u8)
}

// Decode packed 1-bit indexed BMP rows.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 66'u32
    fh.bfOffBits = 62'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40'u32
    bh.biWidth     = 8
    bh.biHeight    = 1
    bh.biPlanes    = 1'u16
    bh.biBitCount  = 1'u16
    bh.biClrUsed   = 2'u32
    bh.biSizeImage = 4'u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 9, 8, 7)
    cb.addNative(0b10100000'u8)
    cb.addNative(0'u8)
    cb.addNative(0'u8)
    cb.addNative(0'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 9'u8)
    Swag.assert(img.pixels.buffer[1] == 8'u8)
    Swag.assert(img.pixels.buffer[2] == 7'u8)
    Swag.assert(img.pixels.buffer[3] == 0'u8)
    Swag.assert(img.pixels.buffer[6] == 9'u8)
}

// Decode packed 4-bit indexed BMP rows.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 70'u32
    fh.bfOffBits = 66'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40'u32
    bh.biWidth     = 4
    bh.biHeight    = 1
    bh.biPlanes    = 1'u16
    bh.biBitCount  = 4'u16
    bh.biClrUsed   = 3'u32
    bh.biSizeImage = 4'u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 11, 12, 13)
    addBmpPaletteColor(&cb, 21, 22, 23)
    cb.addNative(0x12'u8)
    cb.addNative(0x10'u8)
    cb.addNative(0'u8)
    cb.addNative(0'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 11'u8)
    Swag.assert(img.pixels.buffer[1] == 12'u8)
    Swag.assert(img.pixels.buffer[2] == 13'u8)
    Swag.assert(img.pixels.buffer[3] == 21'u8)
    Swag.assert(img.pixels.buffer[4] == 22'u8)
    Swag.assert(img.pixels.buffer[5] == 23'u8)
}

// Decode 16-bit BI_RGB pixels using the default 5-5-5 masks.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 58'u32
    fh.bfOffBits = 54'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize      = 40'u32
    bh.biWidth     = 2
    bh.biHeight    = 1
    bh.biPlanes    = 1'u16
    bh.biBitCount  = 16'u16
    bh.biSizeImage = 4'u32
    cb.addStruct(bh)
    cb.addNative(0x7C00'u16)
    cb.addNative(0x03E0'u16)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 0'u8)
    Swag.assert(img.pixels.buffer[1] == 0'u8)
    Swag.assert(img.pixels.buffer[2] == 255'u8)
    Swag.assert(img.pixels.buffer[3] == 0'u8)
    Swag.assert(img.pixels.buffer[4] == 255'u8)
    Swag.assert(img.pixels.buffer[5] == 0'u8)
}

// Decode 16-bit BI_BITFIELDS pixels using explicit 5-6-5 masks.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 70'u32
    fh.bfOffBits = 66'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40'u32
    bh.biWidth       = 2
    bh.biHeight      = 1
    bh.biPlanes      = 1'u16
    bh.biBitCount    = 16'u16
    bh.biCompression = Bmp.BI_BITFIELDS
    bh.biSizeImage   = 4'u32
    cb.addStruct(bh)
    cb.addNative(0xF800'u32)
    cb.addNative(0x07E0'u32)
    cb.addNative(0x001F'u32)
    cb.addNative(0x001F'u16)
    cb.addNative(0x07E0'u16)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 255'u8)
    Swag.assert(img.pixels.buffer[1] == 0'u8)
    Swag.assert(img.pixels.buffer[2] == 0'u8)
    Swag.assert(img.pixels.buffer[3] == 0'u8)
    Swag.assert(img.pixels.buffer[4] == 255'u8)
    Swag.assert(img.pixels.buffer[5] == 0'u8)
}

// Decode BI_RLE8 indexed data.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 82'u32
    fh.bfOffBits = 70'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40'u32
    bh.biWidth       = 4
    bh.biHeight      = 2
    bh.biPlanes      = 1'u16
    bh.biBitCount    = 8'u16
    bh.biCompression = Bmp.BI_RLE8
    bh.biClrUsed     = 4'u32
    bh.biSizeImage   = 12'u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 10, 0, 0)
    addBmpPaletteColor(&cb, 0, 20, 0)
    addBmpPaletteColor(&cb, 0, 0, 30)
    cb.addNative(4'u8)
    cb.addNative(1'u8)
    cb.addNative(0'u8)
    cb.addNative(0'u8)
    cb.addNative(0'u8)
    cb.addNative(4'u8)
    cb.addNative(2'u8)
    cb.addNative(3'u8)
    cb.addNative(0'u8)
    cb.addNative(1'u8)
    cb.addNative(0'u8)
    cb.addNative(1'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 10'u8)
    Swag.assert(img.pixels.buffer[12] == 0'u8)
    Swag.assert(img.pixels.buffer[13] == 20'u8)
    Swag.assert(img.pixels.buffer[15] == 0'u8)
    Swag.assert(img.pixels.buffer[16] == 0'u8)
    Swag.assert(img.pixels.buffer[17] == 30'u8)
}

// Decode BI_RLE4 indexed data.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 74'u32
    fh.bfOffBits = 70'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40'u32
    bh.biWidth       = 4
    bh.biHeight      = 1
    bh.biPlanes      = 1'u16
    bh.biBitCount    = 4'u16
    bh.biCompression = Bmp.BI_RLE4
    bh.biClrUsed     = 4'u32
    bh.biSizeImage   = 4'u32
    cb.addStruct(bh)
    addBmpPaletteColor(&cb, 0, 0, 0)
    addBmpPaletteColor(&cb, 11, 12, 13)
    addBmpPaletteColor(&cb, 21, 22, 23)
    addBmpPaletteColor(&cb, 31, 32, 33)
    cb.addNative(4'u8)
    cb.addNative(0x12'u8)
    cb.addNative(0'u8)
    cb.addNative(1'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 11'u8)
    Swag.assert(img.pixels.buffer[1] == 12'u8)
    Swag.assert(img.pixels.buffer[2] == 13'u8)
    Swag.assert(img.pixels.buffer[3] == 21'u8)
    Swag.assert(img.pixels.buffer[4] == 22'u8)
    Swag.assert(img.pixels.buffer[5] == 23'u8)
}

// Decode with decodePixels=false: metadata fields are populated but no pixel buffer is allocated.
#test
{
    let path  = getTestDataPath("test.bmp")
    let bytes = expect File.readAllBytes(path)
    var opts: DecodeOptions
    opts.decodePixels = false

    let img = expect Image.decode(path, bytes.toSlice(), opts)
    Swag.assert(img.width == 4)
    Swag.assert(img.height == 4)
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(!img.isValid())
}

// Error: indexed BMP with no palette must fail.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 58'u32
    fh.bfOffBits = 54'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize     = 40'u32
    bh.biWidth    = 2
    bh.biHeight   = 1
    bh.biPlanes   = 1'u16
    bh.biBitCount = 8'u16
    cb.addStruct(bh)
    for 4 do
        cb.addNative(0'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    var img: Image
    img = catch Image.load(path.toString()) as err34
    Swag.assert(err34 != null)
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
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 18'u32
    fh.bfOffBits = 54'u32
    cb.addStruct(fh)
    cb.addNative(40'u32)     // biSize only - rest of DIB header missing

    discard expect File.writeAllBytes(path.toString(), cb)
    var img: Image
    img = catch Image.load(path.toString()) as err36
    Swag.assert(err36 != null)
}

// Error: unknown compression value (not BI_RGB, BI_RLE8, BI_RLE4, or BI_BITFIELDS) must fail.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 58'u32
    fh.bfOffBits = 54'u32
    cb.addStruct(fh)

    var bh: Bmp.Header
    bh.biSize        = 40'u32
    bh.biWidth       = 2
    bh.biHeight      = 1
    bh.biPlanes      = 1'u16
    bh.biBitCount    = 24'u16
    bh.biCompression = 4'u32     // value 4 is not a recognised compression type
    cb.addStruct(bh)
    for 4 do
        cb.addNative(0'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    var img: Image
    img = catch Image.load(path.toString()) as err38
    Swag.assert(err38 != null)
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
        for i in src.pixels.count do
            src.pixels.buffer![i] = cast(u8) ((i * 37 + 19) & 0xFF)

        var cb       = expect src.encode("memory.bmp")
        let rowBytes = cast(u64) Width * src.bytesPerPixel
        let stride   = Bmp.rowStride(Width, src.bitsPerPixel)
        Swag.assert(cb.count() == #sizeof(BmpFH) + #sizeof(Bmp.Header) + stride * Height)
        cb.makeLinear()
        let bytes = nnBytes(cb.toSlice())
        if pixelFormat == .RGB8
        {
            for y in Height
            {
                for offset in rowBytes until stride do
                    Swag.assert(bytes[#sizeof(BmpFH) + #sizeof(Bmp.Header) + cast(u64) y * stride + offset] == 0)
            }
        }

        let img           = expect Image.decode("memory.bmp", bytes, {})
        let bytesPerPixel = cast(u64) src.bytesPerPixel
        Swag.assert(img.pixelFormat == (bytesPerPixel == 3 ? .BGR8 : .BGRA8))
        for pixel in cast(u64) Width * Height
        {
            let offset = pixel * bytesPerPixel
            Swag.assert(img.pixels.buffer![offset] == src.pixels.buffer![offset + 2])
            Swag.assert(img.pixels.buffer![offset + 1] == src.pixels.buffer![offset + 1])
            Swag.assert(img.pixels.buffer![offset + 2] == src.pixels.buffer![offset])
            if bytesPerPixel == 4 do
                Swag.assert(img.pixels.buffer![offset + 3] == src.pixels.buffer![offset + 3])
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
    Swag.assert(img.width == 4)
    Swag.assert(img.height == 4)
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.bitsPerPixel == 24)
    Swag.assert(img.bytesPerPixel == 3)
    Swag.assert(img.pixels.count == 48)
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
    Swag.assert(img.width == 5)
    Swag.assert(img.height == 5)
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.pixels.count == 75)
}

// Encode BGR8: pixel byte values survive the encode/decode round-trip unchanged.
// The encoder copies raw BGR bytes when stride is already 4-byte aligned.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(4, 4, .BGR8)
    src.clear()
    let srcBuf = src.pixels.buffer!
    srcBuf[0]  = 200'u8     // pixel(0,0) B
    srcBuf[1]  = 128'u8     //             G
    srcBuf[2]  = 64'u8      //             R
    srcBuf[45] = 33'u8      // last row, pixel 3, B channel

    let cb = expect src.encode("memory.bmp")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 200'u8)
    Swag.assert(img.pixels.buffer[1] == 128'u8)
    Swag.assert(img.pixels.buffer[2] == 64'u8)
    Swag.assert(img.pixels.buffer[45] == 33'u8)
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
    Swag.assert(img.width == 2)
    Swag.assert(img.height == 2)
    Swag.assert(img.pixelFormat == .BGRA8)
    Swag.assert(img.bitsPerPixel == 32)
    Swag.assert(img.bytesPerPixel == 4)
    Swag.assert(img.pixels.count == 16)
}

// Encode BGRA8: pixel byte values survive the encode/decode round-trip unchanged.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(2, 2, .BGRA8)
    src.clear()
    let srcBuf = src.pixels.buffer!
    srcBuf[0] = 10'u8      // pixel(0,0) B
    srcBuf[1] = 20'u8      //             G
    srcBuf[2] = 30'u8      //             R
    srcBuf[3] = 200'u8     //             A
    srcBuf[4] = 50'u8      // pixel(1,0) B
    srcBuf[7] = 128'u8     // pixel(1,0) A

    let cb = expect src.encode("memory.bmp")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 10'u8)
    Swag.assert(img.pixels.buffer[1] == 20'u8)
    Swag.assert(img.pixels.buffer[2] == 30'u8)
    Swag.assert(img.pixels.buffer[3] == 200'u8)
    Swag.assert(img.pixels.buffer[4] == 50'u8)
    Swag.assert(img.pixels.buffer[7] == 128'u8)
}

// Encode an RGB8 4x4 image: encoder swaps R/B to write BGR bytes into the BMP file,
// so the loaded image is BGR8 with channels in reversed order relative to the source.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(4, 4, .RGB8)
    src.clear()
    let srcBuf = src.pixels.buffer!
    srcBuf[0] = 100'u8     // pixel(0,0) R
    srcBuf[1] = 150'u8     //             G
    srcBuf[2] = 200'u8     //             B

    let cb = expect src.encode("memory.bmp")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.width == 4)
    Swag.assert(img.height == 4)
    Swag.assert(img.pixelFormat == .BGR8)     // RGB8 saved as 24-bit BGR, loads as BGR8
    // Encoder writes [B=200, G=150, R=100]; decoder stores as BGR8 bytes verbatim
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 200'u8)     // B
    Swag.assert(img.pixels.buffer[1] == 150'u8)     // G
    Swag.assert(img.pixels.buffer[2] == 100'u8)     // R
}

// Encode an RGBA8 2x2 image: encoder swaps R/B to write BGRA bytes,
// so the loaded image is BGRA8 with channels in reversed R/B order relative to the source.
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(2, 2, .RGBA8)
    src.clear()
    let srcBuf = src.pixels.buffer!
    srcBuf[0] = 10'u8      // pixel(0,0) R
    srcBuf[1] = 20'u8      //             G
    srcBuf[2] = 30'u8      //             B
    srcBuf[3] = 255'u8     //             A

    let cb = expect src.encode("memory.bmp")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.width == 2)
    Swag.assert(img.height == 2)
    Swag.assert(img.pixelFormat == .BGRA8)     // RGBA8 saved as 32-bit BGRA, loads as BGRA8
    // Encoder writes [B=30, G=20, R=10, A=255]; decoder stores as BGRA8 bytes verbatim
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 30'u8)      // B
    Swag.assert(img.pixels.buffer[1] == 20'u8)      // G
    Swag.assert(img.pixels.buffer[2] == 10'u8)      // R
    Swag.assert(img.pixels.buffer[3] == 255'u8)     // A
}

// Encode BGR8 5x5 with row padding: pixel values survive despite the on-disk stride difference.
// Verifies encoder pads correctly and decoder strips the padding (file = 134 bytes, decoded = 75 bytes).
#test
{
    let path = makeTempBmpPath()
    defer discard catch File.delete(path.toString())
    var src = Image.create(5, 5, .BGR8)
    src.clear()
    let srcBuf = src.pixels.buffer!
    srcBuf[0]  = 77'u8     // pixel(0,0) B
    srcBuf[1]  = 88'u8     //             G
    srcBuf[2]  = 99'u8     //             R
    srcBuf[72] = 42'u8     // row4 pixel(0) B

    let cb = expect src.encode("memory.bmp")

    // File must contain alignment padding: 5 rows x 16 bytes = 80 bytes pixel data
    Swag.assert(cb.count() == 134)     // 14+40+80
    cb.makeLinear()
    let bytes = nnBytes(cb.toSlice())
    Swag.assert(bytes != null)
    let fh = cast(const *BmpFH) bytes.buffer
    let bh = cast(const *Bmp.Header) (bytes.buffer + #sizeof(BmpFH))
    Swag.assert(fh.bfSize == cast(u32) cb.count())
    Swag.assert(fh.bfOffBits == 54'u32)
    Swag.assert(bh.biSizeImage == 80'u32)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.count == 75)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 77'u8)
    Swag.assert(img.pixels.buffer[1] == 88'u8)
    Swag.assert(img.pixels.buffer[2] == 99'u8)
    Swag.assert(img.pixels.buffer[72] == 42'u8)
}
