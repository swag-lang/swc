//! Format: Windows Bitmap (BMP/DIB) decoder component.
//! Supported: Windows and OS/2 headers; 1-, 4-, 8-, 16-, 24-, and 32-bit pixels; palettes, RGB, bitfields, RLE4, RLE8, and either row direction.
//! Not supported: JPEG/PNG-compressed BMP payloads and other compression modes.
//! Role: This file owns RLE4 and RLE8 command decoding.
//
#global namespace Bmp

using Core, Core.Errors

func decodeRle8(result: *Image, src, last: const [*] u8, palette: const [*] u8, paletteEntrySize, paletteCount: u32) fail
{
    try checkBuffer(src, last, 2)
    let commandEnd = last - 1
    let entries    = makePackedPalette(palette, paletteEntrySize, paletteCount)
    let colors     = cast(const [*] u32, &entries[0])
    let pixels     = result.pixels.storage()
    let height     = result.height
    let stride     = cast(u64, result.rowStride)
    var rowEnd     = stride
    var offset: u64
    var y:      s32
    var p          = src

    while p < commandEnd and y < height
    {
        let count = p[0]
        let value = p[1]
        p += 2

        if count
        {
            let runBytes = cast(u64, count) * 3
            if runBytes > rowEnd - offset do
                fail InvalidFormatError{"invalid source buffer"}
            if value >= paletteCount do
                fail InvalidFormatError{"BMP RLE8 index exceeds its palette"}

            let dst = pixels + offset
            if count < 4
            {
                let color = colors[value]
                for i in count do
                    writePackedBgr(dst + cast(u64, i) * 3, color)
            }
            else
            {
                let entry = palette + cast(u64, value) * paletteEntrySize
                PackedPixel.fillBgr24Row(entry, dst, count)
            }

            offset += runBytes
            continue
        }

        switch value
        {
        case FILL_RLE_ENDOFLINE:
            offset = rowEnd
            y      += 1
            rowEnd += stride

        case FILL_RLE_ENDOFBITMAP:
            return

        case FILL_RLE_DELTA:
            try checkBuffer(p, last, 2)
            let horizontal = cast(u64, p[0]) * 3
            let dy         = p[1]
            if horizontal > rowEnd - offset or dy > height - y do
                fail InvalidFormatError{"invalid source buffer"}
            let vertical = cast(u64, dy) * stride
            offset += horizontal + vertical
            y      += dy
            rowEnd += vertical
            p      += 2

        default:
            let absoluteCount = cast(u32, value)
            let padding       = absoluteCount & 1
            try checkBuffer(p, last, absoluteCount + padding)
            let runBytes = cast(u64, absoluteCount) * 3
            if runBytes > rowEnd - offset do
                fail InvalidFormatError{"invalid source buffer"}

            if paletteCount < 256 and not palette8RowFits(p, absoluteCount, paletteCount) do
                fail InvalidFormatError{"BMP RLE8 index exceeds its palette"}

            let dst = pixels + offset
            decodePalette8Row(p, dst, absoluteCount, colors)

            p      += absoluteCount + padding
            offset += runBytes
        }
    }

    // The compressed bitmap is not complete until its explicit end marker is present.
    if p >= commandEnd or p[0] != 0 or p[1] != FILL_RLE_ENDOFBITMAP do
        fail InvalidFormatError{"invalid source buffer"}
}

func rle4Index(value: u8, index: u32)->u32 => cast(u32, ((index & 1) ? (value & 0x0F) : (value >> 4)))

private func fillPalettePair(destination: [*] u8, count: u64, pair: u64)
{
    const RepeatPair = cast(Math.Simd.U8x16, [0'u8, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 128, 128, 128, 128])
    let block = Math.Simd.shuffle(cast #bit(Math.Simd.U8x16, Math.Simd.splat(pair)), RepeatPair)
    var dst   = destination
    for count / 4
    {
        Image.storeLow12(dst, block)
        dst += 12
    }

    for i in count & 3
    {
        let color = i & 1 ? pair >> 24 : pair & 0xFF_FFFF
        writePackedBgr(dst + i * 3, cast(u32, color))
    }
}

func decodeRle4(result: *Image, src, last: const [*] u8, palette: const [*] u8, paletteEntrySize, paletteCount: u32) fail
{
    try checkBuffer(src, last, 2)
    let commandEnd = last - 1
    let entries    = makePackedPalette(palette, paletteEntrySize, paletteCount)
    let colors     = cast(const [*] u32, &entries[0])
    let pairs      = makePalettePairs(colors)
    let pixels     = result.pixels.storage()
    let height     = result.height
    let stride     = cast(u64, result.rowStride)
    var rowEnd     = stride
    var offset: u64
    var y:      s32
    var p          = src

    while p < commandEnd and y < height
    {
        let count = p[0]
        let value = p[1]
        p += 2

        if count
        {
            let runBytes = cast(u64, count) * 3
            if runBytes > rowEnd - offset do
                fail InvalidFormatError{"invalid source buffer"}
            if rle4Index(value, 0) >= paletteCount or
               (count > 1 and rle4Index(value, 1) >= paletteCount) do
                fail InvalidFormatError{"BMP RLE4 index exceeds its palette"}

            let dst = pixels + offset
            fillPalettePair(dst, count, pairs[value])

            offset += runBytes
            continue
        }

        switch value
        {
        case FILL_RLE_ENDOFLINE:
            offset = rowEnd
            y      += 1
            rowEnd += stride

        case FILL_RLE_ENDOFBITMAP:
            return

        case FILL_RLE_DELTA:
            try checkBuffer(p, last, 2)
            let horizontal = cast(u64, p[0]) * 3
            let dy         = p[1]
            if horizontal > rowEnd - offset or dy > height - y do
                fail InvalidFormatError{"invalid source buffer"}
            let vertical = cast(u64, dy) * stride
            offset += horizontal + vertical
            y      += dy
            rowEnd += vertical
            p      += 2

        default:
            let pixelCount = cast(u32, value)
            let byteCount  = (pixelCount + 1) / 2
            let padding    = byteCount & 1
            try checkBuffer(p, last, byteCount + padding)
            let runBytes = cast(u64, pixelCount) * 3
            if runBytes > rowEnd - offset do
                fail InvalidFormatError{"invalid source buffer"}

            if paletteCount < 16 and not palette4RowFits(p, pixelCount, paletteCount) do
                fail InvalidFormatError{"BMP RLE4 index exceeds its palette"}

            let dst = pixels + offset
            decodePalette4Row(p, dst, pixelCount, colors, cast(const [*] u64, &pairs[0]))

            p      += byteCount + padding
            offset += runBytes
        }
    }

    // The compressed bitmap is not complete until its explicit end marker is present.
    if p >= commandEnd or p[0] != 0 or p[1] != FILL_RLE_ENDOFBITMAP do
        fail InvalidFormatError{"invalid source buffer"}
}
