//! Format: Windows icon/cursor (ICO/CUR) decoder component.
//! Supported: Multi-entry containers with PNG images or uncompressed 1-, 4-, 8-, 24-, and 32-bit DIB images and AND masks.
//! Not supported: Compressed DIB entries and DIB bit depths outside the supported set.
//! Role: This file owns container directory parsing and embedded-image decoding.
//
#global namespace Ico

using Core, Core.Errors

// ICONDIR (6 bytes)
#[Swag.Pack(1)]
struct IconDir
{
    reserved: u16
    type:     u16
    count:    u16
}

// ICONDIRENTRY (16 bytes)
#[Swag.Pack(1)]
struct IconDirEntry
{
    width:       u8
    height:      u8
    colorCount:  u8
    reserved:    u8
    planes:      u16
    bitCount:    u16
    bytesInRes:  u32
    imageOffset: u32
}

// BITMAPINFOHEADER (40 bytes) embedded in an icon entry
#[Swag.Pack(1)]
struct DibHeader
{
    size:          u32
    width:         s32
    height:        s32
    planes:        u16
    bitCount:      u16
    compression:   u32
    sizeImage:     u32
    xPelsPerMeter: s32
    yPelsPerMeter: s32
    clrUsed:       u32
    clrImportant:  u32
}

// Decodes Windows icon containers and selects their embedded BMP or PNG image.
internal struct Decoder
{
    bytes:      const [..] u8?
    entryCount: u32
}

func checkBuffer(ptr, last: const [*] u8, size: u64) fail
{
    if ptr + size > last do
        fail InvalidFormatError{"invalid source buffer"}
}

// Width/height of 0 in a directory entry means 256
func dimFromByte(value: u8)->s32 => value == 0 ? 256 : cast(s32, value)

func checkEntryDimensions(entry: IconDirEntry, width, height: s32) fail
{
    if width != dimFromByte(entry.width) or height != dimFromByte(entry.height) do
        fail InvalidFormatError{"icon entry dimensions do not match its directory"}
}

func isPngSignature(p: const [*] u8, size: u64)->bool
{
    if size < 8 do
        return false
    return p[0] == 0x89 and
           p[1] == 0x50 and
           p[2] == 0x4E and
           p[3] == 0x47 and
           p[4] == 0x0D and
           p[5] == 0x0A and
           p[6] == 0x1A and
           p[7] == 0x0A
}

func rowStride32(widthBits: u64)->u64 => ((widthBits + 31) / 32) * 4

func packedIndex(src: const [*] u8, bitCount: u16, x: s32)->u32
{
    switch bitCount
    {
    case 1:
        return cast(u32, ((src[x / 8] >> cast(u32, (7 - (x & 7)))) & 1))

    case 4:
        let b = src[x / 2]
        return cast(u32, ((x & 1) ? (b & 0x0F) : (b >> 4)))

    default:
        return src[x]
    }
}

func maskBit(andRow: const [*] u8, x: s32)->u32 => cast(u32, ((andRow[x / 8] >> cast(u32, (7 - (x & 7)))) & 1))

