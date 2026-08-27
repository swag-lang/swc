// @LICENCE: BSD-3-Clause
// @ORIGIN: Go standard library, https://github.com/golang/go
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#go-standard-library

#global public
#global namespace Utf8

// Defines rune error.
const RuneError = 0xFFFD'rune

// Defines max runes.
const MaxRunes = 0x10FFFF'rune

// Defines surrogate min.
const SurrogateMin = 0xD800'rune

// Defines surrogate max.
const SurrogateMax = 0xDFFF'rune

private
{
    const MaskX = 0b00111111'u8
    const Mask2 = 0b00011111'u8
    const Mask3 = 0b00001111'u8
    const Mask4 = 0b00000111'u8

    // The default lowest and highest continuation byte.
    const LoCB = 0b10000000'u8
    const HiCB = 0b10111111'u8

    // These names of these constants are chosen to give nice alignment in the
    // table below. The first nibble is an index into AcceptRanges or F for
    // special one-byte cases. The second nibble is the Rune length or the

    // Status for the special one-byte case.
    const XX = 0xF1     // invalid: size 1
    const AS = 0xF0     // ASCII: size 1
    const S1 = 0x02     // accept 0, size 2
    const S2 = 0x13     // accept 1, size 3
    const S3 = 0x03     // accept 0, size 3
    const S4 = 0x23     // accept 2, size 3
    const S5 = 0x34     // accept 3, size 4
    const S6 = 0x04     // accept 0, size 4
    const S7 = 0x44     // accept 4, size 4

    // first is information about the first byte in a UTF-8 sequence.
    const First: [256] u8 = [
        //   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
        AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS,
        // 0x00-0x0F
        AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS,
        // 0x10-0x1F
        AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS,
        // 0x20-0x2F
        AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS,
        // 0x30-0x3F
        AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS,
        // 0x40-0x4F
        AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS,
        // 0x50-0x5F
        AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS,
        // 0x60-0x6F
        AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS, AS,
        // 0x70-0x7F
        //   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
        XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX,
        // 0x80-0x8F
        XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX,
        // 0x90-0x9F
        XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX,
        // 0xA0-0xAF
        XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX,
        // 0xB0-0xBF
        XX, XX, S1, S1, S1, S1, S1, S1, S1, S1, S1, S1, S1, S1, S1, S1,
        // 0xC0-0xCF
        S1, S1, S1, S1, S1, S1, S1, S1, S1, S1, S1, S1, S1, S1, S1, S1,
        // 0xD0-0xDF
        S2, S3, S3, S3, S3, S3, S3, S3, S3, S3, S3, S3, S3, S4, S3, S3,
        // 0xE0-0xEF
        S5, S6, S6, S6, S7, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX]

    struct AcceptRange
    {
        lo: u8     // Lo associated with this value.
        hi: u8     // Hi associated with this value.
    }

    const AcceptRanges: [?] AcceptRange = [
        {LoCB, HiCB},
        {0xA0, HiCB},
        {LoCB, 0x9F},
        {0x90, HiCB},
        {LoCB, 0x8F}]
}

private func indexOfAnyAscii(src: const [*] u8, length: u64, what: const [..] u8)->u64
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    let count   = @countof(what)
    let needle0 = Math.Simd.splat(what[0])
    let needle1 = count > 1 ? Math.Simd.splat(what[1]) : needle0
    let needle2 = count > 2 ? Math.Simd.splat(what[2]) : needle0
    let needle3 = count > 3 ? Math.Simd.splat(what[3]) : needle0

    var offset = 0'u64
    while length - offset >= VectorSize
    {
        let values = Math.Simd.load(src + offset)
        var mask   = Math.Simd.bitmask(values == needle0)
        if count > 1 do
            mask |= Math.Simd.bitmask(values == needle1)
        if count > 2 do
            mask |= Math.Simd.bitmask(values == needle2)
        if count > 3 do
            mask |= Math.Simd.bitmask(values == needle3)
        if mask do
            return offset + Math.trailingZeros(mask)
        offset += VectorSize
    }

    while offset < length
    {
        if Slice.contains(what, src[offset]) do
            return offset
        offset += 1
    }

    return Swag.U64.Max
}

