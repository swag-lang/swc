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
    colors:        const [*] u32?
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

func isMappedType(imageType: u8)->bool => imageType == TYPE_MAP or imageType == TYPE_RLE_MAP

func isRgbType(imageType: u8)->bool => imageType == TYPE_RGB or imageType == TYPE_RLE_RGB

func isMonoType(imageType: u8)->bool => imageType == TYPE_MONO or imageType == TYPE_RLE_MONO

func isRleType(imageType: u8)->bool => imageType == TYPE_RLE_MAP or imageType == TYPE_RLE_RGB or imageType == TYPE_RLE_MONO

func hasAttributeBits(header: Header)->bool => (header.descriptorByte & DESC_ALPHA_MASK) != 0

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

func expand5(value: u32)->u8 => cast(u8, ((value * 255 + 15) / 31))

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
    let pixel = cast(u32, value)
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
    let srcX = cast(s32, (pixelIndex % header.width))
    let srcY = cast(s32, (pixelIndex / header.width))
    let dstX = header.descriptorByte & DESC_ORIGIN_RIGHT ? result.width - srcX - 1 : srcX
    let dstY = header.descriptorByte & DESC_ORIGIN_TOP ? result.height - srcY - 1 : srcY
    return cast([*] u8, result.pixels.storage()) + cast(u64, dstY) * result.rowStride + cast(u64, dstX) * result.bytesPerPixel
}

func paletteIndex(src: const [*] u8, bpp: u8)->u32
{
    if bpp == 16 do
        return cast(const *u16, src)[]
    return src[0]
}

func writePalettePixel(dst: [*] u8, palette: Palette, index: u32, alphaFromBit: bool) fail
{
    if index < palette.first or index >= cast(u32, palette.first) + palette.count do
        fail InvalidFormatError{"invalid palette index"}

    let paletteData = cast(const [*] u8, unwrap palette.data)
    let entry       = paletteData + cast(u64, (index - palette.first)) * palette.bytesPerPixel
    switch palette.bitsPerPixel
    {
    case 15: writeTga16Pixel(dst, cast(const *u16, entry)[], false, false)
    case 16: writeTga16Pixel(dst, cast(const *u16, entry)[], true, alphaFromBit)
    case 24: writeBgrPixel(dst, entry[0], entry[1], entry[2])
    case 32: writeBgraPixel(dst, entry[0], entry[1], entry[2], entry[3])
    }
}

