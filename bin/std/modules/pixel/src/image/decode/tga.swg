#global namespace Tga

using Core, Core.Errors

const TYPE_MAP      = 1
const TYPE_RGB      = 2
const TYPE_MONO     = 3
const TYPE_RLE_MAP  = 9
const TYPE_RLE_RGB  = 10
const TYPE_RLE_MONO = 11

const DESC_ALPHA_MASK   = 0x0F'u8
const DESC_ORIGIN_RIGHT = 0x10'u8
const DESC_ORIGIN_TOP   = 0x20'u8

#[Swag.Pack(1)]
struct Header
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
    bpp:            u8
    descriptorByte: u8
}

struct Palette
{
    data:  #null const [*] u8
    first: u16
    count: u16
    bpp:   u8
    bpp8:  u8
}

public struct Decoder {}

func checkBuffer(ptr, last: const [*] u8, size: u64) throw
{
    if ptr + size > last do
        throw InvalidFormatError{"invalid source buffer"}
}

func isMappedType(imageType: u8)->bool
{
    return imageType == TYPE_MAP or imageType == TYPE_RLE_MAP
}

func isRgbType(imageType: u8)->bool
{
    return imageType == TYPE_RGB or imageType == TYPE_RLE_RGB
}

func isMonoType(imageType: u8)->bool
{
    return imageType == TYPE_MONO or imageType == TYPE_RLE_MONO
}

func isRleType(imageType: u8)->bool
{
    return imageType == TYPE_RLE_MAP or imageType == TYPE_RLE_RGB or imageType == TYPE_RLE_MONO
}

func sourcePixelBytes(header: Header)->u8 throw
{
    if isMappedType(header.imageTypeCode)
    {
        if header.bpp != 8 and header.bpp != 16 do
            throw UnsupportedFormatError{"unsupported bit depth"}
        return header.bpp / 8
    }

    if isMonoType(header.imageTypeCode)
    {
        if header.bpp != 8 and header.bpp != 16 do
            throw UnsupportedFormatError{"unsupported bit depth"}
        return header.bpp / 8
    }

    if isRgbType(header.imageTypeCode)
    {
        if header.bpp == 15 or header.bpp == 16 do
            return 2
        if header.bpp == 24 or header.bpp == 32 do
            return header.bpp / 8
        throw UnsupportedFormatError{"unsupported bit depth"}
    }

    throw UnsupportedFormatError{"unsupported type"}
}

func palettePixelBytes(bpp: u8)->u8 throw
{
    switch bpp
    {
    case 15, 16: return 2
    case 24:     return 3
    case 32:     return 4
    default:     throw UnsupportedFormatError{"unsupported palette bit depth"}
    }
}

func pixelFormat(header: Header, palette: Palette)->PixelFormat throw
{
    if isMappedType(header.imageTypeCode)
    {
        if palette.bpp == 16 or palette.bpp == 32 do
            return .BGRA8
        if palette.bpp == 15 or palette.bpp == 24 do
            return .BGR8
        throw UnsupportedFormatError{"unsupported palette bit depth"}
    }

    if isMonoType(header.imageTypeCode) do
        return header.bpp == 16 ? .BGRA8 : .BGR8

    if header.bpp == 16 or header.bpp == 32 do
        return .BGRA8
    if header.bpp == 15 or header.bpp == 24 do
        return .BGR8
    throw UnsupportedFormatError{"unsupported bit depth"}
}

func expand5(value: u32)->u8
{
    return cast(u8) ((value * 255 + 15) / 31)
}

func writeBgrPixel(dst: [*] u8, b, g, r: u8)
{
    dst[0] = b
    dst[1] = g
    dst[2] = r
}

func writeBgraPixel(dst: [*] u8, b, g, r, a: u8)
{
    dst[0] = b
    dst[1] = g
    dst[2] = r
    dst[3] = a
}