private func lastIndexOfAnyAscii(src: const [*] u8, length: u64, what: const [..] u8)->u64
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    let count   = @countof(what)
    let needle0 = Math.Simd.splat(what[0])
    let needle1 = count > 1 ? Math.Simd.splat(what[1]) : needle0
    let needle2 = count > 2 ? Math.Simd.splat(what[2]) : needle0
    let needle3 = count > 3 ? Math.Simd.splat(what[3]) : needle0

    var offset = length
    while offset >= VectorSize
    {
        offset -= VectorSize
        let values = Math.Simd.load(src + offset)
        var mask   = Math.Simd.bitmask(values == needle0)
        if count > 1 do
            mask |= Math.Simd.bitmask(values == needle1)
        if count > 2 do
            mask |= Math.Simd.bitmask(values == needle2)
        if count > 3 do
            mask |= Math.Simd.bitmask(values == needle3)
        if mask do
            return offset + 31 - Math.leadingZeros(mask)
    }

    while offset
    {
        offset -= 1
        if Slice.contains(what, src[offset]) do
            return offset
    }

    return Swag.U64.Max
}

private func lastIndexOfSubslice(src: const [*] u8, length: u64, what: const [..] u8)->u64
{
    let whatLength   = @countof(what)
    let lastByte     = @mkslice(@dataof(what) + whatLength - 1, 1)
    var searchLength = length
    while searchLength >= whatLength
    {
        let endIndex = lastIndexOfAnyAscii(src, searchLength, lastByte)
        if endIndex == Swag.U64.Max or endIndex + 1 < whatLength do
            return Swag.U64.Max
        let startIndex = endIndex + 1 - whatLength
        if Memory.compare(src + startIndex, @dataof(what), whatLength) == 0 do
            return startIndex
        searchLength = endIndex
    }

    return Swag.U64.Max
}

private func indexOfSubsliceNoCase(src: const [*] u8, length: u64, what: const [..] u8)->u64
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    var needles: [2] u8
    needles[0] = what[0]
    needles[1] = what[0]
    var hasAlternate = false
    if Latin1.isLower(what[0])
    {
        needles[1]   = Latin1.toUpper(what[0])
        hasAlternate = true
    }
    elif Latin1.isUpper(what[0])
    {
        needles[1]   = Latin1.toLower(what[0])
        hasAlternate = true
    }

    let whatLength = @countof(what)
    let lastStart  = length - whatLength
    let numStarts  = lastStart + 1
    let needle0    = Math.Simd.splat(needles[0])
    let needle1    = Math.Simd.splat(needles[1])
    var offset     = 0'u64
    while numStarts - offset >= VectorSize
    {
        let values = Math.Simd.load(src + offset)
        var mask   = Math.Simd.bitmask(values == needle0)
        if hasAlternate do
            mask |= Math.Simd.bitmask(values == needle1)
        while mask
        {
            let candidate = offset + Math.trailingZeros(mask)
            if compare(@mkslice(src + candidate, whatLength), what, .Latin1NoCase) == 0 do
                return candidate
            mask &= mask - 1
        }

        offset += VectorSize
    }

    while offset <= lastStart
    {
        if compare(@mkslice(src + offset, whatLength), what, .Latin1NoCase) == 0 do
            return offset
        offset += 1
    }

    return Swag.U64.Max
}

private func lastIndexOfSubsliceNoCase(src: const [*] u8, length: u64, what: const [..] u8)->u64
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    var needles: [2] u8
    needles[0] = what[0]
    needles[1] = what[0]
    var hasAlternate = false
    if Latin1.isLower(what[0])
    {
        needles[1]   = Latin1.toUpper(what[0])
        hasAlternate = true
    }
    elif Latin1.isUpper(what[0])
    {
        needles[1]   = Latin1.toLower(what[0])
        hasAlternate = true
    }

    let whatLength = @countof(what)
    let needle0    = Math.Simd.splat(needles[0])
    let needle1    = Math.Simd.splat(needles[1])
    var offset     = length - whatLength + 1
    while offset >= VectorSize
    {
        offset -= VectorSize
        let values = Math.Simd.load(src + offset)
        var mask   = Math.Simd.bitmask(values == needle0)
        if hasAlternate do
            mask |= Math.Simd.bitmask(values == needle1)
        while mask
        {
            let bit       = 31 - Math.leadingZeros(mask)
            let candidate = offset + bit
            if compare(@mkslice(src + candidate, whatLength), what, .Latin1NoCase) == 0 do
                return candidate
            mask &= ~(1'u32 << bit)
        }
    }

    while offset
    {
        offset -= 1
        if compare(@mkslice(src + offset, whatLength), what, .Latin1NoCase) == 0 do
            return offset
    }

    return Swag.U64.Max
}

