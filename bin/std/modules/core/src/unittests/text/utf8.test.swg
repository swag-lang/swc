#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertUtf8String(value: const &String, expected: string)->bool
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

#test
{
    var bytes: [4] u8

    @assert(Utf8.encodeRune(bytes, 'A''rune) == 1)
    @assert(bytes[0] == 0x41)

    @assert(Utf8.encodeRune(bytes, '\u00E9''rune) == 2)
    @assert(bytes[0] == 0xC3)
    @assert(bytes[1] == 0xA9)

    @assert(Utf8.encodeRune(bytes, '\u20AC''rune) == 3)
    @assert(bytes[0] == 0xE2)
    @assert(bytes[1] == 0x82)
    @assert(bytes[2] == 0xAC)

    @assert(Utf8.encodeRune(bytes, '\U0001F642''rune) == 4)
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
    let expected = "A\u00E9\u20AC\U0001F642"
    let runes: [4] rune = ['A''rune, '\u00E9''rune, '\u20AC''rune, '\U0001F642''rune]
    let utf16: [5] u16 = [0x0041, 0x00E9, 0x20AC, 0xD83D, 0xDE42]

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

#test
{
    let text = "A\u00E9\u20AC\U0001F642"
        var (c, eat) = Utf8.decodeRune(text)
    @assert(c == 'A''rune)
    @assert(eat == 1)

        (c, eat) = Utf8.decodeRune(text[1 until @countof(text)])
    @assert(c == '\u00E9''rune)
    @assert(eat == 2)

        (c, eat) = Utf8.decodeRune(text[3 until @countof(text)])
    @assert(c == '\u20AC''rune)
    @assert(eat == 3)

        (c, eat) = Utf8.decodeRune(text[6 until @countof(text)])
    @assert(c == '\U0001F642''rune)
    @assert(eat == 4)

        (c, eat) = Utf8.decodeLastRune(text)
    @assert(c == '\U0001F642''rune)
    @assert(eat == 4)

        (c, eat) = Utf8.decodeLastRune(text[0 until 6])
    @assert(c == '\u20AC''rune)
    @assert(eat == 3)
}

#test
{
    let invalidStart: [1] u8 = [0x80]
    let truncated: [2] u8 = [0xE2, 0x82]
    let overlong: [2] u8 = [0xC0, 0xAF]
    let surrogate: [3] u8 = [0xED, 0xA0, 0x80]

    @assert(!Utf8.isValid(invalidStart))
    @assert(!Utf8.isValid(truncated))
    @assert(!Utf8.isValid(overlong))
    @assert(!Utf8.isValid(surrogate))

        var (c, eat) = Utf8.decodeRune(invalidStart)
    @assert(c == Utf8.RuneError)
    @assert(eat == 1)

        (c, eat) = Utf8.decodeRune(truncated)
    @assert(c == Utf8.RuneError)
    @assert(eat == 1)

        (c, eat) = Utf8.decodeLastRune(truncated)
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
    @assert(Utf8.indexOf(text, '\u00E9''rune) == 8)
    @assert(Utf8.indexOf(text, "core", comparisonType: Utf8.ComparisonType.Latin1NoCase) == 0)
    @assert(Utf8.indexOf(text, "missing") == Swag.U64.Max)
    @assert(Utf8.indexOf(text, "missing", @countof(text)) == Swag.U64.Max)

    let byteNeedles: [2] u8 = ['f''u8, 'x''u8]
    @assert(Utf8.indexOfAny(text, byteNeedles) == 7)
    @assert(Utf8.indexOfAny(text, byteNeedles, 8) == Swag.U64.Max)
    @assert(Utf8.indexOfAny(text, byteNeedles, @countof(text)) == Swag.U64.Max)

    let runeNeedles: [2] rune = ['\u00E9''rune, '\U0001F642''rune]
    @assert(Utf8.indexOfAny(text, runeNeedles) == 8)
    @assert(Utf8.indexOfAny(text, runeNeedles, 9) == 11)
    @assert(Utf8.indexOfAny(text, runeNeedles, @countof(text)) == Swag.U64.Max)
}

#test
{
    let text = "one fish two fish"

    @assert(Utf8.contains(text, cast(string) "fish"))
    @assert(Utf8.contains(text, 'f''u8))
    @assert(Utf8.contains(text, 'o''rune))
    @assert(!Utf8.contains(text, cast(string) "bird"))

    @assert(Utf8.lastIndexOf(text, "fish") == 13)
    @assert(Utf8.lastIndexOf(text, "FISH", Utf8.ComparisonType.Latin1NoCase) == 13)
    @assert(Utf8.lastIndexOf(text, 'i''rune) == 14)

    let runeNeedles: [2] rune = ['o''rune, 't''rune]
    @assert(Utf8.lastIndexOfAny(text, runeNeedles) == 11)
    let missingRuneNeedles: [2] rune = ['z''rune, '\u2603''rune]
    @assert(Utf8.lastIndexOfAny(text, missingRuneNeedles) == Swag.U64.Max)
    @assert(Utf8.lastIndexOfAny(text, @mkslice(@dataof(runeNeedles), 0)) == Swag.U64.Max)

    let byteNeedles: [2] u8 = ['h''u8, 'x''u8]
    @assert(Utf8.lastIndexOfAny(text, byteNeedles) == 16)
    let missingByteNeedles: [2] u8 = ['z''u8, 'x''u8]
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

    @assert(Utf8.firstRune(text) == '\u00E9''rune)
    @assert(Utf8.lastRune(text) == '\U0001F642''rune)
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

    var runeSum: u32
    var charIndexSum: u64
    var byteIndexSum: u64

    Utf8.visitRunes(text) #code(c, charIndex, byteIndex)
    {
        runeSum += cast(u32) c
        charIndexSum += charIndex
        byteIndexSum += byteIndex
    }

    @assert(runeSum == cast(u32) 'A''rune + cast(u32) '\u00E9''rune + cast(u32) '\U0001F642''rune)
    @assert(charIndexSum == 3)
    @assert(byteIndexSum == 4)
}

#test
{
    @assert(firstNonAsciiRune("ASCII") == 0)
    @assert(firstNonAsciiRune("AB\u00E9\U0001F642") == '\u00E9''rune)
}
