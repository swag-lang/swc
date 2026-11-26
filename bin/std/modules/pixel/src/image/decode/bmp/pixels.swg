//! Format: Windows Bitmap (BMP/DIB) decoder component.
//! Supported: Windows and OS/2 headers; 1-, 4-, 8-, 16-, 24-, and 32-bit pixels; palettes, RGB, bitfields, RLE4, RLE8, and either row direction.
//! Not supported: JPEG/PNG-compressed BMP payloads and other compression modes.
//! Role: This file owns palette, packed-index, direct-color, and bitfield row expansion.
//
#global namespace Bmp

using Core, Core.Errors

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

func writePalettePixel(dst: [*] u8, palette: const [*] u8, paletteEntrySize, index: u32)
{
    let entry = palette + cast(u64, index) * paletteEntrySize
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
        return cast(u32, ((src[x / 8] >> cast(u32, (7 - (x & 7)))) & 1))

    case 4:
        let b = src[x / 2]
        return cast(u32, ((x & 1) ? (b & 0x0F) : (b >> 4)))

    default:
        return src[x]
    }
}

func makePackedPalette(palette: const [*] u8, entrySize, count: u32)->[256] u32
{
    var colors: [256] u32
    var entry = palette
    for index in Math.min(count, 256'u32)
    {
        colors[index] = cast(u32, entry[0]) | (cast(u32, entry[1]) << 8) | (cast(u32, entry[2]) << 16)
        entry         += entrySize
    }

    return colors
}

#[Swag.Inline]
func writePackedBgr(destination: [*] u8, color: u32)
{
    cast(*u16, destination)[] = cast(u16, (color & 0xFFFF))
    destination[2] = cast(u8, (color >> 16))
}

private func makeBinaryPatterns(colors: const [*] u32)->[16] Math.Simd.U8x16
{
    var result: #returntype
    for pattern in 16
    {
        var bytes: [16] u8
        for pixel in 4 do
            writePackedBgr(cast([*] u8, &bytes[pixel * 3]), colors[(pattern >> (3 - pixel)) & 1])
        result[pattern] = cast(Math.Simd.U8x16, bytes)
    }

    return result
}

func makePalettePairs(colors: const [*] u32)->[256] u64
{
    var pairs: #returntype
    for value in 256 do
        pairs[value] = cast(u64, colors[value >> 4]) | (cast(u64, colors[value & 15]) << 24)
    return pairs
}

private func decodePalette1Row(source: const [*] u8, destination: [*] u8, count: u64, colors: const [*] u32, patterns: const [*] Math.Simd.U8x16)
{
    var src  = source
    var dst  = destination
    var left = count
    while left >= 8
    {
        let value = src[0]
        Image.storeLow12(dst, patterns[value >> 4])
        Image.storeLow12(dst + 12, patterns[value & 15])
        src  += 1
        dst  += 24
        left -= 8
    }

    for pixel in left do
        writePackedBgr(dst + pixel * 3, colors[(src[0] >> (7 - pixel)) & 1])
}

func decodePalette4Row(source: const [*] u8, destination: [*] u8, count: u64, colors: const [*] u32, pairs: const [*] u64)
{
    var src  = source
    var dst  = destination
    var left = count
    while left >= 3
    {
        // The next pixel overwrites the two high bytes covered by this store.
        cast(*u64, dst)[] = pairs[src[0]]
        src  += 1
        dst  += 6
        left -= 2
    }

    if left
    {
        let value = src[0]
        writePackedBgr(dst, colors[value >> 4])
        if left == 2 do
            writePackedBgr(dst + 3, colors[value & 15])
    }
}

func decodePalette8Row(source: const [*] u8, destination: [*] u8, count: u64, colors: const [*] u32)
{
    for pixel in count - 1 do
        cast(*u32, (destination + pixel * 3))[] = colors[source[pixel]]
    writePackedBgr(destination + (count - 1) * 3, colors[source[count - 1]])
}

func palette4RowFits(source: const [*] u8, count: u64, paletteCount: u32)->bool
{
    let pairs = count / 2
    let limit = Math.Simd.splat(cast(u8, paletteCount))
    var i     = 0'u64
    while pairs - i >= 16
    {
        let values = Math.Simd.load(source + i)
        let high   = cast #bit(Math.Simd.U8x16, ((cast #bit(Math.Simd.U16x8, values) >> 4) & 0x0F0F'u16))
        if Math.Simd.anyTrue((high >= limit) | ((values & 15'u8) >= limit)) do
            return false
        i += 16
    }

    for index in i until pairs
    {
        let pair = source[index]
        if pair >> 4 >= paletteCount or (pair & 15) >= paletteCount do
            return false
    }

    return not (count & 1) or source[pairs] >> 4 < paletteCount
}

func palette8RowFits(source: const [*] u8, count: u64, paletteCount: u32)->bool
{
    let limit = Math.Simd.splat(cast(u8, paletteCount))
    var i     = 0'u64
    while count - i >= 16
    {
        if Math.Simd.anyTrue(Math.Simd.load(source + i) >= limit) do
            return false
        i += 16
    }

    for index in i until count where source[index] >= paletteCount do
        return false
    return true
}

private func palette1RowFits(source: const [*] u8, count: u64)->bool
{
    let bytes = count / 8
    for index in bytes where source[index] do
        return false
    let remaining = count & 7
    return not remaining or source[bytes] >> (8 - remaining) == 0
}

func decodePackedPalette(result: *Image, src, last: const [*] u8, palette: const [*] u8, paletteEntrySize, paletteCount: u32, bitCount: u16, topDown: bool) fail
{
    let stride = rowStride(result.width, bitCount)
    try checkBuffer(src, last, stride * cast(u64, result.height))

    // A full palette covers every value representable by the packed pixel, so it
    // needs no validation pass. A shorter declared palette must contain every
    // referenced index before decoding starts.
    if paletteCount < (1'u32 << cast(u32, bitCount))
    {
        for y in result.height
        {
            let srcRow = src + stride * cast(u64, y)
            let width  = cast(u64, result.width)
            var valid: bool
            switch bitCount
            {
            case 1:  valid = palette1RowFits(srcRow, width)
            case 4:  valid = palette4RowFits(srcRow, width, paletteCount)
            default: valid = palette8RowFits(srcRow, width, paletteCount)
            }

            if not valid do
                fail InvalidFormatError{"BMP pixel index exceeds its palette"}
        }
    }

    if cast(u64, result.width) * cast(u64, result.height) >= 512
    {
        let entries = makePackedPalette(palette, paletteEntrySize, paletteCount)
        let colors  = cast(const [*] u32, &entries[0])
        var patterns: [16] Math.Simd.U8x16
        var pairs:    [256] u64
        if bitCount == 1 do
            patterns = makeBinaryPatterns(colors)
        elif bitCount == 4 do
            pairs = makePalettePairs(colors)
        for y in result.height
        {
            let dstY   = topDown ? result.height - y - 1 : y
            let srcRow = src + stride * cast(u64, y)
            let dst    = result.pixels.storage() + cast(u64, dstY) * result.rowStride
            let width  = cast(u64, result.width)
            switch bitCount
            {
            case 1:  decodePalette1Row(srcRow, dst, width, colors, cast(const [*] Math.Simd.U8x16, &patterns[0]))
            case 4:  decodePalette4Row(srcRow, dst, width, colors, cast(const [*] u64, &pairs[0]))
            default: decodePalette8Row(srcRow, dst, width, colors)
            }
        }

        return
    }

    for y in result.height
    {
        let dstY   = topDown ? result.height - y - 1 : y
        let srcRow = src + stride * cast(u64, y)
        var dst    = cast([*] u8, result.pixels.storage()) + cast(u64, dstY) * result.rowStride
        for x in result.width
        {
            writePalettePixel(dst, palette, paletteEntrySize, packedIndex(srcRow, bitCount, x))
            dst += 3
        }
    }
}

func decodeUncompressedDirect(result: *Image, src, last: const [*] u8, bitCount: u16, topDown: bool) fail
{
    let stride   = rowStride(result.width, bitCount)
    let rowBytes = cast(u64, result.width) * result.bytesPerPixel
    try checkBuffer(src, last, stride * cast(u64, result.height))

    for y in result.height
    {
        let dstY = topDown ? result.height - y - 1 : y
        Memory.copy(cast([*] u8, result.pixels.storage()) + cast(u64, dstY) * rowBytes, src + stride * cast(u64, y), rowBytes)
    }
}

func decode16Row(source: const [*] u8, destination: [*] u8, pixelCount: u64, masks: Masks)
{
    if masks.r.value == 0x7C00 and
       masks.g.value == 0x03E0 and
       masks.b.value == 0x001F and
       not masks.a.value
    {
        PackedPixel.decodeBgr555Row(source, destination, pixelCount)
        return
    }

    if masks.r.value == 0xF800 and
       masks.g.value == 0x07E0 and
       masks.b.value == 0x001F and
       not masks.a.value
    {
        PackedPixel.decodeBgr565Row(source, destination, pixelCount)
        return
    }

    let rExpected = masks.r.bits and masks.r.bits <= 8 ? ((1'u32 << masks.r.bits) - 1) << masks.r.shift : 0
    let gExpected = masks.g.bits and masks.g.bits <= 8 ? ((1'u32 << masks.g.bits) - 1) << masks.g.shift : 0
    let bExpected = masks.b.bits and masks.b.bits <= 8 ? ((1'u32 << masks.b.bits) - 1) << masks.b.shift : 0
    if rExpected and
       gExpected and
       bExpected and
       masks.r.value == rExpected and
       masks.g.value == gExpected and
       masks.b.value == bExpected and
       masks.r.shift + masks.r.bits <= 16 and
       masks.g.shift + masks.g.bits <= 16 and
       masks.b.shift + masks.b.bits <= 16
    {
        PackedPixel.decodeBgrMasked16Row(source, destination, pixelCount, cast(u16, masks.b.value), masks.b.shift, masks.b.bits, cast(u16, masks.g.value), masks.g.shift, masks.g.bits, cast(u16, masks.r.value), masks.r.shift, masks.r.bits)
        return
    }

    var src   = source
    var dst   = destination
    var count = pixelCount
    if validMask(masks.b, 16) and validMask(masks.g, 16) and validMask(masks.r, 16)
    {
        let blue  = prepareField(masks.b)
        let green = prepareField(masks.g)
        let red   = prepareField(masks.r)
        while count >= 16
        {
            let first  = Math.Simd.load(cast(const [*] u16, src))
            let second = Math.Simd.load(cast(const [*] u16, (src + 16)))
            let p0     = Math.Simd.widenLow(first)
            let p1     = Math.Simd.widenHigh(first)
            let p2     = Math.Simd.widenLow(second)
            let p3     = Math.Simd.widenHigh(second)
            let b      = packField16(p0, p1, p2, p3, blue)
            let g      = packField16(p0, p1, p2, p3, green)
            let r      = packField16(p0, p1, p2, p3, red)
            PackedPixel.storeTriplets16(dst, b, g, r)
            src   += 32
            dst   += 48
            count -= 16
        }
    }

    for count
    {
        writeMaskedPixel(dst, cast(const *u16, src)[], masks, false)
        src += 2
        dst += 3
    }
}

func decode16(result: *Image, src, last: const [*] u8, masks: Masks, topDown: bool) fail
{
    let stride = rowStride(result.width, 16)
    try checkBuffer(src, last, stride * cast(u64, result.height))

    for y in result.height
    {
        let dstY   = topDown ? result.height - y - 1 : y
        let srcPix = src + stride * cast(u64, y)
        let dst    = cast([*] u8, result.pixels.storage()) + cast(u64, dstY) * result.rowStride
        decode16Row(srcPix, dst, result.width, masks)
    }
}

private struct FieldScale
{
    mask:        u32
    sourceShift: u8
    resultShift: u8
    scale:       u32
    bias:        u32
}

private func prepareField(mask: Mask)->FieldScale
{
    if not mask.value do
        return {}

    let bits = cast(u32, mask.bits)

    // Repeating a field's bits keeps its normalized value while making its maximum at least 255.
    let resultBits  = bits < 8 ? (7 / bits + 1) * bits : bits
    let sourceMax   = (1'u32 << bits) - 1
    let repeatedMax = (1'u32 << resultBits) - 1
    return FieldScale{mask.value, mask.shift, cast(u8, resultBits), (repeatedMax / sourceMax) * 255, repeatedMax / 2}
}

#[Swag.Inline]
private func expandField(pixels: Math.Simd.U32x4, field: FieldScale)->Math.Simd.U32x4
{
    let samples  = (pixels & field.mask) >> field.sourceShift
    let weighted = samples * field.scale + field.bias

    // Each quotient is at most 255. In this range the second shift divides exactly by 2^bits - 1.
    return (weighted + 1 + (weighted >> field.resultShift)) >> field.resultShift
}

#[Swag.Inline]
private func packField16(p0, p1, p2, p3: Math.Simd.U32x4, field: FieldScale)->Math.Simd.U8x16
{
    let low  = Math.Simd.packUnsigned(cast #bit(Math.Simd.S32x4, expandField(p0, field)), cast #bit(Math.Simd.S32x4, expandField(p1, field)))
    let high = Math.Simd.packUnsigned(cast #bit(Math.Simd.S32x4, expandField(p2, field)), cast #bit(Math.Simd.S32x4, expandField(p3, field)))
    return Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8, low), cast #bit(Math.Simd.S16x8, high))
}

private func byteFieldOrder(masks: Masks)->Math.Simd.U8x16
{
    var order: [16] u8
    for lane in 4
    {
        let start = cast(u8, lane * 4)
        order[start]     = start + masks.b.shift / 8
        order[start + 1] = start + masks.g.shift / 8
        order[start + 2] = start + masks.r.shift / 8
        order[start + 3] = masks.a.value ? start + masks.a.shift / 8 : 0x80
    }

    return cast(Math.Simd.U8x16, order)
}

func decode32(result: *Image, src, last: const [*] u8, masks: Masks, topDown: bool) fail
{
    let stride = rowStride(result.width, 32)
    try checkBuffer(src, last, stride * cast(u64, result.height))

    let aligned = masks.r.bits == 8 and
                  masks.g.bits == 8 and
                  masks.b.bits == 8 and
                  (not masks.a.value or masks.a.bits == 8) and
                  ((masks.r.shift | masks.g.shift | masks.b.shift | masks.a.shift) & 7) == 0
    let packed = not aligned and
                 masks.r.bits <= 24 and
                 masks.g.bits <= 24 and
                 masks.b.bits <= 24 and
                 masks.a.bits <= 24
    let order  = aligned ? byteFieldOrder(masks) : Math.Simd.splat(0'u8)
    let opaque = Math.Simd.splat(masks.a.value ? 0'u32 : 0xFF00_0000'u32)
    let blue   = packed ? prepareField(masks.b) : FieldScale{}
    let green  = packed ? prepareField(masks.g) : FieldScale{}
    let red    = packed ? prepareField(masks.r) : FieldScale{}
    let alpha  = packed ? prepareField(masks.a) : FieldScale{}

    let rows        = topDown ? result.height : 1
    let pixelCount  = cast(u64, result.width) * (topDown ? 1 : cast(u64, result.height))
    let destination = result.pixels.storage()
    for y in rows
    {
        let dstY   = topDown ? result.height - y - 1 : y
        var srcPix = src + stride * cast(u64, y)
        var dst    = destination + cast(u64, dstY) * stride
        var count  = pixelCount
        if aligned
        {
            while count >= 4
            {
                let rgba = Math.Simd.shuffle(Math.Simd.load(srcPix), order) | cast #bit(Math.Simd.U8x16, opaque)
                Math.Simd.store(dst, rgba)
                srcPix += 16
                dst    += 16
                count  -= 4
            }
        }
        elif packed
        {
            while count >= 4
            {
                let pixels = Math.Simd.load(cast(const [*] u32, srcPix))
                let b      = expandField(pixels, blue)
                let g      = expandField(pixels, green) << 8
                let r      = expandField(pixels, red) << 16
                let a      = masks.a.value ? expandField(pixels, alpha) << 24 : opaque
                Math.Simd.store(cast([*] u32, dst), b | g | r | a)
                srcPix += 16
                dst    += 16
                count  -= 4
            }
        }

        for count
        {
            writeMaskedPixel(dst, cast(const *u32, srcPix)[], masks, true)
            srcPix += 4
            dst    += 4
        }
    }
}
