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
    while left >= 9
    {
        // Each following pair or tail pixel overwrites the extra two bytes.
        cast(*u64, dst)[]        = pairs[src[0]]
        cast(*u64, (dst + 6))[]  = pairs[src[1]]
        cast(*u64, (dst + 12))[] = pairs[src[2]]
        cast(*u64, (dst + 18))[] = pairs[src[3]]
        src                      += 4
        dst                      += 24
        left                     -= 8
    }

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
    var src  = source
    var dst  = destination
    var left = count
    while left >= 5
    {
        let first = cast(u64, colors[src[0]]) | (cast(u64, colors[src[1]]) << 24)
        let last  = cast(u64, colors[src[2]]) | (cast(u64, colors[src[3]]) << 24)

        // The next pixel overwrites the two bytes beyond this block.
        cast(*u64, dst)[]       = first
        cast(*u64, (dst + 6))[] = last
        src                     += 4
        dst                     += 12
        left                    -= 4
    }

    for pixel in left - 1 do
        cast(*u32, (dst + pixel * 3))[] = colors[src[pixel]]
    writePackedBgr(dst + (left - 1) * 3, colors[src[left - 1]])
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

enum RowFormat16
{
    Scalar
    Bgr555
    Bgr565
    Masked
}

struct RowDecoder16
{
    format: RowFormat16
    masks:  Masks
    blue:   FieldScale16
    green:  FieldScale16
    red:    FieldScale16
}

func prepareRowDecoder16(masks: Masks)->RowDecoder16
{
    if masks.g.value == 0x03E0 and
       masks.b.value == 0x001F and
       not masks.a.value and
       masks.r.value == 0x7C00 do
        return {format: .Bgr555}
    if masks.g.value == 0x07E0 and
       masks.b.value == 0x001F and
       not masks.a.value and
       masks.r.value == 0xF800 do
        return {format: .Bgr565}
    if validMask(masks.b, 16) and
       validMask(masks.g, 16) and
       validMask(masks.r, 16) and
       masks.b.bits < 16 and
       masks.g.bits < 16 and
       masks.r.bits < 16 do
        return {format: .Masked, blue: prepareField16(masks.b), green: prepareField16(masks.g), red: prepareField16(masks.r)}

    return {masks: masks}
}

func decode16Row(source: const [*] u8, destination: [*] u8, pixelCount: u64, decoder: const *RowDecoder16)
{
    switch decoder.format
    {
    case .Bgr555:
        PackedPixel.decodeBgr555Row(source, destination, pixelCount)

    case .Bgr565:
        PackedPixel.decodeBgr565Row(source, destination, pixelCount)

    case .Masked:
        var src   = source
        var dst   = destination
        var count = pixelCount
        let blue  = decoder.blue
        let green = decoder.green
        let red   = decoder.red
        while count >= 16
        {
            let first  = Math.Simd.load(cast(const [*] u16, src))
            let second = Math.Simd.load(cast(const [*] u16, (src + 16)))
            let b      = packField16(first, second, blue)
            let g      = packField16(first, second, green)
            let r      = packField16(first, second, red)
            PackedPixel.storeTriplets16(dst, b, g, r)
            src   += 32
            dst   += 48
            count -= 16
        }

        for count
        {
            let pixel = cast(const *u16, src)[]
            writeBgrPixel(dst, expandField16(pixel, blue), expandField16(pixel, green), expandField16(pixel, red))
            src += 2
            dst += 3
        }

    case .Scalar:
        var src = source
        var dst = destination
        for pixelCount
        {
            writeMaskedPixel(dst, cast(const *u16, src)[], decoder.masks, false)
            src += 2
            dst += 3
        }
    }
}

func decode16(result: *Image, src, last: const [*] u8, masks: Masks, topDown: bool) fail
{
    let stride = rowStride(result.width, 16)
    try checkBuffer(src, last, stride * cast(u64, result.height))

    let decoder = prepareRowDecoder16(masks)
    for y in result.height
    {
        let dstY   = topDown ? result.height - y - 1 : y
        let srcPix = src + stride * cast(u64, y)
        let dst    = cast([*] u8, result.pixels.storage()) + cast(u64, dstY) * result.rowStride
        decode16Row(srcPix, dst, result.width, &decoder)
    }
}

private func fieldMultiplier(bits, fractionBits: u8)->u64
{
    let range = 1'u64 << bits
    let max   = range - 1
    return ((255'u64 << fractionBits) * range + max / 2) / max
}

private struct FieldScale32
{
    mask:        Math.Simd.U32x4
    scale:       Math.Simd.U32x4
    sourceShift: u8
}

private func prepareField32(mask: Mask)->FieldScale32
{
    if not mask.value do
        return {}

    // Left alignment preserves 23 fractional bits in the high product.
    let scale = cast(u32, fieldMultiplier(mask.bits, 23))
    return {Math.Simd.splat(mask.value), Math.Simd.splat(scale), cast(u8, (32 - mask.bits - mask.shift))}
}

#[Swag.Inline]
private func expandField32(pixels: Math.Simd.U32x4, field: FieldScale32)->Math.Simd.U32x4
{
    let aligned = (pixels & field.mask) << field.sourceShift
    return (Math.Simd.mulHigh(aligned, field.scale) + (1'u32 << 22)) >> 23
}

struct FieldScale16
{
    mask:        Math.Simd.U16x8
    scale:       Math.Simd.U16x8
    sourceShift: u8
}

private func prepareField16(mask: Mask)->FieldScale16
{
    // Left-align the field so the high product keeps seven fractional bits.
    // The rounded multiplier preserves exact 8-bit normalization for fields up to 15 bits.
    let scale = cast(u16, fieldMultiplier(mask.bits, 7))
    return {Math.Simd.splat(cast(u16, mask.value)), Math.Simd.splat(scale), cast(u8, (16 - mask.bits - mask.shift))}
}

#[Swag.Inline]
private func expandField16(pixels: Math.Simd.U16x8, field: FieldScale16)->Math.Simd.U16x8
{
    let aligned = (pixels & field.mask) << field.sourceShift
    return (Math.Simd.mulHigh(aligned, field.scale) + 64'u16) >> 7
}

#[Swag.Inline]
private func expandField16(pixel: u16, field: FieldScale16)->u8
{
    let aligned = cast(u32, (pixel & field.mask[0])) << field.sourceShift
    return cast(u8, ((aligned * field.scale[0] + (1'u32 << 22)) >> 23))
}

#[Swag.Inline]
private func packField16(first, second: Math.Simd.U16x8, field: FieldScale16)->Math.Simd.U8x16
{
    return Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8, expandField16(first, field)), cast #bit(Math.Simd.S16x8, expandField16(second, field)))
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
    let order  = aligned ? byteFieldOrder(masks) : Math.Simd.splat(0'u8)
    let opaque = Math.Simd.splat(masks.a.value ? 0'u32 : 0xFF00_0000'u32)
    let blue   = aligned ? FieldScale32{} : prepareField32(masks.b)
    let green  = aligned ? FieldScale32{} : prepareField32(masks.g)
    let red    = aligned ? FieldScale32{} : prepareField32(masks.r)
    let alpha  = aligned ? FieldScale32{} : prepareField32(masks.a)

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
        else
        {
            while count >= 4
            {
                let pixels = Math.Simd.load(cast(const [*] u32, srcPix))
                let b      = expandField32(pixels, blue)
                let g      = expandField32(pixels, green) << 8
                let r      = expandField32(pixels, red) << 16
                let a      = masks.a.value ? expandField32(pixels, alpha) << 24 : opaque
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
