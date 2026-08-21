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
        PackedPixel.decodeBgr555Row(source, destination, pixelCount)
        return
    }

    if masks.r.value == 0xF800 and masks.g.value == 0x07E0 and masks.b.value == 0x001F and !masks.a.value
    {
        PackedPixel.decodeBgr565Row(source, destination, pixelCount)
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
