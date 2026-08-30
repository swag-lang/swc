#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertUtf8String(value: String, expected: string)->bool
{
    let text = value.toString()
    return value == expected and
           value.count == expected.count and
           text.count == expected.count and
           Memory.compare(text.buffer, expected.buffer, expected.count) == 0
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
    var srcPtr     = src.buffer
    var destPtr    = dest.buffer
    var srcLength  = src.count
    var destLength = dest.count
    while srcLength
    {
        let {c, eat} = Utf16.decodeRune(Swag.makeSlice(srcPtr, srcLength))
        let eatDest  = Utf8.encodeRune(Swag.makeSlice(destPtr, destLength), c)
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
        count += Utf8.encodeRune(dest[count until dest.count], value)
    return count
}

#test
{
    var bytes: [4] u8

    Swag.assert(Utf8.encodeRune(bytes, 'A'rune) == 1)
    Swag.assert(bytes[0] == 0x41)

    Swag.assert(Utf8.encodeRune(bytes, '\u00E9'rune) == 2)
    Swag.assert(bytes[0] == 0xC3)
    Swag.assert(bytes[1] == 0xA9)

    Swag.assert(Utf8.encodeRune(bytes, '\u20AC'rune) == 3)
    Swag.assert(bytes[0] == 0xE2)
    Swag.assert(bytes[1] == 0x82)
    Swag.assert(bytes[2] == 0xAC)

    Swag.assert(Utf8.encodeRune(bytes, '\U0001F642'rune) == 4)
    Swag.assert(bytes[0] == 0xF0)
    Swag.assert(bytes[1] == 0x9F)
    Swag.assert(bytes[2] == 0x99)
    Swag.assert(bytes[3] == 0x82)

    Swag.assert(Utf8.encodeRune(bytes, 0xD800'rune) == 3)
    Swag.assert(bytes[0] == 0xEF)
    Swag.assert(bytes[1] == 0xBF)
    Swag.assert(bytes[2] == 0xBD)

    Swag.assert(Utf8.isValidRune(0))
    Swag.assert(Utf8.isValidRune(Utf8.MaxRunes))
    Swag.assert(!Utf8.isValidRune(0xD800'rune))
    Swag.assert(!Utf8.isValidRune(0x110000'rune))
}

#test
{
    let expected        = "A\u00E9\u20AC\U0001F642"
    let runes: [4] rune = ['A'rune, '\u00E9'rune, '\u20AC'rune, '\U0001F642'rune]
    let utf16: [5] u16  = [0x0041, 0x00E9, 0x20AC, 0xD83D, 0xDE42]

    var dest: [16] u8
    var count = Utf8.fromUnicode(dest, runes)
    Swag.assert(count == expected.count)
    Swag.assert(Memory.compare(dest.buffer, expected.buffer, count) == 0)
    Swag.assert(assertUtf8String(Utf8.fromUnicode(runes), expected))

    count = Utf8.fromUtf16(dest, utf16)
    Swag.assert(count == expected.count)
    Swag.assert(Memory.compare(dest.buffer, expected.buffer, count) == 0)
    Swag.assert(assertUtf8String(Utf8.fromUtf16(utf16), expected))

    let invalidUtf16: [1] u16 = [0xD800]
    count = Utf8.fromUtf16(dest, invalidUtf16)
    Swag.assert(count == 3)
    Swag.assert(dest[0] == 0xEF)
    Swag.assert(dest[1] == 0xBF)
    Swag.assert(dest[2] == 0xBD)
}

// Homogeneous two- and three-byte runs exercise every packed BMP path in both source
// representations, across every vector tail.
#test
{
    var runes:    [80] rune
    var utf16:    [80] u16
    var actual:   [320] u8
    var expected: [320] u8
    for index in runes.count
    {
        let value = 0x80 + (index * 37 % 0x780)
        runes[index] = cast(rune) value
        utf16[index] = cast(u16) value
    }

    for length in 66'u64
    {
        for index in actual.count
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let runeSlice     = Swag.makeSlice(runes.buffer, length)
        var actualCount   = Utf8.fromUnicode(actual, runeSlice)
        var expectedCount = scalarUtf8FromUnicode(expected, runeSlice)
        Swag.assert(actualCount == expectedCount)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)

        for index in actual.count
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let utf16Slice = Swag.makeSlice(utf16.buffer, length)
        actualCount   = Utf8.fromUtf16(actual, utf16Slice)
        expectedCount = scalarUtf8FromUtf16(expected, utf16Slice)
        Swag.assert(actualCount == expectedCount)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)
    }
}

#test
{
    var runes:    [80] rune
    var utf16:    [80] u16
    var actual:   [320] u8
    var expected: [320] u8
    for index in runes.count
    {
        let value = index % 2 ? 0x0800 + index * 997 % 0xD000 : 0xE000 + index * 613 % 0x2000
        runes[index] = cast(rune) value
        utf16[index] = cast(u16) value
    }

    for length in 66'u64
    {
        for index in actual.count
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let runeSlice     = Swag.makeSlice(runes.buffer, length)
        var actualCount   = Utf8.fromUnicode(actual, runeSlice)
        var expectedCount = scalarUtf8FromUnicode(expected, runeSlice)
        Swag.assert(actualCount == expectedCount)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)

        for index in actual.count
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let utf16Slice = Swag.makeSlice(utf16.buffer, length)
        actualCount   = Utf8.fromUtf16(actual, utf16Slice)
        expectedCount = scalarUtf8FromUtf16(expected, utf16Slice)
        Swag.assert(actualCount == expectedCount)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)
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
    for index in runes.count
    {
        let value = 0x10000 + index * 7919 % 0x100000
        runes[index] = cast(rune) value
        let surrogate = value - 0x10000
        utf16[2 * index]     = cast(u16) (0xD800 + (surrogate >> 10))
        utf16[2 * index + 1] = cast(u16) (0xDC00 + (surrogate & 0x3FF))
    }

    for length in 66'u64
    {
        for index in actual.count
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let runeSlice     = Swag.makeSlice(runes.buffer, length)
        var actualCount   = Utf8.fromUnicode(actual, runeSlice)
        var expectedCount = scalarUtf8FromUnicode(expected, runeSlice)
        Swag.assert(actualCount == expectedCount)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)

        for index in actual.count
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let utf16Slice = Swag.makeSlice(utf16.buffer, 2 * length)
        actualCount   = Utf8.fromUtf16(actual, utf16Slice)
        expectedCount = scalarUtf8FromUtf16(expected, utf16Slice)
        Swag.assert(actualCount == expectedCount)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)
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
        for index in actual.count
        {
            actual[index]   = 0xA5
            expected[index] = 0xA5
        }

        let actualCount   = Utf8.fromUtf16(actual, source)
        let expectedCount = scalarUtf8FromUtf16(expected, source)
        Swag.assert(actualCount == expectedCount)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)
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
    for source.count do
        source[Swag.index] = cast(u16) ('a' + Swag.index % 26)

    for 66
    {
        for actual.count
        {
            actual[Swag.index]   = 0xA5
            expected[Swag.index] = 0xA5
        }

        let src           = Swag.makeSlice(source.buffer, Swag.index)
        let actualCount   = Utf8.fromUtf16(actual, src)
        let expectedCount = scalarUtf8FromUtf16(expected, src)
        Swag.assert(actualCount == expectedCount)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)
    }

    for 48
    {
        for source.count do
            source[Swag.index] = cast(u16) ('a' + Swag.index % 26)
        source[Swag.index] = 0x20AC
        for actual.count
        {
            actual[Swag.index]   = 0xA5
            expected[Swag.index] = 0xA5
        }

        let src           = Swag.makeSlice(source.buffer, 64)
        let actualCount   = Utf8.fromUtf16(actual, src)
        let expectedCount = scalarUtf8FromUtf16(expected, src)
        Swag.assert(actualCount == expectedCount)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)
    }
}

