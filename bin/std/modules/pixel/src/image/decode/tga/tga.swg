//! Format: Truevision TGA decoder component.
//! Supported: Mapped, grayscale, and true-color images; raw or RLE packets; 8-, 15-, 16-, 24-, and 32-bit layouts; all image origins.
//! Not supported: Huffman/delta-compressed TGA 2.0 images and unsupported palette or pixel depths.
//! Role: This file owns TGA header parsing, packet traversal, and top-level decoding.
//
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
    bitsPerPixel:   u8
    descriptorByte: u8
}

struct Palette
{
    data:          const [*] u8?
    first:         u16
    count:         u16
    bitsPerPixel:  u8
    bytesPerPixel: u8
}

// Decodes mapped, grayscale, and true-color TGA images with optional RLE.
internal struct Decoder {}

func checkBuffer(ptr, last: const [*] u8, size: u64) fail
{
    if ptr + size > last do
        fail InvalidFormatError{"invalid source buffer"}
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

func sourcePixelBytes(header: Header)->u8 fail
{
    if isMappedType(header.imageTypeCode)
    {
        if header.bitsPerPixel != 8 and header.bitsPerPixel != 16 do
            fail UnsupportedFormatError{"unsupported bit depth"}
        return header.bitsPerPixel / 8
    }

    if isMonoType(header.imageTypeCode)
    {
        if header.bitsPerPixel != 8 and header.bitsPerPixel != 16 do
            fail UnsupportedFormatError{"unsupported bit depth"}
        return header.bitsPerPixel / 8
    }

    if isRgbType(header.imageTypeCode)
    {
        if header.bitsPerPixel == 15 or header.bitsPerPixel == 16 do
            return 2
        if header.bitsPerPixel == 24 or header.bitsPerPixel == 32 do
            return header.bitsPerPixel / 8
        fail UnsupportedFormatError{"unsupported bit depth"}
    }

    fail UnsupportedFormatError{"unsupported type"}
}

func palettePixelBytes(bpp: u8)->u8 fail
{
    switch bpp
    {
    case 15, 16: return 2
    case 24:     return 3
    case 32:     return 4
    default:     fail UnsupportedFormatError{"unsupported palette bit depth"}
    }
}

func pixelFormat(header: Header, palette: Palette)->PixelFormat fail
{
    if isMappedType(header.imageTypeCode)
    {
        if palette.bitsPerPixel == 16 or palette.bitsPerPixel == 32 do
            return .BGRA8
        if palette.bitsPerPixel == 15 or palette.bitsPerPixel == 24 do
            return .BGR8
        fail UnsupportedFormatError{"unsupported palette bit depth"}
    }

    if isMonoType(header.imageTypeCode) do
        return header.bitsPerPixel == 16 ? .BGRA8 : .BGR8

    if header.bitsPerPixel == 16 or header.bitsPerPixel == 32 do
        return .BGRA8
    if header.bitsPerPixel == 15 or header.bitsPerPixel == 24 do
        return .BGR8
    fail UnsupportedFormatError{"unsupported bit depth"}
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

func decodeTga15Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    PackedPixel.decodeBgr555Row(source, destination, pixelCount)
}

func decodeTga16Row(source: const [*] u8, destination: [*] u8, pixelCount: u64, alphaFromBit: bool)
{
    PackedPixel.decodeBgra5551Row(source, destination, pixelCount, alphaFromBit)
}

func decodeTga15RowReversed(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    PackedPixel.decodeBgr555RowReversed(source, destination, pixelCount)
}

func decodeTga16RowReversed(source: const [*] u8, destination: [*] u8, pixelCount: u64, alphaFromBit: bool)
{
    PackedPixel.decodeBgra5551RowReversed(source, destination, pixelCount, alphaFromBit)
}

func dstPixel(result: *Image, header: Header, pixelIndex: u64)->[*] u8
{
    let srcX = cast(s32) (pixelIndex % header.width)
    let srcY = cast(s32) (pixelIndex / header.width)
    let dstX = header.descriptorByte & DESC_ORIGIN_RIGHT ? result.width - srcX - 1 : srcX
    let dstY = header.descriptorByte & DESC_ORIGIN_TOP ? result.height - srcY - 1 : srcY
    return cast([*] u8) result.pixels.buffer! + cast(u64) dstY * result.rowStride + cast(u64) dstX * result.bytesPerPixel
}

func paletteIndex(src: const [*] u8, bpp: u8)->u32
{
    if bpp == 16 do
        return src[as u16]
    return src[0]
}

func writePalettePixel(dst: [*] u8, palette: Palette, index: u32) fail
{
    if index < palette.first or index >= cast(u32) palette.first + palette.count do
        fail InvalidFormatError{"invalid palette index"}

    let paletteData = cast(const [*] u8) palette.data!
    let entry       = paletteData + cast(u64) (index - palette.first) * palette.bytesPerPixel
    switch palette.bitsPerPixel
    {
    case 15: writeTga16Pixel(dst, entry[as u16], false, false)
    case 16: writeTga16Pixel(dst, entry[as u16], true, true)
    case 24: writeBgrPixel(dst, entry[0], entry[1], entry[2])
    case 32: writeBgraPixel(dst, entry[0], entry[1], entry[2], entry[3])
    }
}

func writeSourcePixel(result: *Image, header: Header, palette: Palette, pixelIndex: u64, src: const [*] u8) fail
{
    let dst = dstPixel(result, header, pixelIndex)

    if isMappedType(header.imageTypeCode)
    {
        writePalettePixel(dst, palette, paletteIndex(src, header.bitsPerPixel))
        return
    }

    if isMonoType(header.imageTypeCode)
    {
        let gray = src[0]
        if header.bitsPerPixel == 16 do
            writeBgraPixel(dst, gray, gray, gray, src[1])
        else do
            writeBgrPixel(dst, gray, gray, gray)
        return
    }

    switch header.bitsPerPixel
    {
    case 15: writeTga16Pixel(dst, src[as u16], false, false)
    case 16: writeTga16Pixel(dst, src[as u16], true, (header.descriptorByte & DESC_ALPHA_MASK) != 0)
    case 24: writeBgrPixel(dst, src[0], src[1], src[2])
    case 32: writeBgraPixel(dst, src[0], src[1], src[2], src[3])
    }
}

func decodeRaw(result: *Image, header: Header, palette: Palette, src, last: const [*] u8, pixelBytes: u8, pixelCount: u64) fail
{
    var p = src
    checkBuffer(p, last, pixelCount * pixelBytes)
    if header.imageTypeCode == TYPE_RGB and (header.bitsPerPixel == 15 or header.bitsPerPixel == 16)
    {
        let rightOrigin = (header.descriptorByte & DESC_ORIGIN_RIGHT) != 0
        for y in result.height
        {
            let dstY = header.descriptorByte & DESC_ORIGIN_TOP ? result.height - y - 1 : y
            let dst  = cast([*] u8) result.pixels.buffer! + cast(u64) dstY * result.rowStride
            if header.bitsPerPixel == 15
            {
                if rightOrigin do
                    decodeTga15RowReversed(p, dst, result.width)
                else do
                    decodeTga15Row(p, dst, result.width)
            }
            else
            {
                let alphaFromBit = (header.descriptorByte & DESC_ALPHA_MASK) != 0
                if rightOrigin do
                    decodeTga16RowReversed(p, dst, result.width, alphaFromBit)
                else do
                    decodeTga16Row(p, dst, result.width, alphaFromBit)
            }

            p += cast(u64) result.width * 2
        }

        return
    }

    if header.imageTypeCode == TYPE_RGB and (header.bitsPerPixel == 24 or header.bitsPerPixel == 32)
    {
        let rightOrigin = (header.descriptorByte & DESC_ORIGIN_RIGHT) != 0
        let rowBytes    = cast(u64) result.width * pixelBytes
        for y in result.height
        {
            let dstY = header.descriptorByte & DESC_ORIGIN_TOP ? result.height - y - 1 : y
            let dst  = cast([*] u8) result.pixels.buffer! + cast(u64) dstY * result.rowStride
            if rightOrigin
            {
                if header.bitsPerPixel == 24 do
                    PackedPixel.reverseBgr24Row(p, dst, result.width)
                else do
                    PackedPixel.reverseBgra32Row(p, dst, result.width)
            }
            else
            {
                Memory.copy(dst, p, rowBytes)
            }

            p += rowBytes
        }

        return
    }

    for i in pixelCount
    {
        writeSourcePixel(result, header, palette, i, p)
        p += pixelBytes
    }
}

func decodeRle(result: *Image, header: Header, palette: Palette, src, last: const [*] u8, pixelBytes: u8, pixelCount: u64) fail
{
    var index: u64
    var p = src

    if header.imageTypeCode == TYPE_RLE_RGB and (header.bitsPerPixel == 24 or header.bitsPerPixel == 32)
    {
        let rightOrigin = (header.descriptorByte & DESC_ORIGIN_RIGHT) != 0
        while index < pixelCount
        {
            checkBuffer(p, last, 1)
            let packet = p[0]
            p += 1

            let count = cast(u64) ((packet & 0x7F) + 1)
            if index + count > pixelCount do
                fail InvalidFormatError{"invalid source buffer"}

            let repeated = (packet & 0x80) != 0
            checkBuffer(p, last, repeated ? pixelBytes : count * pixelBytes)
            var remaining = count
            var source    = p
            while remaining
            {
                let rowRemaining = cast(u64) header.width - index % header.width
                let segmentCount = Math.min(remaining, rowRemaining)
                let dstIndex     = rightOrigin ? index + segmentCount - 1 : index
                let dst          = dstPixel(result, header, dstIndex)
                if repeated
                {
                    if header.bitsPerPixel == 24 do
                        PackedPixel.fillBgr24Row(source, dst, segmentCount)
                    else do
                        PackedPixel.fillBgra32Row(source, dst, segmentCount)
                }
                else
                {
                    if rightOrigin
                    {
                        if header.bitsPerPixel == 24 do
                            PackedPixel.reverseBgr24Row(source, dst, segmentCount)
                        else do
                            PackedPixel.reverseBgra32Row(source, dst, segmentCount)
                    }
                    else
                    {
                        Memory.copy(dst, source, segmentCount * pixelBytes)
                    }

                    source += segmentCount * pixelBytes
                }

                index     += segmentCount
                remaining -= segmentCount
            }

            p += repeated ? pixelBytes : count * pixelBytes
        }

        return
    }

    while index < pixelCount
    {
        checkBuffer(p, last, 1)
        let packet = p[0]
        p += 1

        let count = cast(u64) ((packet & 0x7F) + 1)
        if index + count > pixelCount do
            fail InvalidFormatError{"invalid source buffer"}

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

internal impl IImageDecoder for Decoder
{
    func impl format(me)->ImageFormat => {"TGA - Truevision Targa", ".tga"}

    func impl decode(me, buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        var dataof  = buffer.buffer
        let countof = buffer.count
        let last    = dataof + countof

        if countof < #sizeof(Header) do
            fail InvalidFormatError{"invalid source buffer"}

        let header = dataof[as Header]
        dataof += #sizeof(Header)

        if header.width == 0 or header.height == 0 do
            fail InvalidFormatError{"invalid dimensions"}
        if header.colorMapType != 0 and header.colorMapType != 1 do
            fail UnsupportedFormatError{"unsupported palette"}

        let pixelBytes = sourcePixelBytes(header)
        checkBuffer(dataof, last, header.idLength)
        dataof += header.idLength

        var palette: Palette
        if header.colorMapType
        {
            palette.first         = header.colorMapFirst
            palette.count         = header.colorMapLength
            palette.bitsPerPixel  = header.colorMapBpp
            palette.bytesPerPixel = palettePixelBytes(header.colorMapBpp)
            palette.data          = dataof
            checkBuffer(dataof, last, cast(u64) palette.count * palette.bytesPerPixel)
            dataof += cast(u64) palette.count * palette.bytesPerPixel
        }

        if isMappedType(header.imageTypeCode) and !palette.count do
            fail InvalidFormatError{"missing palette"}

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
