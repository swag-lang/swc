#global namespace Bmp

using Core, Core.Errors

const Expand5Low  = cast(Math.Simd.U8x16) [0'u8, 8, 16, 25, 33, 41, 49, 58, 66, 74, 82, 90, 99, 107, 115, 123]
const Expand5High = cast(Math.Simd.U8x16) [132'u8, 140, 148, 156, 165, 173, 181, 189, 197, 206, 214, 222, 230, 239, 247, 255]
const BgrB0       = cast(Math.Simd.U8x16) [0'u8, 0x80, 0x80, 1, 0x80, 0x80, 2, 0x80, 0x80, 3, 0x80, 0x80, 4, 0x80, 0x80, 5]
const BgrG0       = cast(Math.Simd.U8x16) [0x80'u8, 0, 0x80, 0x80, 1, 0x80, 0x80, 2, 0x80, 0x80, 3, 0x80, 0x80, 4, 0x80, 0x80]
const BgrR0       = cast(Math.Simd.U8x16) [0x80'u8, 0x80, 0, 0x80, 0x80, 1, 0x80, 0x80, 2, 0x80, 0x80, 3, 0x80, 0x80, 4, 0x80]
const BgrB1       = cast(Math.Simd.U8x16) [0x80'u8, 0x80, 6, 0x80, 0x80, 7, 0x80, 0x80, 8, 0x80, 0x80, 9, 0x80, 0x80, 10, 0x80]
const BgrG1       = cast(Math.Simd.U8x16) [5'u8, 0x80, 0x80, 6, 0x80, 0x80, 7, 0x80, 0x80, 8, 0x80, 0x80, 9, 0x80, 0x80, 10]
const BgrR1       = cast(Math.Simd.U8x16) [0x80'u8, 5, 0x80, 0x80, 6, 0x80, 0x80, 7, 0x80, 0x80, 8, 0x80, 0x80, 9, 0x80, 0x80]
const BgrB2       = cast(Math.Simd.U8x16) [0x80'u8, 11, 0x80, 0x80, 12, 0x80, 0x80, 13, 0x80, 0x80, 14, 0x80, 0x80, 15, 0x80, 0x80]
const BgrG2       = cast(Math.Simd.U8x16) [0x80'u8, 0x80, 11, 0x80, 0x80, 12, 0x80, 0x80, 13, 0x80, 0x80, 14, 0x80, 0x80, 15, 0x80]
const BgrR2       = cast(Math.Simd.U8x16) [10'u8, 0x80, 0x80, 11, 0x80, 0x80, 12, 0x80, 0x80, 13, 0x80, 0x80, 14, 0x80, 0x80, 15]

#[Swag.Inline]
func expand5Packed(value: Math.Simd.U8x16)->Math.Simd.U8x16
{
    let high = value > Math.Simd.splat(15'u8)
    return Math.Simd.select(high, Math.Simd.shuffle(Expand5High, value), Math.Simd.shuffle(Expand5Low, value))
}

func decodeBgr555Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    var src   = source
    var dst   = destination
    var count = pixelCount
    while count >= 16
    {
        let lowPixels  = Math.Simd.load(cast(const [*] u16) src)
        let highPixels = Math.Simd.load(cast(const [*] u16) (src + 16))
        let b          = expand5Packed(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) (lowPixels & 31'u16),
                                                              cast #bit(Math.Simd.S16x8) (highPixels & 31'u16)))
        let g = expand5Packed(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) ((lowPixels >> 5) & 31'u16),
                                                     cast #bit(Math.Simd.S16x8) ((highPixels >> 5) & 31'u16)))
        let r = expand5Packed(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) ((lowPixels >> 10) & 31'u16),
                                                     cast #bit(Math.Simd.S16x8) ((highPixels >> 10) & 31'u16)))
        Math.Simd.store(dst, Math.Simd.shuffle(b, BgrB0) | Math.Simd.shuffle(g, BgrG0) | Math.Simd.shuffle(r, BgrR0))
        Math.Simd.store(dst + 16, Math.Simd.shuffle(b, BgrB1) | Math.Simd.shuffle(g, BgrG1) | Math.Simd.shuffle(r, BgrR1))
        Math.Simd.store(dst + 32, Math.Simd.shuffle(b, BgrB2) | Math.Simd.shuffle(g, BgrG2) | Math.Simd.shuffle(r, BgrR2))
        src   += 32
        dst   += 48
        count -= 16
    }

    while count
    {
        let pixel = cast(u32) src[as u16]
        dst[0] = cast(u8) (((pixel & 0x1F) * 255 + 15) / 31)
        dst[1] = cast(u8) ((((pixel >> 5) & 0x1F) * 255 + 15) / 31)
        dst[2] = cast(u8) ((((pixel >> 10) & 0x1F) * 255 + 15) / 31)
        src    += 2
        dst    += 3
        count  -= 1
    }
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

func writePalettePixel(dst: [*] u8, palette: const [*] u8, paletteEntrySize: u32, index, paletteCount: u32) fail
{
    if index >= paletteCount do
        fail InvalidFormatError{"invalid palette index"}

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

func decodePackedPalette(result: *Image, src, last: const [*] u8, palette: const [*] u8, paletteEntrySize, paletteCount: u32, bitCount: u16, topDown: bool) fail
{
    let stride = rowStride(result.width, bitCount)
    checkBuffer(src, last, stride * cast(u64) result.height)

    for y in result.height
    {
        let dstY   = topDown ? result.height - y - 1 : y
        let srcRow = src + stride * cast(u64) y
        var dst    = cast([*] u8) result.pixels.buffer! + cast(u64) dstY * result.rowStride
        for x in result.width
        {
            writePalettePixel(dst, palette, paletteEntrySize, packedIndex(srcRow, bitCount, x), paletteCount)
            dst += 3
        }
    }
}

func decodeUncompressedDirect(result: *Image, src, last: const [*] u8, bitCount: u16, topDown: bool) fail
{
    let stride   = rowStride(result.width, bitCount)
    let rowBytes = cast(u64) result.width * result.bytesPerPixel
    checkBuffer(src, last, stride * cast(u64) result.height)

    for y in result.height
    {
        let dstY = topDown ? result.height - y - 1 : y
        Memory.copy(cast([*] u8) result.pixels.buffer! + cast(u64) dstY * rowBytes, src + stride * cast(u64) y, rowBytes)
    }
}

func decode16Row(source: const [*] u8, destination: [*] u8, pixelCount: u64, masks: Masks)
{
    if masks.r.value == 0x7C00 and masks.g.value == 0x03E0 and masks.b.value == 0x001F and !masks.a.value
    {
        decodeBgr555Row(source, destination, pixelCount)
        return
    }

    var src = source
    var dst = destination
    for pixelCount
    {
        writeMaskedPixel(dst, src[as u16], masks, false)
        src += 2
        dst += 3
    }
}

func decode16(result: *Image, src, last: const [*] u8, masks: Masks, topDown: bool) fail
{
    let stride = rowStride(result.width, 16)
    checkBuffer(src, last, stride * cast(u64) result.height)

    for y in result.height
    {
        let dstY   = topDown ? result.height - y - 1 : y
        let srcPix = src + stride * cast(u64) y
        let dst    = cast([*] u8) result.pixels.buffer! + cast(u64) dstY * result.rowStride
        decode16Row(srcPix, dst, result.width, masks)
    }
}