#test
{
    let text     = "A\u00E9\u20AC\U0001F642"
    var {c, eat} = Utf8.decodeRune(text)
    Swag.assert(c == 'A'rune)
    Swag.assert(eat == 1)

    {c, eat} = Utf8.decodeRune(text[1 until text.count])
    Swag.assert(c == '\u00E9'rune)
    Swag.assert(eat == 2)

    {c, eat} = Utf8.decodeRune(text[3 until text.count])
    Swag.assert(c == '\u20AC'rune)
    Swag.assert(eat == 3)

    {c, eat} = Utf8.decodeRune(text[6 until text.count])
    Swag.assert(c == '\U0001F642'rune)
    Swag.assert(eat == 4)

    {c, eat} = Utf8.decodeLastRune(text)
    Swag.assert(c == '\U0001F642'rune)
    Swag.assert(eat == 4)

    {c, eat} = Utf8.decodeLastRune(text[0 until 6])
    Swag.assert(c == '\u20AC'rune)
    Swag.assert(eat == 3)
}

#test
{
    let invalidStart: [1] u8 = [0x80]
    let truncated:    [2] u8 = [0xE2, 0x82]
    let overlong:     [2] u8 = [0xC0, 0xAF]
    let surrogate:    [3] u8 = [0xED, 0xA0, 0x80]

    Swag.assert(!Utf8.isValid(invalidStart))
    Swag.assert(!Utf8.isValid(truncated))
    Swag.assert(!Utf8.isValid(overlong))
    Swag.assert(!Utf8.isValid(surrogate))

    var {c, eat} = Utf8.decodeRune(invalidStart)
    Swag.assert(c == Utf8.RuneError)
    Swag.assert(eat == 1)

    {c, eat} = Utf8.decodeRune(truncated)
    Swag.assert(c == Utf8.RuneError)
    Swag.assert(eat == 1)

    {c, eat} = Utf8.decodeLastRune(truncated)
    Swag.assert(c == Utf8.RuneError)
    Swag.assert(eat == 1)

    Swag.assert(Utf8.countBytesAt(invalidStart) == 1)
    Swag.assert(Utf8.countBytesAt(truncated) == 1)
    Swag.assert(Utf8.countRunes(invalidStart) == 1)
}

