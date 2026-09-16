#global public
#global namespace Latin1

using Swag

#[Inline, ConstExpr]
{
    // Returns whether ascii.
    func isAscii(c: u8) => c <= 0x7F

    // Returns whether digit.
    func isDigit(c: u8) => cast(bool) (CharProperties[c] & .Digit)

    // Returns whether number.
    func isNumber(c: u8) => cast(bool) (CharProperties[c] & .Digit)

    // Returns whether bin digit.
    func isBinDigit(c: u8) => cast(bool) (CharProperties[c] & .BinDigit)

    // Returns whether hex digit.
    func isHexDigit(c: u8) => cast(bool) (CharProperties[c] & .HexDigit)

    // Returns whether upper.
    func isUpper(c: u8) => cast(bool) (CharProperties[c] & .Upper)

    // Returns whether lower.
    func isLower(c: u8) => cast(bool) (CharProperties[c] & .Lower)

    // Returns whether punctuation.
    func isPunctuation(c: u8) => cast(bool) (CharProperties[c] & .Punctuation)

    // Returns whether letter.
    func isLetter(c: u8) => cast(bool) (CharProperties[c] & .Letter)

    // Returns whether letter or digit.
    func isLetterOrDigit(c: u8) => cast(bool) (CharProperties[c] & (.Letter | .Digit))

    // Returns whether space.
    func isSpace(c: u8) => cast(bool) (CharProperties[c] & .Spacing)

    // Returns whether control.
    func isControl(c: u8) => cast(bool) (CharProperties[c] & .Control)

    // Returns whether symbol.
    func isSymbol(c: u8) => cast(bool) (CharProperties[c] & .Symbol)

    // Returns whether word.
    func isWord(c: u8) => isLetter(c) or isDigit(c) or c == '_'

    // Returns the lowercase Latin-1 byte, preserving bytes with no lowercase mapping.
    func toLower(c: u8) => isUpper(c) ? (c | 0x20'u8) : c

    // Returns the uppercase Latin-1 byte, preserving mappings outside this repertoire.
    func toUpper(c: u8) => ((c >= 0x61 and c <= 0x7A) or (c >= 0xE0 and c <= 0xFE and c != 0xF7)) ? (c & ~0x20'u8) : c
}

#[Inline, ConstExpr]
private func isLowerUtf8(c: u8)->bool
{
    if isAscii(c) and isLower(c) do
        return true
    return cast(bool) (CharProperties[c] & .LowerUtf8)
}

#[Inline, ConstExpr]
private func isUpperUtf8(c: u8)->bool
{
    if isAscii(c) and isUpper(c) do
        return true
    return cast(bool) (CharProperties[c] & .UpperUtf8)
}

private func spaceMaskAt(data: const [*] u8)->u32
{
    let value    = Math.Simd.load(data)
    let controls = (value >= Math.Simd.splat(9'u8)) & (value <= Math.Simd.splat(13'u8))
    return Math.Simd.bitmask(controls | (value == Math.Simd.splat(32'u8)))
}

private func isAsciiSpace(value: u8)->bool => (value >= 9 and value <= 13) or value == 32

// Latin-1 whitespace outside ASCII is encoded as C2 85 or C2 A0 in UTF-8.
private func isEncodedSpace(first, last: u8)->bool => first == 0xC2 and (last == 0x85 or last == 0xA0)

#[Swag.Inline]
internal func firstNonSpace(buffer: const [..] u8, includeLatin1 = true)->u64
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    let data   = buffer.buffer
    let count  = buffer.count
    var offset = 0'u64
    while count - offset >= VectorSize
    {
        let mask = spaceMaskAt(data + offset)
        if mask != 0xFFFF
        {
            offset += Math.trailingZeros((~mask) & 0xFFFF)
            break
        }

        offset += VectorSize
    }

    while offset < count
    {
        if isAsciiSpace(data[offset]) do
            offset += 1
        elif includeLatin1 and count - offset >= 2 and isEncodedSpace(data[offset], data[offset + 1]) do
            offset += 2
        else do
            break
    }

    return offset
}

#[Swag.Inline]
internal func lastNonSpace(buffer: const [..] u8, includeLatin1 = true)->u64
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    let data   = buffer.buffer
    var offset = buffer.count
    while offset >= VectorSize
    {
        let block = offset - VectorSize
        let mask  = spaceMaskAt(data + block)
        if mask != 0xFFFF
        {
            offset = block + 32 - Math.leadingZeros((~mask) & 0xFFFF)
            break
        }

        offset = block
    }

    while offset
    {
        if isAsciiSpace(data[offset - 1]) do
            offset -= 1
        elif includeLatin1 and offset >= 2 and isEncodedSpace(data[offset - 2], data[offset - 1]) do
            offset -= 2
        else do
            break
    }

    return offset
}

// Uppercases ASCII and Latin-1 letters in UTF-8, preserving all other encoded characters.
//
// Mapping is in place and keeps the byte count. Only case pairs contained in Latin-1
// are mapped; this does not perform full Unicode case mapping or normalization.
func makeUpper(buffer: [..] u8)
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    let asciiFirst = Math.Simd.splat(0x61'u8)
    let asciiLast  = Math.Simd.splat(0x7A'u8)
    let caseBit    = Math.Simd.splat(0x20'u8)
    var offset     = 0'u64
    while buffer.count - offset >= VectorSize
    {
        let value = Math.Simd.load(buffer.buffer + offset)
        if Math.Simd.anyTrue(value >= Math.Simd.splat(0x80'u8)) do
            break
        let mask = (value >= asciiFirst) & (value <= asciiLast)
        Math.Simd.store(buffer.buffer + offset, value - (mask & caseBit))
        offset += VectorSize
    }

    for i in offset until buffer.count do
        buffer[i] = upperUtf8Byte(buffer, i)
}

#[Inline]
private func toLowerUtf8(value: Math.Simd.U8x16)->Math.Simd.U8x16
{
    let asciiMask = (value >= Math.Simd.splat(0x41'u8)) & (value <= Math.Simd.splat(0x5A'u8))
    return value + (asciiMask & Math.Simd.splat(0x20'u8))
}

// Lowercases ASCII and Latin-1 letters in UTF-8, preserving all other encoded characters.
//
// Mapping is in place and keeps the byte count. Only case pairs contained in Latin-1
// are mapped; this does not perform full Unicode case mapping or normalization.
func makeLower(buffer: [..] u8)
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    var offset = 0'u64
    while buffer.count - offset >= VectorSize
    {
        let value = Math.Simd.load(buffer.buffer + offset)
        if Math.Simd.anyTrue(value >= Math.Simd.splat(0x80'u8)) do
            break
        Math.Simd.store(buffer.buffer + offset, toLowerUtf8(value))
        offset += VectorSize
    }

    for i in offset until buffer.count do
        buffer[i] = lowerUtf8Byte(buffer, i)
}

#[Inline]
private func upperUtf8Byte(buffer: const [..] u8, index: u64)->u8
{
    let value = buffer[index]
    if isAscii(value) do
        return toUpper(value)
    if index and buffer[index - 1] == 0xC3 and isLowerUtf8(value) do
        return value - 0x20
    return value
}

// Folds only ASCII and the second byte of an encoded Latin-1 uppercase letter.
#[Inline]
private func lowerUtf8Byte(buffer: const [..] u8, index: u64)->u8
{
    let value = buffer[index]
    if isAscii(value) do
        return toLower(value)
    if index and buffer[index - 1] == 0xC3 and isUpperUtf8(value) do
        return value + 0x20
    return value
}

// Compares UTF-8 text in byte order, optionally ignoring ASCII and Latin-1 case pairs.
//
// Returns -1, 0 or 1. Case-insensitive comparison folds A-Z and U+00C0-U+00DE except
// U+00D7 to their lowercase partners. Other encoded characters remain byte-exact;
// this performs neither full Unicode case folding nor Unicode normalization.
func compare(src, dst: const [..] u8, ignoreCase = false)->s32
{
    let length      = src.count
    let otherLength = dst.count
    let minLen      = Math.min(length, otherLength)

    var result: s32
    if ignoreCase
    {
        const VectorSize = #sizeof(Math.Simd.U8x16)
        var offset = 0'u64
        while minLen - offset >= VectorSize
        {
            let raw1 = Math.Simd.load(src.buffer + offset)
            let raw2 = Math.Simd.load(dst.buffer + offset)
            if Math.Simd.bitmask(raw1 == raw2) == 0xFFFF
            {
                offset += VectorSize
                continue
            }

            // A non-ASCII block needs the preceding UTF-8 lead byte, including at
            // a block boundary. Keep the packed path for ASCII and fold the rest below.
            if Math.Simd.anyTrue((raw1 | raw2) >= Math.Simd.splat(0x80'u8)) do
                break

            let c1        = toLowerUtf8(raw1)
            let c2        = toLowerUtf8(raw2)
            let equalMask = Math.Simd.bitmask(c1 == c2)
            if equalMask != 0xFFFF
            {
                let lane = Math.trailingZeros((~equalMask) & 0xFFFF)
                return Math.sign(cast(s32) c1[lane] - cast(s32) c2[lane])
            }

            offset += VectorSize
        }

        #[Swag.Safety(.BoundCheck, false)]
        for i in offset until minLen
        {
            let c1 = lowerUtf8Byte(src, i)
            let c2 = lowerUtf8Byte(dst, i)
            result = cast(s32) c1 - cast(s32) c2
            if result != 0 do
                return Math.sign(result)
        }
    }
    else
    {
        result = Memory.compare(src.buffer, dst.buffer, minLen)
    }

    if result != 0 do
        return Math.sign(result)
    return length <=> otherLength
}

// Compares UTF-8 text naturally, returning -1, 0 or 1.
//
// ASCII digit runs compare numerically and ASCII/Latin-1 whitespace is skipped.
// `ignoreCase` maps only ASCII and Latin-1 case pairs; other encoded characters
// remain byte-exact. No Unicode normalization is performed.
//
// @LICENCE: Zlib
// @ORIGIN: Natural sort by Martin Pool, https://github.com/sourcefrog/natsort
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#natural-sort
#[Swag.Sanity(Swag.SafetyWhat.All, false)]
func compareNatural(src, dst: const [..] u8, ignoreCase = false)->s32
{
    func compareLeft(src, dst: const [..] u8)->s32
    {
        var csrc   = src.count
        var cdst   = dst.count
        var ai, bi = 0
        for
        {
            let ca = not csrc ? 0 : src[ai]
            let cb = not cdst ? 0 : dst[bi]

            let dga = ca >= '0'u8 and ca <= '9'u8
            let dgb = cb >= '0'u8 and cb <= '9'u8

            if not dga and not dgb do
                return 0
            if not dga do
                return -1
            if not dgb do
                return 1
            if ca < cb do
                return -1
            if ca > cb do
                return 1

            ai, bi     += 1
            csrc, cdst -= 1
        }

        return 0
    }

    func compareRight(src, dst: const [..] u8)->s32
    {
        var bias   = 0
        var csrc   = src.count
        var cdst   = dst.count
        var ai, bi = 0
        for
        {
            let ca = not csrc ? 0 : src[ai]
            let cb = not cdst ? 0 : dst[bi]

            let dga = ca >= '0'u8 and ca <= '9'u8
            let dgb = cb >= '0'u8 and cb <= '9'u8

            if not dga and not dgb do
                return bias
            if not dga do
                return -1
            if not dgb do
                return 1

            if ca < cb
            {
                if not bias do
                    bias = -1
            }
            elif ca > cb
            {
                if not bias do
                    bias = 1
            }
            elif not ca and not cb do
                return bias

            ai, bi     += 1
            csrc, cdst -= 1
        }

        return 0
    }

    var ai, bi = 0'u64
    for
    {
        if ai < src.count and (isAsciiSpace(src[ai]) or src.count - ai >= 2 and isEncodedSpace(src[ai], src[ai + 1])) do
            ai += firstNonSpace(src[ai until src.count])
        if bi < dst.count and (isAsciiSpace(dst[bi]) or dst.count - bi >= 2 and isEncodedSpace(dst[bi], dst[bi + 1])) do
            bi += firstNonSpace(dst[bi until dst.count])
        if ai == src.count or bi == dst.count do
            return (src.count - ai) <=> (dst.count - bi)

        var ca = src[ai]
        var cb = dst[bi]

        // A UTF-8 continuation byte is never part of an ASCII decimal run.
        if ca >= '0'u8 and ca <= '9'u8 and cb >= '0'u8 and cb <= '9'u8
        {
            let left   = src[ai until src.count]
            let right  = dst[bi until dst.count]
            let result = ca == '0'u8 or cb == '0'u8 ? compareLeft(left, right) : compareRight(left, right)
            if result do
                return result
        }

        if ignoreCase
        {
            ca = upperUtf8Byte(src, ai)
            cb = upperUtf8Byte(dst, bi)
        }

        if ca < cb do
            return -1
        if ca > cb do
            return 1
        ai, bi += 1
    }
}

// Trims ASCII and Latin-1 whitespace from UTF-8 text, returning a borrowed view.
//
// Encoded U+0085 and U+00A0 are removed as complete characters. Other Unicode
// whitespace is preserved; the returned view remains valid while `str` does.
func trim(str: string)->string
{
    let bytes = Swag.makeSlice(str.buffer, str.count)
    let first = firstNonSpace(bytes)
    if first == str.count do
        return ""
    let tail = bytes[first until bytes.count]
    let last = first + lastNonSpace(tail)
    return Swag.makeString(str.buffer + first, last - first)
}
