#global #if #command == Swag.CompilerCommand.Test
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
    idLength:          u8
    colorMapType:      u8
    imageTypeCode:     u8
    colorMapFirst:     u16
    colorMapLength:    u16
    colorMapBpp:       u8
    originX:           u16
    originY:           u16
    width:             u16
    height:            u16
    bpp:               u8
    descriptorByte:    u8
}

func tgaCanEncode(fileName: #nonull string)->bool
{
    var enc: Tga.Encoder
    let itf = @mkinterface(&enc, #typeof(Tga.Encoder), IImageEncoder)
    return itf.canEncode(fileName)
}

func encodeTga(result: #nonull *ConcatBuffer, image: Image) throw
{
    var enc: Tga.Encoder
    let itf = @mkinterface(&enc, #typeof(Tga.Encoder), IImageEncoder)
    itf.encode(result, image, null)
}

func addTgaImageHeader(cb: #nonull *ConcatBuffer, imageType, bpp, descriptor: u8, width, height: u16)
{
    var h: TgaH
    h.imageTypeCode  = imageType
    h.width          = width
    h.height         = height
    h.bpp            = bpp
    h.descriptorByte = descriptor
    cb.addStruct(h)
}

func addTgaPaletteColor(cb: #nonull *ConcatBuffer, b, g, r: u8)
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
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, 0'u8, 2'u16, 2'u16)
    cb.addNative(10'u8);  cb.addNative(20'u8);  cb.addNative(30'u8)
    cb.addNative(40'u8);  cb.addNative(50'u8);  cb.addNative(60'u8)
    cb.addNative(70'u8);  cb.addNative(80'u8);  cb.addNative(90'u8)
    cb.addNative(100'u8); cb.addNative(110'u8); cb.addNative(120'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.width == 2)
    @assert(img.height == 2)
    @assert(img.pf == .BGR8)
    @assert(img.pixels.buffer[0] == 10'u8)
    @assert(img.pixels.buffer[1] == 20'u8)
    @assert(img.pixels.buffer[2] == 30'u8)
    @assert(img.pixels.buffer[9] == 100'u8)
    @assert(img.pixels.buffer[10] == 110'u8)
    @assert(img.pixels.buffer[11] == 120'u8)
}

// Load larger RGB/RGBA fixtures copied from the historical pixel test data.
#test
{
    var rgb: Image
    rgb = catch Image.load(getTestDataPath("rgb.tga"))
    @assert(@err == null)
    @assert(rgb.isValid())
    @assert(rgb.width == 660)
    @assert(rgb.height == 441)
    @assert(rgb.pf == .BGR8)
    @assert(rgb.pixels.count == 873180)
    @assert(rgb.pixels.buffer[0] == 201'u8)
    @assert(rgb.pixels.buffer[1] == 205'u8)
    @assert(rgb.pixels.buffer[2] == 194'u8)

    var rgba: Image
    rgba = catch Image.load(getTestDataPath("rgba.tga"))
    @assert(@err == null)
    @assert(rgba.isValid())
    @assert(rgba.width == 660)
    @assert(rgba.height == 441)
    @assert(rgba.pf == .BGRA8)
    @assert(rgba.pixels.count == 1164240)
    @assert(rgba.pixels.buffer[0] == 201'u8)
    @assert(rgba.pixels.buffer[1] == 205'u8)
    @assert(rgba.pixels.buffer[2] == 194'u8)
    @assert(rgba.pixels.buffer[3] == 255'u8)
}

// Load RLE RGB/RGBA fixtures copied from the historical pixel test data.
#test
{
    var rle24: Image
    rle24 = catch Image.load(getTestDataPath("rle24.tga"))
    @assert(@err == null)
    @assert(rle24.isValid())
    @assert(rle24.width == 660)
    @assert(rle24.height == 441)
    @assert(rle24.pf == .BGR8)
    @assert(rle24.pixels.buffer[0] == 201'u8)
    @assert(rle24.pixels.buffer[1] == 205'u8)
    @assert(rle24.pixels.buffer[2] == 194'u8)

    var rle32: Image
    rle32 = catch Image.load(getTestDataPath("rle32.tga"))
    @assert(@err == null)
    @assert(rle32.isValid())
    @assert(rle32.width == 660)
    @assert(rle32.height == 441)
    @assert(rle32.pf == .BGRA8)
    @assert(rle32.pixels.buffer[0] == 201'u8)
    @assert(rle32.pixels.buffer[1] == 205'u8)
    @assert(rle32.pixels.buffer[2] == 194'u8)
    @assert(rle32.pixels.buffer[3] == 255'u8)
}

// Decode skips the optional image ID field before pixel data.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    var h: TgaH
    h.idLength      = 3'u8
    h.imageTypeCode = TGA_TYPE_RGB
    h.width         = 1'u16
    h.height        = 1'u16
    h.bpp           = 24'u8
    cb.addStruct(h)
    cb.addNative(73'u8)
    cb.addNative(68'u8)
    cb.addNative(33'u8)
    cb.addNative(8'u8); cb.addNative(9'u8); cb.addNative(10'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pixels.buffer[0] == 8'u8)
    @assert(img.pixels.buffer[1] == 9'u8)
    @assert(img.pixels.buffer[2] == 10'u8)
}

// Decode a top-origin TGA into the module's bottom-up image buffer.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, TGA_DESC_TOP, 2'u16, 2'u16)
    cb.addNative(1'u8);  cb.addNative(2'u8);  cb.addNative(3'u8)
    cb.addNative(4'u8);  cb.addNative(5'u8);  cb.addNative(6'u8)
    cb.addNative(7'u8);  cb.addNative(8'u8);  cb.addNative(9'u8)
    cb.addNative(10'u8); cb.addNative(11'u8); cb.addNative(12'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pixels.buffer[0] == 7'u8)
    @assert(img.pixels.buffer[1] == 8'u8)
    @assert(img.pixels.buffer[2] == 9'u8)
    @assert(img.pixels.buffer[6] == 1'u8)
    @assert(img.pixels.buffer[7] == 2'u8)
    @assert(img.pixels.buffer[8] == 3'u8)
}

// Decode a right-origin TGA by reversing pixels within the row.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, TGA_DESC_RIGHT, 2'u16, 1'u16)
    cb.addNative(1'u8); cb.addNative(2'u8); cb.addNative(3'u8)
    cb.addNative(4'u8); cb.addNative(5'u8); cb.addNative(6'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pixels.buffer[0] == 4'u8)
    @assert(img.pixels.buffer[1] == 5'u8)
    @assert(img.pixels.buffer[2] == 6'u8)
    @assert(img.pixels.buffer[3] == 1'u8)
    @assert(img.pixels.buffer[4] == 2'u8)
    @assert(img.pixels.buffer[5] == 3'u8)
}

// Decode 16-bit true-color TGA pixels as BGRA8.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 16'u8, 1'u8, 2'u16, 1'u16)
    cb.addNative(0xFC00'u16)
    cb.addNative(0x03E0'u16)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pf == .BGRA8)
    @assert(img.pixels.buffer[0] == 0'u8)
    @assert(img.pixels.buffer[1] == 0'u8)
    @assert(img.pixels.buffer[2] == 255'u8)
    @assert(img.pixels.buffer[3] == 255'u8)
    @assert(img.pixels.buffer[4] == 0'u8)
    @assert(img.pixels.buffer[5] == 255'u8)
    @assert(img.pixels.buffer[6] == 0'u8)
    @assert(img.pixels.buffer[7] == 0'u8)
}

// Decode 8-bit grayscale TGA as BGR8.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_MONO, 8'u8, 0'u8, 3'u16, 1'u16)
    cb.addNative(5'u8); cb.addNative(10'u8); cb.addNative(15'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pf == .BGR8)
    @assert(img.pixels.buffer[0] == 5'u8)
    @assert(img.pixels.buffer[1] == 5'u8)
    @assert(img.pixels.buffer[2] == 5'u8)
    @assert(img.pixels.buffer[6] == 15'u8)
    @assert(img.pixels.buffer[7] == 15'u8)
    @assert(img.pixels.buffer[8] == 15'u8)
}

// Decode an 8-bit indexed TGA with a non-zero palette base index.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    var h: TgaH
    h.colorMapType   = 1'u8
    h.imageTypeCode  = TGA_TYPE_MAP
    h.colorMapFirst  = 2'u16
    h.colorMapLength = 2'u16
    h.colorMapBpp    = 24'u8
    h.width          = 2'u16
    h.height         = 1'u16
    h.bpp            = 8'u8
    cb.addStruct(h)
    addTgaPaletteColor(&cb, 10, 20, 30)
    addTgaPaletteColor(&cb, 40, 50, 60)
    cb.addNative(2'u8); cb.addNative(3'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pf == .BGR8)
    @assert(img.pixels.buffer[0] == 10'u8)
    @assert(img.pixels.buffer[1] == 20'u8)
    @assert(img.pixels.buffer[2] == 30'u8)
    @assert(img.pixels.buffer[3] == 40'u8)
    @assert(img.pixels.buffer[4] == 50'u8)
    @assert(img.pixels.buffer[5] == 60'u8)
}

// Decode indexed TGA with 32-bit palette entries and preserve alpha.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    var h: TgaH
    h.colorMapType   = 1'u8
    h.imageTypeCode  = TGA_TYPE_MAP
    h.colorMapLength = 1'u16
    h.colorMapBpp    = 32'u8
    h.width          = 1'u16
    h.height         = 1'u16
    h.bpp            = 8'u8
    cb.addStruct(h)
    cb.addNative(3'u8); cb.addNative(4'u8); cb.addNative(5'u8); cb.addNative(6'u8)
    cb.addNative(0'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pf == .BGRA8)
    @assert(img.pixels.buffer[0] == 3'u8)
    @assert(img.pixels.buffer[1] == 4'u8)
    @assert(img.pixels.buffer[2] == 5'u8)
    @assert(img.pixels.buffer[3] == 6'u8)
}

// Decode RLE true-color packets.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RLE_RGB, 24'u8, 0'u8, 4'u16, 1'u16)
    cb.addNative(0x83'u8)
    cb.addNative(1'u8); cb.addNative(2'u8); cb.addNative(3'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pixels.buffer[0] == 1'u8)
    @assert(img.pixels.buffer[9] == 1'u8)
    @assert(img.pixels.buffer[10] == 2'u8)
    @assert(img.pixels.buffer[11] == 3'u8)
}

// Decode RLE color-mapped packets.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    var h: TgaH
    h.colorMapType   = 1'u8
    h.imageTypeCode  = TGA_TYPE_RLE_MAP
    h.colorMapLength = 3'u16
    h.colorMapBpp    = 24'u8
    h.width          = 3'u16
    h.height         = 1'u16
    h.bpp            = 8'u8
    cb.addStruct(h)
    addTgaPaletteColor(&cb, 1, 2, 3)
    addTgaPaletteColor(&cb, 4, 5, 6)
    addTgaPaletteColor(&cb, 7, 8, 9)
    cb.addNative(0x02'u8)
    cb.addNative(0'u8); cb.addNative(1'u8); cb.addNative(2'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pixels.buffer[0] == 1'u8)
    @assert(img.pixels.buffer[3] == 4'u8)
    @assert(img.pixels.buffer[6] == 7'u8)
}

// Decode RLE grayscale packets.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RLE_MONO, 8'u8, 0'u8, 3'u16, 1'u16)
    cb.addNative(0x02'u8)
    cb.addNative(9'u8); cb.addNative(10'u8); cb.addNative(11'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pixels.buffer[0] == 9'u8)
    @assert(img.pixels.buffer[3] == 10'u8)
    @assert(img.pixels.buffer[6] == 11'u8)
}

// Decode metadata without allocating pixels.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, 0'u8, 2'u16, 2'u16)

    var opts: DecodeOptions
    opts.decodePixels = false

    var img: Image
    img = catch Image.decode("meta.tga", nnBytes(cb.toSlice()), opts)
    @assert(@err == null)
    @assert(img.width == 2)
    @assert(img.height == 2)
    @assert(img.pf == .BGR8)
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
    img = catch Image.decode("bad.tga", nnBytes(cb.toSlice()), {})
    @assert(@err != null)
}

// Error: color-mapped images require palette data.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_MAP, 8'u8, 0'u8, 1'u16, 1'u16)
    cb.addNative(0'u8)

    var img: Image
    img = catch Image.decode("bad.tga", nnBytes(cb.toSlice()), {})
    @assert(@err != null)
}

// Encode BGR8 and round-trip through the decoder.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(2, 1, .BGR8)
    src.pixels.buffer[0] = 1'u8
    src.pixels.buffer[1] = 2'u8
    src.pixels.buffer[2] = 3'u8
    src.pixels.buffer[3] = 4'u8
    src.pixels.buffer[4] = 5'u8
    src.pixels.buffer[5] = 6'u8

    var cb: ConcatBuffer
    catch encodeTga(&cb, src)
    @assert(@err == null)
    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pixels.buffer[0] == 1'u8)
    @assert(img.pixels.buffer[5] == 6'u8)
}

// Encode RGB8 by swapping R/B into the on-disk BGR order.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(1, 1, .RGB8)
    src.pixels.buffer[0] = 10'u8
    src.pixels.buffer[1] = 20'u8
    src.pixels.buffer[2] = 30'u8

    var cb: ConcatBuffer
    catch encodeTga(&cb, src)
    @assert(@err == null)
    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pf == .BGR8)
    @assert(img.pixels.buffer[0] == 30'u8)
    @assert(img.pixels.buffer[1] == 20'u8)
    @assert(img.pixels.buffer[2] == 10'u8)
}

// Encode RGBA8 with descriptor alpha bits and preserve alpha through round-trip.
#test
{
    let path = makeTempTgaPath()
    defer { discard catch File.delete(path.toString()) }

    var src = Image.create(1, 1, .RGBA8)
    src.pixels.buffer[0] = 1'u8
    src.pixels.buffer[1] = 2'u8
    src.pixels.buffer[2] = 3'u8
    src.pixels.buffer[3] = 4'u8

    var cb: ConcatBuffer
    catch encodeTga(&cb, src)
    @assert(@err == null)
    cb.makeLinear()
    let bytes = nnBytes(cb.toSlice())
    @assert(bytes != null)
    let h = cast(#nonull const *TgaH) @dataof(bytes)
    @assert(h.imageTypeCode == TGA_TYPE_RGB)
    @assert(h.bpp == 32'u8)
    @assert(h.descriptorByte == 8'u8)

    discard catch File.writeAllBytes(path.toString(), cb)
    @assert(@err == null)

    var img: Image
    img = catch Image.load(path.toString())
    @assert(@err == null)
    @assert(img.pf == .BGRA8)
    @assert(img.pixels.buffer[0] == 3'u8)
    @assert(img.pixels.buffer[1] == 2'u8)
    @assert(img.pixels.buffer[2] == 1'u8)
    @assert(img.pixels.buffer[3] == 4'u8)
}
