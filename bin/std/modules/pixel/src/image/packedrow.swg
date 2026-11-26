#global namespace PackedPixel

using Core

private const ReverseBgr24  = cast(Math.Simd.U8x16, [13'u8, 14, 15, 10, 11, 12, 7, 8, 9, 4, 5, 6, 128, 128, 128, 128])
private const ReverseBgra32 = cast(Math.Simd.U8x16, [12'u8, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3])
private const RepeatBgr24   = cast(Math.Simd.U8x16, [0'u8, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 128, 128, 128, 128])
private const SwapRedBlue24 = cast(Math.Simd.U8x16, [2'u8, 1, 0, 5, 4, 3, 8, 7, 6, 11, 10, 9, 128, 128, 128, 128])
private const SwapRedBlue32 = cast(Math.Simd.U8x16, [2'u8, 1, 0, 3, 6, 5, 4, 7, 10, 9, 8, 11, 14, 13, 12, 15])
private const ShiftBytes1      = cast(Math.Simd.U8x16, [0x80'u8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])
private const ShiftBytes2      = cast(Math.Simd.U8x16, [0x80'u8, 0x80, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
private const ShiftBytes3      = cast(Math.Simd.U8x16, [0x80'u8, 0x80, 0x80, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
private const ShiftBytes4      = cast(Math.Simd.U8x16, [0x80'u8, 0x80, 0x80, 0x80, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
private const ShiftBytes6      = cast(Math.Simd.U8x16, [0x80'u8, 0x80, 0x80, 0x80, 0x80, 0x80, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
private const ShiftBytes8      = cast(Math.Simd.U8x16, [0x80'u8, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0, 1, 2, 3, 4, 5, 6, 7])
private const ShiftBytes12     = cast(Math.Simd.U8x16, [0x80'u8, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0, 1, 2, 3])
private const CarryBytes6      = cast(Math.Simd.U8x16, [0'u8, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 0, 1, 2, 3])
private const CarryBytes3      = cast(Math.Simd.U8x16, [0'u8, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0])

func countSame32(pixel, source: const [*] u8, pixelCount: u64)->u64
{
    let pattern = Math.Simd.splat(cast(const *u32, pixel)[])
    var x       = 0'u64
    while pixelCount - x >= 4
    {
        if not Math.Simd.allTrue(Math.Simd.load(cast(const [*] u32, source) + x) == pattern) do
            break
        x += 4
    }

    while x < pixelCount
    {
        if cast(const [*] u32, source)[x] != cast(const *u32, pixel)[] do
            break
        x += 1
    }

    return x
}

func swapRedBlue24Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    var x = 0'u64
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
    var x = 0'u64
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

func fillBgr24Row(pixel: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    let packed  = cast(u32, pixel[0]) | (cast(u32, pixel[1]) << 8) | (cast(u32, pixel[2]) << 16)
    let pattern = Math.Simd.shuffle(cast #bit(Math.Simd.U8x16, Math.Simd.splat(packed)), RepeatBgr24)
    var x       = 0'u64
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
    var x       = 0'u64
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
    var x = 0'u64
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
    var x = 0'u64
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
    var offset = 0'u64
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

        // The prefix sum with strides three, six, and twelve reaches back twenty-one
        // bytes, so fifteen bytes — five whole pixels — resolve per step; the sixteenth
        // stored byte is a partial sum the next step or the scalar tail rewrites.
        while count - offset >= 16
        {
            var values = Math.Simd.load(source + offset)
            values += Math.Simd.shuffle(values, ShiftBytes3)
            values += Math.Simd.shuffle(values, ShiftBytes6)
            values += Math.Simd.shuffle(values, ShiftBytes12)
            let carry = cast #bit(Math.Simd.U8x16, Math.Simd.splat(cast(const [*] u64, (destination + offset - 3))[0]))
            values += Math.Simd.shuffle(carry, CarryBytes3)
            Math.Simd.store(destination + offset, values)
            offset += 15
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
