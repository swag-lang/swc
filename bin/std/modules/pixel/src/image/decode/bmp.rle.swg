#global namespace Bmp

using Core, Core.Errors

func decodeRle8(result: *Image, src, last: const [*] u8, palette: const [*] u8, paletteEntrySize, paletteCount: u32) fail
{
    var x: s32
    var y: s32
    var p = src

    while p < last and y < result.height
    {
        checkBuffer(p, last, 2)
        let count = p[0]
        let value = p[1]
        p += 2

        if count
        {
            if x + count > result.width do
                fail InvalidFormatError{"invalid source buffer"}

            var dst = cast([*] u8) (notnull result.pixels.buffer) + cast(u64) y * result.width8 + cast(u64) x * 3
            for count
            {
                writePalettePixel(dst, palette, paletteEntrySize, value, paletteCount)
                dst += 3
            }

            x += count
            continue
        }

        switch value
        {
        case FILL_RLE_ENDOFLINE:
            x = 0
            y += 1

        case FILL_RLE_ENDOFBITMAP:
            return

        case FILL_RLE_DELTA:
            checkBuffer(p, last, 2)
            x += p[0]
            y += p[1]
            p += 2
            if x > result.width or y > result.height do
                fail InvalidFormatError{"invalid source buffer"}

        default:
            let absoluteCount = cast(u32) value
            let padding       = absoluteCount & 1
            checkBuffer(p, last, absoluteCount + padding)
            if x + absoluteCount > result.width do
                fail InvalidFormatError{"invalid source buffer"}

            var dst = cast([*] u8) (notnull result.pixels.buffer) + cast(u64) y * result.width8 + cast(u64) x * 3
            for [i] in absoluteCount
            {
                writePalettePixel(dst, palette, paletteEntrySize, p[i], paletteCount)
                dst += 3
            }

            p += absoluteCount
            if padding do
                p += 1
            x     += absoluteCount
        }
    }
}

func rle4Index(value: u8, index: u32)->u32
{
    return cast(u32) ((index & 1) ? (value & 0x0F) : (value >> 4))
}

func decodeRle4(result: *Image, src, last: const [*] u8, palette: const [*] u8, paletteEntrySize, paletteCount: u32) fail
{
    var x: s32
    var y: s32
    var p = src

    while p < last and y < result.height
    {
        checkBuffer(p, last, 2)
        let count = p[0]
        let value = p[1]
        p += 2

        if count
        {
            if x + count > result.width do
                fail InvalidFormatError{"invalid source buffer"}

            var dst = cast([*] u8) (notnull result.pixels.buffer) + cast(u64) y * result.width8 + cast(u64) x * 3
            for [i] in count
            {
                writePalettePixel(dst, palette, paletteEntrySize, rle4Index(value, i), paletteCount)
                dst += 3
            }

            x += count
            continue
        }

        switch value
        {
        case FILL_RLE_ENDOFLINE:
            x = 0
            y += 1

        case FILL_RLE_ENDOFBITMAP:
            return

        case FILL_RLE_DELTA:
            checkBuffer(p, last, 2)
            x += p[0]
            y += p[1]
            p += 2
            if x > result.width or y > result.height do
                fail InvalidFormatError{"invalid source buffer"}

        default:
            let pixelCount = cast(u32) value
            let byteCount  = (pixelCount + 1) / 2
            let padding    = byteCount & 1
            checkBuffer(p, last, byteCount + padding)
            if x + pixelCount > result.width do
                fail InvalidFormatError{"invalid source buffer"}

            var dst = cast([*] u8) (notnull result.pixels.buffer) + cast(u64) y * result.width8 + cast(u64) x * 3
            for [i] in pixelCount
            {
                writePalettePixel(dst, palette, paletteEntrySize, rle4Index(p[i / 2], i), paletteCount)
                dst += 3
            }

            p += byteCount
            if padding do
                p += 1
            x     += pixelCount
        }
    }
}
