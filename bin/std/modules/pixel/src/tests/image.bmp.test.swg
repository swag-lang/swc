#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

// Create an image in memory and verify its metadata.
#test
{
    let img = Image.create(4, 4, .BGR8)
    @assert(img.isValid())
    @assert(img.width == 4)
    @assert(img.height == 4)
    @assert(img.pf == .BGR8)
    @assert(img.bpp == 24)
    @assert(img.bpp8 == 3)
    @assert(img.pixels.count == 48)
}

// Verify getTestDataPath resolves the file path correctly.
#test
{
    let path = getTestDataPath("test.bmp")
    @assert(@countof(path) > 0)
    @assert(File.exists(path))
}

// Read the BMP bytes from disk without decoding.
#test
{
    let path  = getTestDataPath("test.bmp")
    let bytes = catch File.readAllBytes(path)
    @assert(@err == null)
    @assert(bytes.count == 102)
}

// Verify that the decoder registry is functional and finds the BMP decoder.
#test
{
    @assert(Image.canLoad("test.bmp"))
    @assert(!Image.canLoad("test.xyz"))
}

// Decode a BMP from pre-loaded bytes using Image.decode (same internal path as Image.load).
#test
{
    let path  = getTestDataPath("test.bmp")
    let bytes = catch File.readAllBytes(path)
    @assert(@err == null)
    var img: Image
    img = catch Image.decode(path, bytes.toSlice(), {})
    @assert(@err == null)
    @assert(img.isValid())
    @assert(img.width == 4)
    @assert(img.height == 4)
    @assert(img.pf == .BGR8)
}

