#global namespace Ico
using Core, Core.Errors

// ICONDIR (6 bytes)
#[Swag.Pack(1)]
struct IconDir
{
    reserved:     u16
    type:         u16
    count:        u16
}

// ICONDIRENTRY (16 bytes)
#[Swag.Pack(1)]
struct IconDirEntry
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

// BITMAPINFOHEADER (40 bytes) embedded in an icon entry
#[Swag.Pack(1)]
struct DibHeader
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

public struct Decoder {}

func checkBuffer(ptr, last: const [*] u8, size: u64) throw
{
    if ptr + size > last do
        throw InvalidFormatError{"invalid source buffer"}
}

// Width/height of 0 in a directory entry means 256
func dimFromByte(value: u8)->s32
{
    return value == 0 ? 256 : cast(s32) value
}

func isPngSignature(p: const [*] u8, size: u64)->bool
{
    if size < 8 do
        return false
    return p[0] == 0x89 and p[1] == 0x50 and p[2] == 0x4E and p[3] == 0x47 and
           p[4] == 0x0D and p[5] == 0x0A and p[6] == 0x1A and p[7] == 0x0A
}

func rowStride32(widthBits: u64)->u64
{
    return ((widthBits + 31) / 32) * 4
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

func maskBit(andRow: const [*] u8, x: s32)->u32
{
    return cast(u32) ((andRow[x / 8] >> cast(u32) (7 - (x & 7))) & 1)
}

// Decode the embedded BITMAPINFOHEADER icon image into a BGRA8 result.
func decodeDib(result: *Image, dib: DibHeader, src, last: const [*] u8) throw
{
    if dib.bitCount != 1 and dib.bitCount != 4 and dib.bitCount != 8 and dib.bitCount != 24 and dib.bitCount != 32 do
        throw UnsupportedFormatError{"unsupported icon bit count"}
    if dib.compression != 0 do
        throw UnsupportedFormatError{"unsupported icon compression"}

    let width  = result.width
    let height = result.height

    // Palette (for indexed images): one BGRA quad per entry
    var paletteCount = dib.clrUsed
    if !paletteCount and dib.bitCount <= 8 do
        paletteCount = 1'u32 << cast(u32) dib.bitCount

    let palette = src
    var dataof  = src
    if paletteCount
    {
        checkBuffer(palette, last, cast(u64) paletteCount * 4)
        dataof += cast(u64) paletteCount * 4
    }

    let xorStride = rowStride32(cast(u64) width * dib.bitCount)
    let andStride = rowStride32(cast(u64) width)
    let xorData   = dataof
    let andData   = dataof + xorStride * cast(u64) height

    checkBuffer(xorData, last, xorStride * cast(u64) height)
    // The AND mask is optional for 32-bit images that carry their own alpha
    let hasAndMask = andData + andStride * cast(u64) height <= last

    // Icon pixel data is bottom-up, matching the internal buffer convention
    for y in height
    {
        let xorRow = xorData + xorStride * cast(u64) y
        let andRow = andData + andStride * cast(u64) y
        var dst    = cast([*] u8) (assume result.pixels.buffer) + cast(u64) y * result.width8

        for x in width
        {
            var b, g, r, a: u8

            switch dib.bitCount
            {
            case 32:
                let pix = xorRow + cast(u64) x * 4
                b = pix[0]
                g = pix[1]
                r = pix[2]
                a = pix[3]

            case 24:
                let pix = xorRow + cast(u64) x * 3
                b = pix[0]
                g = pix[1]
                r = pix[2]
                a = hasAndMask and maskBit(andRow, x) ? 0'u8 : 255'u8

            default:
                let index = packedIndex(xorRow, dib.bitCount, x)
                if index >= paletteCount do
                    throw InvalidFormatError{"invalid palette index"}
                let entry = palette + cast(u64) index * 4
                b = entry[0]
                g = entry[1]
                r = entry[2]
                a = hasAndMask and maskBit(andRow, x) ? 0'u8 : 255'u8
            }

            dst[0] = b
            dst[1] = g
            dst[2] = r
            dst[3] = a
            dst += 4
        }
    }
}

public impl IImageDecoder for Decoder
{
    mtd impl canDecode(fileName: string)->bool
    {
        let ext = Path.getExtensionLowerCase(fileName)
        return ext == ".ico" or ext == ".cur"
    }

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image throw
    {
        let base    = @dataof(buffer)
        let countof = @countof(buffer)
        let last    = base + countof

        if countof < #sizeof(IconDir) do
            throw InvalidFormatError{"invalid source buffer"}

        let dir = dref cast(const *IconDir) base
        if dir.type != 1 and dir.type != 2 do
            throw InvalidFormatError{"not an icon"}
        if dir.count == 0 do
            throw InvalidFormatError{"empty icon"}

        checkBuffer(base, last, cast(u64) #sizeof(IconDir) + cast(u64) dir.count * #sizeof(IconDirEntry))

        // Select the best image: largest area, tie-break on bit depth
        var bestEntry:  IconDirEntry
        var bestScore:  u64
        var found:      bool
        for i in dir.count
        {
            let entry = dref cast(const *IconDirEntry) (base + #sizeof(IconDir) + cast(u64) i * #sizeof(IconDirEntry))
            let area  = cast(u64) dimFromByte(entry.width) * cast(u64) dimFromByte(entry.height)
            let score = (area << 16) + entry.bitCount
            if !found or score > bestScore
            {
                bestScore = score
                bestEntry = entry
                found     = true
            }
        }

        if cast(u64) bestEntry.imageOffset + bestEntry.bytesInRes > countof do
            throw InvalidFormatError{"invalid source buffer"}

        let imgPtr = base + bestEntry.imageOffset
        let imgLen = cast(u64) bestEntry.bytesInRes

        // PNG-compressed entry: delegate to the PNG decoder
        if isPngSignature(imgPtr, imgLen)
        {
            var pngDec: Png.Decoder
            let itf = @mkinterface(&pngDec, #typeof(Png.Decoder), IImageDecoder)
            return try itf.decode(@mkslice(imgPtr, imgLen), options)
        }

        // BMP/DIB-encoded entry
        if imgLen < #sizeof(DibHeader) do
            throw InvalidFormatError{"invalid source buffer"}

        let dib = dref cast(const *DibHeader) imgPtr
        if dib.size < #sizeof(DibHeader) do
            throw UnsupportedFormatError{"unsupported icon header"}
        if dib.width <= 0 or dib.height <= 0 or (dib.height & 1) do
            throw InvalidFormatError{"invalid dimensions"}

        var result: retval
        result.init(dib.width, dib.height / 2, PixelFormat.BGRA8)

        if !options.decodePixels do
            return result

        result.allocPixels()
        decodeDib(&result, dib, imgPtr + dib.size, last)
        return result
    }
}
