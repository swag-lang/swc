#global if #command == Swag.CompilerCommand.Test

using Swag, Core

const TGA_TYPE_MAP      = 1'u8
const TGA_TYPE_RGB      = 2'u8
const TGA_TYPE_MONO     = 3'u8
const TGA_TYPE_RLE_MAP  = 9'u8
const TGA_TYPE_RLE_RGB  = 10'u8
const TGA_TYPE_RLE_MONO = 11'u8

const TGA_DESC_RIGHT = 0x10'u8
const TGA_DESC_TOP   = 0x20'u8

#[Swag.Pack(1)]
struct TgaH
{
    idLength:       u8
    colorMapType:   u8
    imageTypeCode:  u8
    colorMapFirst:  u16
    colorMapLength: u16
    colorMapBpp:    u8
    originX:        u16
    originY:        u16
    width:          u16
    height:         u16
    bitsPerPixel:   u8
    descriptorByte: u8
}

func tgaCanEncode(fileName: string)->bool
{
    var enc: Tga.Encoder
    let itf = @mkinterface(&enc, #typeof(Tga.Encoder), IImageEncoder)
    return itf.canEncode(fileName)
}

func encodeTga(result: *ConcatBuffer, image: Image, options: #null any = null) fail
{
    var enc: Tga.Encoder
    let itf = @mkinterface(&enc, #typeof(Tga.Encoder), IImageEncoder)
    itf.encode(result, image, options)
}

func addTgaImageHeader(cb: *ConcatBuffer, imageType, bpp, descriptor: u8, width, height: u16)
{
    var h: TgaH
    h.imageTypeCode  = imageType
    h.width          = width
    h.height         = height
    h.bitsPerPixel   = bpp
    h.descriptorByte = descriptor
    cb.addStruct(h)
}

func addTgaPaletteColor(cb: *ConcatBuffer, b, g, r: u8)
{
    cb.addNative(b)
    cb.addNative(g)
    cb.addNative(r)
}

// Decoder and encoder registries recognise TGA files.
#test
{
    @assert(Image.canLoad("in.tga"))
    @assert(Image.canSave("out.tga"))
    @assert(tgaCanEncode("out.tga"))
    @assert(!tgaCanEncode("out.bmp"))
}

// Decode a raw 2x2 24-bit TGA with the default bottom-left origin.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, 0'u8, 2'u16, 2'u16)
    cb.addNative(10'u8);  cb.addNative(20'u8);  cb.addNative(30'u8)
    cb.addNative(40'u8);  cb.addNative(50'u8);  cb.addNative(60'u8)
    cb.addNative(70'u8);  cb.addNative(80'u8);  cb.addNative(90'u8)
    cb.addNative(100'u8); cb.addNative(110'u8); cb.addNative(120'u8)

    discard catch File.writeAllBytes(path.toString(), cb) as err
    @assert(err == null)

    var img: Image
    img = catch Image.load(path.toString()) as err2
    @assert(err2 == null)
    @assert(img.width == 2)
    @assert(img.height == 2)
    @assert(img.pixelFormat == .BGR8)
    @assert((notnull img.pixels.buffer)[0] == 10'u8)
    @assert((notnull img.pixels.buffer)[1] == 20'u8)
    @assert((notnull img.pixels.buffer)[2] == 30'u8)
    @assert((notnull img.pixels.buffer)[9] == 100'u8)
    @assert((notnull img.pixels.buffer)[10] == 110'u8)
    @assert((notnull img.pixels.buffer)[11] == 120'u8)
}

// Load larger RGB/RGBA fixtures copied from the historical pixel test data.
#test
{
    var rgb: Image
    rgb = catch Image.load(getTestDataPath("rgb.tga")) as err3
    @assert(err3 == null)
    @assert(rgb.isValid())
    @assert(rgb.width == 660)
    @assert(rgb.height == 441)
    @assert(rgb.pixelFormat == .BGR8)
    @assert(rgb.pixels.count == 873180)
    @assert((notnull rgb.pixels.buffer)[0] == 201'u8)
    @assert((notnull rgb.pixels.buffer)[1] == 205'u8)
    @assert((notnull rgb.pixels.buffer)[2] == 194'u8)

    var rgba: Image
    rgba = catch Image.load(getTestDataPath("rgba.tga")) as err4
    @assert(err4 == null)
    @assert(rgba.isValid())
    @assert(rgba.width == 660)
    @assert(rgba.height == 441)
    @assert(rgba.pixelFormat == .BGRA8)
    @assert(rgba.pixels.count == 1164240)
    @assert((notnull rgba.pixels.buffer)[0] == 201'u8)
    @assert((notnull rgba.pixels.buffer)[1] == 205'u8)
    @assert((notnull rgba.pixels.buffer)[2] == 194'u8)
    @assert((notnull rgba.pixels.buffer)[3] == 255'u8)
}

// Load RLE RGB/RGBA fixtures copied from the historical pixel test data.
#test
{
    var rle24: Image
    rle24 = catch Image.load(getTestDataPath("rle24.tga")) as err5
    @assert(err5 == null)
    @assert(rle24.isValid())
    @assert(rle24.width == 660)
    @assert(rle24.height == 441)
    @assert(rle24.pixelFormat == .BGR8)
    @assert((notnull rle24.pixels.buffer)[0] == 201'u8)
    @assert((notnull rle24.pixels.buffer)[1] == 205'u8)
    @assert((notnull rle24.pixels.buffer)[2] == 194'u8)

    var rle32: Image
    rle32 = catch Image.load(getTestDataPath("rle32.tga")) as err6
    @assert(err6 == null)
    @assert(rle32.isValid())
    @assert(rle32.width == 660)
    @assert(rle32.height == 441)
    @assert(rle32.pixelFormat == .BGRA8)
    @assert((notnull rle32.pixels.buffer)[0] == 201'u8)
    @assert((notnull rle32.pixels.buffer)[1] == 205'u8)
    @assert((notnull rle32.pixels.buffer)[2] == 194'u8)
    @assert((notnull rle32.pixels.buffer)[3] == 255'u8)
}

// Decode skips the optional image ID field before pixel data.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var cb: ConcatBuffer
    var h:  TgaH
    h.idLength      = 3'u8
    h.imageTypeCode = TGA_TYPE_RGB
    h.width         = 1'u16
    h.height        = 1'u16
    h.bitsPerPixel  = 24'u8
    cb.addStruct(h)
    cb.addNative(73'u8)
    cb.addNative(68'u8)
    cb.addNative(33'u8)
    cb.addNative(8'u8); cb.addNative(9'u8); cb.addNative(10'u8)

    discard catch File.writeAllBytes(path.toString(), cb) as err7
    @assert(err7 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err8
    @assert(err8 == null)
    @assert((notnull img.pixels.buffer)[0] == 8'u8)
    @assert((notnull img.pixels.buffer)[1] == 9'u8)
    @assert((notnull img.pixels.buffer)[2] == 10'u8)
}

// Decode a top-origin TGA into the module's bottom-up image buffer.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, TGA_DESC_TOP, 2'u16, 2'u16)
    cb.addNative(1'u8);  cb.addNative(2'u8);  cb.addNative(3'u8)
    cb.addNative(4'u8);  cb.addNative(5'u8);  cb.addNative(6'u8)
    cb.addNative(7'u8);  cb.addNative(8'u8);  cb.addNative(9'u8)
    cb.addNative(10'u8); cb.addNative(11'u8); cb.addNative(12'u8)

    discard catch File.writeAllBytes(path.toString(), cb) as err9
    @assert(err9 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err10
    @assert(err10 == null)
    @assert((notnull img.pixels.buffer)[0] == 7'u8)
    @assert((notnull img.pixels.buffer)[1] == 8'u8)
    @assert((notnull img.pixels.buffer)[2] == 9'u8)
    @assert((notnull img.pixels.buffer)[6] == 1'u8)
    @assert((notnull img.pixels.buffer)[7] == 2'u8)
    @assert((notnull img.pixels.buffer)[8] == 3'u8)
}

// Decode a right-origin TGA by reversing pixels within the row.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, TGA_DESC_RIGHT, 2'u16, 1'u16)
    cb.addNative(1'u8); cb.addNative(2'u8); cb.addNative(3'u8)
    cb.addNative(4'u8); cb.addNative(5'u8); cb.addNative(6'u8)

    discard catch File.writeAllBytes(path.toString(), cb) as err11
    @assert(err11 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err12
    @assert(err12 == null)
    @assert((notnull img.pixels.buffer)[0] == 4'u8)
    @assert((notnull img.pixels.buffer)[1] == 5'u8)
    @assert((notnull img.pixels.buffer)[2] == 6'u8)
    @assert((notnull img.pixels.buffer)[3] == 1'u8)
    @assert((notnull img.pixels.buffer)[4] == 2'u8)
    @assert((notnull img.pixels.buffer)[5] == 3'u8)
}

// Decode 16-bit true-color TGA pixels as BGRA8.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 16'u8, 1'u8, 2'u16, 1'u16)
    cb.addNative(0xFC00'u16)
    cb.addNative(0x03E0'u16)

    discard catch File.writeAllBytes(path.toString(), cb) as err13
    @assert(err13 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err14
    @assert(err14 == null)
    @assert(img.pixelFormat == .BGRA8)
    @assert((notnull img.pixels.buffer)[0] == 0'u8)
    @assert((notnull img.pixels.buffer)[1] == 0'u8)
    @assert((notnull img.pixels.buffer)[2] == 255'u8)
    @assert((notnull img.pixels.buffer)[3] == 255'u8)
    @assert((notnull img.pixels.buffer)[4] == 0'u8)
    @assert((notnull img.pixels.buffer)[5] == 255'u8)
    @assert((notnull img.pixels.buffer)[6] == 0'u8)
    @assert((notnull img.pixels.buffer)[7] == 0'u8)
}

// Decode 8-bit grayscale TGA as BGR8.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_MONO, 8'u8, 0'u8, 3'u16, 1'u16)
    cb.addNative(5'u8); cb.addNative(10'u8); cb.addNative(15'u8)

    discard catch File.writeAllBytes(path.toString(), cb) as err15
    @assert(err15 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err16
    @assert(err16 == null)
    @assert(img.pixelFormat == .BGR8)
    @assert((notnull img.pixels.buffer)[0] == 5'u8)
    @assert((notnull img.pixels.buffer)[1] == 5'u8)
    @assert((notnull img.pixels.buffer)[2] == 5'u8)
    @assert((notnull img.pixels.buffer)[6] == 15'u8)
    @assert((notnull img.pixels.buffer)[7] == 15'u8)
    @assert((notnull img.pixels.buffer)[8] == 15'u8)
}

// Decode an 8-bit indexed TGA with a non-zero palette base index.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var cb: ConcatBuffer
    var h:  TgaH
    h.colorMapType   = 1'u8
    h.imageTypeCode  = TGA_TYPE_MAP
    h.colorMapFirst  = 2'u16
    h.colorMapLength = 2'u16
    h.colorMapBpp    = 24'u8
    h.width          = 2'u16
    h.height         = 1'u16
    h.bitsPerPixel   = 8'u8
    cb.addStruct(h)
    addTgaPaletteColor(&cb, 10, 20, 30)
    addTgaPaletteColor(&cb, 40, 50, 60)
    cb.addNative(2'u8); cb.addNative(3'u8)

    discard catch File.writeAllBytes(path.toString(), cb) as err17
    @assert(err17 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err18
    @assert(err18 == null)
    @assert(img.pixelFormat == .BGR8)
    @assert((notnull img.pixels.buffer)[0] == 10'u8)
    @assert((notnull img.pixels.buffer)[1] == 20'u8)
    @assert((notnull img.pixels.buffer)[2] == 30'u8)
    @assert((notnull img.pixels.buffer)[3] == 40'u8)
    @assert((notnull img.pixels.buffer)[4] == 50'u8)
    @assert((notnull img.pixels.buffer)[5] == 60'u8)
}

// Decode indexed TGA with 32-bit palette entries and preserve alpha.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var cb: ConcatBuffer
    var h:  TgaH
    h.colorMapType   = 1'u8
    h.imageTypeCode  = TGA_TYPE_MAP
    h.colorMapLength = 1'u16
    h.colorMapBpp    = 32'u8
    h.width          = 1'u16
    h.height         = 1'u16
    h.bitsPerPixel   = 8'u8
    cb.addStruct(h)
    cb.addNative(3'u8); cb.addNative(4'u8); cb.addNative(5'u8); cb.addNative(6'u8)
    cb.addNative(0'u8)

    discard catch File.writeAllBytes(path.toString(), cb) as err19
    @assert(err19 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err20
    @assert(err20 == null)
    @assert(img.pixelFormat == .BGRA8)
    @assert((notnull img.pixels.buffer)[0] == 3'u8)
    @assert((notnull img.pixels.buffer)[1] == 4'u8)
    @assert((notnull img.pixels.buffer)[2] == 5'u8)
    @assert((notnull img.pixels.buffer)[3] == 6'u8)
}

// Decode RLE true-color packets.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RLE_RGB, 24'u8, 0'u8, 4'u16, 1'u16)
    cb.addNative(0x83'u8)
    cb.addNative(1'u8); cb.addNative(2'u8); cb.addNative(3'u8)

    discard catch File.writeAllBytes(path.toString(), cb) as err21
    @assert(err21 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err22
    @assert(err22 == null)
    @assert((notnull img.pixels.buffer)[0] == 1'u8)
    @assert((notnull img.pixels.buffer)[9] == 1'u8)
    @assert((notnull img.pixels.buffer)[10] == 2'u8)
    @assert((notnull img.pixels.buffer)[11] == 3'u8)
}

// Decode RLE color-mapped packets.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var cb: ConcatBuffer
    var h:  TgaH
    h.colorMapType   = 1'u8
    h.imageTypeCode  = TGA_TYPE_RLE_MAP
    h.colorMapLength = 3'u16
    h.colorMapBpp    = 24'u8
    h.width          = 3'u16
    h.height         = 1'u16
    h.bitsPerPixel   = 8'u8
    cb.addStruct(h)
    addTgaPaletteColor(&cb, 1, 2, 3)
    addTgaPaletteColor(&cb, 4, 5, 6)
    addTgaPaletteColor(&cb, 7, 8, 9)
    cb.addNative(0x02'u8)
    cb.addNative(0'u8); cb.addNative(1'u8); cb.addNative(2'u8)

    discard catch File.writeAllBytes(path.toString(), cb) as err23
    @assert(err23 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err24
    @assert(err24 == null)
    @assert((notnull img.pixels.buffer)[0] == 1'u8)
    @assert((notnull img.pixels.buffer)[3] == 4'u8)
    @assert((notnull img.pixels.buffer)[6] == 7'u8)
}

// Decode RLE grayscale packets.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RLE_MONO, 8'u8, 0'u8, 3'u16, 1'u16)
    cb.addNative(0x02'u8)
    cb.addNative(9'u8); cb.addNative(10'u8); cb.addNative(11'u8)

    discard catch File.writeAllBytes(path.toString(), cb) as err25
    @assert(err25 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err26
    @assert(err26 == null)
    @assert((notnull img.pixels.buffer)[0] == 9'u8)
    @assert((notnull img.pixels.buffer)[3] == 10'u8)
    @assert((notnull img.pixels.buffer)[6] == 11'u8)
}

// Decode metadata without allocating pixels.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, 0'u8, 2'u16, 2'u16)

    var opts: DecodeOptions
    opts.decodePixels = false

    var img: Image
    img = catch Image.decode("meta.tga", nnBytes(cb.toSlice()), opts) as err27
    @assert(err27 == null)
    @assert(img.width == 2)
    @assert(img.height == 2)
    @assert(img.pixelFormat == .BGR8)
    @assert(!img.isValid())
}

// Error: RLE packet cannot exceed the destination image.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RLE_RGB, 24'u8, 0'u8, 2'u16, 1'u16)
    cb.addNative(0x82'u8)
    cb.addNative(1'u8); cb.addNative(2'u8); cb.addNative(3'u8)

    var img: Image
    img = catch Image.decode("bad.tga", nnBytes(cb.toSlice()), {}) as err28
    @assert(err28 != null)
}

// Error: color-mapped images require palette data.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_MAP, 8'u8, 0'u8, 1'u16, 1'u16)
    cb.addNative(0'u8)

    var img: Image
    img = catch Image.decode("bad.tga", nnBytes(cb.toSlice()), {}) as err29
    @assert(err29 != null)
}

// Encode BGR8 and round-trip through the decoder.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var src    = Image.create(2, 1, .BGR8)
    let srcBuf = notnull src.pixels.buffer
    srcBuf[0] = 1'u8
    srcBuf[1] = 2'u8
    srcBuf[2] = 3'u8
    srcBuf[3] = 4'u8
    srcBuf[4] = 5'u8
    srcBuf[5] = 6'u8

    var cb: ConcatBuffer
    catch encodeTga(&cb, src) as err30
    @assert(err30 == null)
    discard catch File.writeAllBytes(path.toString(), cb) as err31
    @assert(err31 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err32
    @assert(err32 == null)
    @assert((notnull img.pixels.buffer)[0] == 1'u8)
    @assert((notnull img.pixels.buffer)[5] == 6'u8)
}

// Encode RGB8 by swapping R/B into the on-disk BGR order.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var src    = Image.create(1, 1, .RGB8)
    let srcBuf = notnull src.pixels.buffer
    srcBuf[0] = 10'u8
    srcBuf[1] = 20'u8
    srcBuf[2] = 30'u8

    var cb: ConcatBuffer
    catch encodeTga(&cb, src) as err33
    @assert(err33 == null)
    discard catch File.writeAllBytes(path.toString(), cb) as err34
    @assert(err34 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err35
    @assert(err35 == null)
    @assert(img.pixelFormat == .BGR8)
    @assert((notnull img.pixels.buffer)[0] == 30'u8)
    @assert((notnull img.pixels.buffer)[1] == 20'u8)
    @assert((notnull img.pixels.buffer)[2] == 10'u8)
}

// Encode RGBA8 with descriptor alpha bits and preserve alpha through round-trip.
#test
{
    let path = makeTempTgaPath()
    defer
    {
        discard catch File.delete(path.toString())
    }

    var src    = Image.create(1, 1, .RGBA8)
    let srcBuf = notnull src.pixels.buffer
    srcBuf[0] = 1'u8
    srcBuf[1] = 2'u8
    srcBuf[2] = 3'u8
    srcBuf[3] = 4'u8

    var cb: ConcatBuffer
    catch encodeTga(&cb, src) as err36
    @assert(err36 == null)
    cb.makeLinear()
    let bytes = nnBytes(cb.toSlice())
    @assert(bytes != null)
    let h = cast(const *TgaH) @dataof(bytes)
    @assert(h.imageTypeCode == TGA_TYPE_RGB)
    @assert(h.bitsPerPixel == 32'u8)
    @assert(h.descriptorByte == 8'u8)

    discard catch File.writeAllBytes(path.toString(), cb) as err37
    @assert(err37 == null)

    var img: Image
    img = catch Image.load(path.toString()) as err38
    @assert(err38 == null)
    @assert(img.pixelFormat == .BGRA8)
    @assert((notnull img.pixels.buffer)[0] == 3'u8)
    @assert((notnull img.pixels.buffer)[1] == 2'u8)
    @assert((notnull img.pixels.buffer)[2] == 1'u8)
    @assert((notnull img.pixels.buffer)[3] == 4'u8)
}

// Encode RLE packets for repeated and literal BGR pixels, then decode them
// without changing the bottom-up pixel buffer.
#test
{
    var src    = Image.create(8, 1, .BGR8)
    let srcBuf = notnull src.pixels.buffer
    for [x] in 4
    {
        let offset = cast(u64) x * 3
        srcBuf[offset]     = 10'u8
        srcBuf[offset + 1] = 20'u8
        srcBuf[offset + 2] = 30'u8
    }

    for var x = 4; x < 8; x += 1
    {
        let offset = cast(u64) x * 3
        srcBuf[offset]     = cast(u8) x
        srcBuf[offset + 1] = cast(u8) (x + 10)
        srcBuf[offset + 2] = cast(u8) (x + 20)
    }

    var options: Tga.EncodeOptions
    options.rle = true

    var cb: ConcatBuffer
    catch encodeTga(&cb, src, options) as err39
    @assert(err39 == null)
    let bytes = nnBytes(cb.toSlice())
    @assert(bytes[2] == TGA_TYPE_RLE_RGB)
    @assert(bytes[18] == 0x83'u8)
    @assert(@countof(bytes) < 18 + src.pixels.count)

    var img = catch Image.decode("encoded-rle.tga", bytes, {}) as err40
    @assert(err40 == null)
    @assert(img.pixelFormat == .BGR8)
    @assert(Memory.compare(src.pixels.buffer, img.pixels.buffer, src.pixels.count) == 0)
}

// RLE encoding preserves alpha while converting RGBA input to TGA's BGRA order.
#test
{
    var src    = Image.create(3, 1, .RGBA8)
    let srcBuf = notnull src.pixels.buffer
    for [x] in src.width
    {
        let offset = cast(u64) x * 4
        srcBuf[offset]     = 1'u8
        srcBuf[offset + 1] = 2'u8
        srcBuf[offset + 2] = 3'u8
        srcBuf[offset + 3] = 4'u8
    }

    var options: Tga.EncodeOptions
    options.rle = true

    var cb: ConcatBuffer
    catch encodeTga(&cb, src, options) as err41
    @assert(err41 == null)
    let bytes = nnBytes(cb.toSlice())
    @assert(bytes[2] == TGA_TYPE_RLE_RGB)
    @assert(bytes[16] == 32'u8)
    @assert(bytes[17] == 8'u8)

    let img = catch Image.decode("encoded-rle-alpha.tga", bytes, {}) as err42
    @assert(err42 == null)
    @assert(img.pixelFormat == .BGRA8)
    @assert((notnull img.pixels.buffer)[0] == 3'u8)
    @assert((notnull img.pixels.buffer)[1] == 2'u8)
    @assert((notnull img.pixels.buffer)[2] == 1'u8)
    @assert((notnull img.pixels.buffer)[3] == 4'u8)
}