private const DibAlpha  = 0xFF000000'u32
private const DibColors = 0x00FFFFFF'u32
private const AndFirst  = cast(Math.Simd.U32x4, [128'u32, 64, 32, 16])
private const AndLast   = cast(Math.Simd.U32x4, [8'u32, 4, 2, 1])
private const BgrToBgra = cast(Math.Simd.U8x16, [0'u8, 1, 2, 128, 3, 4, 5, 128, 6, 7, 8, 128, 9, 10, 11, 128])

func hasDibAlpha(pixels: const [*] u32, count: u64)->bool
{
    let alpha = Math.Simd.splat(DibAlpha)
    let zero  = Math.Simd.splat(0'u32)
    var x     = 0'u64
    while count - x >= 4
    {
        if Math.Simd.anyTrue((Math.Simd.load(pixels + x) & alpha) != zero) do
            return true
        x += 4
    }

    for i in x until count
    {
        if pixels[i] & DibAlpha do
            return true
    }

    return false
}

#[Swag.Inline]
func(BIT_COUNT: u16) loadDibColors(source: const [*] u8)->Math.Simd.U32x4
{
    #static if BIT_COUNT == 32 do
        return Math.Simd.load(cast(const [*] u32, source))
    else do
        return cast #bit(Math.Simd.U32x4, Math.Simd.shuffle(Math.Simd.load(source), BgrToBgra))
}

func(BIT_COUNT: u16, MASKED: bool) decodeTrueColorDib(result: *Image, xorData, andData: const [*] u8, xorStride, andStride: u64)
{
    const Step = BIT_COUNT / 8

    // A 24-bit row needs two more pixels for the second 16-byte load.
    const MinimumWidth = BIT_COUNT == 24 ? 10 : 8
    let alpha  = Math.Simd.splat(DibAlpha)
    let zero   = Math.Simd.splat(0'u32)
    let output = cast([*] u32, result.pixels.storage())
    let width  = result.width
    for y in result.height
    {
        let source = xorData + y * xorStride
        let mask   = MASKED ? andData + y * andStride : andData
        let target = output + y * width
        var x      = 0
        while width - x >= MinimumWidth
        {
            let bits       = Math.Simd.splat(MASKED ? cast(u32, mask[x / 8]) : 0'u32)
            let firstAlpha = ((bits & AndFirst) == zero) & alpha
            let lastAlpha  = ((bits & AndLast) == zero) & alpha
            Math.Simd.store(target + x, loadDibColors'(BIT_COUNT)(source + x * Step) | firstAlpha)
            Math.Simd.store(target + x + 4, loadDibColors'(BIT_COUNT)(source + (x + 4) * Step) | lastAlpha)
            x += 8
        }

        for i in x until width
        {
            let pixel  = source + i * Step
            let colors = cast(u32, pixel[0]) | (cast(u32, pixel[1]) << 8) | (cast(u32, pixel[2]) << 16)
            target[i] = colors | (MASKED and maskBit(mask, i) ? 0'u32 : DibAlpha)
        }
    }
}

#[Swag.Inline]
func(BIT_COUNT: u16) loadDibIndices(source: const [*] u8)->Math.Simd.U16x8
{
    #static if BIT_COUNT == 4
    {
        let nibble = Math.Simd.splat(15'u8)
        let pairs  = cast #bit(Math.Simd.U8x16, Math.Simd.splat(cast(const [*] u32, source)[0]))
        let upper  = cast #bit(Math.Simd.U8x16, (cast #bit(Math.Simd.U16x8, pairs) >> 4)) & nibble
        return Math.Simd.widenLow(Math.Simd.interleaveLow(upper, pairs & nibble))
    }
    else
    {
        let bytes = cast #bit(Math.Simd.U8x16, Math.Simd.splat(cast(const [*] u64, source)[0]))
        return Math.Simd.widenLow(bytes)
    }
}

func(BIT_COUNT: u16) decodeFullPaletteDib(result: *Image, palette, xorData, andData: const [*] u8, xorStride, andStride: u64, hasAndMask: bool)
{
    let colors     = Math.Simd.splat(DibColors)
    let alpha      = Math.Simd.splat(DibAlpha)
    let zero       = Math.Simd.splat(0'u32)
    let entries    = cast(const [*] s32, palette)
    let words      = cast(const [*] u32, palette)
    let first      = Math.Simd.splat(words[0] & DibColors)
    let difference = Math.Simd.splat((words[0] ^ words[1]) & DibColors)
    let width      = result.width
    let output     = cast([*] u32, result.pixels.storage())
    for y in result.height
    {
        let source = xorData + y * xorStride
        let mask   = hasAndMask ? andData + y * andStride : andData
        let target = output + y * width
        var x      = 0
        while width - x >= 8
        {
            let bits       = Math.Simd.splat(hasAndMask ? cast(u32, mask[x / 8]) : 0'u32)
            let firstAlpha = ((bits & AndFirst) == zero) & alpha
            let lastAlpha  = ((bits & AndLast) == zero) & alpha
            #static if BIT_COUNT == 1
            {
                let indexes     = Math.Simd.splat(cast(u32, source[x / 8]))
                let firstColors = first ^ (difference & ((indexes & AndFirst) != zero))
                let lastColors  = first ^ (difference & ((indexes & AndLast) != zero))
                Math.Simd.store(target + x, firstColors | firstAlpha)
                Math.Simd.store(target + x + 4, lastColors | lastAlpha)
            }
            else
            {
                let indexes     = loadDibIndices'(BIT_COUNT)(source + x * BIT_COUNT / 8)
                let firstColors = cast #bit(Math.Simd.U32x4, Math.Simd.gather(entries, Math.Simd.widenLow(indexes))) & colors
                let lastColors  = cast #bit(Math.Simd.U32x4, Math.Simd.gather(entries, Math.Simd.widenHigh(indexes))) & colors
                Math.Simd.store(target + x, firstColors | firstAlpha)
                Math.Simd.store(target + x + 4, lastColors | lastAlpha)
            }

            x += 8
        }

        for i in x until width
        {
            let index = packedIndex(source, BIT_COUNT, i)
            target[i] = (words[index] & DibColors) | (hasAndMask and maskBit(mask, i) ? 0'u32 : DibAlpha)
        }
    }
}

// Decode the embedded BITMAPINFOHEADER icon image into a BGRA8 result.
func decodeDib(result: *Image, dib: DibHeader, src, last: const [*] u8) fail
{
    if dib.bitCount != 1 and
       dib.bitCount != 4 and
       dib.bitCount != 8 and
       dib.bitCount != 24 and
       dib.bitCount != 32 do
        fail UnsupportedFormatError{"unsupported icon bit count"}
    if dib.compression != 0 do
        fail UnsupportedFormatError{"unsupported icon compression"}

    let width  = result.width
    let height = result.height

    // Palette (for indexed images): one BGRA quad per entry
    var paletteCount = dib.clrUsed
    if not paletteCount and dib.bitCount <= 8 do
        paletteCount = 1'u32 << cast(u32, dib.bitCount)

    let palette = src
    var dataof  = src
    if paletteCount
    {
        try checkBuffer(palette, last, cast(u64, paletteCount) * 4)
        dataof += cast(u64, paletteCount) * 4
    }

    let xorStride = rowStride32(cast(u64, width) * dib.bitCount)
    let andStride = rowStride32(cast(u64, width))
    let xorData   = dataof
    let andData   = dataof + xorStride * cast(u64, height)

    try checkBuffer(xorData, last, xorStride * cast(u64, height))

    // The AND mask is optional for 32-bit images that carry their own alpha
    let hasAndMask = andData + andStride * cast(u64, height) <= last

    if dib.bitCount == 32
    {
        // A nonzero alpha byte means native alpha. The older all-zero
        // layout takes its transparency from the AND mask.
        let pixels = cast(const [*] u32, xorData)
        if not hasAndMask or hasDibAlpha(pixels, cast(u64, width) * height)
        {
            Memory.copy(result.pixels.storage(), xorData, result.byteCount)
        }
        else
        {
            decodeTrueColorDib'(32, true)(result, xorData, andData, xorStride, andStride)
        }

        return
    }

    if dib.bitCount == 24
    {
        if hasAndMask do
            decodeTrueColorDib'(24, true)(result, xorData, andData, xorStride, andStride)
        else do
            decodeTrueColorDib'(24, false)(result, xorData, andData, xorStride, andStride)
        return
    }

    // A full palette covers every value representable at the entry's bit depth.
    if paletteCount >= 1'u32 << dib.bitCount and width >= 8
    {
        switch dib.bitCount
        {
        case 1: decodeFullPaletteDib'(1)(result, palette, xorData, andData, xorStride, andStride, hasAndMask)
        case 4: decodeFullPaletteDib'(4)(result, palette, xorData, andData, xorStride, andStride, hasAndMask)
        case 8: decodeFullPaletteDib'(8)(result, palette, xorData, andData, xorStride, andStride, hasAndMask)
        }

        return
    }

    let words  = cast(const [*] u32, palette)
    let output = cast([*] u32, result.pixels.storage())
    for y in height
    {
        let xorRow = xorData + xorStride * cast(u64, y)
        let andRow = hasAndMask ? andData + andStride * cast(u64, y) : andData
        let target = output + y * width
        for x in width
        {
            let index = packedIndex(xorRow, dib.bitCount, x)
            if index >= paletteCount do
                fail InvalidFormatError{"invalid palette index"}
            target[x] = (words[index] & DibColors) | (hasAndMask and maskBit(andRow, x) ? 0'u32 : DibAlpha)
        }
    }
}

#[Swag.Inline]
func directoryEntries(buffer: const [..] u8)->const [*] IconDirEntry => cast(const [*] IconDirEntry, buffer.buffer + #sizeof(IconDir))

func readDirectory(buffer: const [..] u8)->const [..] IconDirEntry fail
{
    let base = buffer.buffer
    if buffer.count < #sizeof(IconDir) do
        fail InvalidFormatError{"invalid source buffer"}

    let dir = cast(const *IconDir, base)[]
    if dir.type != 1 and dir.type != 2 do
        fail InvalidFormatError{"not an icon"}
    if dir.count == 0 do
        fail InvalidFormatError{"empty icon"}

    try checkBuffer(base, base + buffer.count, cast(u64, #sizeof(IconDir)) + cast(u64, dir.count) * #sizeof(IconDirEntry))
    return Swag.makeSlice(directoryEntries(buffer), dir.count)
}

func representativeIndex(entries: const [..] IconDirEntry)->u32
{
    // The largest area wins, with bit depth breaking ties.
    var bestIndex: u32
    var bestScore: u64
    for i in entries.count
    {
        let entry = entries[i]
        let area  = cast(u64, dimFromByte(entry.width)) * dimFromByte(entry.height)
        let score = (area << 16) + entry.bitCount
        if score > bestScore
        {
            bestScore = score
            bestIndex = cast(u32, i)
        }
    }

    return bestIndex
}

func decodeEntry(buffer: const [..] u8, options: DecodeOptions, entry: IconDirEntry)->Image fail
{
    if cast(u64, entry.imageOffset) + entry.bytesInRes > buffer.count do
        fail InvalidFormatError{"invalid source buffer"}

    let imgPtr = buffer.buffer + entry.imageOffset
    let imgLen = cast(u64, entry.bytesInRes)

    // PNG-compressed entry: delegate to the PNG decoder
    if isPngSignature(imgPtr, imgLen)
    {
        var pngDec: Png.Decoder
        let itf    = Swag.makeInterface(&pngDec, #typeof(Png.Decoder), IImageDecoder)
        var result = #move try itf.decode(Swag.makeSlice(imgPtr, imgLen), options)
        try checkEntryDimensions(entry, result.width, result.height)
        return #move result
    }

    // BMP/DIB-encoded entry
    if imgLen < #sizeof(DibHeader) do
        fail InvalidFormatError{"invalid source buffer"}

    let dib = cast(const *DibHeader, imgPtr)[]
    if dib.size < #sizeof(DibHeader) do
        fail UnsupportedFormatError{"unsupported icon header"}
    if dib.planes != 1 do
        fail UnsupportedFormatError{"icon DIB must have one color plane"}
    if dib.width <= 0 or dib.height <= 0 or (dib.height & 1) do
        fail InvalidFormatError{"invalid dimensions"}
    try checkEntryDimensions(entry, dib.width, dib.height / 2)

    var result: #returntype
    result.init(dib.width, dib.height / 2, PixelFormat.BGRA8)
    try options.checkImage(result.width, result.height, result.pixelFormat)

    if not options.decodePixels do
        return result

    result.allocPixels()
    if dib.size > imgLen do
        fail InvalidFormatError{"icon DIB header is truncated"}
    try decodeDib(&result, dib, imgPtr + dib.size, imgPtr + imgLen)
    return result
}

impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"ICO - Windows Icon and Cursor", ".ico;.cur"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        let entries = try readDirectory(buffer)
        return try decodeEntry(buffer, options, entries[representativeIndex(entries)])
    }
}

func describeEntry(buffer: const [..] u8, options: DecodeOptions, entry: IconDirEntry)->ImageFrameInfo fail
{
    let probe = try decodeEntry(buffer, options, entry)
    return {kind: ImageFrameKind.Variant, width: probe.width, height: probe.height, pixelFormat: probe.pixelFormat}
}

impl IImageSetDecoder for Decoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        let entries      = try readDirectory(buffer)
        let selected     = representativeIndex(entries)
        var probeOptions = options
        probeOptions.decodePixels   = false
        probeOptions.decodeMetadata = false
        let representative = try describeEntry(buffer, probeOptions, entries[selected])
        try options.checkFrameCount(entries.count)

        var result: #returntype
        result.representativeIndex = selected
        result.frames.reserve(entries.count)
        for i in entries.count
        {
            if i == selected do
                result.frames.add(representative)
            else do
                result.frames.add(try describeEntry(buffer, probeOptions, entries[i]))
        }

        .bytes      = buffer
        .entryCount = cast(u32, entries.count)
        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if index >= .entryCount do
            fail InvalidFormatError{"icon entry index is out of range"}
        let buffer = unwrap .bytes
        return try decodeEntry(buffer, options, directoryEntries(buffer)[index])
    }
}
