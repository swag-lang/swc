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

    // Converts this value to lower.
    func toLower(c: u8) => isUpper(c) ? (c | 0x20'u8) : c

    // Converts this value to upper.
    func toUpper(c: u8) => isLower(c) ? (c & ~0x20'u8) : c
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

// Make an utf8 buffer upper case, dealing only with latin1 table
func makeUpper(buffer: [..] u8)
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    let asciiFirst = Math.Simd.splat(0x61'u8)
    let asciiLast  = Math.Simd.splat(0x7A'u8)
    let utf8First  = Math.Simd.splat(0xA0'u8)
    let utf8Last   = Math.Simd.splat(0xBE'u8)
    let utf8Gap    = Math.Simd.splat(0xB7'u8)
    let caseBit    = Math.Simd.splat(0x20'u8)
    var offset     = 0'u64
    while @countof(buffer) - offset >= VectorSize
    {
        let value     = Math.Simd.load(@dataof(buffer) + offset)
        let asciiMask = (value >= asciiFirst) & (value <= asciiLast)
        let utf8Mask  = (value >= utf8First) & (value <= utf8Last) & (value != utf8Gap)
        Math.Simd.store(@dataof(buffer) + offset, value - ((asciiMask | utf8Mask) & caseBit))
        offset += VectorSize
    }

    while offset < @countof(buffer)
    {
        let c = &buffer[offset]
        if isLowerUtf8(c[]) do
            c[] -= 0x20
        offset += 1
    }
}

#[Inline]
private func toLowerUtf8(value: Math.Simd.U8x16)->Math.Simd.U8x16
{
    let asciiMask = (value >= Math.Simd.splat(0x41'u8)) & (value <= Math.Simd.splat(0x5A'u8))
    let utf8Mask  = (value >= Math.Simd.splat(0x80'u8)) & (value <= Math.Simd.splat(0x9E'u8)) & (value != Math.Simd.splat(0x97'u8))
    return value + ((asciiMask | utf8Mask) & Math.Simd.splat(0x20'u8))
}

// Make an utf8 buffer lower case, dealing only with latin1 table
func makeLower(buffer: [..] u8)
{
    const VectorSize = #sizeof(Math.Simd.U8x16)
    var offset = 0'u64
    while @countof(buffer) - offset >= VectorSize
    {
        Math.Simd.store(@dataof(buffer) + offset, toLowerUtf8(Math.Simd.load(@dataof(buffer) + offset)))
        offset += VectorSize
    }

    while offset < @countof(buffer)
    {
        let c = &buffer[offset]
        if isUpperUtf8(c[]) do
            c[] += 0x20
        offset += 1
    }
}

// Compare two utf8 strings, dealing only with latin1 table
// Returns -1, 0 or 1
func compare(src, dst: const [..] u8, ignoreCase = false)->s32
{
    let length      = @countof(src)
    let otherLength = @countof(dst)
    let minLen      = Math.min(length, otherLength)

    var result: s32
    if ignoreCase
    {
        const VectorSize = #sizeof(Math.Simd.U8x16)
        var offset = 0'u64
        while minLen - offset >= VectorSize
        {
            let raw1 = Math.Simd.load(@dataof(src) + offset)
            let raw2 = Math.Simd.load(@dataof(dst) + offset)
            if Math.Simd.bitmask(raw1 == raw2) == 0xFFFF
            {
                offset += VectorSize
                continue
            }

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
            var c1 = src[i]
            var c2 = dst[i]
            if c1 == c2 do
                continue

            c1     += isUpperUtf8(c1) ? 0x20 : 0
            c2     += isUpperUtf8(c2) ? 0x20 : 0
            result = cast(s32) c1 - cast(s32) c2
            if result != 0 do
                return Math.sign(result)
        }
    }
    else
    {
        result = Memory.compare(@dataof(src), @dataof(dst), minLen)
    }

    if result != 0 do
        return Math.sign(result)
    return length <=> otherLength
}

// Compare two utf8 strings in a natural way, dealing only with latin1 table
// Returns -1, 0 or 1
//
// :LICENCE
// This code is based on 'natsort' by Martin Pool (https://github.com/sourcefrog/natsort)
// The original code has been modified for Swag
// See LICENCE.md for the corresponding licence.
#[Swag.Sanity(Swag.SafetyWhat.All, false)]
func compareNatural(src, dst: const [..] u8, ignoreCase = false)->s32
{
    func compareLeft(src, dst: const [..] u8)->s32
    {
        var csrc   = @countof(src)
        var cdst   = @countof(dst)
        var ai, bi = 0
        for
        {
            let ca = !csrc ? 0 : src[ai]
            let cb = !cdst ? 0 : dst[bi]

            let dga = isDigit(ca)
            let dgb = isDigit(cb)

            if !dga and !dgb do
                return 0
            if !dga do
                return -1
            if !dgb do
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
        var csrc   = @countof(src)
        var cdst   = @countof(dst)
        var ai, bi = 0
        for
        {
            let ca = !csrc ? 0 : src[ai]
            let cb = !cdst ? 0 : dst[bi]

            let dga = isDigit(ca)
            let dgb = isDigit(cb)

            if !dga and !dgb do
                return bias
            if !dga do
                return -1
            if !dgb do
                return 1

            if ca < cb
            {
                if !bias do
                    bias = -1
            }
            elif ca > cb
            {
                if !bias do
                    bias = 1
            }
            elif !ca and !cb do
                return bias

            ai, bi     += 1
            csrc, cdst -= 1
        }

        return 0
    }

    let dsrc = @dataof(src)
    let ddst = @dataof(dst)
    var csrc = @countof(src)
    var cdst = @countof(dst)

    var ai, bi = 0
    for
    {
        var ca = !csrc ? 0 : src[ai]
        var cb = !cdst ? 0 : dst[bi]

        // Skip over leading spaces or zeros
        while isSpace(ca)
        {
            ai   += 1
            csrc -= 1
            ca   = src[ai]
        }

        while isSpace(cb)
        {
            bi   += 1
            cdst -= 1
            cb   = dst[bi]
        }

        // Process run of digits
        if isDigit(ca) and isDigit(cb)
        {
            var result = 0
            let sl0    = @mkslice(dsrc + ai, csrc)
            let sl1    = @mkslice(ddst + bi, cdst)
            if ca == '0'u8 or cb == '0'u8 do
                result = compareLeft(sl0, sl1)
            else do
                result = compareRight(sl0, sl1)
            if result do
                return result
        }

        if !ca and !cb do
            return 0

        if ignoreCase
        {
            ca = toUpper(ca)
            cb = toUpper(cb)
        }

        if ca < cb do
            return -1
        if ca > cb do
            return 1

        ai, bi     += 1
        csrc, cdst -= 1
    }

    return 0
}

// Trim the string.
func trim(str: string)->string
{
    var countof = @countof(str)
    var cpt     = 0'u64
    while cpt < countof and Latin1.isSpace(str[cpt]) do
        cpt += 1
    while countof > cpt and Latin1.isSpace(str[countof - 1]) do
        countof -= 1
    if countof <= cpt do
        return ""
    return @mkstring(@dataof(str) + cpt, countof - cpt)
}
