#global #if #command == Swag.CompilerCommand.Test
#global #[Swag.ExplicitNullability]
using Swag, Core

// Test-only mirrors of the private ICO on-disk structures.

#[Swag.Pack(1)]
struct IcoDir
{
    reserved:     u16
    type:         u16
    count:        u16
}

#[Swag.Pack(1)]
struct IcoEntry
{
    width:        u8
    height:       u8
    colorCount:   u8
    reserved:     u8
    planes:       u16
    bitCount:     u16
    bytesInRes:   u32
    imageOffset:  u32
}

#[Swag.Pack(1)]
struct IcoDib
{
    size:           u32
    width:          s32
    height:         s32
    planes:         u16
    bitCount:       u16
    compression:    u32
    sizeImage:      u32
    xPelsPerMeter:  s32
    yPelsPerMeter:  s32
    clrUsed:        u32
    clrImportant:   u32
}

// Build a single-image ICO from a DIB body (palette + XOR + AND, no BITMAPINFOHEADER).
func buildIco(width, height: s32, bitCount: u16, clrUsed: u32, dibBody: #nonull const [..] u8)->Array'u8
{
    var cb: ConcatBuffer
    let bodyLen = cast(u32) @countof(dibBody)

    var dir: IcoDir
    dir.type  = 1
    dir.count = 1
    cb.addStruct(dir)

    var e: IcoEntry
    e.width       = cast(u8) (width == 256 ? 0 : width)
    e.height      = cast(u8) (height == 256 ? 0 : height)
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
    return cbToArray(&cb)
}

func icoCanEncode(fileName: #nonull string)->bool
{
    var enc: Ico.Encoder
    let itf = @mkinterface(&enc, #typeof(Ico.Encoder), IImageEncoder)
    return itf.canEncode(fileName)
}

func encodeIco(result: #nonull *ConcatBuffer, image: Image) throw
{
    var enc: Ico.Encoder
    let itf = @mkinterface(&enc, #typeof(Ico.Encoder), IImageEncoder)
    itf.encode(result, image, null)
}

func decodeIco(bytes: #nonull const [..] u8, opt: DecodeOptions = {})->Image throw
{
    var dec: Ico.Decoder
    let itf = @mkinterface(&dec, #typeof(Ico.Decoder), IImageDecoder)
    return itf.decode(bytes, opt)
}

func encodePng(result: #nonull *ConcatBuffer, image: Image) throw
{
    var enc: Png.Encoder
    let itf = @mkinterface(&enc, #typeof(Png.Encoder), IImageEncoder)
    itf.encode(result, image, null)
}

// The registries recognise .ico (and .cur for loading).
#test
{
    @assert(Image.canLoad("in.ico"))
    @assert(Image.canLoad("in.cur"))
    @assert(Image.canSave("out.ico"))
    @assert(icoCanEncode("out.ico"))
    @assert(!icoCanEncode("out.bmp"))
}

// Decode a 2x2 32-bit BGRA icon. XOR data is bottom-up, matching the buffer.
#test
{
    var body: ConcatBuffer
    // XOR row 0 (bottom)
    body.addNative(10'u8); body.addNative(20'u8); body.addNative(30'u8); body.addNative(40'u8)
    body.addNative(50'u8); body.addNative(60'u8); body.addNative(70'u8); body.addNative(80'u8)
    // XOR row 1 (top)
    body.addNative(90'u8);  body.addNative(100'u8); body.addNative(110'u8); body.addNative(120'u8)
    body.addNative(130'u8); body.addNative(140'u8); body.addNative(150'u8); body.addNative(160'u8)
    // AND mask: 2 rows of 4 bytes, fully opaque
    for 8 do body.addNative(0'u8)

    let buf = buildIco(2, 2, 32, 0, nnBytes(body.toSlice()))
    var img = catch decodeIco(nnBytes(buf.toSlice()))
    @assert(@err == null)
    @assert(img.width == 2)
    @assert(img.height == 2)
    @assert(img.pf == .BGRA8)
    @assert(img.pixels.buffer[0] == 10'u8)
    @assert(img.pixels.buffer[1] == 20'u8)
    @assert(img.pixels.buffer[2] == 30'u8)
    @assert(img.pixels.buffer[3] == 40'u8)
    @assert(img.pixels.buffer[4] == 50'u8)
    @assert(img.pixels.buffer[7] == 80'u8)
}

// Decode a 2x2 24-bit icon, applying the AND mask as alpha.
#test
{
    var body: ConcatBuffer
    // XOR row 0 (bottom): 2 pixels BGR + 2 pad bytes (row stride = 8)
    body.addNative(10'u8); body.addNative(20'u8); body.addNative(30'u8)
    body.addNative(40'u8); body.addNative(50'u8); body.addNative(60'u8)
    body.addNative(0'u8);  body.addNative(0'u8)
    // XOR row 1 (top)
    for 8 do body.addNative(0'u8)
    // AND row 0 (bottom): bit for x=1 set -> pixel (1,0) transparent
    body.addNative(0x40'u8); body.addNative(0'u8); body.addNative(0'u8); body.addNative(0'u8)
    // AND row 1 (top)
    for 4 do body.addNative(0'u8)

    let buf = buildIco(2, 2, 24, 0, nnBytes(body.toSlice()))
    var img = catch decodeIco(nnBytes(buf.toSlice()))
    @assert(@err == null)
    @assert(img.pf == .BGRA8)
    @assert(img.pixels.buffer[0] == 10'u8)
    @assert(img.pixels.buffer[1] == 20'u8)
    @assert(img.pixels.buffer[2] == 30'u8)
    @assert(img.pixels.buffer[3] == 255'u8)   // opaque
    @assert(img.pixels.buffer[4] == 40'u8)
    @assert(img.pixels.buffer[5] == 50'u8)
    @assert(img.pixels.buffer[6] == 60'u8)
    @assert(img.pixels.buffer[7] == 0'u8)     // transparent via AND mask
}

// Decode a 2x2 8-bit indexed icon through its palette.
#test
{
    var body: ConcatBuffer
    // Palette (4 BGRA quads)
    body.addNative(0'u8);  body.addNative(0'u8);  body.addNative(0'u8);  body.addNative(0'u8)    // idx 0
    body.addNative(10'u8); body.addNative(20'u8); body.addNative(30'u8); body.addNative(0'u8)    // idx 1
    body.addNative(40'u8); body.addNative(50'u8); body.addNative(60'u8); body.addNative(0'u8)    // idx 2
    body.addNative(70'u8); body.addNative(80'u8); body.addNative(90'u8); body.addNative(0'u8)    // idx 3
    // XOR row 0 (bottom): indices [1,2] + 2 pad (row stride = 4)
    body.addNative(1'u8); body.addNative(2'u8); body.addNative(0'u8); body.addNative(0'u8)
    // XOR row 1 (top)
    body.addNative(3'u8); body.addNative(0'u8); body.addNative(0'u8); body.addNative(0'u8)
    // AND mask: 2 rows of 4 bytes, opaque
    for 8 do body.addNative(0'u8)

    let buf = buildIco(2, 2, 8, 4, nnBytes(body.toSlice()))
    var img = catch decodeIco(nnBytes(buf.toSlice()))
    @assert(@err == null)
    @assert(img.pf == .BGRA8)
    @assert(img.pixels.buffer[0] == 10'u8)
    @assert(img.pixels.buffer[1] == 20'u8)
    @assert(img.pixels.buffer[2] == 30'u8)
    @assert(img.pixels.buffer[3] == 255'u8)
    @assert(img.pixels.buffer[4] == 40'u8)
    @assert(img.pixels.buffer[6] == 60'u8)
}

// Decode a 2x1 1-bit indexed icon.
#test
{
    var body: ConcatBuffer
    // Palette (2 BGRA quads)
    body.addNative(0'u8); body.addNative(0'u8); body.addNative(0'u8); body.addNative(0'u8)    // idx 0
    body.addNative(7'u8); body.addNative(8'u8); body.addNative(9'u8); body.addNative(0'u8)    // idx 1
    // XOR row 0 (only row): x0=1, x1=0 -> 0b10000000, + 3 pad (row stride = 4)
    body.addNative(0x80'u8); body.addNative(0'u8); body.addNative(0'u8); body.addNative(0'u8)
    // AND mask: 1 row of 4 bytes
    for 4 do body.addNative(0'u8)

    let buf = buildIco(2, 1, 1, 2, nnBytes(body.toSlice()))
    var img = catch decodeIco(nnBytes(buf.toSlice()))
    @assert(@err == null)
    @assert(img.pixels.buffer[0] == 7'u8)
    @assert(img.pixels.buffer[1] == 8'u8)
    @assert(img.pixels.buffer[2] == 9'u8)
    @assert(img.pixels.buffer[3] == 255'u8)
    @assert(img.pixels.buffer[4] == 0'u8)     // idx 0 color
}

// With multiple entries, the decoder picks the largest image.
#test
{
    // Two 32-bit images: 1x1 and 2x2. Directory holds 2 entries.
    let body1Len = cast(u32) (40 + 4 + 4)         // 1x1: 4 XOR + 4 AND
    let body2Len = cast(u32) (40 + 16 + 8)         // 2x2: 16 XOR + 8 AND
    let off1     = 6 + 32'u32                       // after dir + 2 entries
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
    cb.addNative(1'u8); cb.addNative(2'u8); cb.addNative(3'u8); cb.addNative(4'u8)   // XOR
    for 4 do cb.addNative(0'u8)                                                       // AND

    // Image 2 (2x2)
    var d2: IcoDib
    d2.size     = 40
    d2.width    = 2
    d2.height   = 4
    d2.planes   = 1
    d2.bitCount = 32
    cb.addStruct(d2)
    cb.addNative(200'u8); cb.addNative(201'u8); cb.addNative(202'u8); cb.addNative(203'u8)
    for 12 do cb.addNative(0'u8)   // rest of XOR
    for 8 do cb.addNative(0'u8)    // AND

    var img = catch decodeIco(nnBytes(cb.toSlice()))
    @assert(@err == null)
    @assert(img.width == 2)
    @assert(img.height == 2)
    @assert(img.pixels.buffer[0] == 200'u8)
    @assert(img.pixels.buffer[3] == 203'u8)
}

// A PNG-compressed icon entry is delegated to the PNG decoder.
#test
{
    var src = Image.create(3, 2, .RGBA8)
    src.clear()
    src.pixels.buffer[0] = 11'u8
    src.pixels.buffer[1] = 22'u8
    src.pixels.buffer[2] = 33'u8
    src.pixels.buffer[3] = 255'u8

    var png: ConcatBuffer
    catch encodePng(&png, src)
    @assert(@err == null)
    png.makeLinear()
    let pngBytes = nnBytes(png.toSlice())
    let pngLen   = cast(u32) @countof(pngBytes)

    var cb: ConcatBuffer
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

    var img = catch decodeIco(nnBytes(cb.toSlice()))
    @assert(@err == null)
    @assert(img.width == 3)
    @assert(img.height == 2)
}

// Decode metadata only: dimensions populated, no pixels allocated.
#test
{
    var body: ConcatBuffer
    for 24 do body.addNative(0'u8)   // 16 XOR + 8 AND

    let buf = buildIco(2, 2, 32, 0, nnBytes(body.toSlice()))

    var opt: DecodeOptions
    opt.decodePixels = false
    var img = catch decodeIco(nnBytes(buf.toSlice()), opt)
    @assert(@err == null)
    @assert(img.width == 2)
    @assert(img.height == 2)
    @assert(img.pf == .BGRA8)
    @assert(!img.isValid())
}

// Error: directory type is neither icon (1) nor cursor (2).
#test
{
    var cb: ConcatBuffer
    var dir: IcoDir
    dir.type  = 7
    dir.count = 1
    cb.addStruct(dir)

    var img = catch decodeIco(nnBytes(cb.toSlice()))
    @assert(@err != null)
}

// Error: empty directory.
#test
{
    var cb: ConcatBuffer
    var dir: IcoDir
    dir.type  = 1
    dir.count = 0
    cb.addStruct(dir)

    var img = catch decodeIco(nnBytes(cb.toSlice()))
    @assert(@err != null)
}

// Encode a 2x2 BGRA8 image and round-trip it unchanged.
#test
{
    var src = Image.create(2, 2, .BGRA8)
    src.clear()
    src.pixels.buffer[0]  = 10'u8
    src.pixels.buffer[1]  = 20'u8
    src.pixels.buffer[2]  = 30'u8
    src.pixels.buffer[3]  = 128'u8
    src.pixels.buffer[12] = 200'u8   // last pixel B

    var cb: ConcatBuffer
    catch encodeIco(&cb, src)
    @assert(@err == null)

    var img = catch decodeIco(nnBytes(cb.toSlice()))
    @assert(@err == null)
    @assert(img.width == 2)
    @assert(img.height == 2)
    @assert(img.pf == .BGRA8)
    @assert(img.pixels.buffer[0]  == 10'u8)
    @assert(img.pixels.buffer[1]  == 20'u8)
    @assert(img.pixels.buffer[2]  == 30'u8)
    @assert(img.pixels.buffer[3]  == 128'u8)
    @assert(img.pixels.buffer[12] == 200'u8)
}

// Encode a BGR8 image: alpha is filled opaque.
#test
{
    var src = Image.create(1, 1, .BGR8)
    src.pixels.buffer[0] = 10'u8
    src.pixels.buffer[1] = 20'u8
    src.pixels.buffer[2] = 30'u8

    var cb: ConcatBuffer
    catch encodeIco(&cb, src)
    @assert(@err == null)

    var img = catch decodeIco(nnBytes(cb.toSlice()))
    @assert(@err == null)
    @assert(img.pf == .BGRA8)
    @assert(img.pixels.buffer[0] == 10'u8)
    @assert(img.pixels.buffer[1] == 20'u8)
    @assert(img.pixels.buffer[2] == 30'u8)
    @assert(img.pixels.buffer[3] == 255'u8)
}

// Encode an RGBA8 image: channels are swapped to BGRA on disk.
#test
{
    var src = Image.create(1, 1, .RGBA8)
    src.pixels.buffer[0] = 30'u8    // R
    src.pixels.buffer[1] = 20'u8    // G
    src.pixels.buffer[2] = 10'u8    // B
    src.pixels.buffer[3] = 99'u8    // A

    var cb: ConcatBuffer
    catch encodeIco(&cb, src)
    @assert(@err == null)

    var img = catch decodeIco(nnBytes(cb.toSlice()))
    @assert(@err == null)
    @assert(img.pf == .BGRA8)
    @assert(img.pixels.buffer[0] == 10'u8)    // B
    @assert(img.pixels.buffer[1] == 20'u8)    // G
    @assert(img.pixels.buffer[2] == 30'u8)    // R
    @assert(img.pixels.buffer[3] == 99'u8)    // A
}

// Error: dimensions above 256 cannot be encoded.
#test
{
    var src = Image.create(300, 8, .BGRA8)
    src.clear()

    var cb: ConcatBuffer
    catch encodeIco(&cb, src)
    @assert(@err != null)
}

// Full registry round-trip through Image.save / Image.load on a temp file.
#test
{
    let path = makeTempIcoPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(4, 4, .BGRA8)
    src.clear()
    src.pixels.buffer[0] = 77'u8
    src.pixels.buffer[1] = 88'u8
    src.pixels.buffer[2] = 99'u8
    src.pixels.buffer[3] = 255'u8

    catch src.save(path.toString())
    @assert(@err == null)

    var img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width == 4)
    @assert(img.height == 4)
    @assert(img.pf == .BGRA8)
    @assert(img.pixels.buffer[0] == 77'u8)
    @assert(img.pixels.buffer[1] == 88'u8)
    @assert(img.pixels.buffer[2] == 99'u8)
}
