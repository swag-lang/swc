#global namespace Bmp
using Core, Core.Errors

const FILL_RLE_COMMAND     = 0
const FILL_RLE_ENDOFLINE   = 0
const FILL_RLE_ENDOFBITMAP = 1
const FILL_RLE_DELTA       = 2

public const BI_RGB = 0
public const BI_RLE8 = 1
public const BI_RLE4 = 2
public const BI_BITFIELDS = 3

const BMP_SIGNATURE = 0x4D42'u16

#[Swag.Pack(1)]
public struct Header
{
    biSize:          u32
    biWidth:         s32
    biHeight:        s32
    biPlanes:        u16
    biBitCount:      u16
    biCompression:   u32
    biSizeImage:     u32
    biXPelsPerMeter: u32
    biYPelsPerMeter: u32
    biClrUsed:       u32
    biClrImportant:  u32
}

#[Swag.Pack(1)]
struct CoreHeader
{
    bcSize:     u32
    bcWidth:    u16
    bcHeight:   u16
    bcPlanes:   u16
    bcBitCount: u16
}

#[Swag.Pack(1)]
struct FileHeader
{
    bfType:      u16
    bfSize:      u32
    bfReserved1: u16
    bfReserved2: u16
    bfOffBits:   u32
}

struct Mask
{
    value: u32
    shift: u8
    bits:  u8
}

struct Masks
{
    r: Mask
    g: Mask
    b: Mask
    a: Mask
}

public struct Decoder {}

func checkBuffer(ptr, last: const [*] u8, size: u64) throw
{
    if ptr + size > last do
        throw InvalidFormatError{"invalid source buffer"}
}

func rowStride(width: s32, bitCount: u16)->u64
{
    return ((cast(u64) width * cast(u64) bitCount + 31) / 32) * 4
}

func defaultPaletteCount(bitCount: u16)->u32
{
    if bitCount <= 8 do
        return 1'u32 << cast(u32) bitCount
    return 0
}

func readMask(mask: u32)->Mask
{
    var result: retval
    result.value = mask

    var cur = mask
    while cur and (cur & 1) == 0
    {
        result.shift += 1
        cur          >>= 1
    }

    while cur and (cur & 1)
    {
        result.bits += 1
        cur         >>= 1
    }

    return result
}