#test
{
    let text = "A\u00E9\u20AC\U0001F642"

    Swag.assert(Utf8.isValid(text))
    Swag.assert(Utf8.countRunes(text) == 4)
    Swag.assert(Utf8.countBytesAt(text) == 1)
    Swag.assert(Utf8.countBytesAt(text[1 until text.count]) == 2)
    Swag.assert(Utf8.countBytesAt(text[3 until text.count]) == 3)
    Swag.assert(Utf8.countBytesAt(text[6 until text.count]) == 4)

    var idx = Utf8.byteIndex(text, 0)
    Swag.assert(idx.success)
    Swag.assert(idx.index == 0)

    idx = Utf8.byteIndex(text, 1)
    Swag.assert(idx.success)
    Swag.assert(idx.index == 1)

    idx = Utf8.byteIndex(text, 2)
    Swag.assert(idx.success)
    Swag.assert(idx.index == 3)

    idx = Utf8.byteIndex(text, 3)
    Swag.assert(idx.success)
    Swag.assert(idx.index == 6)

    idx = Utf8.byteIndex(text, 4)
    Swag.assert(!idx.success)
    Swag.assert(idx.index == text.count)
}

#test
{
    let text = "Core Caf\u00E9 \U0001F642"

    Swag.assert(Utf8.indexOf(text, "Core") == 0)
    Swag.assert(Utf8.indexOf(text, "Caf") == 5)
    Swag.assert(Utf8.indexOf(text, "\u00E9") == 8)
    Swag.assert(Utf8.indexOf(text, "\U0001F642") == 11)
    Swag.assert(Utf8.indexOf(text, '\u00E9'rune) == 8)
    Swag.assert(Utf8.indexOf(text, "core", comparisonType: Utf8.ComparisonType.Latin1NoCase) == 0)
    Swag.assert(Utf8.indexOf(text, "\u00C9", comparisonType: Utf8.ComparisonType.Latin1NoCase) == 8)
    Swag.assert(Utf8.lastIndexOf(text, "\u00C9", Utf8.ComparisonType.Latin1NoCase) == 8)
    Swag.assert(Utf8.indexOf(text, "missing") == Swag.U64.Max)
    Swag.assert(Utf8.indexOf(text, "missing", text.count) == Swag.U64.Max)

    let byteNeedles: [2] u8 = ['f'u8, 'x'u8]
    Swag.assert(Utf8.indexOfAny(text, byteNeedles) == 7)
    Swag.assert(Utf8.indexOfAny(text, byteNeedles, 8) == Swag.U64.Max)
    Swag.assert(Utf8.indexOfAny(text, byteNeedles, text.count) == Swag.U64.Max)

    let runeNeedles: [2] rune = ['\u00E9'rune, '\U0001F642'rune]
    Swag.assert(Utf8.indexOfAny(text, runeNeedles) == 8)
    Swag.assert(Utf8.indexOfAny(text, runeNeedles, 9) == 11)
    Swag.assert(Utf8.indexOfAny(text, runeNeedles, text.count) == Swag.U64.Max)
}

