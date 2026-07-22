#global namespace Tiff
using Core, Core.Errors

// Baseline TIFF tags
const TAG_IMAGE_WIDTH       = 256
const TAG_IMAGE_LENGTH      = 257
const TAG_BITS_PER_SAMPLE   = 258
const TAG_COMPRESSION       = 259
const TAG_PHOTOMETRIC       = 262
const TAG_STRIP_OFFSETS     = 273
const TAG_SAMPLES_PER_PIXEL = 277
const TAG_ROWS_PER_STRIP    = 278
const TAG_STRIP_BYTE_COUNTS = 279
const TAG_PLANAR_CONFIG      = 284
const TAG_COLOR_MAP          = 320
const TAG_EXTRA_SAMPLES      = 338

// Field types
const TYPE_BYTE  = 1
const TYPE_SHORT = 3
const TYPE_LONG  = 4

// Compression schemes
const COMPRESSION_NONE     = 1
const COMPRESSION_PACKBITS = 32773

// Photometric interpretations
const PHOTO_WHITE_IS_ZERO = 0
const PHOTO_BLACK_IS_ZERO = 1
const PHOTO_RGB           = 2
const PHOTO_PALETTE       = 3

public struct Decoder {}

func checkBuffer(ptr, last: const [*] u8, size: u64) throw
{
    if ptr + size > last do
        throw InvalidFormatError{"invalid source buffer"}
}

func rd16(p: const [*] u8, le: bool)->u32
{
    if le do
        return cast(u32) p[0] | (cast(u32) p[1] << 8)
    return (cast(u32) p[0] << 8) | cast(u32) p[1]
}

func rd32(p: const [*] u8, le: bool)->u32
{
    if le do
        return cast(u32) p[0] | (cast(u32) p[1] << 8) | (cast(u32) p[2] << 16) | (cast(u32) p[3] << 24)
    return (cast(u32) p[0] << 24) | (cast(u32) p[1] << 16) | (cast(u32) p[2] << 8) | cast(u32) p[3]
}

func typeSize(type: u32)->u32
{
    switch type
    {
    case TYPE_BYTE:
        return 1
    case TYPE_SHORT:
        return 2
    case TYPE_LONG:
        return 4
    default:
        return 0
    }
}

struct Entry
{
    tag:     u32
    type:    u32
    count:   u32
    valoff:  u32     // raw value/offset field
    fieldAt: const [*] u8         // address of the 4-byte value/offset field
}

struct Ifd
{
    entries:  Array'Entry
}

impl Ifd
{
    mtd find(tag: u32)->#null *Entry
    {
        for i in .entries.count
        {
            if .entries[i].tag == tag do
                return &.entries[i]
        }
        return null
    }
}

// Read 'count' scalar values (BYTE/SHORT/LONG) of an entry into an array.
func readValues(base, last: const [*] u8, le: bool, e: *Entry)->Array'u32 throw
{
    var result: retval

    let ts = typeSize(e.type)
    if !ts do
        throw UnsupportedFormatError{"unsupported field type"}

    let totalBytes = cast(u64) e.count * ts
    var p: const [*] u8 = e.fieldAt
    if totalBytes > 4
    {
        p = base + e.valoff
        checkBuffer(p, last, totalBytes)
    }

    for i in e.count
    {
        let q = p + cast(u64) i * ts
        switch e.type
        {
        case TYPE_BYTE:
            result.add(cast(u32) q[0])
        case TYPE_SHORT:
            result.add(rd16(q, le))
        case TYPE_LONG:
            result.add(rd32(q, le))
        }
    }

    return result
}

func readScalar(base, last: const [*] u8, le: bool, ifd: *Ifd, tag: u32, defValue: u32)->u32 throw
{
    let e = ifd.find(tag)
    if !e do
        return defValue
    let values = try readValues(base, last, le, cast(*Entry) (e))
    if !values.count do
        return defValue
    return values[0]
}

// PackBits run-length decoder. Decodes up to 'expected' bytes into 'dst'.
func unpackBits(dst: [*] u8, expected: u64, src, last: const [*] u8) throw
{
    var out: u64
    var p = src
    while out < expected
    {
        if p >= last do
            throw InvalidFormatError{"invalid source buffer"}
        let header = cast(s32) cast #bit (s8) p[0]
        p += 1

        if header >= 0
        {
            let count = cast(u64) (header + 1)
            if out + count > expected do
                throw InvalidFormatError{"invalid source buffer"}
            checkBuffer(p, last, count)
            Memory.copy(dst + out, p, count)
            p += count
            out += count
        }
        elif header != -128
        {
            let count = cast(u64) (1 - header)
            if out + count > expected do
                throw InvalidFormatError{"invalid source buffer"}
            checkBuffer(p, last, 1)
            let value = p[0]
            p += 1
            for count do
                dst[out + @index] = value
            out += count
        }
    }
}

