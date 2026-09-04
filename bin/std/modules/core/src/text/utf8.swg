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

// Searches for one byte, which is what every scanner over text asks for.
//
// It is separate from the general form because the general one splats four vectors and tests a
// slice per byte of the tail: on the short runs a parser reads — a word, an attribute value — that
// preparation costs more than the search itself.
private func indexOfByte(src: const [*] u8, length: u64, what: u8)->u64
{
    const VectorSize = #sizeof(Math.Simd.U8x16)

    var offset = 0'u64
    if length >= VectorSize
    {
        let needle = Math.Simd.splat(what)
        while length - offset >= VectorSize
        {
            let mask = Math.Simd.bitmask(Math.Simd.load(src + offset) == needle)
            if mask do
                return offset + Math.trailingZeros(mask)
            offset += VectorSize
        }
    }

    while offset < length
    {
        if src[offset] == what do
            return offset
        offset += 1
    }

    return Swag.U64.Max
}

// Searches for either of two bytes, which is what a scanner that has to notice one thing while
// looking for another asks for.
private func indexOfEitherByte(src: const [*] u8, length: u64, first, second: u8)->u64
{
    const VectorSize = #sizeof(Math.Simd.U8x16)

    var offset = 0'u64
    if length >= VectorSize
    {
        let needle0 = Math.Simd.splat(first)
        let needle1 = Math.Simd.splat(second)
        while length - offset >= VectorSize
        {
            let values = Math.Simd.load(src + offset)
            let mask   = Math.Simd.bitmask(values == needle0) | Math.Simd.bitmask(values == needle1)
            if mask do
                return offset + Math.trailingZeros(mask)
            offset += VectorSize
        }
    }

    while offset < length
    {
        if src[offset] == first or src[offset] == second do
            return offset
        offset += 1
    }

    return Swag.U64.Max
}

private func indexOfAnyAscii(src: const [*] u8, length: u64, what: const [..] u8)->u64
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    let count = what.count
    if count == 1 do
        return indexOfByte(src, length, what[0])
    if count == 2 do
        return indexOfEitherByte(src, length, what[0], what[1])

    let needle0 = Math.Simd.splat(what[0])
    let needle1 = Math.Simd.splat(what[1])
    let needle2 = count > 2 ? Math.Simd.splat(what[2]) : needle1
    let needle3 = count > 3 ? Math.Simd.splat(what[3]) : needle1

    var offset = 0'u64
    while length - offset >= VectorSize
    {
        let values = Math.Simd.load(src + offset)
        var mask   = Math.Simd.bitmask(values == needle0) | Math.Simd.bitmask(values == needle1)
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
    let count   = what.count
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
    let whatLength   = what.count
    let lastByte     = Swag.makeSlice(what.buffer + whatLength - 1, 1)
    var searchLength = length
    while searchLength >= whatLength
    {
        let endIndex = lastIndexOfAnyAscii(src, searchLength, lastByte)
        if endIndex == Swag.U64.Max or endIndex + 1 < whatLength do
            return Swag.U64.Max
        let startIndex = endIndex + 1 - whatLength
        if Memory.compare(src + startIndex, what.buffer, whatLength) == 0 do
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

    let whatLength = what.count
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
            if compare(Swag.makeSlice(src + candidate, whatLength), what, .Latin1NoCase) == 0 do
                return candidate
            mask &= mask - 1
        }

        offset += VectorSize
    }

    while offset <= lastStart
    {
        if compare(Swag.makeSlice(src + offset, whatLength), what, .Latin1NoCase) == 0 do
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

    let whatLength = what.count
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
            if compare(Swag.makeSlice(src + candidate, whatLength), what, .Latin1NoCase) == 0 do
                return candidate
            mask &= ~(1'u32 << bit)
        }
    }

    while offset
    {
        offset -= 1
        if compare(Swag.makeSlice(src + offset, whatLength), what, .Latin1NoCase) == 0 do
            return offset
    }

    return Swag.U64.Max
}