// Get the last unicode rune of the utf8 slice, and the number of
// bytes to encode it
func decodeLastRune(buffer: const [..] u8)->{ c: rune, eat: u32 }
{
    var result: retval

    let countof = @countof(buffer)
    if !countof
    {
        result.c = RuneError
        return result
    }

    let dataof = @dataof(buffer)
    var ptr    = dataof + (countof - 1)

    // Ascii
    var c = cast(rune) ptr[]
    if c & 0x80 == 0
    {
        result.c   = c
        result.eat = 1
        return result
    }

    var eat = 1'u32
    for
    {
        c = ptr[]
        if c >> 6 != 2 do
            break
        if ptr == dataof
        {
            result.c   = RuneError
            result.eat = 1
            return result
        }

        ptr -= 1
        eat += 1
        if eat > 4
        {
            result.c   = RuneError
            result.eat = 1
            return result
        }
    }

    result = decodeRune(@mkslice(ptr, cast(u64) eat))
    if result.eat != eat
    {
        result.c   = RuneError
        result.eat = 1
    }

    return result
}

// Get the unicode rune pointed by 'buffer', and the number of bytes to encode it
//
// Will return 'RuneError' for an invalid utf8 sequence
func decodeRune(buffer: const [..] u8)->{ c: rune, eat: u32 }
{
    var result: retval

    let countof = @countof(buffer)
    if countof == 0
    {
        result.c = RuneError
        return result
    }

    let dataof = @dataof(buffer)
    let p0     = cast(rune) dataof[]
    if (p0 & 0x80) == 0
    {
        result.c   = p0
        result.eat = 1
        return result
    }

    let x = First[cast(u8) p0]

    // Invalid first byte
    if x == XX
    {
        result.c   = RuneError
        result.eat = 1
        return result
    }

    // Be sure input buffer is large enough to hold the requested
    // encoded size
    let sz = x & 7
    if countof < sz
    {
        result.c   = RuneError
        result.eat = 1
        return result
    }

    let accept = AcceptRanges[x >> 4]

    // Length == 2
    let b1 = dataof[1]
    if !(accept.lo <= b1 and b1 <= accept.hi)
    {
        result.c   = RuneError
        result.eat = 1
        return result
    }

    if sz <= 2
    {
        result.c   = (p0 & Mask2) << 6 | (b1 & MaskX)
        result.eat = 2
        return result
    }

    // Length == 3
    let b2 = dataof[2]
    if !(LoCB <= b2 and b2 <= HiCB)
    {
        result.c   = RuneError
        result.eat = 1
        return result
    }

    if sz <= 3
    {
        result.c   = (p0 & Mask3) << 12 | cast(rune) (b1 & MaskX) << 6 | (b2 & MaskX)
        result.eat = 3
        return result
    }

    // Length == 4
    let b3 = dataof[3]
    if !(LoCB <= b3 and b3 <= HiCB)
    {
        result.c   = RuneError
        result.eat = 1
        return result
    }

    result.c   = (p0 & Mask4) << 18 | cast(rune) (b1 & MaskX) << 12 | cast(rune) (b2 & MaskX) << 6 | (b3 & MaskX)
    result.eat = 4
    return result
}

// Convert rune 'src' to an utf8 sequence, and returns
// the number of bytes that were needed to make the conversion.
//
// 'dest' must be at least 4 bytes long
func encodeRune(dest: [..] u8, src: rune)->u32
{
    Debug.assert(@countof(dest) >= 4, "destination buffer is too small")

    switch
    {
    case src <= 0x7F:
        dest[0] = cast(u8) src
        return 1

    case src <= 0x07FF:
        dest[0] = cast(u8) (((src >> 6) & 0x1F) | 0xC0)
        dest[1] = cast(u8) (((src >> 0) & 0x3F) | 0x80)
        return 2

    case !isValidRune(src):
        dest[0] = cast(u8) (((RuneError >> 12) & 0x0F) | 0xE0)
        dest[1] = cast(u8) (((RuneError >> 6) & 0x3F) | 0x80)
        dest[2] = cast(u8) (((RuneError >> 0) & 0x3F) | 0x80)
        return 3

    case src <= 0xFFFF:
        dest[0] = cast(u8) (((src >> 12) & 0x0F) | 0xE0)
        dest[1] = cast(u8) (((src >> 6) & 0x3F) | 0x80)
        dest[2] = cast(u8) (((src >> 0) & 0x3F) | 0x80)
        return 3

    default:
        dest[0] = cast(u8) (((src >> 18) & 0x07) | 0xF0)
        dest[1] = cast(u8) (((src >> 12) & 0x3F) | 0x80)
        dest[2] = cast(u8) (((src >> 6) & 0x3F) | 0x80)
        dest[3] = cast(u8) (((src >> 0) & 0x3F) | 0x80)
        return 4
    }
}

