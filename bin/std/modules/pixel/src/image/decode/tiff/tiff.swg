//! Format: Tagged Image File Format (TIFF) decoder component.
//! Supported: 8-bit chunky grayscale, palette, RGB, and RGBA strips using no compression, PackBits, or LZW with predictors.
//! Not supported: Planar samples, tiled images, JPEG/Deflate compression, and sample depths other than 8-bit.
//! Role: This file owns IFD and strip parsing, sample expansion, and top-level decoding.
//
#global namespace Tiff

using Core, Core.Errors

// Baseline TIFF tags
const TAG_IMAGE_WIDTH       = 256
const TAG_IMAGE_LENGTH      = 257
const TAG_BITS_PER_SAMPLE   = 258
const TAG_COMPRESSION       = 259
const TAG_PHOTOMETRIC       = 262
const TAG_STRIP_OFFSETS     = 273
const TAG_ORIENTATION       = 274
const TAG_SAMPLES_PER_PIXEL = 277
const TAG_ROWS_PER_STRIP    = 278
const TAG_STRIP_BYTE_COUNTS = 279
const TAG_PLANAR_CONFIG     = 284
const TAG_PREDICTOR         = 317
const TAG_COLOR_MAP         = 320
const TAG_EXTRA_SAMPLES     = 338

// Field types
const TYPE_BYTE  = 1
const TYPE_SHORT = 3
const TYPE_LONG  = 4

// Compression schemes
const COMPRESSION_NONE     = 1
const COMPRESSION_LZW      = 5
const COMPRESSION_PACKBITS = 32773

// Photometric interpretations
const PHOTO_WHITE_IS_ZERO = 0
const PHOTO_BLACK_IS_ZERO = 1
const PHOTO_RGB           = 2
const PHOTO_PALETTE       = 3

// Decodes baseline TIFF images with uncompressed, PackBits, or LZW strips.
internal struct Decoder
{
    bytes:       const [..] u8?
    directories: Array'u32
}

func checkBuffer(ptr, last: const [*] u8, size: u64) fail
{
    if ptr + size > last do
        fail InvalidFormatError{"invalid source buffer"}
}

func rd16(p: const [*] u8, le: bool)->u32
{
    if le do
        return cast(u32, p[0]) | (cast(u32, p[1]) << 8)
    return (cast(u32, p[0]) << 8) | cast(u32, p[1])
}

func rd32(p: const [*] u8, le: bool)->u32
{
    if le do
        return cast(u32, p[0]) | (cast(u32, p[1]) << 8) | (cast(u32, p[2]) << 16) | (cast(u32, p[3]) << 24)
    return (cast(u32, p[0]) << 24) | (cast(u32, p[1]) << 16) | (cast(u32, p[2]) << 8) | cast(u32, p[3])
}

func typeSize(type: u32)->u32
{
    switch type
    {
    case TYPE_BYTE:  return 1
    case TYPE_SHORT: return 2
    case TYPE_LONG:  return 4
    default:         return 0
    }
}

private struct Entry
{
    type:    u32
    count:   u32
    valoff:  u32
    fieldAt: const [*] u8     // address of the 4-byte value/offset field
}

private func readEntry(p: const [*] u8, le: bool)->Entry
{
    return {rd16(p + 2, le), rd32(p + 4, le), rd32(p + 8, le), p + 8}
}

private struct Ifd
{
    fields: [TAG_EXTRA_SAMPLES - TAG_IMAGE_WIDTH + 1] (const [*] u8?)
}

private impl Ifd
{
    mtd const find(tag: u32)->const [*] u8? => .fields[tag - TAG_IMAGE_WIDTH]
}

private struct Values
{
    data:  const [*] u8
    count: u32
    type:  u32
    le:    bool
}

private impl Values
{
    #[Swag.Inline]
    mtd const read(index: u64)->u32
    {
        switch .type
        {
        case TYPE_BYTE:  return .data[index]
        case TYPE_SHORT: return rd16(.data + index * 2, .le)
        default:         return rd32(.data + index * 4, .le)
        }
    }
}

