#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertUtf8String(value: String, expected: string)->bool
{
    let text = value.toString()
    return value == expected and
           @countof(value) == @countof(expected) and
           @countof(text) == @countof(expected) and
           Memory.compare(@dataof(text), @dataof(expected), @countof(expected)) == 0
}

func firstNonAsciiRune(text: string)->rune
{
    Utf8.visitRunes(text) #code(c, charIndex, byteIndex)
    {
        discard charIndex
        discard byteIndex
        if c < 0x80 do
            continue
        return c
    }

    return 0
}

func scalarUtf8FromUtf16(dest: [..] u8, src: const [..] u16)->u64
{
    var count      = 0'u64
    var srcPtr     = @dataof(src)
    var destPtr    = @dataof(dest)
    var srcLength  = @countof(src)
    var destLength = @countof(dest)
    while srcLength
    {
        let {c, eat} = Utf16.decodeRune(@mkslice(srcPtr, srcLength))
        let eatDest  = Utf8.encodeRune(@mkslice(destPtr, destLength), c)
        srcPtr     += eat
        srcLength  -= eat
        destPtr    += eatDest
        destLength -= eatDest
        count      += eatDest
    }

    return count
}

func scalarUtf8FromUnicode(dest: [..] u8, src: const [..] rune)->u64
{
    var count = 0'u64
    for value in src do
        count += Utf8.encodeRune(dest[count until @countof(dest)], value)
    return count
}