// Get the last unicode rune of the utf8 slice, and the number of
// bytes to encode it
func decodeLastRune(buffer: const [..] u8)->{ c: rune, eat: u32 }
{
    var result: retval

    let countof = buffer.count
    if !countof
    {
        result.c = RuneError
        return result
    }

    let dataof = buffer.buffer
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

    result = decodeRune(Swag.makeSlice(ptr, cast(u64) eat))
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

    let countof = buffer.count
    if countof == 0
    {
        result.c = RuneError
        return result
    }

    let dataof = buffer.buffer
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
    Debug.assert(dest.count >= 4, "destination buffer is too small")

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
    const ContinuationsToLow   = cast(Math.Simd.U8x16) [4'u8, 5, 6, 7, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128]
    const ThreeByteLead        = cast(Math.Simd.U8x16) [0'u8, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 128, 128, 128, 128]
    const ThreeByteMiddle      = cast(Math.Simd.U8x16) [128'u8, 4, 128, 128, 5, 128, 128, 6, 128, 128, 7, 128, 128, 128, 128, 128]
    const ThreeByteLast        = cast(Math.Simd.U8x16) [128'u8, 128, 0, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 128, 128]
    const FourByteLead         = cast(Math.Simd.U8x16) [0'u8, 128, 128, 128, 1, 128, 128, 128, 2, 128, 128, 128, 3, 128, 128, 128]
    const FourByteContinuation = cast(Math.Simd.U8x16) [128'u8, 4, 128, 128, 128, 5, 128, 128, 128, 6, 128, 128, 128, 7, 128, 128]
    const FourByteMiddle       = cast(Math.Simd.U8x16) [128'u8, 128, 0, 128, 128, 128, 1, 128, 128, 128, 2, 128, 128, 128, 3, 128]
    const FourByteLast         = cast(Math.Simd.U8x16) [128'u8, 128, 128, 4, 128, 128, 128, 5, 128, 128, 128, 6, 128, 128, 128, 7]
    var srcPtr     = cast(const [*] s32) src.buffer
    var destPtr    = dest.buffer
    var srcLength  = src.count
    var destLength = dest.count
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

            if destLength >= 12 and Math.Simd.allTrue(cast #bit(Math.Simd.U32x4) ((values >= Math.Simd.splat(0x800's32)) & ((values < Math.Simd.splat(0xD800's32)) | ((values >= Math.Simd.splat(0xE000's32)) & (values <= Math.Simd.splat(0xFFFF's32))))))
            {
                let lead         = (values >> 12) | Math.Simd.splat(0xE0's32)
                let middle       = ((values >> 6) & Math.Simd.splat(0x3F's32)) | Math.Simd.splat(0x80's32)
                let last         = (values & Math.Simd.splat(0x3F's32)) | Math.Simd.splat(0x80's32)
                let leadMiddle16 = Math.Simd.packUnsigned(lead, middle)
                let last16       = Math.Simd.packUnsigned(last, last)
                let leadMiddle   = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) leadMiddle16, cast #bit(Math.Simd.S16x8) leadMiddle16)
                let lastBytes    = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) last16, cast #bit(Math.Simd.S16x8) last16)
                let bytes        = Math.Simd.shuffle(leadMiddle, ThreeByteLead) | Math.Simd.shuffle(leadMiddle, ThreeByteMiddle) | Math.Simd.shuffle(lastBytes, ThreeByteLast)
                Math.Simd.storeLow8(destPtr, bytes)
                Math.Simd.storeLow4(destPtr + 8, Math.Simd.shuffle(bytes, cast(Math.Simd.U8x16) [8'u8, 9, 10, 11, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128]))
                srcPtr         += 4
                destPtr, total += 12
                srcLength      -= 4
                destLength     -= 12
                continue
            }

            if destLength >= 16 and Math.Simd.allTrue(cast #bit(Math.Simd.U32x4) ((values >= Math.Simd.splat(0x10000's32)) & (values <= Math.Simd.splat(cast(s32) MaxRunes))))
            {
                let lead         = (values >> 18) | Math.Simd.splat(0xF0's32)
                let continuation = ((values >> 12) & Math.Simd.splat(0x3F's32)) | Math.Simd.splat(0x80's32)
                let middle       = ((values >> 6) & Math.Simd.splat(0x3F's32)) | Math.Simd.splat(0x80's32)
                let last         = (values & Math.Simd.splat(0x3F's32)) | Math.Simd.splat(0x80's32)
                let leadMiddle16 = Math.Simd.packUnsigned(lead, continuation)
                let middleLast16 = Math.Simd.packUnsigned(middle, last)
                let leadMiddle   = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) leadMiddle16, cast #bit(Math.Simd.S16x8) leadMiddle16)
                let middleLast   = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) middleLast16, cast #bit(Math.Simd.S16x8) middleLast16)
                let bytes        = Math.Simd.shuffle(leadMiddle, FourByteLead) | Math.Simd.shuffle(leadMiddle, FourByteContinuation) | Math.Simd.shuffle(middleLast, FourByteMiddle) | Math.Simd.shuffle(middleLast, FourByteLast)
                Math.Simd.store(destPtr, bytes)
                srcPtr         += 4
                destPtr, total += 16
                srcLength      -= 4
                destLength     -= 16
                continue
            }
        }

        Debug.assert(destLength >= 4, "destination buffer is too small")
        let cpt = encodeRune(Swag.makeSlice(destPtr, destLength), cast(rune) srcPtr[])
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
    result.reserve(4 * src.count)
    result.length = fromUnicode(Swag.makeSlice(result.buffer, result.capacity), src)
    return result
}

// Convert an utf16 array to an utf8 buffer
//
// Returns the number of bytes written in the destination buffer.
// 'dest' must be at least 4 bytes long
func fromUtf16(dest: [..] u8, src: const [..] u16)->u64
{
    const ContinuationsToLow   = cast(Math.Simd.U8x16) [8'u8, 9, 10, 11, 12, 13, 14, 15, 128, 128, 128, 128, 128, 128, 128, 128]
    const ThreeByteLeadLow     = cast(Math.Simd.U8x16) [0'u8, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 128, 128, 128, 128]
    const ThreeByteMiddleLow   = cast(Math.Simd.U8x16) [128'u8, 8, 128, 128, 9, 128, 128, 10, 128, 128, 11, 128, 128, 128, 128, 128]
    const ThreeByteLastLow     = cast(Math.Simd.U8x16) [128'u8, 128, 0, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 128, 128]
    const ThreeByteLeadHigh    = cast(Math.Simd.U8x16) [4'u8, 128, 128, 5, 128, 128, 6, 128, 128, 7, 128, 128, 128, 128, 128, 128]
    const ThreeByteMiddleHigh  = cast(Math.Simd.U8x16) [128'u8, 12, 128, 128, 13, 128, 128, 14, 128, 128, 15, 128, 128, 128, 128, 128]
    const ThreeByteLastHigh    = cast(Math.Simd.U8x16) [128'u8, 128, 4, 128, 128, 5, 128, 128, 6, 128, 128, 7, 128, 128, 128, 128]
    const HighSurrogatesToLow  = cast(Math.Simd.U8x16) [0'u8, 1, 4, 5, 8, 9, 12, 13, 128, 128, 128, 128, 128, 128, 128, 128]
    const LowSurrogatesToLow   = cast(Math.Simd.U8x16) [2'u8, 3, 6, 7, 10, 11, 14, 15, 128, 128, 128, 128, 128, 128, 128, 128]
    const FourByteLead         = cast(Math.Simd.U8x16) [0'u8, 128, 128, 128, 1, 128, 128, 128, 2, 128, 128, 128, 3, 128, 128, 128]
    const FourByteContinuation = cast(Math.Simd.U8x16) [128'u8, 4, 128, 128, 128, 5, 128, 128, 128, 6, 128, 128, 128, 7, 128, 128]
    const FourByteMiddle       = cast(Math.Simd.U8x16) [128'u8, 128, 0, 128, 128, 128, 1, 128, 128, 128, 2, 128, 128, 128, 3, 128]
    const FourByteLast         = cast(Math.Simd.U8x16) [128'u8, 128, 128, 4, 128, 128, 128, 5, 128, 128, 128, 6, 128, 128, 128, 7]
    const LastFourBytesToLow   = cast(Math.Simd.U8x16) [8'u8, 9, 10, 11, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128]
    const VectorSize           = #sizeof(Math.Simd.U16x8) / #sizeof(u16)
    var count      = 0'u64
    var srcPtr     = src.buffer
    var destPtr    = dest.buffer
    var srcLength  = src.count
    var destLength = dest.count

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

            if destLength >= 3 * VectorSize and Math.Simd.allTrue((values >= Math.Simd.splat(0x800'u16)) & ((values < Math.Simd.splat(0xD800'u16)) | (values >= Math.Simd.splat(0xE000'u16))))
            {
                let lead       = cast #bit(Math.Simd.S16x8) ((values >> 12) | Math.Simd.splat(0xE0'u16))
                let middle     = cast #bit(Math.Simd.S16x8) (((values >> 6) & Math.Simd.splat(0x3F'u16)) | Math.Simd.splat(0x80'u16))
                let last       = cast #bit(Math.Simd.S16x8) ((values & Math.Simd.splat(0x3F'u16)) | Math.Simd.splat(0x80'u16))
                let leadMiddle = Math.Simd.packUnsigned(lead, middle)
                let lastBytes  = Math.Simd.packUnsigned(last, last)
                let lowBytes   = Math.Simd.shuffle(leadMiddle, ThreeByteLeadLow) | Math.Simd.shuffle(leadMiddle, ThreeByteMiddleLow) | Math.Simd.shuffle(lastBytes, ThreeByteLastLow)
                let highBytes  = Math.Simd.shuffle(leadMiddle, ThreeByteLeadHigh) | Math.Simd.shuffle(leadMiddle, ThreeByteMiddleHigh) | Math.Simd.shuffle(lastBytes, ThreeByteLastHigh)
                Math.Simd.storeLow8(destPtr, lowBytes)
                Math.Simd.storeLow4(destPtr + 8, Math.Simd.shuffle(lowBytes, LastFourBytesToLow))
                Math.Simd.storeLow8(destPtr + 12, highBytes)
                Math.Simd.storeLow4(destPtr + 20, Math.Simd.shuffle(highBytes, LastFourBytesToLow))
                srcPtr         += VectorSize
                destPtr, count += 3 * VectorSize
                srcLength      -= VectorSize
                destLength     -= 3 * VectorSize
                continue
            }

            if destLength >= 2 * VectorSize
            {
                let sourceBytes = cast #bit(Math.Simd.U8x16) values
                let high16      = cast #bit(Math.Simd.U16x8) Math.Simd.shuffle(sourceBytes, HighSurrogatesToLow)
                let low16       = cast #bit(Math.Simd.U16x8) Math.Simd.shuffle(sourceBytes, LowSurrogatesToLow)
                let high        = Math.Simd.widenLow(high16)
                let low         = Math.Simd.widenLow(low16)
                if Math.Simd.allTrue((high >= Math.Simd.splat(0xD800'u32)) & (high < Math.Simd.splat(0xDC00'u32)) & (low >= Math.Simd.splat(0xDC00'u32)) & (low < Math.Simd.splat(0xE000'u32)))
                {
                    let runes        = Math.Simd.splat(0x10000'u32) + ((high - Math.Simd.splat(0xD800'u32)) << 10) + (low - Math.Simd.splat(0xDC00'u32))
                    let signedRunes  = cast #bit(Math.Simd.S32x4) runes
                    let lead         = (signedRunes >> 18) | Math.Simd.splat(0xF0's32)
                    let continuation = ((signedRunes >> 12) & Math.Simd.splat(0x3F's32)) | Math.Simd.splat(0x80's32)
                    let middle       = ((signedRunes >> 6) & Math.Simd.splat(0x3F's32)) | Math.Simd.splat(0x80's32)
                    let last         = (signedRunes & Math.Simd.splat(0x3F's32)) | Math.Simd.splat(0x80's32)
                    let leadMiddle16 = Math.Simd.packUnsigned(lead, continuation)
                    let middleLast16 = Math.Simd.packUnsigned(middle, last)
                    let leadMiddle   = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) leadMiddle16, cast #bit(Math.Simd.S16x8) leadMiddle16)
                    let middleLast   = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) middleLast16, cast #bit(Math.Simd.S16x8) middleLast16)
                    let bytes        = Math.Simd.shuffle(leadMiddle, FourByteLead) | Math.Simd.shuffle(leadMiddle, FourByteContinuation) | Math.Simd.shuffle(middleLast, FourByteMiddle) | Math.Simd.shuffle(middleLast, FourByteLast)
                    Math.Simd.store(destPtr, bytes)
                    srcPtr         += VectorSize
                    destPtr, count += 2 * VectorSize
                    srcLength      -= VectorSize
                    destLength     -= 2 * VectorSize
                    continue
                }
            }
        }

        let {c, eat} = Utf16.decodeRune(Swag.makeSlice(srcPtr, srcLength))

        Debug.assert(destLength >= 4, "destination buffer is too small")
        let eatDest = encodeRune(Swag.makeSlice(destPtr, destLength), c)
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
    result.reserve(4 * src.count)
    result.length = fromUtf16(Swag.makeSlice(result.buffer, result.capacity), src)
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
    let dataof  = buffer.buffer
    let countof = buffer.count
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

    var countof = buffer.count
    if !countof do
        return result

    if !charIndex
    {
        result.success = true
        return result
    }

    var dataof = buffer.buffer

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

        let val = countBytesAt(Swag.makeSlice(dataof, countof))
        Debug.assert(val <= countof, "invalid utf8 character")
        resultByte += val
        resultChar += 1
        dataof     += val
        countof    -= val
    }

    result.index   = resultByte
    result.success = resultByte < buffer.count
    return result
}

// Returns the number of runes in an utf8 buffer
func countRunes(buffer: const [..] u8)->u64
{
    var dataof  = buffer.buffer
    var countof = buffer.count

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

        let val = countBytesAt(Swag.makeSlice(dataof, countof))
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
    // The ASCII case is what a scanner asks for, and it is one comparison per byte rather than a
    // needle array built for the general one.
    if what <= 0x7F
    {
        let length = src.count
        if startByteIndex >= length
        {
            Debug.safetyBoundCheck(startByteIndex == length, "index out of range")
            return Swag.U64.Max
        }

        let result = indexOfByte(src.buffer + startByteIndex, length - startByteIndex, cast(u8) what)
        return result == Swag.U64.Max ? result : startByteIndex + result
    }

    return indexOfAny(src, [what], startByteIndex)
}

// Find the given string, and returns the byte index of it
func indexOf(src: const [..] u8, what: string, startByteIndex = 0'u64, comparisonType = ComparisonType.Latin1)->u64
{
    let length = src.count
    if !length do
        return Swag.U64.Max
    if startByteIndex >= length
    {
        Debug.safetyBoundCheck(startByteIndex == length, "index out of range")
        return Swag.U64.Max
    }

    let countof = what.count
    if !countof or countof > (length - startByteIndex) do
        return Swag.U64.Max

    if comparisonType == .Latin1 or comparisonType == .Unicode
    {
        let result = Slice.findSubslice(Swag.makeSlice(src.buffer + startByteIndex, length - startByteIndex), what)
        return result == Swag.U64.Max ? result : startByteIndex + result
    }

    if comparisonType == .Latin1NoCase
    {
        let result = indexOfSubsliceNoCase(src.buffer + startByteIndex, length - startByteIndex, what)
        return result == Swag.U64.Max ? result : startByteIndex + result
    }

    var idx    = startByteIndex
    var scan   = src.buffer + startByteIndex
    var remain = length - startByteIndex
    while countof <= remain
    {
        let res = compare(Swag.makeSlice(scan, countof), what, comparisonType)
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
    let length = src.count
    if !length do
        return Swag.U64.Max
    if startByteIndex >= length
    {
        Debug.safetyBoundCheck(startByteIndex == length, "index out of range")
        return Swag.U64.Max
    }

    let countof = what.count
    if !countof do
        return Swag.U64.Max

    if countof <= 4
    {
        let result = indexOfAnyAscii(src.buffer + startByteIndex, length - startByteIndex, what)
        return result == Swag.U64.Max ? result : startByteIndex + result
    }

    var idx    = startByteIndex
    var scan   = src.buffer + startByteIndex
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
    let length = src.count
    if !length do
        return Swag.U64.Max
    if startByteIndex >= length
    {
        Debug.safetyBoundCheck(startByteIndex == length, "index out of range")
        return Swag.U64.Max
    }

    let countof = what.count
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
                let result = indexOfAnyAscii(src.buffer + startByteIndex, length - startByteIndex, Swag.makeSlice(ascii.buffer, countof))
                return result == Swag.U64.Max ? result : startByteIndex + result
            }
        }
    }

    var idx    = startByteIndex
    var scan   = src.buffer + startByteIndex
    var remain = length - startByteIndex
    while remain
    {
        let res = Utf8.decodeRune(Swag.makeSlice(scan, remain))
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
    let length = src.count
    if !length do
        return Swag.U64.Max
    let countof = what.count
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
                return lastIndexOfAnyAscii(src.buffer, length, Swag.makeSlice(ascii.buffer, countof))
        }
    }

    let dataof = src.buffer

    var byteIdx = length
    for
    {
        let sl       = Swag.makeSlice(dataof, byteIdx)
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
    let length = src.count
    if !length do
        return Swag.U64.Max
    if !what.count do
        return Swag.U64.Max

    if what.count <= 4 do
        return lastIndexOfAnyAscii(src.buffer, length, what)

    var scan    = src.buffer + length
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
    let length = src.count
    if !length do
        return Swag.U64.Max
    let lengthStr = what.count
    if lengthStr > length do
        return Swag.U64.Max
    if !lengthStr do
        return length
    if comparisonType == .Latin1 or comparisonType == .Unicode do
        return lastIndexOfSubslice(src.buffer, length, what)
    if comparisonType == .Latin1NoCase do
        return lastIndexOfSubsliceNoCase(src.buffer, length, what)

    var idx    = length - lengthStr
    var dataof = src.buffer + idx
    for
    {
        let res = compare(Swag.makeSlice(dataof, lengthStr), what, comparisonType)
        if res == 0 do
            return idx
        if !idx do
            return Swag.U64.Max
        idx, dataof -= 1
    }

    return Swag.U64.Max
}

// Return true if the string starts with 'str'
func startsWith(src: const [..] u8?, str: string, comparisonType = ComparisonType.Latin1)->bool
{
    let length = src.count
    if !length do
        return false
    let countof = str.count
    if countof > length do
        return false
    let buffer = src.buffer
    return compare(Swag.makeSlice(buffer, countof), str, comparisonType) == 0
}

// Return true if the string ends with 'str'
func endsWith(src: const [..] u8, str: string, comparisonType = ComparisonType.Latin1)->bool
{
    let length = src.count
    if !length do
        return false
    let countof = str.count
    if countof > length do
        return false
    let buffer = src.buffer
    return compare(Swag.makeSlice((buffer + length) - countof, countof), str, comparisonType) == 0
}

// Returns the first rune of the slice
func firstRune(src: const [..] u8)->rune
{
    let countof = src.count
    if !countof do
        return 0
    let dataof = src.buffer!
    if Latin1.isAscii(dataof[0]) do
        return cast(rune) dataof[0]
    let {c, ?} = Utf8.decodeRune(Swag.makeSlice(dataof, countof))
    return c
}

// Returns the last rune of the slice
func lastRune(src: const [..] u8)->rune
{
    let countof = src.count
    if !countof do
        return 0
    let dataof = src.buffer!
    if Latin1.isAscii(dataof[countof - 1]) do
        return cast(rune) dataof[countof - 1]
    let {c, ?} = Utf8.decodeLastRune(Swag.makeSlice(dataof, countof))
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
        var length      = src.count
        var otherLength = dst.count
        var data        = src.buffer
        var otherData   = dst.buffer

        var result:     s32
        var c1, c2:     rune
        var eat1, eat2: u32
        for
        {
            {c1, eat1} = decodeRune(Swag.makeSlice(data, length))
            {c2, eat2} = decodeRune(Swag.makeSlice(otherData, otherLength))
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
    var count = buffer.count
    if !count do
        return

    var curByteIdx = 0'u64
    var curCharIdx = 0'u64
    var scan       = buffer.buffer
    while count
    {
        let sl             = Swag.makeSlice(scan, count)
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
    var p       = buffer.buffer
    var countof = buffer.count
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