#test
{
    let text = "one fish two fish"

    Swag.assert(Utf8.contains(text, cast(string) "fish"))
    Swag.assert(Utf8.contains(text, 'f'u8))
    Swag.assert(Utf8.contains(text, 'o'rune))
    Swag.assert(!Utf8.contains(text, cast(string) "bird"))

    Swag.assert(Utf8.lastIndexOf(text, "fish") == 13)
    Swag.assert(Utf8.lastIndexOf(text, "FISH", Utf8.ComparisonType.Latin1NoCase) == 13)
    Swag.assert(Utf8.lastIndexOf(text, 'i'rune) == 14)

    let runeNeedles: [2] rune = ['o'rune, 't'rune]
    Swag.assert(Utf8.lastIndexOfAny(text, runeNeedles) == 11)
    let missingRuneNeedles: [2] rune = ['z'rune, '\u2603'rune]
    Swag.assert(Utf8.lastIndexOfAny(text, missingRuneNeedles) == Swag.U64.Max)
    Swag.assert(Utf8.lastIndexOfAny(text, Swag.makeSlice(runeNeedles.buffer, 0)) == Swag.U64.Max)

    let byteNeedles: [2] u8 = ['h'u8, 'x'u8]
    Swag.assert(Utf8.lastIndexOfAny(text, byteNeedles) == 16)
    let missingByteNeedles: [2] u8 = ['z'u8, 'x'u8]
    Swag.assert(Utf8.lastIndexOfAny(text, missingByteNeedles) == Swag.U64.Max)
    Swag.assert(Utf8.lastIndexOfAny(text, Swag.makeSlice(byteNeedles.buffer, 0)) == Swag.U64.Max)

    Swag.assert(Utf8.startsWith(text, "one"))
    Swag.assert(Utf8.startsWith(text, "ONE", Utf8.ComparisonType.Latin1NoCase))
    Swag.assert(!Utf8.startsWith(text, "fish"))
    Swag.assert(Utf8.endsWith(text, "fish"))
    Swag.assert(Utf8.endsWith(text, "FISH", Utf8.ComparisonType.Latin1NoCase))
    Swag.assert(!Utf8.endsWith(text, "one"))
}

