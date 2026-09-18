#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.assert(Latin1.isAscii(0x00))
    Swag.assert(Latin1.isAscii(0x7F))
    Swag.assert(not Latin1.isAscii(0x80))

    Swag.assert(Latin1.isDigit('5'u8))
    Swag.assert(Latin1.isNumber('5'u8))
    Swag.assert(not Latin1.isDigit('a'u8))
    Swag.assert(Latin1.isBinDigit('0'u8))
    Swag.assert(Latin1.isBinDigit('1'u8))
    Swag.assert(not Latin1.isBinDigit('2'u8))
    Swag.assert(Latin1.isHexDigit('0'u8))
    Swag.assert(Latin1.isHexDigit('9'u8))
    Swag.assert(Latin1.isHexDigit('a'u8))
    Swag.assert(Latin1.isHexDigit('F'u8))
    Swag.assert(not Latin1.isHexDigit('g'u8))

    Swag.assert(Latin1.isUpper('A'u8))
    Swag.assert(not Latin1.isUpper('a'u8))
    Swag.assert(Latin1.isLower('a'u8))
    Swag.assert(not Latin1.isLower('A'u8))
    Swag.assert(Latin1.isLetter('Z'u8))
    Swag.assert(Latin1.isLetter('z'u8))
    Swag.assert(not Latin1.isLetter('5'u8))
    Swag.assert(Latin1.isLetterOrDigit('Z'u8))
    Swag.assert(Latin1.isLetterOrDigit('5'u8))
    Swag.assert(not Latin1.isLetterOrDigit('_'u8))
    Swag.assert(Latin1.isWord('Z'u8))
    Swag.assert(Latin1.isWord('5'u8))
    Swag.assert(Latin1.isWord('_'u8))
    Swag.assert(not Latin1.isWord('-'u8))

    Swag.assert(Latin1.isSpace(' 'u8))
    Swag.assert(Latin1.isSpace(0x09))
    Swag.assert(not Latin1.isSpace('A'u8))
    Swag.assert(Latin1.isControl(0x1F))
    Swag.assert(not Latin1.isControl('A'u8))
    Swag.assert(Latin1.isPunctuation('.'u8))
    Swag.assert(not Latin1.isPunctuation('A'u8))
    Swag.assert(Latin1.isSymbol('$'u8))
    Swag.assert(not Latin1.isSymbol('A'u8))
}