public impl IImageDecoder for Decoder
{
    mtd impl canDecode(fileName: string)->bool
    {
        let ext = Path.getExtensionLowerCase(fileName)
        return ext == ".tif" or ext == ".tiff"
    }

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image throw
    {
        let base    = @dataof(buffer)
        let countof = @countof(buffer)
        let last    = base + countof

        if countof < 8 do
            throw InvalidFormatError{"invalid source buffer"}

        // Byte order
        var le: bool
        if base[0] == 0x49 and base[1] == 0x49 do
            le = true
        elif base[0] == 0x4D and base[1] == 0x4D do
            le = false
        else do
            throw InvalidFormatError{"not a tiff"}

        if rd16(base + 2, le) != 42 do
            throw InvalidFormatError{"not a tiff"}

        let ifdOffset = rd32(base + 4, le)
        if cast(u64) ifdOffset + 2 > countof do
            throw InvalidFormatError{"invalid source buffer"}

        // Parse the first IFD
        var ifd: Ifd
        let numEntries = rd16(base + ifdOffset, le)
        checkBuffer(base + ifdOffset, last, cast(u64) 2 + cast(u64) numEntries * 12)
        for i in numEntries
        {
            let ep = base + ifdOffset + 2 + cast(u64) i * 12
            var e: Entry = undefined
            e.tag     = rd16(ep, le)
            e.type    = rd16(ep + 2, le)
            e.count   = rd32(ep + 4, le)
            e.valoff  = rd32(ep + 8, le)
            e.fieldAt = ep + 8
            ifd.entries.add(e)
        }

        let width  = readScalar(base, last, le, &ifd, TAG_IMAGE_WIDTH, 0)
        let height = readScalar(base, last, le, &ifd, TAG_IMAGE_LENGTH, 0)
        if width == 0 or height == 0 do
            throw InvalidFormatError{"invalid dimensions"}
        if width > Swag.S32.Max or height > Swag.S32.Max do
            throw UnsupportedFormatError{"image is too big"}

        let compression   = readScalar(base, last, le, &ifd, TAG_COMPRESSION, COMPRESSION_NONE)
        let photometric   = readScalar(base, last, le, &ifd, TAG_PHOTOMETRIC, PHOTO_BLACK_IS_ZERO)
        let samples       = readScalar(base, last, le, &ifd, TAG_SAMPLES_PER_PIXEL, 1)
        let planar        = readScalar(base, last, le, &ifd, TAG_PLANAR_CONFIG, 1)
        var rowsPerStrip  = readScalar(base, last, le, &ifd, TAG_ROWS_PER_STRIP, height)

        if compression != COMPRESSION_NONE and compression != COMPRESSION_PACKBITS do
            throw UnsupportedFormatError{"unsupported compression"}
        if planar != 1 do
            throw UnsupportedFormatError{"unsupported planar configuration"}
        if samples != 1 and samples != 3 and samples != 4 do
            throw UnsupportedFormatError{"unsupported samples per pixel"}
        if rowsPerStrip == 0 do
            rowsPerStrip = height

        // Bits per sample - baseline 8-bit only
        let bpsEntry = ifd.find(TAG_BITS_PER_SAMPLE)
        if bpsEntry
        {
            let bps = try readValues(base, last, le, cast(*Entry) (bpsEntry))
            for b in bps
            {
                if b != 8 do
                    throw UnsupportedFormatError{"unsupported bit depth"}
            }
        }

        // Determine output pixel format
        var pf: PixelFormat
        if samples == 1
        {
            if photometric != PHOTO_WHITE_IS_ZERO and photometric != PHOTO_BLACK_IS_ZERO and photometric != PHOTO_PALETTE do
                throw UnsupportedFormatError{"unsupported photometric"}
            // Palette images carry real colors (RGB8); grayscale replicates a
            // single channel and is tagged BGR8 like the other decoders.
            pf = photometric == PHOTO_PALETTE ? PixelFormat.RGB8 : PixelFormat.BGR8
        }
        elif samples == 3
        {
            pf = .RGB8
        }
        else
        {
            pf = .RGBA8
        }

        var result: retval
        result.init(cast(s32) width, cast(s32) height, pf)

        if !options.decodePixels do
            return result

        // Palette (for photometric=palette)
        var palette: Array'u32       // packed 0x00RRGGBB
        if samples == 1 and photometric == PHOTO_PALETTE
        {
            let cmEntry = ifd.find(TAG_COLOR_MAP)
            if !cmEntry do
                throw InvalidFormatError{"missing color map"}
            let cm = try readValues(base, last, le, cast(*Entry) (cmEntry))
            let entries = cm.count / 3
            for i in entries
            {
                let r = cast(u32) (cm[i] >> 8)
                let g = cast(u32) (cm[entries + i] >> 8)
                let b = cast(u32) (cm[2 * entries + i] >> 8)
                palette.add((r << 16) | (g << 8) | b)
            }
        }

        // Strips
        let stripOffEntry = ifd.find(TAG_STRIP_OFFSETS)
        let stripCntEntry = ifd.find(TAG_STRIP_BYTE_COUNTS)
        if !stripOffEntry or !stripCntEntry do
            throw InvalidFormatError{"missing strip data"}
        let stripOffsets = try readValues(base, last, le, cast(*Entry) (stripOffEntry))
        let stripCounts  = try readValues(base, last, le, cast(*Entry) (stripCntEntry))
        if stripOffsets.count != stripCounts.count or !stripOffsets.count do
            throw InvalidFormatError{"invalid strip data"}

        let rowBytes  = cast(u64) width * samples
        let totalRows = height

        // Decode all strips into a top-down byte buffer
        var decoded: Array'u8
        decoded.resize(rowBytes * cast(u64) totalRows)

        var rowStart: u32
        for s in stripOffsets.count
        {
            if rowStart >= totalRows do
                break

            var rowsInStrip = rowsPerStrip
            if rowStart + rowsInStrip > totalRows do
                rowsInStrip = totalRows - rowStart

            let stripBytes = rowBytes * cast(u64) rowsInStrip
            let srcOff     = stripOffsets[s]
            let srcCount   = cast(u64) stripCounts[s]
            let srcPtr     = base + srcOff
            checkBuffer(srcPtr, last, srcCount)

            let dstPtr = (notnull decoded.buffer) + cast(u64) rowStart * rowBytes

            if compression == COMPRESSION_PACKBITS
            {
                unpackBits(dstPtr, stripBytes, srcPtr, srcPtr + srcCount)
            }
            else
            {
                if srcCount < stripBytes do
                    throw InvalidFormatError{"invalid source buffer"}
                Memory.copy(dstPtr, srcPtr, stripBytes)
            }

            rowStart += rowsInStrip
        }

        result.allocPixels()

        // Convert top-down 'decoded' into the bottom-up result buffer
        for y in cast(s32) height
        {
            let srcRow = decoded.buffer + cast(u64) y * rowBytes
            let dstY   = result.height - y - 1
            var dst    = cast([*] u8) (notnull result.pixels.buffer) + cast(u64) dstY * result.width8

            for x in cast(s32) width
            {
                if samples == 1
                {
                    if photometric == PHOTO_PALETTE
                    {
                        let index = cast(u32) srcRow[x]
                        if index >= palette.count do
                            throw InvalidFormatError{"invalid palette index"}
                        let argb = palette[index]
                        dst[0] = cast(u8) ((argb >> 16) & 0xFF)
                        dst[1] = cast(u8) ((argb >> 8) & 0xFF)
                        dst[2] = cast(u8) (argb & 0xFF)
                    }
                    else
                    {
                        var v = srcRow[x]
                        if photometric == PHOTO_WHITE_IS_ZERO do
                            v = 255 - v
                        dst[0] = v
                        dst[1] = v
                        dst[2] = v
                    }
                    dst += 3
                }
                elif samples == 3
                {
                    let pix = srcRow + cast(u64) x * 3
                    dst[0] = pix[0]
                    dst[1] = pix[1]
                    dst[2] = pix[2]
                    dst += 3
                }
                else
                {
                    let pix = srcRow + cast(u64) x * 4
                    dst[0] = pix[0]
                    dst[1] = pix[1]
                    dst[2] = pix[2]
                    dst[3] = pix[3]
                    dst += 4
                }
            }
        }

        return result
    }
}