// Convert a rune array to an utf8 buffer
//
// Returns the number of bytes written in the destination buffer
// 'dest' must be at least 4 bytes long
func fromUnicode(dest: [..] u8, src: const [..] rune)->u64
{
    const ContinuationsToLow = cast(Math.Simd.U8x16) [4'u8, 5, 6, 7, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128]
    var srcPtr     = cast(const [*] s32) @dataof(src)
    var destPtr    = @dataof(dest)
    var srcLength  = @countof(src)
    var destLength = @countof(dest)
    var total      = 0'u64

    while srcLength
    {
        if srcLength >= 4
        {
            let values = Math.Simd.load(srcPtr)
            if destLength >= 4 and Math.Simd.allTrue(cast #bit(Math.Simd.U32x4) ((values >= Math.Simd.splat(0's32)) & (values < Math.Simd.splat(0x80's32))))
            {
                let words = Math.Simd.packUnsigned(values, values)
                let bytes = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) words, cast #bit(Math.Simd.S16x8) words)
                Math.Simd.storeLow4(destPtr, bytes)
                srcPtr                += 4
                destPtr, total        += 4
                srcLength, destLength -= 4
                continue
            }

            if destLength >= 8 and Math.Simd.allTrue(cast #bit(Math.Simd.U32x4) ((values >= Math.Simd.splat(0x80's32)) & (values < Math.Simd.splat(0x800's32))))
            {
                let lead         = (values >> 6) | Math.Simd.splat(0xC0's32)
                let continuation = (values & Math.Simd.splat(0x3F's32)) | Math.Simd.splat(0x80's32)
                let words        = Math.Simd.packUnsigned(lead, continuation)
                let bytes        = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) words, cast #bit(Math.Simd.S16x8) words)
                let high         = Math.Simd.shuffle(bytes, ContinuationsToLow)
                Math.Simd.storeLow8(destPtr, Math.Simd.interleaveLow(bytes, high))
                srcPtr         += 4
                destPtr, total += 8
                srcLength      -= 4
                destLength     -= 8
                continue
            }
        }

        Debug.assert(destLength >= 4, "destination buffer is too small")
        let cpt = encodeRune(@mkslice(destPtr, destLength), cast(rune) srcPtr[])
        srcPtr     += 1
        srcLength  -= 1
        destPtr    += cpt
        destLength -= cpt
        total      += cpt
    }

    return total
}

// Convert an unicode buffer to a String
func fromUnicode(src: const [..] rune)->String
{
    var result: retval
    result.reserve(4 * @countof(src))
    result.length = fromUnicode(@mkslice(result.buffer, result.capacity), src)
    return result
}

// Convert an utf16 array to an utf8 buffer
//
// Returns the number of bytes written in the destination buffer.
// 'dest' must be at least 4 bytes long
func fromUtf16(dest: [..] u8, src: const [..] u16)->u64
{
    const ContinuationsToLow = cast(Math.Simd.U8x16) [8'u8, 9, 10, 11, 12, 13, 14, 15, 128, 128, 128, 128, 128, 128, 128, 128]
    const VectorSize         = #sizeof(Math.Simd.U16x8) / #sizeof(u16)
    var count      = 0'u64
    var srcPtr     = @dataof(src)
    var destPtr    = @dataof(dest)
    var srcLength  = @countof(src)
    var destLength = @countof(dest)

    while srcLength
    {
        if srcLength >= VectorSize
        {
            let values = Math.Simd.load(srcPtr)
            if destLength >= VectorSize and Math.Simd.allTrue(values < Math.Simd.splat(0x80'u16))
            {
                let signed = cast #bit(Math.Simd.S16x8) values
                Math.Simd.storeLow8(destPtr, Math.Simd.packUnsigned(signed, signed))
                srcPtr, destPtr       += VectorSize
                count                 += VectorSize
                srcLength, destLength -= VectorSize
                continue
            }

            if destLength >= 2 * VectorSize and Math.Simd.allTrue((values >= Math.Simd.splat(0x80'u16)) & (values < Math.Simd.splat(0x800'u16)))
            {
                let lead         = cast #bit(Math.Simd.S16x8) ((values >> 6) | Math.Simd.splat(0xC0'u16))
                let continuation = cast #bit(Math.Simd.S16x8) ((values & Math.Simd.splat(0x3F'u16)) | Math.Simd.splat(0x80'u16))
                let bytes        = Math.Simd.packUnsigned(lead, continuation)
                let high         = Math.Simd.shuffle(bytes, ContinuationsToLow)
                Math.Simd.store(destPtr, Math.Simd.interleaveLow(bytes, high))
                srcPtr         += VectorSize
                destPtr, count += 2 * VectorSize
                srcLength      -= VectorSize
                destLength     -= 2 * VectorSize
                continue
            }
        }

        let {c, eat} = Utf16.decodeRune(@mkslice(srcPtr, srcLength))

        Debug.assert(destLength >= 4, "destination buffer is too small")
        let eatDest = encodeRune(@mkslice(destPtr, destLength), c)
        destPtr, count += eatDest
        destLength     -= eatDest

        srcPtr    += eat
        srcLength -= eat
    }

    return count
}

// Convert an utf16 buffer to a String
func fromUtf16(src: const [..] u16)->String
{
    var result: retval
    result.reserve(4 * @countof(src))
    result.length = fromUtf16(@mkslice(result.buffer, result.capacity), src)
    Debug.assert(result.length + 1 < result.capacity)
    let buffer = result.buffer!
    buffer[result.length] = 0
    return result
}

// Returns true if the given unicode rune can be encoded in utf8
func isValidRune(c: rune)->bool
{
    switch
    {
    case 0 <= c and c < SurrogateMin:        return true
    case SurrogateMax < c and c <= MaxRunes: return true
    }

    return false
}

// Returns the number of bytes to encode the first rune of the utf8 buffer
//
// If it's an invalid encoding, returns 1.
func countBytesAt(buffer: const [..] u8)->u32
{
    let dataof  = @dataof(buffer)
    let countof = @countof(buffer)
    if !countof do
        return 1

    let p0 = cast(rune) dataof[]
    if (p0 & 0x80) == 0 do
        return 1

    // Invalid first byte
    let x = First[cast(u8) p0]
    if x == XX do
        return 1

    // Be sure input buffer is large enough to hold the requested
    // encoded size
    let sz = x & 7
    if countof < sz do
        return 1

    let accept = AcceptRanges[x >> 4]

    let b1 = dataof[1]
    if !(accept.lo <= b1 and b1 <= accept.hi) do
        return 1
    if sz <= 2 do
        return 2

    let b2 = dataof[2]
    if !(LoCB <= b2 and b2 <= HiCB) do
        return 1
    if sz <= 3 do
        return 3

    let b3 = dataof[3]
    if !(LoCB <= b3 and b3 <= HiCB) do
        return 1
    return 4
}

// Returns the byte index of the given rune index
func byteIndex(buffer: const [..] u8, charIndex: u64)->{ index: u64, success: bool }
{
    var result: retval

    var countof = @countof(buffer)
    if !countof do
        return result

    if !charIndex
    {
        result.success = true
        return result
    }

    var dataof = @dataof(buffer)

    var resultChar = 0'u64
    var resultByte = 0'u64
    while countof and resultChar != charIndex
    {
        if charIndex - resultChar >= #sizeof(Math.Simd.U8x16) and countof >= #sizeof(Math.Simd.U8x16) and !Math.Simd.bitmask(Math.Simd.load(dataof))
        {
            resultByte, resultChar += #sizeof(Math.Simd.U8x16)
            dataof                 += #sizeof(Math.Simd.U8x16)
            countof                -= #sizeof(Math.Simd.U8x16)
            continue
        }

        let val = countBytesAt(@mkslice(dataof, countof))
        Debug.assert(val <= countof, "invalid utf8 character")
        resultByte += val
        resultChar += 1
        dataof     += val
        countof    -= val
    }

    result.index   = resultByte
    result.success = resultByte < @countof(buffer)
    return result
}

// Returns the number of runes in an utf8 buffer
func countRunes(buffer: const [..] u8)->u64
{
    var dataof  = @dataof(buffer)
    var countof = @countof(buffer)

    var cpt = 0'u64
    while countof
    {
        if countof >= #sizeof(Math.Simd.U8x16) and !Math.Simd.bitmask(Math.Simd.load(dataof))
        {
            cpt     += #sizeof(Math.Simd.U8x16)
            dataof  += #sizeof(Math.Simd.U8x16)
            countof -= #sizeof(Math.Simd.U8x16)
            continue
        }

        let val = countBytesAt(@mkslice(dataof, countof))
        Debug.assert(val <= countof)
        cpt     += 1
        dataof  += val
        countof -= val
    }

    return cpt
}

// Find the first occurence of rune 'what', and returns the byte index of it.
// Returns 'Swag.U64.Max' if not found
func indexOf(src: const [..] u8, what: rune, startByteIndex = 0'u64)->u64
{
    return indexOfAny(src, [what], startByteIndex)
}

// Find the given string, and returns the byte index of it
func indexOf(src: const [..] u8, what: string, startByteIndex = 0'u64, comparisonType = ComparisonType.Latin1)->u64
{
    let length = @countof(src)
    if !length do
        return Swag.U64.Max
    if startByteIndex >= length
    {
        Debug.safetyBoundCheck(startByteIndex == length, "index out of range")
        return Swag.U64.Max
    }

    let countof = @countof(what)
    if !countof or countof > (length - startByteIndex) do
        return Swag.U64.Max

    if comparisonType == .Latin1 or comparisonType == .Unicode
    {
        let result = Slice.findSubslice(@mkslice(@dataof(src) + startByteIndex, length - startByteIndex), what)
        return result == Swag.U64.Max ? result : startByteIndex + result
    }

    if comparisonType == .Latin1NoCase
    {
        let result = indexOfSubsliceNoCase(@dataof(src) + startByteIndex, length - startByteIndex, what)
        return result == Swag.U64.Max ? result : startByteIndex + result
    }

    var idx    = startByteIndex
    var scan   = @dataof(src) + startByteIndex
    var remain = length - startByteIndex
    while countof <= remain
    {
        let res = compare(@mkslice(scan, countof), what, comparisonType)
        if res == 0 do
            return idx
        scan, idx += 1
        remain    -= 1
    }

    return Swag.U64.Max
}

// Find one of the runes in 'what', and returns the byte index of it.
// Returns 'Swag.U64.Max' if not found
func indexOfAny(src: const [..] u8, what: const [..] u8, startByteIndex = 0'u64)->u64
{
    let length = @countof(src)
    if !length do
        return Swag.U64.Max
    if startByteIndex >= length
    {
        Debug.safetyBoundCheck(startByteIndex == length, "index out of range")
        return Swag.U64.Max
    }

    let countof = @countof(what)
    if !countof do
        return Swag.U64.Max

    if countof <= 4
    {
        let result = indexOfAnyAscii(@dataof(src) + startByteIndex, length - startByteIndex, what)
        return result == Swag.U64.Max ? result : startByteIndex + result
    }

    var idx    = startByteIndex
    var scan   = @dataof(src) + startByteIndex
    var remain = length - startByteIndex
    while remain
    {
        if Slice.contains(what, scan[]) do
            return idx
        scan, idx += 1
        remain    -= 1
    }

    return Swag.U64.Max
}

// Find one of the runes in 'what', and returns the byte index of it
func indexOfAny(src: const [..] u8, what: const [..] rune, startByteIndex = 0'u64)->u64
{
    let length = @countof(src)
    if !length do
        return Swag.U64.Max
    if startByteIndex >= length
    {
        Debug.safetyBoundCheck(startByteIndex == length, "index out of range")
        return Swag.U64.Max
    }

    let countof = @countof(what)
    if !countof do
        return Swag.U64.Max

    if countof <= 4
    {
        var ascii: [4] u8
        for value, index in what
        {
            if value > 0x7F do
                break
            ascii[index] = cast(u8) value
            if index + 1 == countof
            {
                let result = indexOfAnyAscii(@dataof(src) + startByteIndex, length - startByteIndex, @mkslice(@dataof(ascii), countof))
                return result == Swag.U64.Max ? result : startByteIndex + result
            }
        }
    }

    var idx    = startByteIndex
    var scan   = @dataof(src) + startByteIndex
    var remain = length - startByteIndex
    while remain
    {
        let res = Utf8.decodeRune(@mkslice(scan, remain))
        if !res.eat do
            break
        if Slice.contains(what, res.c) do
            return idx
        scan, idx += res.eat
        remain    -= res.eat
    }

    return Swag.U64.Max
}

// Returns true if 'src' contains the string 'what'
func contains(src: const [..] u8, what: string)->bool
{
    return indexOf(src, what) != Swag.U64.Max
}

// Returns true if 'src' contains the string 'what'
func contains(src: const [..] u8, what: rune)->bool
{
    return indexOf(src, what) != Swag.U64.Max
}

// Returns true if 'src' contains the string 'what'
func contains(src: const [..] u8, what: u8)->bool
{
    return Slice.contains(src, what)
}

// Returns true if 'src' contains the slice 'what'
func contains(src, what: const [..] u8)->bool
{
    return Slice.findSubslice(src, what) != Swag.U64.Max
}

// Find the last rune occurence of 'what', and returns the byte index of it.
// Returns 'Swag.U64.Max' if not found
func lastIndexOf(src: const [..] u8, what: rune)->u64
{
    return lastIndexOfAny(src, [what])
}

// Returns the last index (in bytes) of a any of the runes in 'what'.
// Returns 'Swag.U64.Max' if not found
func lastIndexOfAny(src: const [..] u8, what: const [..] rune)->u64
{
    let length = @countof(src)
    if !length do
        return Swag.U64.Max
    let countof = @countof(what)
    if !countof do
        return Swag.U64.Max

    if countof <= 4
    {
        var ascii: [4] u8
        for value, index in what
        {
            if value > 0x7F do
                break
            ascii[index] = cast(u8) value
            if index + 1 == countof do
                return lastIndexOfAnyAscii(@dataof(src), length, @mkslice(@dataof(ascii), countof))
        }
    }

    let dataof = @dataof(src)

    var byteIdx = length
    for
    {
        let sl       = @mkslice(dataof, byteIdx)
        let {c, eat} = decodeLastRune(sl)
        if eat == 0 do
            return Swag.U64.Max

        byteIdx -= eat
        if Slice.contains(what, c) do
            return byteIdx
    }

    return Swag.U64.Max
}

// Returns the last index (in bytes) of a any of the bytes in 'what'.
// Returns 'Swag.U64.Max' if not found
func lastIndexOfAny(src: const [..] u8, what: const [..] u8)->u64
{
    let length = @countof(src)
    if !length do
        return Swag.U64.Max
    if !@countof(what) do
        return Swag.U64.Max

    if @countof(what) <= 4 do
        return lastIndexOfAnyAscii(@dataof(src), length, what)

    var scan    = @dataof(src) + length
    var byteIdx = length
    while byteIdx
    {
        scan, byteIdx -= 1
        if Slice.contains(what, scan[]) do
            return byteIdx
    }

    return Swag.U64.Max
}

// Returns the last index (in bytes) of a string.
// Returns 'Swag.U64.Max' if not found
func lastIndexOf(src: const [..] u8, what: string, comparisonType = ComparisonType.Latin1)->u64
{
    let length = @countof(src)
    if !length do
        return Swag.U64.Max
    let lengthStr = @countof(what)
    if lengthStr > length do
        return Swag.U64.Max
    if !lengthStr do
        return length
    if comparisonType == .Latin1 or comparisonType == .Unicode do
        return lastIndexOfSubslice(@dataof(src), length, what)
    if comparisonType == .Latin1NoCase do
        return lastIndexOfSubsliceNoCase(@dataof(src), length, what)

    var idx    = length - lengthStr
    var dataof = @dataof(src) + idx
    for
    {
        let res = compare(@mkslice(dataof, lengthStr), what, comparisonType)
        if res == 0 do
            return idx
        if !idx do
            return Swag.U64.Max
        idx, dataof -= 1
    }

    return Swag.U64.Max
}

// Return true if the string starts with 'str'
func startsWith(src: #null const [..] u8, str: string, comparisonType = ComparisonType.Latin1)->bool
{
    let length = @countof(src)
    if !length do
        return false
    let countof = @countof(str)
    if countof > length do
        return false
    let buffer = @dataof(src)
    return compare(@mkslice(buffer, countof), str, comparisonType) == 0
}

// Return true if the string ends with 'str'
func endsWith(src: const [..] u8, str: string, comparisonType = ComparisonType.Latin1)->bool
{
    let length = @countof(src)
    if !length do
        return false
    let countof = @countof(str)
    if countof > length do
        return false
    let buffer = @dataof(src)
    return compare(@mkslice((buffer + length) - countof, countof), str, comparisonType) == 0
}

// Returns the first rune of the slice
func firstRune(src: const [..] u8)->rune
{
    let countof = @countof(src)
    if !countof do
        return 0
    let dataof = @dataof(src)!
    if Latin1.isAscii(dataof[0]) do
        return cast(rune) dataof[0]
    let {c, ?} = Utf8.decodeRune(@mkslice(dataof, countof))
    return c
}

// Returns the last rune of the slice
func lastRune(src: const [..] u8)->rune
{
    let countof = @countof(src)
    if !countof do
        return 0
    let dataof = @dataof(src)!
    if Latin1.isAscii(dataof[countof - 1]) do
        return cast(rune) dataof[countof - 1]
    let {c, ?} = Utf8.decodeLastRune(@mkslice(dataof, countof))
    return c
}

// Selects comparison type.
enum ComparisonType
{
    Latin1            // Selects latin1.
    Latin1NoCase      // Selects latin1 no case.
    Unicode           // Selects unicode.
    UnicodeNoCase     // Selects unicode no case.
}

// Compare two utf8 buffers with the given algorithm
func compare(src, dst: const [..] u8, comparisonType = ComparisonType.Latin1)->s32
{
    using ComparisonType

    switch #complete comparisonType
    {
    case .Latin1:
        return Core.Latin1.compare(src, dst)     // bytes compare

    case .Latin1NoCase:
        return Core.Latin1.compare(src, dst, ignoreCase: true)

    case .Unicode:
        return Core.Latin1.compare(src, dst)     // bytes compare

    case .UnicodeNoCase:
        var length      = @countof(src)
        var otherLength = @countof(dst)
        var data        = @dataof(src)
        var otherData   = @dataof(dst)

        var result:     s32
        var c1, c2:     rune
        var eat1, eat2: u32
        for
        {
            {c1, eat1} = decodeRune(@mkslice(data, length))
            {c2, eat2} = decodeRune(@mkslice(otherData, otherLength))
            if eat1 == 0 or eat2 == 0 do
                break

            if c1 != c2
            {
                c1     = Core.Unicode.toLower(c1)
                c2     = Core.Unicode.toLower(c2)
                result = cast(s32) c1 - cast(s32) c2
                if result != 0 do
                    return Math.sign(result)
            }

            length      -= eat1
            otherLength -= eat2
            data        += eat1
            otherData   += eat2
        }

        if !eat1 and eat2 do
            return -1
        if eat1 and !eat2 do
            return 1
        return 0
    }

    return 0
}

// Macro to visit the unicode characters of the utf8 sequence.
// Block parameters:
// - 'c':       the character
// - 'charIdx': the character index
// - 'byteIdx': the byte index of that character within the utf8 sequence
#[Swag.Macro]
func visitRunes(buffer: const [..] u8, stmt: #code(c: rune, charIdx: u64, byteIdx: u64))
{
    var count = @countof(buffer)
    if !count do
        return

    var curByteIdx = 0'u64
    var curCharIdx = 0'u64
    var scan       = @dataof(buffer)
    while count
    {
        let sl             = @mkslice(scan, count)
        let {curRune, eat} = decodeRune(sl)
        if eat == 0 do
            break

        #scope(Inside)
        {
            #inject(stmt, c = curRune, charIdx = curCharIdx, byteIdx = curByteIdx, continue = break to Inside)
        }

        curCharIdx       += 1
        curByteIdx, scan += eat
        count            -= eat
    }
}

// Returns true if the utf8 sequence is valid
func isValid(buffer: const [..] u8)->bool
{
    var p       = @dataof(buffer)
    var countof = @countof(buffer)
    if !countof do
        return true

    // Quick zap ascii characters
    while countof >= 8
    {
        let first64 = p[as u64]
        if first64 & 0x80808080_80808080 do
            break
        p       += 8
        countof -= 8
    }

    while countof
    {
        let p0 = cast(rune) p[]
        if (p0 & 0x80) == 0
        {
            p       += 1
            countof -= 1
            continue
        }

        // Invalid first byte
        let x = First[cast(u8) p0]
        if x == XX do
            return false

        // Be sure input buffer is large enough to hold the requested
        // encoded size
        let sz = x & 7
        if countof < sz do
            return false

        let accept = AcceptRanges[x >> 4]

        let b1 = p[1]
        if !(accept.lo <= b1 and b1 <= accept.hi) do
            return false
        if sz <= 2
        {
            p       += 2
            countof -= 2
            continue
        }

        let b2 = p[2]
        if !(LoCB <= b2 and b2 <= HiCB) do
            return false
        if sz <= 3
        {
            p       += 3
            countof -= 3
            continue
        }

        let b3 = p[3]
        if !(LoCB <= b3 and b3 <= HiCB) do
            return false
        p       += 4
        countof -= 4
    }

    return true
}

// Defines beautify name.
func beautifyName(name: const [..] u8)->String
{
    var result: retval

    var first    = true
    var wasUpper = true
    visitRunes(name)
    {
        if Unicode.isUpper(c)
        {
            if !wasUpper
            {
                wasUpper = true
                result   += " "
            }
        }
        else
        {
            wasUpper = false
        }

        if first
        {
            result += Unicode.toUpper(c)
            first  = false
        }
        else do
            result += c
    }

    return result
}