#test
{
    var bytes: [4] u8

    @assert(Utf8.encodeRune(bytes, 'A'rune) == 1)
    @assert(bytes[0] == 0x41)

    @assert(Utf8.encodeRune(bytes, '\u00E9'rune) == 2)
    @assert(bytes[0] == 0xC3)
    @assert(bytes[1] == 0xA9)

    @assert(Utf8.encodeRune(bytes, '\u20AC'rune) == 3)
    @assert(bytes[0] == 0xE2)
    @assert(bytes[1] == 0x82)
    @assert(bytes[2] == 0xAC)

    @assert(Utf8.encodeRune(bytes, '\U0001F642'rune) == 4)
    @assert(bytes[0] == 0xF0)
    @assert(bytes[1] == 0x9F)
    @assert(bytes[2] == 0x99)
    @assert(bytes[3] == 0x82)

    @assert(Utf8.encodeRune(bytes, 0xD800'rune) == 3)
    @assert(bytes[0] == 0xEF)
    @assert(bytes[1] == 0xBF)
    @assert(bytes[2] == 0xBD)

    @assert(Utf8.isValidRune(0))
    @assert(Utf8.isValidRune(Utf8.MaxRunes))
    @assert(!Utf8.isValidRune(0xD800'rune))
    @assert(!Utf8.isValidRune(0x110000'rune))
}

#test
{
    let expected        = "A\u00E9\u20AC\U0001F642"
    let runes: [4] rune = ['A'rune, '\u00E9'rune, '\u20AC'rune, '\U0001F642'rune]
    let utf16: [5] u16  = [0x0041, 0x00E9, 0x20AC, 0xD83D, 0xDE42]

    var dest: [16] u8
    var count = Utf8.fromUnicode(dest, runes)
    @assert(count == @countof(expected))
    @assert(Memory.compare(@dataof(dest), @dataof(expected), count) == 0)
    @assert(assertUtf8String(Utf8.fromUnicode(runes), expected))

    count = Utf8.fromUtf16(dest, utf16)
    @assert(count == @countof(expected))
    @assert(Memory.compare(@dataof(dest), @dataof(expected), count) == 0)
    @assert(assertUtf8String(Utf8.fromUtf16(utf16), expected))

    let invalidUtf16: [1] u16 = [0xD800]
    count = Utf8.fromUtf16(dest, invalidUtf16)
    @assert(count == 3)
    @assert(dest[0] == 0xEF)
    @assert(dest[1] == 0xBF)
    @assert(dest[2] == 0xBD)
}

// Homogeneous two- and three-byte runs exercise every packed BMP path in both source
// representations, across every vector tail.
#test
{
    var runes:    [80] rune
    var utf16:    [80] u16
    var actual:   [320] u8
    var expected: [320] u8
    for index in @countof(runes)
    {
        let value = 0x80 + (index * 37 % 0x780)
        runes[index] = cast(rune) value
        utf16[index] = cast(u16) value
    }

    for length in 66'u64
    {
        for index in @countof(actual)
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let runeSlice     = @mkslice(@dataof(runes), length)
        var actualCount   = Utf8.fromUnicode(actual, runeSlice)
        var expectedCount = scalarUtf8FromUnicode(expected, runeSlice)
        @assert(actualCount == expectedCount)
        @assert(Memory.compare(@dataof(actual), @dataof(expected), #sizeof(actual)) == 0)

        for index in @countof(actual)
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let utf16Slice = @mkslice(@dataof(utf16), length)
        actualCount   = Utf8.fromUtf16(actual, utf16Slice)
        expectedCount = scalarUtf8FromUtf16(expected, utf16Slice)
        @assert(actualCount == expectedCount)
        @assert(Memory.compare(@dataof(actual), @dataof(expected), #sizeof(actual)) == 0)
    }
}

#test
{
    var runes:    [80] rune
    var utf16:    [80] u16
    var actual:   [320] u8
    var expected: [320] u8
    for index in @countof(runes)
    {
        let value = index % 2 ? 0x0800 + index * 997 % 0xD000 : 0xE000 + index * 613 % 0x2000
        runes[index] = cast(rune) value
        utf16[index] = cast(u16) value
    }

    for length in 66'u64
    {
        for index in @countof(actual)
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let runeSlice     = @mkslice(@dataof(runes), length)
        var actualCount   = Utf8.fromUnicode(actual, runeSlice)
        var expectedCount = scalarUtf8FromUnicode(expected, runeSlice)
        @assert(actualCount == expectedCount)
        @assert(Memory.compare(@dataof(actual), @dataof(expected), #sizeof(actual)) == 0)

        for index in @countof(actual)
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let utf16Slice = @mkslice(@dataof(utf16), length)
        actualCount   = Utf8.fromUtf16(actual, utf16Slice)
        expectedCount = scalarUtf8FromUtf16(expected, utf16Slice)
        @assert(actualCount == expectedCount)
        @assert(Memory.compare(@dataof(actual), @dataof(expected), #sizeof(actual)) == 0)
    }
}

// Four-byte rune runs and their UTF-16 surrogate-pair representation use different source
// geometries, so both are compared to the scalar conversion independently.
#test
{
    var runes:    [80] rune
    var utf16:    [160] u16
    var actual:   [320] u8
    var expected: [320] u8
    for index in @countof(runes)
    {
        let value = 0x10000 + index * 7919 % 0x100000
        runes[index] = cast(rune) value
        let surrogate = value - 0x10000
        utf16[2 * index]     = cast(u16) (0xD800 + (surrogate >> 10))
        utf16[2 * index + 1] = cast(u16) (0xDC00 + (surrogate & 0x3FF))
    }

    for length in 66'u64
    {
        for index in @countof(actual)
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let runeSlice     = @mkslice(@dataof(runes), length)
        var actualCount   = Utf8.fromUnicode(actual, runeSlice)
        var expectedCount = scalarUtf8FromUnicode(expected, runeSlice)
        @assert(actualCount == expectedCount)
        @assert(Memory.compare(@dataof(actual), @dataof(expected), #sizeof(actual)) == 0)

        for index in @countof(actual)
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let utf16Slice = @mkslice(@dataof(utf16), 2 * length)
        actualCount   = Utf8.fromUtf16(actual, utf16Slice)
        expectedCount = scalarUtf8FromUtf16(expected, utf16Slice)
        @assert(actualCount == expectedCount)
        @assert(Memory.compare(@dataof(actual), @dataof(expected), #sizeof(actual)) == 0)
    }
}

// A malformed value in any lane must leave the whole block to the scalar decoder without
// disturbing the valid surrogate pairs around it.
#test
{
    var source:   [32] u16
    var actual:   [128] u8
    var expected: [128] u8
    for index in 16
    {
        source[2 * index]     = 0xD83D
        source[2 * index + 1] = 0xDE42
    }

    for interruption in 24
    {
        source[interruption] = 0x0041
        for index in @countof(actual)
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let actualCount   = Utf8.fromUtf16(actual, source)
        let expectedCount = scalarUtf8FromUtf16(expected, source)
        @assert(actualCount == expectedCount)
        @assert(Memory.compare(@dataof(actual), @dataof(expected), #sizeof(actual)) == 0)
        source[interruption] = interruption % 2 ? 0xDE42 : 0xD83D
    }
}

// Exercise every tail around the eight-lane pack and every possible interruption of a long
// ASCII run. The untouched sentinel bytes are part of the comparison.
#test
{
    var source:   [80] u16
    var actual:   [320] u8
    var expected: [320] u8
    for @countof(source) do
        source[@index] = cast(u16) ('a' + @index % 26)

    for 66
    {
        for @countof(actual)
        {
            actual[@index]   = 0xA5
            expected[@index] = 0xA5
        }

        let src           = @mkslice(@dataof(source), @index)
        let actualCount   = Utf8.fromUtf16(actual, src)
        let expectedCount = scalarUtf8FromUtf16(expected, src)
        @assert(actualCount == expectedCount)
        @assert(Memory.compare(@dataof(actual), @dataof(expected), #sizeof(actual)) == 0)
    }

    for 48
    {
        for @countof(source) do
            source[@index] = cast(u16) ('a' + @index % 26)
        source[@index] = 0x20AC
        for @countof(actual)
        {
            actual[@index]   = 0xA5
            expected[@index] = 0xA5
        }

        let src           = @mkslice(@dataof(source), 64)
        let actualCount   = Utf8.fromUtf16(actual, src)
        let expectedCount = scalarUtf8FromUtf16(expected, src)
        @assert(actualCount == expectedCount)
        @assert(Memory.compare(@dataof(actual), @dataof(expected), #sizeof(actual)) == 0)
    }
}

#test
{
    let text     = "A\u00E9\u20AC\U0001F642"
    var {c, eat} = Utf8.decodeRune(text)
    @assert(c == 'A'rune)
    @assert(eat == 1)

    {c, eat} = Utf8.decodeRune(text[1 until @countof(text)])
    @assert(c == '\u00E9'rune)
    @assert(eat == 2)

    {c, eat} = Utf8.decodeRune(text[3 until @countof(text)])
    @assert(c == '\u20AC'rune)
    @assert(eat == 3)

    {c, eat} = Utf8.decodeRune(text[6 until @countof(text)])
    @assert(c == '\U0001F642'rune)
    @assert(eat == 4)

    {c, eat} = Utf8.decodeLastRune(text)
    @assert(c == '\U0001F642'rune)
    @assert(eat == 4)

    {c, eat} = Utf8.decodeLastRune(text[0 until 6])
    @assert(c == '\u20AC'rune)
    @assert(eat == 3)
}

#test
{
    let invalidStart: [1] u8 = [0x80]
    let truncated:    [2] u8 = [0xE2, 0x82]
    let overlong:     [2] u8 = [0xC0, 0xAF]
    let surrogate:    [3] u8 = [0xED, 0xA0, 0x80]

    @assert(!Utf8.isValid(invalidStart))
    @assert(!Utf8.isValid(truncated))
    @assert(!Utf8.isValid(overlong))
    @assert(!Utf8.isValid(surrogate))

    var {c, eat} = Utf8.decodeRune(invalidStart)
    @assert(c == Utf8.RuneError)
    @assert(eat == 1)

    {c, eat} = Utf8.decodeRune(truncated)
    @assert(c == Utf8.RuneError)
    @assert(eat == 1)

    {c, eat} = Utf8.decodeLastRune(truncated)
    @assert(c == Utf8.RuneError)
    @assert(eat == 1)

    @assert(Utf8.countBytesAt(invalidStart) == 1)
    @assert(Utf8.countBytesAt(truncated) == 1)
    @assert(Utf8.countRunes(invalidStart) == 1)
}

#test
{
    let text = "A\u00E9\u20AC\U0001F642"

    @assert(Utf8.isValid(text))
    @assert(Utf8.countRunes(text) == 4)
    @assert(Utf8.countBytesAt(text) == 1)
    @assert(Utf8.countBytesAt(text[1 until @countof(text)]) == 2)
    @assert(Utf8.countBytesAt(text[3 until @countof(text)]) == 3)
    @assert(Utf8.countBytesAt(text[6 until @countof(text)]) == 4)

    var idx = Utf8.byteIndex(text, 0)
    @assert(idx.success)
    @assert(idx.index == 0)

    idx = Utf8.byteIndex(text, 1)
    @assert(idx.success)
    @assert(idx.index == 1)

    idx = Utf8.byteIndex(text, 2)
    @assert(idx.success)
    @assert(idx.index == 3)

    idx = Utf8.byteIndex(text, 3)
    @assert(idx.success)
    @assert(idx.index == 6)

    idx = Utf8.byteIndex(text, 4)
    @assert(!idx.success)
    @assert(idx.index == @countof(text))
}

#test
{
    let text = "Core Caf\u00E9 \U0001F642"

    @assert(Utf8.indexOf(text, "Core") == 0)
    @assert(Utf8.indexOf(text, "Caf") == 5)
    @assert(Utf8.indexOf(text, "\u00E9") == 8)
    @assert(Utf8.indexOf(text, "\U0001F642") == 11)
    @assert(Utf8.indexOf(text, '\u00E9'rune) == 8)
    @assert(Utf8.indexOf(text, "core", comparisonType: Utf8.ComparisonType.Latin1NoCase) == 0)
    @assert(Utf8.indexOf(text, "\u00C9", comparisonType: Utf8.ComparisonType.Latin1NoCase) == 8)
    @assert(Utf8.lastIndexOf(text, "\u00C9", Utf8.ComparisonType.Latin1NoCase) == 8)
    @assert(Utf8.indexOf(text, "missing") == Swag.U64.Max)
    @assert(Utf8.indexOf(text, "missing", @countof(text)) == Swag.U64.Max)

    let byteNeedles: [2] u8 = ['f'u8, 'x'u8]
    @assert(Utf8.indexOfAny(text, byteNeedles) == 7)
    @assert(Utf8.indexOfAny(text, byteNeedles, 8) == Swag.U64.Max)
    @assert(Utf8.indexOfAny(text, byteNeedles, @countof(text)) == Swag.U64.Max)

    let runeNeedles: [2] rune = ['\u00E9'rune, '\U0001F642'rune]
    @assert(Utf8.indexOfAny(text, runeNeedles) == 8)
    @assert(Utf8.indexOfAny(text, runeNeedles, 9) == 11)
    @assert(Utf8.indexOfAny(text, runeNeedles, @countof(text)) == Swag.U64.Max)
}

#test
{
    let text = "one fish two fish"

    @assert(Utf8.contains(text, cast(string) "fish"))
    @assert(Utf8.contains(text, 'f'u8))
    @assert(Utf8.contains(text, 'o'rune))
    @assert(!Utf8.contains(text, cast(string) "bird"))

    @assert(Utf8.lastIndexOf(text, "fish") == 13)
    @assert(Utf8.lastIndexOf(text, "FISH", Utf8.ComparisonType.Latin1NoCase) == 13)
    @assert(Utf8.lastIndexOf(text, 'i'rune) == 14)

    let runeNeedles: [2] rune = ['o'rune, 't'rune]
    @assert(Utf8.lastIndexOfAny(text, runeNeedles) == 11)
    let missingRuneNeedles: [2] rune = ['z'rune, '\u2603'rune]
    @assert(Utf8.lastIndexOfAny(text, missingRuneNeedles) == Swag.U64.Max)
    @assert(Utf8.lastIndexOfAny(text, @mkslice(@dataof(runeNeedles), 0)) == Swag.U64.Max)

    let byteNeedles: [2] u8 = ['h'u8, 'x'u8]
    @assert(Utf8.lastIndexOfAny(text, byteNeedles) == 16)
    let missingByteNeedles: [2] u8 = ['z'u8, 'x'u8]
    @assert(Utf8.lastIndexOfAny(text, missingByteNeedles) == Swag.U64.Max)
    @assert(Utf8.lastIndexOfAny(text, @mkslice(@dataof(byteNeedles), 0)) == Swag.U64.Max)

    @assert(Utf8.startsWith(text, "one"))
    @assert(Utf8.startsWith(text, "ONE", Utf8.ComparisonType.Latin1NoCase))
    @assert(!Utf8.startsWith(text, "fish"))
    @assert(Utf8.endsWith(text, "fish"))
    @assert(Utf8.endsWith(text, "FISH", Utf8.ComparisonType.Latin1NoCase))
    @assert(!Utf8.endsWith(text, "one"))
}

#test
{
    let text = "\u00E9clair\U0001F642"

    @assert(Utf8.firstRune(text) == '\u00E9'rune)
    @assert(Utf8.lastRune(text) == '\U0001F642'rune)
    @assert(Utf8.firstRune("") == 0)
    @assert(Utf8.lastRune("") == 0)

    @assert(Utf8.compare("abc", "abc") == 0)
    @assert(Utf8.compare("abc", "abd") == -1)
    @assert(Utf8.compare("abd", "abc") == 1)
    @assert(Utf8.compare("Ab\u00C9", "ab\u00E9", Utf8.ComparisonType.UnicodeNoCase) == 0)

    @assert(assertUtf8String(Utf8.beautifyName("httpServerURL"), "Http Server URL"))
}

#test
{
    let text = "A\u00E9\U0001F642"

    var runeSum:      u32
    var charIndexSum: u64
    var byteIndexSum: u64

    Utf8.visitRunes(text) #code(c, charIndex, byteIndex)
    {
        runeSum      += cast(u32) c
        charIndexSum += charIndex
        byteIndexSum += byteIndex
    }

    @assert(runeSum == cast(u32) 'A'rune + cast(u32) '\u00E9'rune + cast(u32) '\U0001F642'rune)
    @assert(charIndexSum == 3)
    @assert(byteIndexSum == 4)
}

#test
{
    @assert(firstNonAsciiRune("ASCII") == 0)
    @assert(firstNonAsciiRune("AB\u00E9\U0001F642") == '\u00E9'rune)
}

// Rune counting crosses packed ASCII blocks without consuming the first byte
// of a following multi-byte rune.
#test
{
    var ascii: [80] u8
    for &value in ascii do
        value[] = 'a'
    for length in 66 do
        @assert(Utf8.countRunes(ascii[until length]) == length)

    @assert(Utf8.countRunes("aaaaaaaaaaaaaaa\u00E9") == 16)
    @assert(Utf8.countRunes("aaaaaaaaaaaaaaaa\u00E9") == 17)
    @assert(Utf8.countRunes("aaaaaaaaaaaaaaaaa\U0001F642") == 18)
}

// Forward and backward ASCII searches preserve exact byte indices across SIMD
// boundaries, arbitrary starts, and scalar tails.
#test
{
    var values: [96] u8
    const ByteNeedles: [4] u8   = ['w', 'x', 'y', 'z']
    const RuneNeedles: [1] rune = ['z']
    for position in 96
    {
        for &value in values do
            value[] = 'a'
        values[position] = 'z'
        let text = @mkstring(@dataof(values), @countof(values))
        @assert(Utf8.indexOfAny(values, ByteNeedles) == position)
        @assert(Utf8.indexOfAny(values, RuneNeedles) == position)
        @assert(Utf8.lastIndexOfAny(values, ByteNeedles) == position)
        @assert(Utf8.lastIndexOfAny(values, RuneNeedles) == position)
        @assert(Utf8.indexOfAny(values, ByteNeedles, position + 1) == Swag.U64.Max)
        @assert(Utf8.indexOf(text, 'z'rune) == position)
        @assert(Utf8.lastIndexOf(text, 'z'rune) == position)
    }

    for position in 94
    {
        for &value in values do
            value[] = 'a'
        values[position + 0] = 'x'
        values[position + 1] = 'y'
        values[position + 2] = 'z'
        let text = @mkstring(@dataof(values), @countof(values))
        @assert(Utf8.indexOf(text, "xyz") == position)
        @assert(Utf8.lastIndexOf(text, "xyz") == position)
        @assert(Utf8.indexOf(text, "XyZ", comparisonType: Utf8.ComparisonType.Latin1NoCase) == position)
        @assert(Utf8.lastIndexOf(text, "XyZ", Utf8.ComparisonType.Latin1NoCase) == position)
    }

    for &value in values do
        value[] = 'a'
    let repeated = @mkstring(@dataof(values), @countof(values))
    @assert(Utf8.indexOf(repeated, "azzz") == Swag.U64.Max)
    @assert(Utf8.lastIndexOf(repeated, "azzz") == Swag.U64.Max)
    @assert(Utf8.indexOf(repeated, "AzZZ", comparisonType: Utf8.ComparisonType.Latin1NoCase) == Swag.U64.Max)
    @assert(Utf8.lastIndexOf(repeated, "AzZZ", Utf8.ComparisonType.Latin1NoCase) == Swag.U64.Max)
}

// Byte-index lookup skips only complete ASCII blocks and stops before a
// following multi-byte rune.
#test
{
    var ascii: [80] u8
    for &value in ascii do
        value[] = 'a'
    for index in 81
    {
        let result = Utf8.byteIndex(ascii, index)
        @assert(result.index == index)
        @assert(result.success == (index < @countof(ascii)))
    }

    let mixed = "aaaaaaaaaaaaaaa\u00E9"
    @assert(Utf8.byteIndex(mixed, 15).index == 15)
    let end = Utf8.byteIndex(mixed, 16)
    @assert(end.index == @countof(mixed) and !end.success)
}