// A lowercase classification does not imply an uppercase partner fits in Latin-1.
#test
{
    const Upper: [5] u8 = ['A'u8, 'Z'u8, 0xC0, 0xC9, 0xDE]
    const Lower: [5] u8 = ['a'u8, 'z'u8, 0xE0, 0xE9, 0xFE]
    for index in Upper.count
    {
        Swag.assert(Latin1.isUpper(Upper[index]))
        Swag.assert(not Latin1.isLower(Upper[index]))
        Swag.assert(Latin1.isLower(Lower[index]))
        Swag.assert(not Latin1.isUpper(Lower[index]))
        Swag.assert(Latin1.toLower(Upper[index]) == Lower[index])
        Swag.assert(Latin1.toUpper(Lower[index]) == Upper[index])
    }

    // Micro sign, sharp s and y-diaeresis have no single-byte uppercase partner.
    for value in [0xB5'u8, 0xDF'u8, 0xFF'u8]
    {
        Swag.assert(Latin1.isLower(value))
        Swag.assert(not Latin1.isUpper(value))
        Swag.assert(Latin1.toUpper(value) == value)
        Swag.assert(Latin1.toLower(value) == value)
    }

    for value in [0xD7'u8, 0xF7'u8]
    {
        Swag.assert(Latin1.isSymbol(value))
        Swag.assert(not Latin1.isLower(value))
        Swag.assert(not Latin1.isUpper(value))
        Swag.assert(Latin1.toUpper(value) == value)
        Swag.assert(Latin1.toLower(value) == value)
    }
}

#test
{
    Swag.assert(Latin1.toLower('A'u8) == 'a'u8)
    Swag.assert(Latin1.toLower('a'u8) == 'a'u8)
    Swag.assert(Latin1.toLower(0xC0) == 0xE0)
    Swag.assert(Latin1.toUpper('a'u8) == 'A'u8)
    Swag.assert(Latin1.toUpper('A'u8) == 'A'u8)
    Swag.assert(Latin1.toUpper(0xE0) == 0xC0)

    var bytes: [6] u8 = ['a'u8, 'Z'u8, 0xC3, 0xA9, '0'u8, '_'u8]
    Latin1.makeUpper(bytes)
    Swag.assert(bytes[0] == 'A'u8)
    Swag.assert(bytes[1] == 'Z'u8)
    Swag.assert(bytes[2] == 0xC3)
    Swag.assert(bytes[3] == 0x89)
    Swag.assert(bytes[4] == '0'u8)
    Swag.assert(bytes[5] == '_'u8)

    Latin1.makeLower(bytes)
    Swag.assert(bytes[0] == 'a'u8)
    Swag.assert(bytes[1] == 'z'u8)
    Swag.assert(bytes[2] == 0xC3)
    Swag.assert(bytes[3] == 0xA9)
    Swag.assert(bytes[4] == '0'u8)
    Swag.assert(bytes[5] == '_'u8)
}

#test
{
    Swag.assert(Latin1.compare("abc", "abc") == 0)
    Swag.assert(Latin1.compare("abc", "abd") == -1)
    Swag.assert(Latin1.compare("abd", "abc") == 1)
    Swag.assert(Latin1.compare("abc", "abcd") == -1)
    Swag.assert(Latin1.compare("abcd", "abc") == 1)

    Swag.assert(Latin1.compare("AbC", "aBc", ignoreCase: true) == 0)
    Swag.assert(Latin1.compare("abc", "ABd", ignoreCase: true) == -1)
    Swag.assert(Latin1.compare("ABd", "abc", ignoreCase: true) == 1)
}

#test
{
    Swag.assert(Latin1.compareNatural("file2", "file10") == -1)
    Swag.assert(Latin1.compareNatural("file10", "file2") == 1)
    Swag.assert(Latin1.compareNatural("file02", "file2") == -1)
    Swag.assert(Latin1.compareNatural("file2", "file02") == 1)
    Swag.assert(Latin1.compareNatural("file2", "file2") == 0)
    Swag.assert(Latin1.compareNatural("  file2", "file2") == 0)
    Swag.assert(Latin1.compareNatural("File2", "file2", ignoreCase: true) == 0)
    Swag.assert(Latin1.compareNatural("File2", "file2") == -1)
}

#test
{
    Swag.assert(Latin1.trim("  abc  ") == "abc")
    Swag.assert(Latin1.trim("\t abc\n") == "abc")
    Swag.assert(Latin1.trim("abc") == "abc")
    Swag.assert(Latin1.trim("   ") == "")
    Swag.assert(Latin1.trim("") == "")
}

// Trim complete encoded Latin-1 spaces without consuming another rune's final byte.
#test
{
    for leading in 33
    {
        for trailing in 33
        {
            var text: String
            for leading do
                text += " \u0085\u00A0\t"
            text += "\u0105\u0120"
            for trailing do
                text += "\u00A0\u0085 \n"
            Swag.assert(Latin1.trim(text.toString()) == "\u0105\u0120")
        }
    }

    Swag.assert(Latin1.trim("\u0120") == "\u0120")
    Swag.assert(Latin1.trim("\u2003") == "\u2003")
    Swag.assert(Latin1.trim(" \u0085\u00A0\t") == "")
}

// Encode every Latin-1 code point and put each one across every packed-block alignment.
#test
{
    for prefixSize in 33
    {
        for code in 256
        {
            var expectedUpperCode = code
            var expectedLowerCode = code
            if (code >= 0x61 and code <= 0x7A) or (code >= 0xE0 and code <= 0xFE and code != 0xF7) do
                expectedUpperCode -= 0x20
            if (code >= 0x41 and code <= 0x5A) or (code >= 0xC0 and code <= 0xDE and code != 0xD7) do
                expectedLowerCode += 0x20

            var original, expectedUpper, expectedLower: String
            for prefixSize
            {
                original      += "a"
                expectedUpper += "A"
                expectedLower += "a"
            }

            original      += cast(rune) code
            expectedUpper += cast(rune) expectedUpperCode
            expectedLower += cast(rune) expectedLowerCode
            original      += "zABCDEFGHIJKLMNOPQRSTUVWXYZ"
            expectedUpper += "ZABCDEFGHIJKLMNOPQRSTUVWXYZ"
            expectedLower += "zabcdefghijklmnopqrstuvwxyz"

            var upper = original
            var lower = original
            Latin1.makeUpper(upper.bytes())
            Latin1.makeLower(lower.bytes())
            Swag.assert(upper.toString() == expectedUpper.toString())
            Swag.assert(lower.toString() == expectedLower.toString())
            Swag.assert(Latin1.compare(upper.toString(), lower.toString(), ignoreCase: true) == 0)
        }
    }
}

// Non-Latin-1 text remains unchanged even when continuation bytes resemble case/space bytes.
#test
{
    for prefixSize in 33
    {
        var prefix: String
        for prefixSize do
            prefix += "0"
        let original = Format.toString("%\u0100\u0101\u0120\u0105\u4E01\U0001F600\U0001F62000000000000000000000000000000000", prefix.toString())
        var upper    = original
        var lower    = original
        Latin1.makeUpper(upper.bytes())
        Latin1.makeLower(lower.bytes())
        Swag.assert(upper.toString() == original.toString())
        Swag.assert(lower.toString() == original.toString())
    }
}

// Comparison preserves encoded characters outside the supported Latin-1 case pairs.
#test
{
    for prefixSize in 33
    {
        var prefix: String
        for prefixSize do
            prefix += "a"
        let upper = Format.toString("%ABC\u00C0\u00C9\u00DE\u00D7\u0100\U0001F600suffix", prefix.toString())
        let lower = Format.toString("%abc\u00E0\u00E9\u00FE\u00D7\u0100\U0001F600suffix", prefix.toString())
        Swag.assert(Latin1.compare(upper.toString(), lower.toString(), ignoreCase: true) == 0)
        Swag.assert(Latin1.compare(upper.toString(), lower.toString()) == -1)
        Swag.assert(Latin1.compare(lower.toString(), upper.toString()) == 1)
    }

    // U+0080 and NBSP are both in Latin-1, but they are not a case pair.
    Swag.assert(Latin1.compare("\u0080", "\u00A0", ignoreCase: true) == -1)
    Swag.assert(Latin1.compare("\u00A0", "\u0080", ignoreCase: true) == 1)
    Swag.assert(Latin1.compare("\u00D7", "\u00F7", ignoreCase: true) == -1)
    Swag.assert(Latin1.compare("", "", ignoreCase: true) == 0)
    Swag.assert(Latin1.compare("a", "AB", ignoreCase: true) == -1)
    Swag.assert(Latin1.compare("AB", "a", ignoreCase: true) == 1)
}

#test
{
    Swag.assert(Latin1.compareNatural("Caf\u00E92", "CAF\u00C910", ignoreCase: true) == -1)
    Swag.assert(Latin1.compareNatural("Caf\u00E92", "CAF\u00C92", ignoreCase: true) == 0)
    Swag.assert(Latin1.compareNatural("\u0100file2", "\u0120file2", ignoreCase: true) == -1)
    Swag.assert(Latin1.compareNatural("\u0105", "\u0120", ignoreCase: true) == -1)
    Swag.assert(Latin1.compareNatural("\u0080", "\u00A0", ignoreCase: true) == 1)
    Swag.assert(Latin1.compareNatural("file2\u00A0", "file2", ignoreCase: true) == 0)
    Swag.assert(Latin1.compareNatural(" \u0085\u00A0", "", ignoreCase: true) == 0)
    Swag.assert(Latin1.compareNatural(" ", "", ignoreCase: true) == 0)
    Swag.assert(Latin1.compareNatural("", " ", ignoreCase: true) == 0)
    Swag.assert(Latin1.compareNatural("\u0100", "\u0101", ignoreCase: true) == -1)
    Swag.assert(Latin1.compareNatural("a\u0000b", "a\u0000c") == -1)
    Swag.assert(Latin1.compareNatural("a\u0000", "a") == 1)
}