func maskToByte(pixel: u32, mask: Mask)->u8
{
    if !mask.value or !mask.bits do
        return 0

    let value = cast(u64) ((pixel & mask.value) >> cast(u32) mask.shift)
    let max   = (1'u64 << cast(u64) mask.bits) - 1
    return cast(u8) ((value * 255 + (max >> 1)) / max)
}

func makeDefaultMasks(bitCount: u16, compression: u32)->Masks
{
    var result: retval

    if bitCount == 16
    {
        result.r = readMask(0x7C00)
        result.g = readMask(0x03E0)
        result.b = readMask(0x001F)
    }
    elif bitCount == 32
    {
        result.r = readMask(0x00FF0000)
        result.g = readMask(0x0000FF00)
        result.b = readMask(0x000000FF)
        if compression == BI_RGB do
            result.a = readMask(0xFF000000)
    }

    return result
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

func writePalettePixel(dst: [*] u8, palette: const [*] u8, paletteEntrySize: u32, index, paletteCount: u32) throw
{
    if index >= paletteCount do
        throw InvalidFormatError{"invalid palette index"}

    let entry = palette + cast(u64) index * paletteEntrySize
    writeBgrPixel(dst, entry[0], entry[1], entry[2])
}

func writeMaskedPixel(dst: [*] u8, pixel: u32, masks: Masks, hasAlpha: bool)
{
    let b = maskToByte(pixel, masks.b)
    let g = maskToByte(pixel, masks.g)
    let r = maskToByte(pixel, masks.r)
    if hasAlpha do
        writeBgraPixel(dst, b, g, r, masks.a.value ? maskToByte(pixel, masks.a) : 255)
    else do
        writeBgrPixel(dst, b, g, r)
}

func packedIndex(src: const [*] u8, bitCount: u16, x: s32)->u32
{
    switch bitCount
    {
    case 1:
        return cast(u32) ((src[x / 8] >> cast(u32) (7 - (x & 7))) & 1)
    case 4:
        let b = src[x / 2]
        return cast(u32) ((x & 1) ? (b & 0x0F) : (b >> 4))
    default:
        return src[x]
    }
}

func decodePackedPalette(result: *Image, src, last: const [*] u8, palette: const [*] u8, paletteEntrySize, paletteCount: u32, bitCount: u16, topDown: bool) throw
{
    let stride = rowStride(result.width, bitCount)
    checkBuffer(src, last, stride * cast(u64) result.height)

    for y in result.height
    {
        let dstY   = topDown ? result.height - y - 1 : y
        let srcRow = src + stride * cast(u64) y
        var dst    = cast([*] u8) (notnull result.pixels.buffer) + cast(u64) dstY * result.width8
        for x in result.width
        {
            writePalettePixel(dst, palette, paletteEntrySize, packedIndex(srcRow, bitCount, x), paletteCount)
            dst += 3
        }
    }
}

func decodeUncompressedDirect(result: *Image, src, last: const [*] u8, bitCount: u16, topDown: bool) throw
{
    let stride   = rowStride(result.width, bitCount)
    let rowBytes = cast(u64) result.width * result.bpp8
    checkBuffer(src, last, stride * cast(u64) result.height)

    for y in result.height
    {
        let dstY = topDown ? result.height - y - 1 : y
        Memory.copy(cast([*] u8) (notnull result.pixels.buffer) + cast(u64) dstY * rowBytes, src + stride * cast(u64) y, rowBytes)
    }
}

func decode16(result: *Image, src, last: const [*] u8, masks: Masks, topDown: bool) throw
{
    let stride = rowStride(result.width, 16)
    checkBuffer(src, last, stride * cast(u64) result.height)

    for y in result.height
    {
        let dstY   = topDown ? result.height - y - 1 : y
        var srcPix = src + stride * cast(u64) y
        var dst    = cast([*] u8) (notnull result.pixels.buffer) + cast(u64) dstY * result.width8
        for result.width
        {
            writeMaskedPixel(dst, dref cast(const *u16) srcPix, masks, false)
            srcPix += 2
            dst    += 3
        }
    }
}

func decodeRle8(result: *Image, src, last: const [*] u8, palette: const [*] u8, paletteEntrySize, paletteCount: u32) throw
{
    var x: s32
    var y: s32
    var p = src

    while p < last and y < result.height
    {
        checkBuffer(p, last, 2)
        let count = p[0]
        let value = p[1]
        p += 2

        if count
        {
            if x + count > result.width do
                throw InvalidFormatError{"invalid source buffer"}

            var dst = cast([*] u8) (notnull result.pixels.buffer) + cast(u64) y * result.width8 + cast(u64) x * 3
            for count
            {
                writePalettePixel(dst, palette, paletteEntrySize, value, paletteCount)
                dst += 3
            }
            x += count
            continue
        }

        switch value
        {
        case FILL_RLE_ENDOFLINE:
            x = 0
            y += 1

        case FILL_RLE_ENDOFBITMAP:
            return

        case FILL_RLE_DELTA:
            checkBuffer(p, last, 2)
            x += p[0]
            y += p[1]
            p += 2
            if x > result.width or y > result.height do
                throw InvalidFormatError{"invalid source buffer"}

        default:
            let absoluteCount = cast(u32) value
            let padding = absoluteCount & 1
            checkBuffer(p, last, absoluteCount + padding)
            if x + absoluteCount > result.width do
                throw InvalidFormatError{"invalid source buffer"}

            var dst = cast([*] u8) (notnull result.pixels.buffer) + cast(u64) y * result.width8 + cast(u64) x * 3
            for i in absoluteCount
            {
                writePalettePixel(dst, palette, paletteEntrySize, p[i], paletteCount)
                dst += 3
            }

            p += absoluteCount
            if padding do
                p += 1
            x     += absoluteCount
        }
    }
}

func rle4Index(value: u8, index: u32)->u32
{
    return cast(u32) ((index & 1) ? (value & 0x0F) : (value >> 4))
}

func decodeRle4(result: *Image, src, last: const [*] u8, palette: const [*] u8, paletteEntrySize, paletteCount: u32) throw
{
    var x: s32
    var y: s32
    var p = src

    while p < last and y < result.height
    {
        checkBuffer(p, last, 2)
        let count = p[0]
        let value = p[1]
        p += 2

        if count
        {
            if x + count > result.width do
                throw InvalidFormatError{"invalid source buffer"}

            var dst = cast([*] u8) (notnull result.pixels.buffer) + cast(u64) y * result.width8 + cast(u64) x * 3
            for i in count
            {
                writePalettePixel(dst, palette, paletteEntrySize, rle4Index(value, i), paletteCount)
                dst += 3
            }
            x += count
            continue
        }

        switch value
        {
        case FILL_RLE_ENDOFLINE:
            x = 0
            y += 1

        case FILL_RLE_ENDOFBITMAP:
            return

        case FILL_RLE_DELTA:
            checkBuffer(p, last, 2)
            x += p[0]
            y += p[1]
            p += 2
            if x > result.width or y > result.height do
                throw InvalidFormatError{"invalid source buffer"}

        default:
            let pixelCount = cast(u32) value
            let byteCount  = (pixelCount + 1) / 2
            let padding    = byteCount & 1
            checkBuffer(p, last, byteCount + padding)
            if x + pixelCount > result.width do
                throw InvalidFormatError{"invalid source buffer"}

            var dst = cast([*] u8) (notnull result.pixels.buffer) + cast(u64) y * result.width8 + cast(u64) x * 3
            for i in pixelCount
            {
                writePalettePixel(dst, palette, paletteEntrySize, rle4Index(p[i / 2], i), paletteCount)
                dst += 3
            }

            p += byteCount
            if padding do
                p += 1
            x     += pixelCount
        }
    }
}

public impl IImageDecoder for Decoder
{
    mtd impl canDecode(fileName: string)->bool
    {
        return Path.getExtensionLowerCase(fileName) == ".bmp"
    }

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image throw
    {
        var dataof  = @dataof(buffer)
        let countof = @countof(buffer)
        let last    = dataof + countof

        if countof < 4 do
            throw InvalidFormatError{"invalid source buffer"}

        // FileHeader
        var hasFileHeader: bool
        var bfOffBits:     u32
        if countof >= #sizeof(FileHeader)
        {
            let fh = cast(const *FileHeader) dataof
            if fh.bfType == BMP_SIGNATURE
            {
                hasFileHeader = true
                dataof        += #sizeof(FileHeader)
                bfOffBits     = fh.bfOffBits
                if fh.bfSize and fh.bfSize > countof do
                    throw InvalidFormatError{"invalid source buffer"}
                if fh.bfSize and fh.bfSize < bfOffBits do
                    throw InvalidFormatError{"invalid source buffer"}
                if bfOffBits > countof do
                    throw InvalidFormatError{"invalid source buffer"}
            }
        }

        checkBuffer(dataof, last, #sizeof(u32))
        let headerStart = dataof
        let size        = dref cast(const *u32) dataof
        if size < #sizeof(CoreHeader) do
            throw UnsupportedFormatError{"unsupported BMP header"}

        // DIB header
        var bh: Header
        var paletteEntrySize = 4'u32
        if size == #sizeof(CoreHeader)
        {
            checkBuffer(dataof, last, #sizeof(CoreHeader))
            let ch = cast(const *CoreHeader) dataof
            dataof           += #sizeof(CoreHeader)
            paletteEntrySize = 3

            bh.biSize        = ch.bcSize
            bh.biWidth       = cast(s32) ch.bcWidth
            bh.biHeight      = cast(s32) ch.bcHeight
            bh.biPlanes      = ch.bcPlanes
            bh.biBitCount    = ch.bcBitCount
            bh.biCompression = BI_RGB
        }
        else
        {
            if size < #sizeof(Header) do
                throw UnsupportedFormatError{"unsupported BMP header"}
            checkBuffer(dataof, last, size)

            Memory.copy(&bh, dataof, #sizeof(Header))
            dataof = headerStart + size
        }

        if bh.biPlanes != 1 do
            throw UnsupportedFormatError{"unsupported planes"}
        if bh.biWidth <= 0 or bh.biHeight == 0 or bh.biHeight == Swag.S32.Min do
            throw InvalidFormatError{"invalid dimensions"}

        let topDown = bh.biHeight < 0
        let height  = Math.abs(bh.biHeight)

        var masks = makeDefaultMasks(bh.biBitCount, bh.biCompression)
        if bh.biCompression == BI_BITFIELDS and (bh.biBitCount == 16 or bh.biBitCount == 32)
        {
            let maskPtr = headerStart + #sizeof(Header)
            if size >= 52
            {
                masks.r = readMask(dref cast(const *u32) maskPtr)
                masks.g = readMask(dref cast(const *u32) (maskPtr + 4))
                masks.b = readMask(dref cast(const *u32) (maskPtr + 8))
                if size >= 56 do
                    masks.a = readMask(dref cast(const *u32) (maskPtr + 12))
            }
            elif size == #sizeof(Header)
            {
                checkBuffer(dataof, last, 12)
                masks.r = readMask(dref cast(const *u32) dataof)
                masks.g = readMask(dref cast(const *u32) (dataof + 4))
                masks.b = readMask(dref cast(const *u32) (dataof + 8))
                dataof  += 12
            }
            else do
                throw InvalidFormatError{"invalid source buffer"}

            if !masks.r.value or !masks.g.value or !masks.b.value do
                throw InvalidFormatError{"invalid bit masks"}
        }

        // Create image
        var result: retval

        switch bh.biBitCount
        {
        case 1, 4, 8, 16, 24:
            result.init(bh.biWidth, height, PixelFormat.BGR8)
        case 32:
            result.init(bh.biWidth, height, PixelFormat.BGRA8)
        default:
            throw UnsupportedFormatError{"unsupported bit count"}
        }

        if bh.biCompression == BI_RLE8 and bh.biBitCount != 8 do
            throw UnsupportedFormatError{"unsupported compression"}
        if bh.biCompression == BI_RLE4 and bh.biBitCount != 4 do
            throw UnsupportedFormatError{"unsupported compression"}
        if bh.biCompression == BI_BITFIELDS and bh.biBitCount != 16 and bh.biBitCount != 24 and bh.biBitCount != 32 do
            throw UnsupportedFormatError{"unsupported compression"}
        if bh.biCompression != BI_RGB and bh.biCompression != BI_BITFIELDS and bh.biCompression != BI_RLE8 and bh.biCompression != BI_RLE4 do
            throw UnsupportedFormatError{"unsupported compression"}
        if topDown and (bh.biCompression == BI_RLE8 or bh.biCompression == BI_RLE4) do
            throw UnsupportedFormatError{"unsupported compression"}

        var paletteCount = bh.biClrUsed ? bh.biClrUsed : defaultPaletteCount(bh.biBitCount)
        let palette      = dataof
        if paletteCount
        {
            checkBuffer(palette, last, cast(u64) paletteCount * paletteEntrySize)
            dataof += cast(u64) paletteCount * paletteEntrySize
        }

        let pixelData = hasFileHeader and bfOffBits ? @dataof(buffer) + bfOffBits : dataof
        if pixelData < dataof do
            throw InvalidFormatError{"invalid source buffer"}

        if !options.decodePixels do
            return result
        result.allocPixels()

        // Decode
        dataof = pixelData

        if bh.biCompression == BI_RLE8
        {
            result.clear()
            decodeRle8(&result, dataof, last, palette, paletteEntrySize, paletteCount)
        }
        elif bh.biCompression == BI_RLE4
        {
            result.clear()
            decodeRle4(&result, dataof, last, palette, paletteEntrySize, paletteCount)
        }
        else
        {
            switch bh.biBitCount
            {
            case 1, 4, 8:
                decodePackedPalette(&result, dataof, last, palette, paletteEntrySize, paletteCount, bh.biBitCount, topDown)
            case 16:
                decode16(&result, dataof, last, masks, topDown)
            case 24, 32:
                decodeUncompressedDirect(&result, dataof, last, bh.biBitCount, topDown)
            }
        }

        return result
    }
}