func writeTga16Pixel(dst: [*] u8, value: u16, writeAlpha, alphaFromBit: bool)
{
    let pixel = cast(u32) value
    let b     = expand5(pixel & 0x1F)
    let g     = expand5((pixel >> 5) & 0x1F)
    let r     = expand5((pixel >> 10) & 0x1F)
    if writeAlpha do
        writeBgraPixel(dst, b, g, r, alphaFromBit ? (value & 0x8000 ? 255'u8 : 0'u8) : 255'u8)
    else do
        writeBgrPixel(dst, b, g, r)
}

func dstPixel(result: *Image, header: Header, pixelIndex: u64)->[*] u8
{
    let srcX = cast(s32) (pixelIndex % header.width)
    let srcY = cast(s32) (pixelIndex / header.width)
    let dstX = header.descriptorByte & DESC_ORIGIN_RIGHT ? result.width - srcX - 1 : srcX
    let dstY = header.descriptorByte & DESC_ORIGIN_TOP ? result.height - srcY - 1 : srcY
    return cast([*] u8) (notnull result.pixels.buffer) + cast(u64) dstY * result.width8 + cast(u64) dstX * result.bpp8
}

func paletteIndex(src: const [*] u8, bpp: u8)->u32
{
    if bpp == 16 do
        return dref cast(const *u16) src
    return src[0]
}

func writePalettePixel(dst: [*] u8, palette: Palette, index: u32) throw
{
    if index < palette.first or index >= cast(u32) palette.first + palette.count do
        throw InvalidFormatError{"invalid palette index"}

    let paletteData = cast(const [*] u8) (notnull palette.data)
    let entry = paletteData + cast(u64) (index - palette.first) * palette.bpp8
    switch palette.bpp
    {
    case 15: writeTga16Pixel(dst, dref cast(const *u16) entry, false, false)
    case 16: writeTga16Pixel(dst, dref cast(const *u16) entry, true, true)
    case 24: writeBgrPixel(dst, entry[0], entry[1], entry[2])
    case 32: writeBgraPixel(dst, entry[0], entry[1], entry[2], entry[3])
    }
}

func writeSourcePixel(result: *Image, header: Header, palette: Palette, pixelIndex: u64, src: const [*] u8) throw
{
    let dst = dstPixel(result, header, pixelIndex)

    if isMappedType(header.imageTypeCode)
    {
        writePalettePixel(dst, palette, paletteIndex(src, header.bpp))
        return
    }

    if isMonoType(header.imageTypeCode)
    {
        let gray = src[0]
        if header.bpp == 16 do
            writeBgraPixel(dst, gray, gray, gray, src[1])
        else do
            writeBgrPixel(dst, gray, gray, gray)
        return
    }

    switch header.bpp
    {
    case 15: writeTga16Pixel(dst, dref cast(const *u16) src, false, false)
    case 16: writeTga16Pixel(dst, dref cast(const *u16) src, true, (header.descriptorByte & DESC_ALPHA_MASK) != 0)
    case 24: writeBgrPixel(dst, src[0], src[1], src[2])
    case 32: writeBgraPixel(dst, src[0], src[1], src[2], src[3])
    }
}

func decodeRaw(result: *Image, header: Header, palette: Palette, src, last: const [*] u8, pixelBytes: u8, pixelCount: u64) throw
{
    var p = src
    checkBuffer(p, last, pixelCount * pixelBytes)
    for [i] in pixelCount
    {
        writeSourcePixel(result, header, palette, i, p)
        p += pixelBytes
    }
}

func decodeRle(result: *Image, header: Header, palette: Palette, src, last: const [*] u8, pixelBytes: u8, pixelCount: u64) throw
{
    var index: u64
    var p = src

    while index < pixelCount
    {
        checkBuffer(p, last, 1)
        let packet = p[0]
        p += 1

        let count = cast(u64) ((packet & 0x7F) + 1)
        if index + count > pixelCount do
            throw InvalidFormatError{"invalid source buffer"}

        if packet & 0x80
        {
            checkBuffer(p, last, pixelBytes)
            for count
            {
                writeSourcePixel(result, header, palette, index, p)
                index += 1
            }

            p += pixelBytes
        }
        else
        {
            checkBuffer(p, last, count * pixelBytes)
            for count
            {
                writeSourcePixel(result, header, palette, index, p)
                index += 1
                p     += pixelBytes
            }
        }
    }
}

public impl IImageDecoder for Decoder
{
    func impl canDecode(me, fileName: string)->bool
    {
        return Path.getExtensionLowerCase(fileName) == ".tga"
    }

    func impl decode(me, buffer: const [..] u8, options: DecodeOptions)->Image throw
    {
        var dataof  = @dataof(buffer)
        let countof = @countof(buffer)
        let last    = dataof + countof

        if countof < #sizeof(Header) do
            throw InvalidFormatError{"invalid source buffer"}

        let header = dref cast(const *Header) dataof
        dataof += #sizeof(Header)

        if header.width == 0 or header.height == 0 do
            throw InvalidFormatError{"invalid dimensions"}
        if header.colorMapType != 0 and header.colorMapType != 1 do
            throw UnsupportedFormatError{"unsupported palette"}

        let pixelBytes = sourcePixelBytes(header)
        checkBuffer(dataof, last, header.idLength)
        dataof += header.idLength

        var palette: Palette
        if header.colorMapType
        {
            palette.first = header.colorMapFirst
            palette.count = header.colorMapLength
            palette.bpp   = header.colorMapBpp
            palette.bpp8  = palettePixelBytes(header.colorMapBpp)
            palette.data  = dataof
            checkBuffer(dataof, last, cast(u64) palette.count * palette.bpp8)
            dataof += cast(u64) palette.count * palette.bpp8
        }

        if isMappedType(header.imageTypeCode) and !palette.count do
            throw InvalidFormatError{"missing palette"}

        var result: retval
        result.init(header.width, header.height, pixelFormat(header, palette))

        if !options.decodePixels do
            return result

        result.allocPixels()
        let pixelCount = cast(u64) result.width * result.height
        if isRleType(header.imageTypeCode) do
            decodeRle(&result, header, palette, dataof, last, pixelBytes, pixelCount)
        else do
            decodeRaw(&result, header, palette, dataof, last, pixelBytes, pixelCount)

        return result
    }
}