func writeSourcePixel(dst: [*] u8, header: Header, palette: Palette, src: const [*] u8) fail
{
    if isMappedType(header.imageTypeCode)
    {
        try writePalettePixel(dst, palette, paletteIndex(src, header.bitsPerPixel), hasAttributeBits(header))
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
    case 15: writeTga16Pixel(dst, cast(const *u16, src)[], false, false)
    case 16: writeTga16Pixel(dst, cast(const *u16, src)[], true, (header.descriptorByte & DESC_ALPHA_MASK) != 0)
    case 24: writeBgrPixel(dst, src[0], src[1], src[2])
    case 32: writeBgraPixel(dst, src[0], src[1], src[2], hasAttributeBits(header) ? src[3] : 255'u8)
    }
}

private func writeOpaqueSpan(destination: [*] u8, source: const [*] u8, count: u64, rightOrigin: bool)
{
    using Math.Simd

    const Reverse = cast(U8x16, [12'u8, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3])
    const Opaque  = 0xFF00_0000'u32
    let mask      = splat(Opaque)
    let samples   = cast(const [*] u32, source)
    let pixels    = cast([*] u32, destination)
    var offset    = 0'u64
    while count - offset >= 4
    {
        let start = rightOrigin ? count - offset - 4 : offset
        var values = load(samples + start) | mask
        if rightOrigin do
            values = cast #bit(U32x4, shuffle(cast #bit(U8x16, values), Reverse))
        store(pixels + offset, values)
        offset += 4
    }

    while offset < count
    {
        let index = rightOrigin ? count - offset - 1 : offset
        pixels[offset] = samples[index] | Opaque
        offset += 1
    }
}

private func(Index) writePaletteSpan(destination: [*] u8, source: const [*] Index, count: u64, palette: Palette, destinationBytes: s32, rightOrigin: bool) fail
{
    let colors = cast(const [*] u32, unwrap palette.colors)
    for x in count
    {
        let index = cast(u32, source[rightOrigin ? count - x - 1 : x])
        let key   = index - #wrap palette.first
        if key >= palette.count do
            fail InvalidFormatError{"invalid palette index"}

        let color = colors[key]
        let pixel = destination + x * destinationBytes
        if destinationBytes == 4
        {
            cast([*] u32, pixel)[0] = color
        }
        else
        {
            cast([*] u16, pixel)[0] = cast #wrap(u16, color)
            pixel[2] = cast(u8, (color >> 16))
        }
    }
}

private func(HAS_ALPHA: bool) writeGraySpan(destination: [*] u8, source: const [*] u8, count: u64, rightOrigin: bool)
{
    using Math.Simd

    const Reverse = cast(U8x16, [15'u8, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
    const Triplets0 = cast(U8x16, [0'u8, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5])
    const Triplets1 = cast(U8x16, [5'u8, 5, 6, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9, 10, 10])
    const Triplets2 = cast(U8x16, [10'u8, 11, 11, 11, 12, 12, 12, 13, 13, 13, 14, 14, 14, 15, 15, 15])
    const Quadruplets0 = cast(U8x16, [0'u8, 0, 0, 1, 2, 2, 2, 3, 4, 4, 4, 5, 6, 6, 6, 7])
    const Quadruplets1 = cast(U8x16, [8'u8, 8, 8, 9, 10, 10, 10, 11, 12, 12, 12, 13, 14, 14, 14, 15])
    const ReverseQuadruplets0 = cast(U8x16, [14'u8, 14, 14, 15, 12, 12, 12, 13, 10, 10, 10, 11, 8, 8, 8, 9])
    const ReverseQuadruplets1 = cast(U8x16, [6'u8, 6, 6, 7, 4, 4, 4, 5, 2, 2, 2, 3, 0, 0, 0, 1])
    const Pixels = HAS_ALPHA ? 8 : 16
    const InputBytes = HAS_ALPHA ? 2 : 1
    const OutputBytes = HAS_ALPHA ? 4 : 3

    var offset = 0'u64
    while count - offset >= Pixels
    {
        let index = rightOrigin ? count - offset - Pixels : offset
        let target = destination + offset * OutputBytes
        var luma = load(source + index * InputBytes)
        #static if HAS_ALPHA
        {
            store(target, shuffle(luma, rightOrigin ? ReverseQuadruplets0 : Quadruplets0))
            store(target + 16, shuffle(luma, rightOrigin ? ReverseQuadruplets1 : Quadruplets1))
        }
        else
        {
            if rightOrigin do
                luma = shuffle(luma, Reverse)
            store(target, shuffle(luma, Triplets0))
            store(target + 16, shuffle(luma, Triplets1))
            store(target + 32, shuffle(luma, Triplets2))
        }

        offset += Pixels
    }

    for x in offset until count
    {
        let index = rightOrigin ? count - x - 1 : x
        let pixel = source + index * InputBytes
        let target = destination + x * OutputBytes
        let luma = pixel[0]
        #static if HAS_ALPHA do
            writeBgraPixel(target, luma, luma, luma, pixel[1])
        else do
            writeBgrPixel(target, luma, luma, luma)
    }
}

private func writeSourceSpan(destination: [*] u8, source: const [*] u8, count: u64, header: Header, palette: Palette, sourceBytes: u8, destinationBytes: s32, rightOrigin: bool) fail
{
    if isMonoType(header.imageTypeCode)
    {
        if sourceBytes == 2 do
            writeGraySpan'true(destination, source, count, rightOrigin)
        else do
            writeGraySpan'false(destination, source, count, rightOrigin)
        return
    }

    if palette.colors
    {
        if sourceBytes == 1 do
            try writePaletteSpan'u8(destination, source, count, palette, destinationBytes, rightOrigin)
        else do
            try writePaletteSpan'u16(destination, cast(const [*] u16, source), count, palette, destinationBytes, rightOrigin)
        return
    }

    if header.bitsPerPixel == 32 and isRgbType(header.imageTypeCode) and not hasAttributeBits(header)
    {
        writeOpaqueSpan(destination, source, count, rightOrigin)
        return
    }

    if isRgbType(header.imageTypeCode)
    {
        if header.bitsPerPixel == 15
        {
            if rightOrigin do
                decodeTga15RowReversed(source, destination, count)
            else do
                decodeTga15Row(source, destination, count)
            return
        }

        if header.bitsPerPixel == 16
        {
            let alpha = hasAttributeBits(header)
            if rightOrigin do
                decodeTga16RowReversed(source, destination, count, alpha)
            else do
                decodeTga16Row(source, destination, count, alpha)
            return
        }
    }

    let step  = rightOrigin ? -destinationBytes : destinationBytes
    let first = destination + (rightOrigin ? (count - 1) * destinationBytes : 0)
    for x in count do
        try writeSourcePixel(first + cast(s64, x) * step, header, palette, source + x * sourceBytes)
}

func decodeRaw(result: *Image, header: Header, palette: Palette, src, last: const [*] u8, pixelBytes: u8, pixelCount: u64) fail
{
    var p = src
    try checkBuffer(p, last, pixelCount * pixelBytes)
    if header.imageTypeCode == TYPE_RGB and
       (header.bitsPerPixel == 24 or (header.bitsPerPixel == 32 and hasAttributeBits(header)))
    {
        let rightOrigin = (header.descriptorByte & DESC_ORIGIN_RIGHT) != 0
        let rowBytes    = cast(u64, result.width) * pixelBytes
        for y in result.height
        {
            let dstY = header.descriptorByte & DESC_ORIGIN_TOP ? result.height - y - 1 : y
            let dst  = cast([*] u8, result.pixels.storage()) + cast(u64, dstY) * result.rowStride
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

    let rightOrigin = (header.descriptorByte & DESC_ORIGIN_RIGHT) != 0
    let sourceStride = cast(u64, header.width) * pixelBytes
    let output = result.pixels.storage()
    for y in result.height
    {
        let dstY = header.descriptorByte & DESC_ORIGIN_TOP ? result.height - y - 1 : y
        let dst = output + cast(u64, dstY) * result.rowStride
        try writeSourceSpan(dst, p, header.width, header, palette, pixelBytes, result.bytesPerPixel, rightOrigin)
        p += sourceStride
    }
}

func decodeRle(result: *Image, header: Header, palette: Palette, src, last: const [*] u8, pixelBytes: u8, pixelCount: u64) fail
{
    let plain = header.imageTypeCode == TYPE_RLE_RGB and
                (header.bitsPerPixel == 24 or (header.bitsPerPixel == 32 and hasAttributeBits(header)))
    let rightOrigin = (header.descriptorByte & DESC_ORIGIN_RIGHT) != 0
    let outputBytes = result.bytesPerPixel
    var decoded: [4] u8
    var index: u64
    var p = src
    while index < pixelCount
    {
        try checkBuffer(p, last, 1)
        let packet = p[0]
        p += 1

        let count = cast(u64, ((packet & 0x7F) + 1))
        if index + count > pixelCount do
            fail InvalidFormatError{"invalid source buffer"}

        let repeated = (packet & 0x80) != 0
        try checkBuffer(p, last, repeated ? pixelBytes : count * pixelBytes)
        if repeated and not plain do
            try writeSourcePixel(&decoded[0], header, palette, p)

        var remaining = count
        var source    = p
        while remaining
        {
            let rowRemaining = cast(u64, header.width) - index % header.width
            let segmentCount = Math.min(remaining, rowRemaining)
            let dstIndex     = rightOrigin ? index + segmentCount - 1 : index
            let dst          = dstPixel(result, header, dstIndex)
            if repeated
            {
                let color = plain ? p : cast(const [*] u8, &decoded[0])
                if outputBytes == 3 do
                    PackedPixel.fillBgr24Row(color, dst, segmentCount)
                else do
                    PackedPixel.fillBgra32Row(color, dst, segmentCount)
            }
            else
            {
                if not plain do
                    try writeSourceSpan(dst, source, segmentCount, header, palette, pixelBytes, outputBytes, rightOrigin)
                elif not rightOrigin do
                    Memory.copy(dst, source, segmentCount * pixelBytes)
                elif outputBytes == 3 do
                    PackedPixel.reverseBgr24Row(source, dst, segmentCount)
                else do
                    PackedPixel.reverseBgra32Row(source, dst, segmentCount)
                source += segmentCount * pixelBytes
            }

            index     += segmentCount
            remaining -= segmentCount
        }

        p += repeated ? pixelBytes : count * pixelBytes
    }
}

internal impl IImageDecoder for Decoder
{
    func impl format(me)->ImageFormat => {"TGA - Truevision Targa", ".tga;.icb;.vda;.vst"}

    func impl decode(me, buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        var dataof  = buffer.buffer
        let countof = buffer.count
        let last    = dataof + countof

        if countof < #sizeof(Header) do
            fail InvalidFormatError{"invalid source buffer"}

        let header = cast(const *Header, dataof)[]
        dataof += #sizeof(Header)

        if header.width == 0 or header.height == 0 do
            fail InvalidFormatError{"invalid dimensions"}
        if header.colorMapType != 0 and header.colorMapType != 1 do
            fail UnsupportedFormatError{"unsupported palette"}
        if (header.descriptorByte & 0xC0) != 0 do
            fail UnsupportedFormatError{"unsupported interleave mode"}

        let pixelBytes = try sourcePixelBytes(header)
        try checkBuffer(dataof, last, header.idLength)
        dataof += header.idLength

        var palette: Palette
        if header.colorMapType
        {
            palette.first         = header.colorMapFirst
            palette.count         = header.colorMapLength
            palette.bitsPerPixel  = header.colorMapBpp
            palette.bytesPerPixel = try palettePixelBytes(header.colorMapBpp)
            palette.data          = dataof
            try checkBuffer(dataof, last, cast(u64, palette.count) * palette.bytesPerPixel)
            dataof += cast(u64, palette.count) * palette.bytesPerPixel
        }

        if isMappedType(header.imageTypeCode) and not palette.count do
            fail InvalidFormatError{"missing palette"}

        let width  = cast(s32, header.width)
        let height = cast(s32, header.height)
        let format = try pixelFormat(header, palette)
        try options.checkImage(width, height, format)

        var result: #returntype
        result.init(width, height, format)

        if not options.decodePixels do
            return result

        result.allocPixels()
        let pixelCount = cast(u64, result.width) * result.height
        var colors: Array'u32
        if isMappedType(header.imageTypeCode) and pixelCount >= palette.count
        {
            colors.resize(palette.count)
            let packed = cast([*] u8, colors.storage())
            for i in palette.count do
                try writePalettePixel(packed + i * 4, palette, cast(u32, palette.first) + i, hasAttributeBits(header))
            palette.colors = colors.storage()
        }

        if isRleType(header.imageTypeCode) do
            try decodeRle(&result, header, palette, dataof, last, pixelBytes, pixelCount)
        else do
            try decodeRaw(&result, header, palette, dataof, last, pixelBytes, pixelCount)

        return result
    }
}
