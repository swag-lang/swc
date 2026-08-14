#global namespace Bmp

using Core, Core.Errors

const FILL_RLE_COMMAND     = 0
const FILL_RLE_ENDOFLINE   = 0
const FILL_RLE_ENDOFBITMAP = 1
const FILL_RLE_DELTA       = 2

public const BI_RGB = 0           // Uncompressed RGB bitmap data.
public const BI_RLE8 = 1          // Run-length encoded 8-bit indexed data.
public const BI_RLE4 = 2          // Run-length encoded 4-bit indexed data.
public const BI_BITFIELDS = 3     // Direct-color data described by channel masks.

const BMP_SIGNATURE = 0x4D42'u16

// Represents the Windows `BITMAPINFOHEADER` binary layout.
//
// Fields retain the names and units defined by the BMP file format. The structure
// can also be used when exchanging DIB data with Windows APIs.
#[Swag.Pack(1)]
public struct Header
{
    public
    {
        biSize:          u32     // Size of this header in bytes.
        biWidth:         s32     // Bitmap width in pixels.
        biHeight:        s32     // Signed height; a negative value denotes top-down rows.
        biPlanes:        u16     // Number of color planes; valid BMP data uses `1`.
        biBitCount:      u16     // Bits stored for one pixel.
        biCompression:   u32     // Compression mode, such as `BI_RGB` or `BI_BITFIELDS`.
        biSizeImage:     u32     // Encoded pixel-data size in bytes, or zero when permitted by the format.
        biXPelsPerMeter: u32     // Preferred horizontal resolution in pixels per meter.
        biYPelsPerMeter: u32     // Preferred vertical resolution in pixels per meter.
        biClrUsed:       u32     // Number of palette entries used, or zero for the format default.
        biClrImportant:  u32     // Number of important palette entries, or zero when all are important.
    }
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

// Decodes Windows BMP/DIB images, including palettes, bitfields, and RLE data.
internal struct Decoder {}

func checkBuffer(ptr, last: const [*] u8, size: u64) fail
{
    if ptr + size > last do
        fail InvalidFormatError{"invalid source buffer"}
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

internal impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"BMP - Windows Bitmap", ".bmp"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        var dataof  = @dataof(buffer)
        let countof = @countof(buffer)
        let last    = dataof + countof

        if countof < 4 do
            fail InvalidFormatError{"invalid source buffer"}

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
                    fail InvalidFormatError{"invalid source buffer"}
                if fh.bfSize and fh.bfSize < bfOffBits do
                    fail InvalidFormatError{"invalid source buffer"}
                if bfOffBits > countof do
                    fail InvalidFormatError{"invalid source buffer"}
            }
        }

        checkBuffer(dataof, last, #sizeof(u32))
        let headerStart = dataof
        let size        = (cast(const *u32) dataof)[]
        if size < #sizeof(CoreHeader) do
            fail UnsupportedFormatError{"unsupported BMP header"}

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
                fail UnsupportedFormatError{"unsupported BMP header"}
            checkBuffer(dataof, last, size)

            Memory.copy(&bh, dataof, #sizeof(Header))
            dataof = headerStart + size
        }

        if bh.biPlanes != 1 do
            fail UnsupportedFormatError{"unsupported planes"}
        if bh.biWidth <= 0 or bh.biHeight == 0 or bh.biHeight == Swag.S32.Min do
            fail InvalidFormatError{"invalid dimensions"}

        let topDown = bh.biHeight < 0
        let height  = Math.abs(bh.biHeight)

        var masks = makeDefaultMasks(bh.biBitCount, bh.biCompression)
        if bh.biCompression == BI_BITFIELDS and (bh.biBitCount == 16 or bh.biBitCount == 32)
        {
            let maskPtr = headerStart + #sizeof(Header)
            if size >= 52
            {
                masks.r = readMask((cast(const *u32) maskPtr)[])
                masks.g = readMask((cast(const *u32) (maskPtr + 4))[])
                masks.b = readMask((cast(const *u32) (maskPtr + 8))[])
                if size >= 56 do
                    masks.a = readMask((cast(const *u32) (maskPtr + 12))[])
            }
            elif size == #sizeof(Header)
            {
                checkBuffer(dataof, last, 12)
                masks.r = readMask((cast(const *u32) dataof)[])
                masks.g = readMask((cast(const *u32) (dataof + 4))[])
                masks.b = readMask((cast(const *u32) (dataof + 8))[])
                dataof  += 12
            }
            else do
                fail InvalidFormatError{"invalid source buffer"}

            if !masks.r.value or !masks.g.value or !masks.b.value do
                fail InvalidFormatError{"invalid bit masks"}
        }

        // Create image
        var result: retval

        switch bh.biBitCount
        {
        case 1, 4, 8, 16, 24: result.init(bh.biWidth, height, PixelFormat.BGR8)
        case 32:              result.init(bh.biWidth, height, PixelFormat.BGRA8)
        default:              fail UnsupportedFormatError{"unsupported bit count"}
        }

        if bh.biCompression == BI_RLE8 and bh.biBitCount != 8 do
            fail UnsupportedFormatError{"unsupported compression"}
        if bh.biCompression == BI_RLE4 and bh.biBitCount != 4 do
            fail UnsupportedFormatError{"unsupported compression"}
        if bh.biCompression == BI_BITFIELDS and bh.biBitCount != 16 and bh.biBitCount != 24 and bh.biBitCount != 32 do
            fail UnsupportedFormatError{"unsupported compression"}
        if bh.biCompression != BI_RGB and bh.biCompression != BI_BITFIELDS and bh.biCompression != BI_RLE8 and bh.biCompression != BI_RLE4 do
            fail UnsupportedFormatError{"unsupported compression"}
        if topDown and (bh.biCompression == BI_RLE8 or bh.biCompression == BI_RLE4) do
            fail UnsupportedFormatError{"unsupported compression"}

        var paletteCount = bh.biClrUsed ? bh.biClrUsed : defaultPaletteCount(bh.biBitCount)
        let palette      = dataof
        if paletteCount
        {
            checkBuffer(palette, last, cast(u64) paletteCount * paletteEntrySize)
            dataof += cast(u64) paletteCount * paletteEntrySize
        }

        let pixelData = hasFileHeader and bfOffBits ? @dataof(buffer) + bfOffBits : dataof
        if pixelData < dataof do
            fail InvalidFormatError{"invalid source buffer"}

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
            case 1, 4, 8: decodePackedPalette(&result, dataof, last, palette, paletteEntrySize, paletteCount, bh.biBitCount, topDown)
            case 16:      decode16(&result, dataof, last, masks, topDown)
            case 24, 32:  decodeUncompressedDirect(&result, dataof, last, bh.biBitCount, topDown)
            }
        }

        return result
    }
}
