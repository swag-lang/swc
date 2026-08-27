#global public
#global namespace Utf16

// Defines rune error.
const RuneError = 0xFFFD'rune

// Defines surr1.
const Surr1 = 0xD800

// Defines surr2.
const Surr2 = 0xDC00

// Defines surr3.
const Surr3 = 0xE000

// Defines surr self.
const SurrSelf = 0x10000

// Get the unicode character pointed by 'buffer', and the number of u16 to encode it
// Will return 'RuneError' for an invalid utf16 sequence
func decodeRune(buffer: const [..] u16)->{ c: rune, eat: u32 }
{
    var result: retval

    if !@countof(buffer)
    {
        result.c = RuneError
        return result
    }

    let r = cast(u32) buffer[0]
    switch
    {
    case r < Surr1, r >= Surr3:
        result.c   = cast(rune) r
        result.eat = 1
        return result

    case Surr1 <= r and r < Surr2 and @countof(buffer) >= 2 and Surr2 <= buffer[1] and buffer[1] < Surr3:
        result.c   = ((r - Surr1) << 10 | (buffer[1] - Surr2)) + SurrSelf
        result.eat = 2
        return result

    default:
        result.c   = RuneError
        result.eat = 1
        return result
    }
}

// Convert unicode character 'src' to an utf16 sequence, and returns
// the number of u16 that were needed to make the conversion.
// 'dest' must be at least 2 u16 long
func encodeRune(dest: [..] u16, src: rune)->u32
{
    Debug.assert(@countof(dest) >= 2, "destination buffer is too small")
    switch
    {
    case 0 <= src and src < Surr1, Surr3 <= src and src < SurrSelf:
        dest[0] = cast(u16) src
        return 1

    case SurrSelf <= src and src <= 0x10FFFF:
        let r = src - SurrSelf
        dest[0] = cast(u16) (Surr1 + ((r >> 10) & 0x3FF))
        dest[1] = cast(u16) (Surr2 + (r & 0x3FF))
        return 2

    default:
        dest[0] = cast(u16) RuneError
        return 1
    }
}

// Convert an utf8 buffer to a utf16 buffer, and returns the
// number of valid elements in the destination buffer
func fromUtf8(dest: [..] u16, src: const [..] u8)->u64
{
    var count      = 0'u64
    var srcPtr     = @dataof(src)
    var destPtr    = @dataof(dest)
    var srcLength  = @countof(src)
    var destLength = @countof(dest)

    const VectorSize = #sizeof(Math.Simd.U8x16)
    while srcLength
    {
        if srcLength >= VectorSize and destLength >= VectorSize
        {
            let values = Math.Simd.load(srcPtr)
            if !Math.Simd.bitmask(values)
            {
                Math.Simd.store(destPtr, Math.Simd.widenLow(values))
                Math.Simd.store(destPtr + VectorSize / 2, Math.Simd.widenHigh(values))
                srcPtr, destPtr, count += VectorSize
                srcLength, destLength  -= VectorSize
                continue
            }
        }

        let {c, eat} = Utf8.decodeRune(@mkslice(srcPtr, srcLength))

        Debug.assert(destLength >= 2, "destination buffer is too small")
        let eatDest = encodeRune(@mkslice(destPtr, destLength), c)
        destPtr, count += eatDest
        destLength     -= eatDest

        srcPtr    += eat
        srcLength -= eat
    }

    return count
}

// Convert an utf8 buffer to an utf16 sequence
func fromUtf8(src: const [..] u8)->Array'u16
{
    var result: retval
    result.reserve(2 * @countof(src))
    result.count = fromUtf8(@mkslice(result.buffer, result.capacity), src)
    return result
}

// Convert a character array (32 bits unicode) to an utf16 buffer
// Returns the number of bytes written in the destination buffer
// 'dest' must be at least 2 bytes long
func fromUnicode(dest: [..] u16, src: const [..] rune)->u64
{
    var dataof = @dataof(dest)
    var remain = @countof(dest)

    for ch in src
    {
        Debug.assert(remain >= 2, "destination buffer is too small")
        let cpt = encodeRune(@mkslice(dataof, remain), ch)
        dataof += cpt
        remain -= cpt
    }

    return cast(u64) (dataof - @dataof(dest))
}

// Convert a character array (32 bits unicode) to an utf16 sequence
func fromUnicode(src: const [..] rune)->Array'u16
{
    var result: retval
    result.reserve(2 * @countof(src))
    result.count = fromUnicode(@mkslice(result.buffer, result.capacity), src)
    return result
}

// Convert string to an utf16 array, zero terminated
func toZeroTerminated(src: string)->Array'u16
{
    var result: retval
    result.reserve(2 * @countof(src) + 1)
    let buffer = result.buffer!
    result.count             = Utf16.fromUtf8(@mkslice(buffer, result.capacity), src) + 1
    result[result.count - 1] = 0
    return result
}

// Returns the number of UTF-16 units before the first zero, bounded by the slice.
//
// The result is `@countof(buf)` when the slice contains no terminator. The function never
// reads outside `buf`; prefer it whenever the storage extent is known.
func lengthUntilZero(buf: const [..] u16)->u64
{
    const VectorCount = #sizeof(Math.Simd.U16x8) / #sizeof(u16)
    let zero   = Math.Simd.splat(0'u16)
    let data   = @dataof(buf)
    let count  = @countof(buf)
    var offset = 0'u64

    while offset + VectorCount <= count
    {
        let matches = Math.Simd.load(data + offset) == zero
        if Math.Simd.anyTrue(matches)
        {
            for lane in VectorCount
            {
                if data[offset + lane] == 0 do
                    return offset + lane
            }
        }

        offset += VectorCount
    }

    while offset < count
    {
        if data[offset] == 0 do
            return offset
        offset += 1
    }

    return count
}

// Returns the number of UTF-16 units before the first zero in unbounded native storage.
//
// `buf` must either be `null` or point to a zero-terminated sequence. Use
// [[Core.Utf16.lengthUntilZero]] when the storage extent is known so a missing terminator
// remains bounded.
func lengthZeroTerminated(buf: #null const [*] u16)->u64
{
    if buf == null do
        return 0
    var ptr   = buf
    var count = 0'u64
    while ptr[] do
        ptr, count += 1
    return count
}
