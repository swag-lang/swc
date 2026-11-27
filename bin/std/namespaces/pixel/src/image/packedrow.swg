#global namespace PackedPixel

using Core

private const ReverseBgr24  = cast(Math.Simd.U8x16, [13_u8, 14, 15, 10, 11, 12, 7, 8, 9, 4, 5, 6, 128, 128, 128, 128])
private const ReverseBgra32 = cast(Math.Simd.U8x16, [12_u8, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3])
private const RepeatBgr24   = cast(Math.Simd.U8x16, [0_u8, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 128, 128, 128, 128])
private const SwapRedBlue24 = cast(Math.Simd.U8x16, [2_u8, 1, 0, 5, 4, 3, 8, 7, 6, 11, 10, 9, 128, 128, 128, 128])
private const SwapRedBlue32 = cast(Math.Simd.U8x16, [2_u8, 1, 0, 3, 6, 5, 4, 7, 10, 9, 8, 11, 14, 13, 12, 15])
private const ShiftBytes1   = cast(Math.Simd.U8x16, [0x80_u8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])
private const ShiftBytes2   = cast(Math.Simd.U8x16, [0x80_u8, 0x80, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
private const ShiftBytes3   = cast(Math.Simd.U8x16, [0x80_u8, 0x80, 0x80, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
private const ShiftBytes4   = cast(Math.Simd.U8x16, [0x80_u8, 0x80, 0x80, 0x80, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
private const ShiftBytes6   = cast(Math.Simd.U8x16, [0x80_u8, 0x80, 0x80, 0x80, 0x80, 0x80, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
private const ShiftBytes8   = cast(Math.Simd.U8x16, [0x80_u8, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0, 1, 2, 3, 4, 5, 6, 7])
private const ShiftBytes12  = cast(Math.Simd.U8x16, [0x80_u8, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0, 1, 2, 3])
private const CarryBytes6   = cast(Math.Simd.U8x16, [0_u8, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 0, 1, 2, 3])
private const CarryBytes3   = cast(Math.Simd.U8x16, [12_u8, 13, 14, 12, 13, 14, 12, 13, 14, 12, 13, 14, 12, 13, 14, 12])

func countSame24(pixel, source: const [*] u8, pixelCount: u64)->u64
{
    using Math.Simd
    let pair    = cast(const *u16, pixel)[]
    let last    = pixel[2]
    let word    = cast(u32, pair) | (cast(u32, last) << 16)
    let pattern = shuffle(cast #bit(U8x16, splat(word)), RepeatBgr24)
    var x       = 0_u64
    while pixelCount - x >= 6
    {
        let matches = bitmask(load(source + x * 3) == pattern)
        if (matches & 0xFFF) != 0xFFF
        {
            break
        }

        x += 4
    }

    while x < pixelCount
    {
        let at = source + x * 3
        if cast(const *u16, at)[] != pair or at[2] != last
        {
            break
        }

        x += 1
    }

    return x
}

func countSame32(pixel, source: const [*] u8, pixelCount: u64)->u64
{
    let pattern = Math.Simd.splat(cast(const *u32, pixel)[])
    var x       = 0_u64
    while pixelCount - x >= 4
    {
        if not Math.Simd.allTrue(Math.Simd.load(cast(const [*] u32, source) + x) == pattern)
        {
            break
        }

        x += 4
    }

    while x < pixelCount
    {
        if cast(const [*] u32, source)[x] != cast(const *u32, pixel)[]
        {
            break
        }

        x += 1
    }

    return x
}

func swapRedBlue24Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    var x = 0_u64
    while pixelCount - x >= 6
    {
        Image.storeLow12(destination + x * 3, Math.Simd.shuffle(Math.Simd.load(source + x * 3), SwapRedBlue24))
        x += 4
    }

    while x < pixelCount
    {
        let srcPixel = source + x * 3
        let dstPixel = destination + x * 3
        dstPixel[0] = srcPixel[2]
        dstPixel[1] = srcPixel[1]
        dstPixel[2] = srcPixel[0]
        x += 1
    }
}

func swapRedBlue32Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    var x = 0_u64
    while pixelCount - x >= 4
    {
        Math.Simd.store(destination + x * 4, Math.Simd.shuffle(Math.Simd.load(source + x * 4), SwapRedBlue32))
        x += 4
    }

    while x < pixelCount
    {
        let srcPixel = source + x * 4
        let dstPixel = destination + x * 4
        dstPixel[0] = srcPixel[2]
        dstPixel[1] = srcPixel[1]
        dstPixel[2] = srcPixel[0]
        dstPixel[3] = srcPixel[3]
        x += 1
    }
}

// Eight-bit alpha conversion is independent for each channel. Use the same normalized
// rounding as Image.convertAlphaTo, including zeroing RGB when the alpha sample is zero.
private func buildStraightAlpha8Table()->[65536] u8
{
    var result: #returntype
    for alpha in 1 until 256
    {
        let a = cast(f32, alpha) / 255.0
        for channel in 256

        {
            result[(alpha << 8) | channel] = normalizedToU8((cast(f32, channel) / 255.0) / a)
        }
    }

    return result
}

private const StraightAlpha8Table = #run buildStraightAlpha8Table()

// Copies premultiplied RGBA8 or BGRA8 samples as straight alpha.
// Source and target may be the same buffer.
func writeStraightAlpha8(source: const [*] u8, target: [*] u8, count: u64, swapRedBlue: bool)
{
    let blue = swapRedBlue ? 2 : 0
    let red  = 2 - blue
    for i in count
    {
        let input  = source + i * 4
        let output = target + i * 4
        let alpha  = input[3]
        let values = StraightAlpha8Table.buffer + (cast(u32, alpha) << 8)
        let b      = values[input[blue]]
        let g      = values[input[1]]
        let r      = values[input[red]]
        output[0] = b
        output[1] = g
        output[2] = r
        output[3] = alpha
    }
}

func fillBgr24Row(pixel: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    let packed  = cast(u32, pixel[0]) | (cast(u32, pixel[1]) << 8) | (cast(u32, pixel[2]) << 16)
    let pattern = Math.Simd.shuffle(cast #bit(Math.Simd.U8x16, Math.Simd.splat(packed)), RepeatBgr24)
    var x       = 0_u64
    while pixelCount - x >= 4
    {
        Image.storeLow12(destination + x * 3, pattern)
        x += 4
    }

    while x < pixelCount
    {
        let dstPixel = destination + x * 3
        dstPixel[0] = pixel[0]
        dstPixel[1] = pixel[1]
        dstPixel[2] = pixel[2]
        x += 1
    }
}

func fillBgra32Row(pixel: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    let pattern = Math.Simd.splat(cast(const *u32, pixel)[])
    var x       = 0_u64
    while pixelCount - x >= 4
    {
        Math.Simd.store(cast([*] u32, destination) + x, pattern)
        x += 4
    }

    while x < pixelCount
    {
        cast([*] u32, destination)[x] = cast(const *u32, pixel)[]
        x += 1
    }
}

func reverseBgr24Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    var x = 0_u64
    while pixelCount - x >= 6
    {
        let srcBlock = source + (pixelCount - x - 4) * 3
        let pixels   = Math.Simd.load(srcBlock - 4)
        Image.storeLow12(destination + x * 3, Math.Simd.shuffle(pixels, ReverseBgr24))
        x += 4
    }

    while x < pixelCount
    {
        let srcPixel = source + (pixelCount - x - 1) * 3
        let dstPixel = destination + x * 3
        dstPixel[0] = srcPixel[0]
        dstPixel[1] = srcPixel[1]
        dstPixel[2] = srcPixel[2]
        x += 1
    }
}

func reverseBgra32Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    var x = 0_u64
    while pixelCount - x >= 4
    {
        let srcBlock = source + (pixelCount - x - 4) * 4
        Math.Simd.store(destination + x * 4, Math.Simd.shuffle(Math.Simd.load(srcBlock), ReverseBgra32))
        x += 4
    }

    while x < pixelCount
    {
        cast([*] u32, destination)[x] = cast(const [*] u32, source)[pixelCount - x - 1]
        x += 1
    }
}

// Restores each byte delta against the corresponding byte of the preceding pixel.
func restoreHorizontalDeltas(source: const [*] u8, destination: [*] u8, count, bytesPerPixel: u64)
{
    var offset = 0_u64
    while offset < bytesPerPixel and offset < count
    {
        destination[offset] = source[offset]
        offset += 1
    }

    switch bytesPerPixel
    {
    case 1:
        while count - offset >= 16
        {
            var values = Math.Simd.load(source + offset)
            values += Math.Simd.shuffle(values, ShiftBytes1)
            values += Math.Simd.shuffle(values, ShiftBytes2)
            values += Math.Simd.shuffle(values, ShiftBytes4)
            values += Math.Simd.shuffle(values, ShiftBytes8)
            values += Math.Simd.splat(destination[offset - 1])
            Math.Simd.store(destination + offset, values)
            offset += 16
        }

    case 2:
        while count - offset >= 16
        {
            var values = Math.Simd.load(source + offset)
            values += Math.Simd.shuffle(values, ShiftBytes2)
            values += Math.Simd.shuffle(values, ShiftBytes4)
            values += Math.Simd.shuffle(values, ShiftBytes8)
            let carry = cast(const [*] u16, (destination + offset - 2))[0]
            values += cast #bit(Math.Simd.U8x16, Math.Simd.splat(carry))
            Math.Simd.store(destination + offset, values)
            offset += 16
        }

    case 3:

        // Carry the last complete RGB pixel to the next block. The extra byte
        // of each store remains inside the row and is overwritten later.
        if count >= 16
        {
            var carry = Math.Simd.splat(0_u8)
            offset = 0
            while count - offset >= 16
            {
                var values = Math.Simd.load(source + offset)
                values += Math.Simd.shuffle(values, ShiftBytes3)
                values += Math.Simd.shuffle(values, ShiftBytes6)
                values += Math.Simd.shuffle(values, ShiftBytes12)
                values += carry
                carry  = Math.Simd.shuffle(values, CarryBytes3)
                Math.Simd.store(destination + offset, values)
                offset += 15
            }
        }

    case 4:
        while count - offset >= 16
        {
            var values = Math.Simd.load(source + offset)
            values += Math.Simd.shuffle(values, ShiftBytes4)
            values += Math.Simd.shuffle(values, ShiftBytes8)
            let carry = cast(const [*] u32, (destination + offset - 4))[0]
            values += cast #bit(Math.Simd.U8x16, Math.Simd.splat(carry))
            Math.Simd.store(destination + offset, values)
            offset += 16
        }

    case 6:

        // Two six-byte pixels are complete per step; the four extra bytes
        // stay inside the row and are rewritten by the next step or tail.
        while count - offset >= 16
        {
            var values = Math.Simd.load(source + offset)
            values += Math.Simd.shuffle(values, ShiftBytes6)
            values += Math.Simd.shuffle(values, ShiftBytes12)
            let carry = cast #bit(Math.Simd.U8x16, Math.Simd.splat(cast(const [*] u64, (destination + offset - 6))[0]))
            values += Math.Simd.shuffle(carry, CarryBytes6)
            Math.Simd.store(destination + offset, values)
            offset += 12
        }

    case 8:
        while count - offset >= 16
        {
            var values = Math.Simd.load(source + offset)
            values += Math.Simd.shuffle(values, ShiftBytes8)
            let carry = cast(const [*] u64, (destination + offset - 8))[0]
            values += cast #bit(Math.Simd.U8x16, Math.Simd.splat(carry))
            Math.Simd.store(destination + offset, values)
            offset += 16
        }
    }

    while offset < count
    {
        destination[offset] = cast #bit(u8, (source[offset] + #wrap destination[offset - bytesPerPixel]))
        offset += 1
    }
}

// Arranges a palette of at most sixteen packed colors into byte lookup tables.
#[Swag.Inline]
func smallPaletteTables(packed: const [*] u32, paletteSize: u64)->[4] Math.Simd.U8x16
{
    // One byte table per channel, indexed by the low four bits of each source byte.
    var channels: [4 * 16] u8
    for index in paletteSize
    {
        let word = packed[index]
        channels[index + 0]  = cast(u8, (word & 255))
        channels[index + 16] = cast(u8, ((word >> 8) & 255))
        channels[index + 32] = cast(u8, ((word >> 16) & 255))
        channels[index + 48] = cast(u8, (word >> 24))
    }

    var tables: [4] Math.Simd.U8x16
    for channel in 4
    {
        tables[channel] = Math.Simd.load(&channels[channel * 16])
    }

    return tables
}

const PaletteDropAlpha = cast(Math.Simd.U8x16, [0_u8, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 128, 128, 128, 128])

#[Swag.Inline]
private func(HAS_ALPHA: bool) writeSmallPaletteHalf(target: [*] u8, redGreen, blueAlpha: Math.Simd.U8x16)
{
    let rg     = cast #bit(Math.Simd.U16x8, redGreen)
    let ba     = cast #bit(Math.Simd.U16x8, blueAlpha)
    let first  = cast #bit(Math.Simd.U8x16, Math.Simd.interleaveLow(rg, ba))
    let second = cast #bit(Math.Simd.U8x16, Math.Simd.interleaveHigh(rg, ba))
    #static if HAS_ALPHA
    {
        Math.Simd.store(target, first)
        Math.Simd.store(target + 16, second)
    }
    else
    {
        Image.storeLow12(target, Math.Simd.shuffle(first, PaletteDropAlpha))
        Image.storeLow12(target + 12, Math.Simd.shuffle(second, PaletteDropAlpha))
    }
}

#[Swag.Inline]
func(HAS_ALPHA: bool) writeSmallPaletteRow(source: const [*] u8, target: [*] u8, width: s32, tables: const [*] Math.Simd.U8x16, combined: *Math.Simd.U8x16)->s32
{
    const Step = HAS_ALPHA ? 4 : 3
    var x = 0
    while width - x >= 16
    {
        let keys = Math.Simd.load(source + x)
        combined[] |= keys
        let r = Math.Simd.shuffle(tables[0], keys)
        let g = Math.Simd.shuffle(tables[1], keys)
        let b = Math.Simd.shuffle(tables[2], keys)
        let a = Math.Simd.shuffle(tables[3], keys)
        let destination = target + x * Step
        writeSmallPaletteHalf!{HAS_ALPHA}(destination, Math.Simd.interleaveLow(r, g), Math.Simd.interleaveLow(b, a))
        writeSmallPaletteHalf!{HAS_ALPHA}(destination + 8 * Step, Math.Simd.interleaveHigh(r, g), Math.Simd.interleaveHigh(b, a))
        x += 16
    }

    return x
}