// Load a 4x4 24-bit BMP from disk and verify image metadata.
#test
{
    let path = getTestDataPath("test.bmp")
    var img: Image
    img = catch Image.load(path)
    @assert(@err == null)
    @assert(img.isValid())
    @assert(img.width == 4)
    @assert(img.height == 4)
    @assert(img.pf == .BGR8)
    @assert(img.bpp == 24)
    @assert(img.bpp8 == 3)
    @assert(img.pixels.count == 48)
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

func bmpCanEncode(fileName: string)->bool
{
    var enc: Bmp.Encoder
    let itf = @mkinterface(&enc, #typeof(Bmp.Encoder), IImageEncoder)
    return itf.canEncode(fileName)
}

func encodeBmp(result: *ConcatBuffer, image: Image) throw
{
    var enc: Bmp.Encoder
    let itf = @mkinterface(&enc, #typeof(Bmp.Encoder), IImageEncoder)
    itf.encode(result, image, null)
}

// Decode a 2x2 32-bit BGRA8 BMP (standard DIB header, no row padding).
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

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
    cb.addNative(10'u8);  cb.addNative(20'u8);  cb.addNative(30'u8);  cb.addNative(255'u8)
    cb.addNative(40'u8);  cb.addNative(50'u8);  cb.addNative(60'u8);  cb.addNative(200'u8)
    cb.addNative(70'u8);  cb.addNative(80'u8);  cb.addNative(90'u8);  cb.addNative(128'u8)
    cb.addNative(100'u8); cb.addNative(110'u8); cb.addNative(120'u8); cb.addNative(64'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width  == 2)
    @assert(img.height == 2)
    @assert(img.pf     == .BGRA8)
    @assert(img.bpp    == 32)
    @assert(img.bpp8   == 4)
    @assert(img.pixels.count == 16)
    @assert(img.pixels.buffer[0]  == 10'u8)
    @assert(img.pixels.buffer[1]  == 20'u8)
    @assert(img.pixels.buffer[2]  == 30'u8)
    @assert(img.pixels.buffer[3]  == 255'u8)
}

// Decode a 5x5 24-bit BGR8 BMP where each row has 1 byte of alignment padding on disk.
// Row stride on disk = 16 bytes (15 pixel bytes + 1 pad); decoded image has 75 bytes (no padding).
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 134'u32    // 14+40+80
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
    cb.addNative(100'u8); cb.addNative(150'u8); cb.addNative(200'u8)
    for 12 do cb.addNative(0'u8)    // pixels 1-4
    cb.addNative(0'u8)               // pad
    // Rows 1-4 all zeros (4 rows x 16 bytes)
    for 64 do cb.addNative(0'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width  == 5)
    @assert(img.height == 5)
    @assert(img.pf     == .BGR8)
    @assert(img.bpp    == 24)
    @assert(img.pixels.count == 75)   // 5x5x3 = 75, no padding in decoded result
    @assert(img.pixels.buffer[0] == 100'u8)
    @assert(img.pixels.buffer[1] == 150'u8)
    @assert(img.pixels.buffer[2] == 200'u8)
}

// Decode a 2x2 24-bit BMP written with the legacy 12-byte BITMAPCOREHEADER.
// The decoder converts CoreHeader fields and uses bfOffBits to find pixel data.
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

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
    cb.addNative(10'u8);  cb.addNative(20'u8);  cb.addNative(30'u8)    // row0 pix0
    cb.addNative(40'u8);  cb.addNative(50'u8);  cb.addNative(60'u8)    // row0 pix1
    cb.addNative(0'u8);   cb.addNative(0'u8)                            // row0 pad
    cb.addNative(70'u8);  cb.addNative(80'u8);  cb.addNative(90'u8)    // row1 pix0
    cb.addNative(100'u8); cb.addNative(110'u8); cb.addNative(120'u8)   // row1 pix1
    cb.addNative(0'u8);   cb.addNative(0'u8)                            // row1 pad

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width  == 2)
    @assert(img.height == 2)
    @assert(img.pf     == .BGR8)
    @assert(img.pixels.count == 12)
    @assert(img.pixels.buffer[0] == 10'u8)
    @assert(img.pixels.buffer[1] == 20'u8)
    @assert(img.pixels.buffer[2] == 30'u8)
}

// Decode a 2x2 24-bit BMP with biCompression=BI_BITFIELDS (value 3).
// The decoder accepts BI_BITFIELDS and treats pixel data identically to BI_RGB.
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

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

    cb.addNative(55'u8); cb.addNative(66'u8); cb.addNative(77'u8)    // row0 pix0
    cb.addNative(88'u8); cb.addNative(99'u8); cb.addNative(110'u8)   // row0 pix1
    cb.addNative(0'u8);  cb.addNative(0'u8)                           // row0 pad
    cb.addNative(11'u8); cb.addNative(22'u8); cb.addNative(33'u8)    // row1 pix0
    cb.addNative(44'u8); cb.addNative(55'u8); cb.addNative(66'u8)    // row1 pix1
    cb.addNative(0'u8);  cb.addNative(0'u8)                           // row1 pad

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width  == 2)
    @assert(img.height == 2)
    @assert(img.pf     == .BGR8)
    @assert(img.pixels.buffer[0] == 55'u8)
    @assert(img.pixels.buffer[1] == 66'u8)
    @assert(img.pixels.buffer[2] == 77'u8)
}

// Decode with decodePixels=false: metadata fields are populated but no pixel buffer is allocated.
#test
{
    let path  = getTestDataPath("test.bmp")
    let bytes = catch File.readAllBytes(path)
    @assert(@err == null)

    var opts: DecodeOptions
    opts.decodePixels = false

    var img: Image
    img = catch Image.decode(path, bytes.toSlice(), opts)
    @assert(@err == null)
    @assert(img.width  == 4)
    @assert(img.height == 4)
    @assert(img.pf     == .BGR8)
    @assert(!img.isValid())
}

// Error: BMP with unsupported bit depth (8 bpp) must throw.
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

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
    bh.biBitCount = 8'u16   // unsupported
    cb.addStruct(bh)
    for 4 do cb.addNative(0'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err != null)
}

// Error: buffer too small to hold the full DIB header must throw.
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

    // FileHeader (14 bytes) + only 4 bytes of DIB header (biSize = 40, non-CoreHeader path).
    // The decoder will see size=40 != 12 and then check dataof+sizeof(Header) > last, then throw.
    var cb: ConcatBuffer
    var fh: BmpFH
    fh.bfType    = 0x4D42'u16
    fh.bfSize    = 18'u32
    fh.bfOffBits = 54'u32
    cb.addStruct(fh)
    cb.addNative(40'u32)   // biSize only - rest of DIB header missing

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err != null)
}

// Error: unknown compression value (not BI_RGB, BI_RLE8, BI_RLE4, or BI_BITFIELDS) must throw.
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

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
    bh.biCompression = 4'u32   // value 4 is not a recognised compression type
    cb.addStruct(bh)
    for 4 do cb.addNative(0'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err != null)
}

// Encode / roundtrip tests.

// The encoder is called directly (not through Image.save) to test BMP encoding
// logic independently of the encoder registry.

// Bmp.Encoder.canEncode recognises .bmp and rejects other extensions.
#test
{
    @assert(bmpCanEncode("output.bmp"))
    @assert(!bmpCanEncode("output.xyz"))
}

// Encode a BGR8 4x4 image (row stride 12 bytes - already 4-byte aligned, no padding needed).
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(4, 4, .BGR8)
    src.clear()

    var cb: ConcatBuffer
    catch encodeBmp(&cb, src)
    @assert(@err == null)
    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width        == 4)
    @assert(img.height       == 4)
    @assert(img.pf           == .BGR8)
    @assert(img.bpp          == 24)
    @assert(img.bpp8         == 3)
    @assert(img.pixels.count == 48)
}

// Encode a BGR8 5x5 image (row stride 15 bytes - encoder pads to 16, decoder strips padding).
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(5, 5, .BGR8)
    src.clear()

    var cb: ConcatBuffer
    catch encodeBmp(&cb, src)
    @assert(@err == null)
    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width        == 5)
    @assert(img.height       == 5)
    @assert(img.pf           == .BGR8)
    @assert(img.pixels.count == 75)
}

// Encode BGR8: pixel byte values survive the encode/decode round-trip unchanged.
// The encoder copies raw BGR bytes when stride is already 4-byte aligned.
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(4, 4, .BGR8)
    src.clear()
    src.pixels.buffer[0]  = 200'u8   // pixel(0,0) B
    src.pixels.buffer[1]  = 128'u8   //             G
    src.pixels.buffer[2]  = 64'u8    //             R
    src.pixels.buffer[45] = 33'u8    // last row, pixel 3, B channel

    var cb: ConcatBuffer
    catch encodeBmp(&cb, src)
    @assert(@err == null)
    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pixels.buffer[0]  == 200'u8)
    @assert(img.pixels.buffer[1]  == 128'u8)
    @assert(img.pixels.buffer[2]  == 64'u8)
    @assert(img.pixels.buffer[45] == 33'u8)
}

// Encode a BGRA8 2x2 image: raw 32-bit bytes are copied directly by the encoder.
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(2, 2, .BGRA8)
    src.clear()

    var cb: ConcatBuffer
    catch encodeBmp(&cb, src)
    @assert(@err == null)
    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width        == 2)
    @assert(img.height       == 2)
    @assert(img.pf           == .BGRA8)
    @assert(img.bpp          == 32)
    @assert(img.bpp8         == 4)
    @assert(img.pixels.count == 16)
}

// Encode BGRA8: pixel byte values survive the encode/decode round-trip unchanged.
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(2, 2, .BGRA8)
    src.clear()
    src.pixels.buffer[0]  = 10'u8    // pixel(0,0) B
    src.pixels.buffer[1]  = 20'u8    //             G
    src.pixels.buffer[2]  = 30'u8    //             R
    src.pixels.buffer[3]  = 200'u8   //             A
    src.pixels.buffer[4]  = 50'u8    // pixel(1,0) B
    src.pixels.buffer[7]  = 128'u8   // pixel(1,0) A

    var cb: ConcatBuffer
    catch encodeBmp(&cb, src)
    @assert(@err == null)
    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pixels.buffer[0]  == 10'u8)
    @assert(img.pixels.buffer[1]  == 20'u8)
    @assert(img.pixels.buffer[2]  == 30'u8)
    @assert(img.pixels.buffer[3]  == 200'u8)
    @assert(img.pixels.buffer[4]  == 50'u8)
    @assert(img.pixels.buffer[7]  == 128'u8)
}

// Encode an RGB8 4x4 image: encoder swaps R/B to write BGR bytes into the BMP file,
// so the loaded image is BGR8 with channels in reversed order relative to the source.
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(4, 4, .RGB8)
    src.clear()
    src.pixels.buffer[0] = 100'u8   // pixel(0,0) R
    src.pixels.buffer[1] = 150'u8   //             G
    src.pixels.buffer[2] = 200'u8   //             B

    var cb: ConcatBuffer
    catch encodeBmp(&cb, src)
    @assert(@err == null)
    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width  == 4)
    @assert(img.height == 4)
    @assert(img.pf     == .BGR8)     // RGB8 saved as 24-bit BGR, loads as BGR8
    // Encoder writes [B=200, G=150, R=100]; decoder stores as BGR8 bytes verbatim
    @assert(img.pixels.buffer[0] == 200'u8)  // B
    @assert(img.pixels.buffer[1] == 150'u8)  // G
    @assert(img.pixels.buffer[2] == 100'u8)  // R
}

// Encode an RGBA8 2x2 image: encoder swaps R/B to write BGRA bytes,
// so the loaded image is BGRA8 with channels in reversed R/B order relative to the source.
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(2, 2, .RGBA8)
    src.clear()
    src.pixels.buffer[0] = 10'u8    // pixel(0,0) R
    src.pixels.buffer[1] = 20'u8    //             G
    src.pixels.buffer[2] = 30'u8    //             B
    src.pixels.buffer[3] = 255'u8   //             A

    var cb: ConcatBuffer
    catch encodeBmp(&cb, src)
    @assert(@err == null)
    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width  == 2)
    @assert(img.height == 2)
    @assert(img.pf     == .BGRA8)   // RGBA8 saved as 32-bit BGRA, loads as BGRA8
    // Encoder writes [B=30, G=20, R=10, A=255]; decoder stores as BGRA8 bytes verbatim
    @assert(img.pixels.buffer[0] == 30'u8)    // B
    @assert(img.pixels.buffer[1] == 20'u8)    // G
    @assert(img.pixels.buffer[2] == 10'u8)    // R
    @assert(img.pixels.buffer[3] == 255'u8)   // A
}

// Encode BGR8 5x5 with row padding: pixel values survive despite the on-disk stride difference.
// Verifies encoder pads correctly and decoder strips the padding (file = 134 bytes, decoded = 75 bytes).
#test
{
    let path = makeTempBmpPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(5, 5, .BGR8)
    src.clear()
    src.pixels.buffer[0]  = 77'u8   // pixel(0,0) B
    src.pixels.buffer[1]  = 88'u8   //             G
    src.pixels.buffer[2]  = 99'u8   //             R
    src.pixels.buffer[72] = 42'u8   // row4 pixel(0) B

    var cb: ConcatBuffer
    catch encodeBmp(&cb, src)
    @assert(@err == null)

    // File must contain alignment padding: 5 rows x 16 bytes = 80 bytes pixel data
    @assert(@countof(cb) == 134)    // 14+40+80

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pixels.count     == 75)
    @assert(img.pixels.buffer[0]  == 77'u8)
    @assert(img.pixels.buffer[1]  == 88'u8)
    @assert(img.pixels.buffer[2]  == 99'u8)
    @assert(img.pixels.buffer[72] == 42'u8)
}