private func readValues(base, last, field: const [*] u8, le: bool)->Values fail
{
    let entry = readEntry(field, le)
    let size  = typeSize(entry.type)
    if not size do
        fail UnsupportedFormatError{"unsupported field type"}

    // Validate the complete field even if the caller needs only its first value.
    let bytes = cast(u64, entry.count) * size
    var data  = entry.fieldAt
    if bytes > 4
    {
        data = base + entry.valoff
        try checkBuffer(data, last, bytes)
    }

    return {data, entry.count, entry.type, le}
}

private func readScalar(base, last: const [*] u8, le: bool, ifd: const *Ifd, tag: u32, defValue: u32)->u32 fail
{
    let field = ifd.find(tag)
    if not field do
        return defValue
    let values = try readValues(base, last, field, le)
    return values.count ? values.read(0) : defValue
}

// Decodes literal and repeated PackBits packets. For bottom-up output, packets
// that cross a source row are split between the corresponding destination rows.
private func(REVERSE_ROWS: bool, SHORT_RUNS: bool) unpackBitsRows(dst: [*] u8, expected: u64, src, last: const [*] u8, rowBytes: u64) fail
{
    var remaining    = expected
    var row          = dst
    var rowRemaining = rowBytes
    var p            = src
    while remaining
    {
        if p >= last do
            fail InvalidFormatError{"invalid source buffer"}
        let header = cast(s32, cast #bit(s8, p[0]))
        p += 1
        if header == -128 do
            continue

        let literal     = header >= 0
        let count       = cast(u64, (literal ? header + 1 : 1 - header))
        let sourceBytes = literal ? count : 1'u64
        if count > remaining or p + sourceBytes > last do
            fail InvalidFormatError{"invalid source buffer"}

        #static if REVERSE_ROWS
        {
            var copied = 0'u64
            while copied < count
            {
                let size   = Math.min(count - copied, rowRemaining)
                let target = row + (rowBytes - rowRemaining)
                if literal do
                    Memory.copy(target, p + copied, size)
                else do
                    Memory.set(target, p[0], size)

                copied       += size
                remaining    -= size
                rowRemaining -= size
                if not rowRemaining and remaining
                {
                    row -= rowBytes
                    rowRemaining = rowBytes
                }
            }
        }
        else
        {
            if literal
            {
                Memory.copy(row, p, count)
            }
            elif SHORT_RUNS and count <= 8 and remaining >= 8
            {
                // Later packets overwrite the extra bytes inside this strip.
                cast(*u64, row)[] = cast(u64, p[0]) * 0x0101_0101_0101_0101'u64
            }
            else
            {
                Memory.set(row, p[0], count)
            }

            row       += count
            remaining -= count
        }

        p += sourceBytes
    }
}

func unpackBits(dst: [*] u8, expected: u64, src, last: const [*] u8, reverseRowBytes: u64 = 0) fail
{
    // Short repeats store two to eight output bytes in two source bytes.
    // Use the word fill when those packets could dominate the strip.
    let compressed = cast(u64, (last - src))
    if reverseRowBytes do
        try unpackBitsRows'(true, false)(dst, expected, src, last, reverseRowBytes)
    elif compressed < expected and compressed >= expected / 4 do
        try unpackBitsRows'(false, true)(dst, expected, src, last, expected)
    else do
        try unpackBitsRows'(false, false)(dst, expected, src, last, expected)
}

// Expands grayscale while the samples are still in registers. The predictor carries
// the last reconstructed sample at each block boundary and restarts at every row.
private func expandGrayRow(source: const [*] u8, destination: [*] u8, count: u64, grayMask: u8, predicted: bool)
{
    const Shift1 = cast(Math.Simd.U8x16, [128'u8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])
    const Shift2 = cast(Math.Simd.U8x16, [128'u8, 128, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
    const Shift4 = cast(Math.Simd.U8x16, [128'u8, 128, 128, 128, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
    const Shift8 = cast(Math.Simd.U8x16, [128'u8, 128, 128, 128, 128, 128, 128, 128, 0, 1, 2, 3, 4, 5, 6, 7])

    const Triplets0 = cast(Math.Simd.U8x16, [0'u8, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5])
    const Triplets1 = cast(Math.Simd.U8x16, [5'u8, 5, 6, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9, 10, 10])
    const Triplets2 = cast(Math.Simd.U8x16, [10'u8, 11, 11, 11, 12, 12, 12, 13, 13, 13, 14, 14, 14, 15, 15, 15])

    let invert = Math.Simd.splat(grayMask)
    var carry  = Math.Simd.splat(0'u8)
    var offset = 0'u64
    while count - offset >= 16
    {
        var samples = Math.Simd.load(source + offset)
        if predicted
        {
            samples += Math.Simd.shuffle(samples, Shift1)
            samples += Math.Simd.shuffle(samples, Shift2)
            samples += Math.Simd.shuffle(samples, Shift4)
            samples += Math.Simd.shuffle(samples, Shift8)
            samples += carry
            carry   = Math.Simd.shuffle(samples, Math.Simd.splat(15'u8))
        }

        let pixels = samples ^ invert
        let target = destination + offset * 3
        Math.Simd.store(target, Math.Simd.shuffle(pixels, Triplets0))
        Math.Simd.store(target + 16, Math.Simd.shuffle(pixels, Triplets1))
        Math.Simd.store(target + 32, Math.Simd.shuffle(pixels, Triplets2))
        offset += 16
    }

    var previous = carry[0]
    while offset < count
    {
        var sample = source[offset]
        if predicted
        {
            sample   += #wrap previous
            previous = sample
        }

        let gray   = sample ^ grayMask
        let target = destination + offset * 3
        target[0], target[1], target[2] = gray
        offset += 1
    }
}

private func expandPaletteRow(source: const [*] u8, destination: [*] u8, count: u64, palette: const [..] u32) fail
{
    if palette.count < 256
    {
        for i in count where source[i] >= palette.count do
            fail InvalidFormatError{"invalid palette index"}
    }

    let colors = palette.buffer
    var src    = source
    var dst    = destination
    var left   = count
    while left >= 5
    {
        let first = cast(u64, colors[src[0]]) | (cast(u64, colors[src[1]]) << 24)
        let last  = cast(u64, colors[src[2]]) | (cast(u64, colors[src[3]]) << 24)

        // Each overlapping store stays inside the output row.
        cast(*u64, dst)[]       = first
        cast(*u64, (dst + 6))[] = last
        src                     += 4
        dst                     += 12
        left                    -= 4
    }

    for i in left - 1 do
        cast(*u32, (dst + 3 * i))[] = colors[src[i]]
    let last = colors[src[left - 1]]
    let tail = dst + 3 * (left - 1)
    cast(*u16, tail)[] = cast(u16, (last & 0xFFFF))
    tail[2] = cast(u8, (last >> 16))
}

// Each strip has its own compression state and maps to a disjoint row range.
private struct StripReader
{
    base, last:   const [*] u8
    destination:  [*] u8
    offsets:      Values
    counts:       Values
    palette:      const [..] u32
    width:        u32
    height:       u32
    samples:      u32
    rowStride:    u64
    rowsPerStrip: u32
    compression:  u32
    predictor:    u32
    photometric:  u32
}

private impl StripReader
{
    mtd const decodeRange(first, end: u64) fail
    {
        let rowBytes = cast(u64, .width) * .samples
        let samples  = .samples
        let grayMask = .photometric == PHOTO_WHITE_IS_ZERO ? 255'u8 : 0'u8
        let palette  = .photometric == PHOTO_PALETTE

        // Borrow raw strips directly. Only compression or the predictor needs writable scratch.
        var decoded:       Array'u8
        var lzwDictionary: Array'u64
        var rowStart = cast(u32, first * .rowsPerStrip)
        for s in first until end
        {
            let rowsInStrip = Math.min(.rowsPerStrip, .height - rowStart)
            let stripBytes  = rowBytes * rowsInStrip
            let srcCount    = .counts.read(s)
            let srcPtr      = .base + .offsets.read(s)
            try checkBuffer(srcPtr, .last, srcCount)
            if .compression == COMPRESSION_NONE and srcCount < stripBytes do
                fail InvalidFormatError{"invalid source buffer"}

            // True-color PackBits can write directly to the bottom-up output rows.
            if .compression == COMPRESSION_PACKBITS and samples != 1 and .predictor == 1
            {
                let firstRow = .destination + cast(u64, .height - rowStart - 1) * .rowStride
                try unpackBits(firstRow, stripBytes, srcPtr, srcPtr + srcCount, rowBytes)
                rowStart += rowsInStrip
                continue
            }

            var strip = srcPtr
            if .compression != COMPRESSION_NONE or (.predictor == 2 and palette)
            {
                decoded.reserve(stripBytes)
                let scratch = decoded.storage()
                switch .compression
                {
                case COMPRESSION_LZW:      try unpackLzw(scratch, stripBytes, srcPtr, srcCount, &lzwDictionary)
                case COMPRESSION_PACKBITS: try unpackBits(scratch, stripBytes, srcPtr, srcPtr + srcCount)
                default: Memory.copy(scratch, srcPtr, stripBytes)
                }

                strip = scratch
            }

            // Convert file order to the bottom-up image layout while the strip is current.
            for y in rowsInStrip
            {
                let offset = cast(u64, y) * rowBytes
                if .predictor == 2 and palette
                {
                    let row = decoded.storage() + offset
                    PackedPixel.restoreHorizontalDeltas(row, row, rowBytes, 1)
                }

                let source = strip + offset
                let dstY   = .height - rowStart - y - 1
                var dst    = .destination + cast(u64, dstY) * .rowStride
                if samples != 1
                {
                    if .predictor == 2 do
                        PackedPixel.restoreHorizontalDeltas(source, dst, rowBytes, samples)
                    else do
                        Memory.copy(dst, source, rowBytes)
                }
                elif palette
                {
                    try expandPaletteRow(source, dst, rowBytes, .palette)
                }
                else
                {
                    expandGrayRow(source, dst, rowBytes, grayMask, .predictor == 2)
                }
            }

            rowStart += rowsInStrip
        }
    }
}

impl Decoder
{
    mtd decodePage(buffer: const [..] u8, options: DecodeOptions, directory: u32 = 0)->Image fail
    {
        let base    = buffer.buffer
        let countof = buffer.count
        let last    = base + countof

        if countof < 8 do
            fail InvalidFormatError{"invalid source buffer"}

        // Byte order
        var le: bool
        if base[0] == 0x49 and base[1] == 0x49 do
            le = true
        elif base[0] == 0x4D and base[1] == 0x4D do
            le = false
        else do
            fail InvalidFormatError{"not a tiff"}

        if rd16(base + 2, le) != 42 do
            fail InvalidFormatError{"not a tiff"}

        let ifdOffset = directory ? directory : rd32(base + 4, le)
        if cast(u64, ifdOffset) + 2 > countof do
            fail InvalidFormatError{"invalid source buffer"}

        // Index the field addresses in one pass. Keep the first value of a
        // duplicate tag, including in files with unordered directories.
        var ifd: Ifd
        let numEntries = rd16(base + ifdOffset, le)
        try checkBuffer(base + ifdOffset, last, 2'u64 + cast(u64, numEntries) * 12)
        var field = base + ifdOffset + 2
        for numEntries
        {
            let tag = rd16(field, le)
            if tag >= TAG_IMAGE_WIDTH and tag <= TAG_EXTRA_SAMPLES
            {
                let index = tag - TAG_IMAGE_WIDTH
                if not ifd.fields[index] do
                    ifd.fields[index] = field
            }

            field += 12
        }

        let width  = try readScalar(base, last, le, &ifd, TAG_IMAGE_WIDTH, 0)
        let height = try readScalar(base, last, le, &ifd, TAG_IMAGE_LENGTH, 0)
        if width == 0 or height == 0 do
            fail InvalidFormatError{"invalid dimensions"}
        if width > Swag.S32.Max or height > Swag.S32.Max do
            fail UnsupportedFormatError{"image is too big"}

        let compression      = try readScalar(base, last, le, &ifd, TAG_COMPRESSION, COMPRESSION_NONE)
        let photometric      = try readScalar(base, last, le, &ifd, TAG_PHOTOMETRIC, PHOTO_BLACK_IS_ZERO)
        var orientation      = 1'u32
        let orientationEntry = ifd.find(TAG_ORIENTATION)
        if orientationEntry
        {
            let entry = readEntry(orientationEntry, le)
            if entry.type != TYPE_SHORT or entry.count != 1 do
                fail InvalidFormatError{"TIFF orientation entry is invalid"}
            orientation = rd16(entry.fieldAt, le)
            if orientation < 1 or orientation > 8 do
                fail InvalidFormatError{"TIFF orientation value is out of range"}
        }

        let samples      = try readScalar(base, last, le, &ifd, TAG_SAMPLES_PER_PIXEL, 1)
        let planar       = try readScalar(base, last, le, &ifd, TAG_PLANAR_CONFIG, 1)
        let predictor    = try readScalar(base, last, le, &ifd, TAG_PREDICTOR, 1)
        var rowsPerStrip = try readScalar(base, last, le, &ifd, TAG_ROWS_PER_STRIP, height)

        if compression != COMPRESSION_NONE and
           compression != COMPRESSION_LZW and
           compression != COMPRESSION_PACKBITS do
            fail UnsupportedFormatError{"unsupported compression"}
        if planar != 1 do
            fail UnsupportedFormatError{"unsupported planar configuration"}
        if predictor != 1 and predictor != 2 do
            fail UnsupportedFormatError{"unsupported predictor"}
        if samples != 1 and samples != 3 and samples != 4 do
            fail UnsupportedFormatError{"unsupported samples per pixel"}
        if rowsPerStrip == 0 do
            rowsPerStrip = height

        // Bits per sample - baseline 8-bit only
        let bpsEntry = ifd.find(TAG_BITS_PER_SAMPLE)
        if not bpsEntry do
            fail UnsupportedFormatError{"TIFF default bit depth is not supported"}
        let bps = try readValues(base, last, bpsEntry, le)
        if bps.count != samples do
            fail InvalidFormatError{"TIFF bits per sample count differs from samples per pixel"}
        for i in bps.count where bps.read(i) != 8 do
            fail UnsupportedFormatError{"unsupported bit depth"}

        // Determine output pixel format
        var pf: PixelFormat
        if samples == 1
        {
            if photometric != PHOTO_WHITE_IS_ZERO and
               photometric != PHOTO_BLACK_IS_ZERO and
               photometric != PHOTO_PALETTE do
                fail UnsupportedFormatError{"unsupported photometric"}

            // Palette images carry real colors (RGB8); grayscale replicates a
            // single channel and is tagged BGR8 like the other decoders.
            pf = photometric == PHOTO_PALETTE ? PixelFormat.RGB8 : PixelFormat.BGR8
        }
        elif samples == 3
        {
            if photometric != PHOTO_RGB do
                fail UnsupportedFormatError{"unsupported photometric for RGB image"}
            pf = .RGB8
        }
        else
        {
            if photometric != PHOTO_RGB do
                fail UnsupportedFormatError{"unsupported photometric for RGBA image"}
            pf = .RGBA8
        }

        var alphaMode = AlphaMode.Straight
        if samples == 4
        {
            let extraSamples = ifd.find(TAG_EXTRA_SAMPLES)
            if extraSamples
            {
                let entry = readEntry(extraSamples, le)
                if entry.type != TYPE_SHORT or entry.count != 1 do
                    fail InvalidFormatError{"TIFF extra samples entry is invalid"}
                switch rd16(entry.fieldAt, le)
                {
                case 1:  alphaMode = .Premultiplied
                case 2:  break
                default: fail UnsupportedFormatError{"TIFF alpha association is not supported"}
                }
            }
        }

        let bytesPerPixel = pf.bitsPerPixel() / 8
        if width > cast(u32, Swag.S32.Max) / bytesPerPixel do
            fail UnsupportedFormatError{"TIFF image row exceeds the image limits"}
        try options.checkImage(cast(s32, width), cast(s32, height), pf)

        var result: #returntype
        if not options.decodePixels
        {
            if orientation >= 5 do
                result.init(cast(s32, height), cast(s32, width), pf, alphaMode)
            else do
                result.init(cast(s32, width), cast(s32, height), pf, alphaMode)
            return result
        }

        result.init(cast(s32, width), cast(s32, height), pf, alphaMode)

        // Palette (for photometric=palette)
        var palette: Array'u32     // packed RGB byte order
        if samples == 1 and photometric == PHOTO_PALETTE
        {
            let cmEntry = ifd.find(TAG_COLOR_MAP)
            if not cmEntry do
                fail InvalidFormatError{"missing color map"}
            let cm      = try readValues(base, last, cmEntry, le)
            let entries = cm.count / 3
            palette.reserve(entries)
            for i in entries
            {
                let r = cm.read(i) >> 8
                let g = cm.read(entries + i) >> 8
                let b = cm.read(2 * entries + i) >> 8
                palette.add(Math.byteSwap((r << 16) | (g << 8) | b) >> 8)
            }
        }

        // Strips
        let stripOffEntry = ifd.find(TAG_STRIP_OFFSETS)
        let stripCntEntry = ifd.find(TAG_STRIP_BYTE_COUNTS)
        if not stripOffEntry or not stripCntEntry do
            fail InvalidFormatError{"missing strip data"}
        let stripOffsets = try readValues(base, last, stripOffEntry, le)
        let stripCounts  = try readValues(base, last, stripCntEntry, le)
        let stripCount   = cast(u64, (height - 1) / rowsPerStrip + 1)
        if stripOffsets.count != stripCounts.count or stripOffsets.count < stripCount do
            fail InvalidFormatError{"invalid strip data"}

        result.allocPixels()
        with var strips: StripReader
        {
            .base         = base
            .last         = last
            .destination  = result.pixels.storage()
            .offsets      = stripOffsets
            .counts       = stripCounts
            .palette      = palette.toSlice()
            .width        = width
            .height       = height
            .samples      = samples
            .rowStride    = result.rowStride
            .rowsPerStrip = rowsPerStrip
            .compression  = compression
            .predictor    = predictor
            .photometric  = photometric
        }

        // Large true-color LZW strips cost enough to amortize the worker dispatch.
        const MinParallelLzwBytes = 2 * 1024 * 1024
        const MaxLzwLanes         = 4
        var lanes = 1'u64
        if compression == COMPRESSION_LZW and
           samples != 1 and
           stripCount >= MaxLzwLanes and
           result.byteCount >= MinParallelLzwBytes do
            lanes = Math.min(cast(u64, Swag.workerCount()), cast(u64, MaxLzwLanes))
        if lanes > 1
        {
            var group: Swag.TaskGroup
            let reader = &strips
            for lane in 1 until lanes
            {
                let first = stripCount * lane / lanes
                let end   = stripCount * (lane + 1) / lanes
                group.spawn(func|reader, first, end|() fail { try reader.decodeRange(first, end) })
            }

            try strips.decodeRange(0, stripCount / lanes)
            try group.join()
        }
        else
        {
            try strips.decodeRange(0, stripCount)
        }

        result.orient(orientation)
        return result
    }
}

impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"TIFF - Tagged Image File Format", ".tif;.tiff"}
    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail => try .decodePage(buffer, options)
}

impl IImageSetDecoder for Decoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        .bytes = buffer
        .directories.clear()
        var probeOptions = options
        probeOptions.decodePixels = false
        var probe  = try .decodePage(buffer, probeOptions)
        let le     = buffer[0] == 0x49
        var offset = rd32(buffer.buffer + 4, le)
        var result:        #returntype
        var visited:       HashSet'u32
        var largestOffset: u32
        while offset
        {
            try options.checkFrameCount(.directories.count + 1)
            if visited.count or offset <= largestOffset
            {
                // Increasing offsets are unique. Index the prior offsets only when
                // the directory chain visits a lower address for the first time.
                if not visited.count
                {
                    visited.reserve(.directories.count + 1)
                    for prior in .directories do
                        discard visited.add(prior)
                }

                let count = visited.count
                discard visited.add(offset)
                if visited.count == count do
                    fail InvalidFormatError{"TIFF directory chain contains a cycle"}
            }
            else
            {
                largestOffset = offset
            }

            if cast(u64, offset) + 2 > buffer.count do
                fail InvalidFormatError{"TIFF directory offset is outside the input"}
            let count = rd16(buffer.buffer + offset, le)
            let next  = cast(u64, offset) + 2 + cast(u64, count) * 12
            if next + 4 > buffer.count do
                fail InvalidFormatError{"TIFF directory chain is truncated"}
            if .directories.count do
                probe = try .decodePage(buffer, probeOptions, offset)
            result.frames.add({kind: ImageFrameKind.Page, width: probe.width, height: probe.height, pixelFormat: probe.pixelFormat})
            .directories.add(offset)
            offset = rd32(buffer.buffer + next, le)
        }

        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if index >= .directories.count do
            fail InvalidFormatError{"TIFF page index is out of range"}
        return try .decodePage(unwrap .bytes, options, .directories[index])
    }
}