#test
{
    let text = "\u00E9clair\U0001F642"

    Swag.assert(Utf8.firstRune(text) == '\u00E9'rune)
    Swag.assert(Utf8.lastRune(text) == '\U0001F642'rune)
    Swag.assert(Utf8.firstRune("") == 0)
    Swag.assert(Utf8.lastRune("") == 0)

    Swag.assert(Utf8.compare("abc", "abc") == 0)
    Swag.assert(Utf8.compare("abc", "abd") == -1)
    Swag.assert(Utf8.compare("abd", "abc") == 1)
    Swag.assert(Utf8.compare("Ab\u00C9", "ab\u00E9", Utf8.ComparisonType.UnicodeNoCase) == 0)

    Swag.assert(assertUtf8String(Utf8.beautifyName("httpServerURL"), "Http Server URL"))
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

    Swag.assert(runeSum == cast(u32) 'A'rune + cast(u32) '\u00E9'rune + cast(u32) '\U0001F642'rune)
    Swag.assert(charIndexSum == 3)
    Swag.assert(byteIndexSum == 4)
}

#test
{
    Swag.assert(firstNonAsciiRune("ASCII") == 0)
    Swag.assert(firstNonAsciiRune("AB\u00E9\U0001F642") == '\u00E9'rune)
}

// Rune counting crosses packed ASCII blocks without consuming the first byte
// of a following multi-byte rune.
#test
{
    var ascii: [80] u8
    for &value in ascii do
        value[] = 'a'
    for length in 66 do
        Swag.assert(Utf8.countRunes(ascii[until length]) == length)

    Swag.assert(Utf8.countRunes("aaaaaaaaaaaaaaa\u00E9") == 16)
    Swag.assert(Utf8.countRunes("aaaaaaaaaaaaaaaa\u00E9") == 17)
    Swag.assert(Utf8.countRunes("aaaaaaaaaaaaaaaaa\U0001F642") == 18)
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
        let text = Swag.makeString(values.buffer, values.count)
        Swag.assert(Utf8.indexOfAny(values, ByteNeedles) == position)
        Swag.assert(Utf8.indexOfAny(values, RuneNeedles) == position)
        Swag.assert(Utf8.lastIndexOfAny(values, ByteNeedles) == position)
        Swag.assert(Utf8.lastIndexOfAny(values, RuneNeedles) == position)
        Swag.assert(Utf8.indexOfAny(values, ByteNeedles, position + 1) == Swag.U64.Max)
        Swag.assert(Utf8.indexOf(text, 'z'rune) == position)
        Swag.assert(Utf8.lastIndexOf(text, 'z'rune) == position)
    }

    for position in 94
    {
        for &value in values do
            value[] = 'a'
        values[position + 0] = 'x'
        values[position + 1] = 'y'
        values[position + 2] = 'z'
        let text = Swag.makeString(values.buffer, values.count)
        Swag.assert(Utf8.indexOf(text, "xyz") == position)
        Swag.assert(Utf8.lastIndexOf(text, "xyz") == position)
        Swag.assert(Utf8.indexOf(text, "XyZ", comparisonType: Utf8.ComparisonType.Latin1NoCase) == position)
        Swag.assert(Utf8.lastIndexOf(text, "XyZ", Utf8.ComparisonType.Latin1NoCase) == position)
    }

    for &value in values do
        value[] = 'a'
    let repeated = Swag.makeString(values.buffer, values.count)
    Swag.assert(Utf8.indexOf(repeated, "azzz") == Swag.U64.Max)
    Swag.assert(Utf8.lastIndexOf(repeated, "azzz") == Swag.U64.Max)
    Swag.assert(Utf8.indexOf(repeated, "AzZZ", comparisonType: Utf8.ComparisonType.Latin1NoCase) == Swag.U64.Max)
    Swag.assert(Utf8.lastIndexOf(repeated, "AzZZ", Utf8.ComparisonType.Latin1NoCase) == Swag.U64.Max)
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
        Swag.assert(result.index == index)
        Swag.assert(result.success == (index < ascii.count))
    }

    let mixed = "aaaaaaaaaaaaaaa\u00E9"
    Swag.assert(Utf8.byteIndex(mixed, 15).index == 15)
    let end = Utf8.byteIndex(mixed, 16)
    Swag.assert(end.index == mixed.count and !end.success)
}
