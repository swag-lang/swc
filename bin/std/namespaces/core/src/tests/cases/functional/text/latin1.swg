#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.require(Latin1.isAscii(0x00))
    Swag.require(Latin1.isAscii(0x7F))
    Swag.require(not Latin1.isAscii(0x80))

    Swag.require(Latin1.isDigit('5'_u8))
    Swag.require(Latin1.isNumber('5'_u8))
    Swag.require(not Latin1.isDigit('a'_u8))
    Swag.require(Latin1.isBinDigit('0'_u8))
    Swag.require(Latin1.isBinDigit('1'_u8))
    Swag.require(not Latin1.isBinDigit('2'_u8))
    Swag.require(Latin1.isHexDigit('0'_u8))
    Swag.require(Latin1.isHexDigit('9'_u8))
    Swag.require(Latin1.isHexDigit('a'_u8))
    Swag.require(Latin1.isHexDigit('F'_u8))
    Swag.require(not Latin1.isHexDigit('g'_u8))

    Swag.require(Latin1.isUpper('A'_u8))
    Swag.require(not Latin1.isUpper('a'_u8))
    Swag.require(Latin1.isLower('a'_u8))
    Swag.require(not Latin1.isLower('A'_u8))
    Swag.require(Latin1.isLetter('Z'_u8))
    Swag.require(Latin1.isLetter('z'_u8))
    Swag.require(not Latin1.isLetter('5'_u8))
    Swag.require(Latin1.isLetterOrDigit('Z'_u8))
    Swag.require(Latin1.isLetterOrDigit('5'_u8))
    Swag.require(not Latin1.isLetterOrDigit('_'_u8))
    Swag.require(Latin1.isWord('Z'_u8))
    Swag.require(Latin1.isWord('5'_u8))
    Swag.require(Latin1.isWord('_'_u8))
    Swag.require(not Latin1.isWord('-'_u8))

    Swag.require(Latin1.isSpace(' '_u8))
    Swag.require(Latin1.isSpace(0x09))
    Swag.require(not Latin1.isSpace('A'_u8))
    Swag.require(Latin1.isControl(0x1F))
    Swag.require(not Latin1.isControl('A'_u8))
    Swag.require(Latin1.isPunctuation('.'_u8))
    Swag.require(not Latin1.isPunctuation('A'_u8))
    Swag.require(Latin1.isSymbol('$'_u8))
    Swag.require(not Latin1.isSymbol('A'_u8))
}

// A lowercase classification does not imply an uppercase partner fits in Latin-1.
#test
{
    const Upper: [5] u8 = ['A'_u8, 'Z'_u8, 0xC0, 0xC9, 0xDE]
    const Lower: [5] u8 = ['a'_u8, 'z'_u8, 0xE0, 0xE9, 0xFE]
    for index in Upper.count
    {
        Swag.require(Latin1.isUpper(Upper[index]))
        Swag.require(not Latin1.isLower(Upper[index]))
        Swag.require(Latin1.isLower(Lower[index]))
        Swag.require(not Latin1.isUpper(Lower[index]))
        Swag.require(Latin1.toLower(Upper[index]) == Lower[index])
        Swag.require(Latin1.toUpper(Lower[index]) == Upper[index])
    }

    // Micro sign, sharp s and y-diaeresis have no single-byte uppercase partner.
    for value in [0xB5_u8, 0xDF_u8, 0xFF_u8]
    {
        Swag.require(Latin1.isLower(value))
        Swag.require(not Latin1.isUpper(value))
        Swag.require(Latin1.toUpper(value) == value)
        Swag.require(Latin1.toLower(value) == value)
    }

    for value in [0xD7_u8, 0xF7_u8]
    {
        Swag.require(Latin1.isSymbol(value))
        Swag.require(not Latin1.isLower(value))
        Swag.require(not Latin1.isUpper(value))
        Swag.require(Latin1.toUpper(value) == value)
        Swag.require(Latin1.toLower(value) == value)
    }
}

#test
{
    Swag.require(Latin1.toLower('A'_u8) == 'a'_u8)
    Swag.require(Latin1.toLower('a'_u8) == 'a'_u8)
    Swag.require(Latin1.toLower(0xC0) == 0xE0)
    Swag.require(Latin1.toUpper('a'_u8) == 'A'_u8)
    Swag.require(Latin1.toUpper('A'_u8) == 'A'_u8)
    Swag.require(Latin1.toUpper(0xE0) == 0xC0)

    var bytes: [6] u8 = ['a'_u8, 'Z'_u8, 0xC3, 0xA9, '0'_u8, '_'_u8]
    Latin1.makeUpper(bytes)
    Swag.require(bytes[0] == 'A'_u8)
    Swag.require(bytes[1] == 'Z'_u8)
    Swag.require(bytes[2] == 0xC3)
    Swag.require(bytes[3] == 0x89)
    Swag.require(bytes[4] == '0'_u8)
    Swag.require(bytes[5] == '_'_u8)

    Latin1.makeLower(bytes)
    Swag.require(bytes[0] == 'a'_u8)
    Swag.require(bytes[1] == 'z'_u8)
    Swag.require(bytes[2] == 0xC3)
    Swag.require(bytes[3] == 0xA9)
    Swag.require(bytes[4] == '0'_u8)
    Swag.require(bytes[5] == '_'_u8)
}

#test
{
    Swag.require(Latin1.compare("abc", "abc") == 0)
    Swag.require(Latin1.compare("abc", "abd") == -1)
    Swag.require(Latin1.compare("abd", "abc") == 1)
    Swag.require(Latin1.compare("abc", "abcd") == -1)
    Swag.require(Latin1.compare("abcd", "abc") == 1)

    Swag.require(Latin1.compare("AbC", "aBc", ignoreCase: true) == 0)
    Swag.require(Latin1.compare("abc", "ABd", ignoreCase: true) == -1)
    Swag.require(Latin1.compare("ABd", "abc", ignoreCase: true) == 1)
}

#test
{
    Swag.require(Latin1.compareNatural("file2", "file10") == -1)
    Swag.require(Latin1.compareNatural("file10", "file2") == 1)
    Swag.require(Latin1.compareNatural("file02", "file2") == -1)
    Swag.require(Latin1.compareNatural("file2", "file02") == 1)
    Swag.require(Latin1.compareNatural("file2", "file2") == 0)
    Swag.require(Latin1.compareNatural("  file2", "file2") == 0)
    Swag.require(Latin1.compareNatural("File2", "file2", ignoreCase: true) == 0)
    Swag.require(Latin1.compareNatural("File2", "file2") == -1)
}

#test
{
    Swag.require(Latin1.trim("  abc  ") == "abc")
    Swag.require(Latin1.trim("\t abc\n") == "abc")
    Swag.require(Latin1.trim("abc") == "abc")
    Swag.require(Latin1.trim("   ") == "")
    Swag.require(Latin1.trim("") == "")
}

// Trim complete encoded Latin-1 spaces without consuming another rune's final byte.
#test
{
    for leading in 33
    {
        for trailing in 33
        {
            var text: String
            for leading
            {
                text += " \u0085\u00A0\t"
            }

            text += "\u0105\u0120"
            for trailing
            {
                text += "\u00A0\u0085 \n"
            }

            Swag.require(Latin1.trim(text.toString()) == "\u0105\u0120")
        }
    }

    Swag.require(Latin1.trim("\u0120") == "\u0120")
    Swag.require(Latin1.trim("\u2003") == "\u2003")
    Swag.require(Latin1.trim(" \u0085\u00A0\t") == "")
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
            if (code >= 0x61 and code <= 0x7A) or (code >= 0xE0 and code <= 0xFE and code != 0xF7)
            {
                expectedUpperCode -= 0x20
            }

            if (code >= 0x41 and code <= 0x5A) or (code >= 0xC0 and code <= 0xDE and code != 0xD7)
            {
                expectedLowerCode += 0x20
            }

            var original, expectedUpper, expectedLower: String
            for prefixSize
            {
                original      += "a"
                expectedUpper += "A"
                expectedLower += "a"
            }

            original      += cast(rune, code)
            expectedUpper += cast(rune, expectedUpperCode)
            expectedLower += cast(rune, expectedLowerCode)
            original      += "zABCDEFGHIJKLMNOPQRSTUVWXYZ"
            expectedUpper += "ZABCDEFGHIJKLMNOPQRSTUVWXYZ"
            expectedLower += "zabcdefghijklmnopqrstuvwxyz"

            var upper = original
            var lower = original
            Latin1.makeUpper(upper.bytes())
            Latin1.makeLower(lower.bytes())
            Swag.require(upper.toString() == expectedUpper.toString())
            Swag.require(lower.toString() == expectedLower.toString())
            Swag.require(Latin1.compare(upper.toString(), lower.toString(), ignoreCase: true) == 0)
        }
    }
}

// Non-Latin-1 text remains unchanged even when continuation bytes resemble case/space bytes.
#test
{
    for prefixSize in 33
    {
        var prefix: String
        for prefixSize
        {
            prefix += "0"
        }

        let original = Format.toString("%\u0100\u0101\u0120\u0105\u4E01\U0001F600\U0001F62000000000000000000000000000000000", prefix.toString())
        var upper    = original
        var lower    = original
        Latin1.makeUpper(upper.bytes())
        Latin1.makeLower(lower.bytes())
        Swag.require(upper.toString() == original.toString())
        Swag.require(lower.toString() == original.toString())
    }
}

// Comparison preserves encoded characters outside the supported Latin-1 case pairs.
#test
{
    for prefixSize in 33
    {
        var prefix: String
        for prefixSize
        {
            prefix += "a"
        }

        let upper = Format.toString("%ABC\u00C0\u00C9\u00DE\u00D7\u0100\U0001F600suffix", prefix.toString())
        let lower = Format.toString("%abc\u00E0\u00E9\u00FE\u00D7\u0100\U0001F600suffix", prefix.toString())
        Swag.require(Latin1.compare(upper.toString(), lower.toString(), ignoreCase: true) == 0)
        Swag.require(Latin1.compare(upper.toString(), lower.toString()) == -1)
        Swag.require(Latin1.compare(lower.toString(), upper.toString()) == 1)
    }

    // U+0080 and NBSP are both in Latin-1, but they are not a case pair.
    Swag.require(Latin1.compare("\u0080", "\u00A0", ignoreCase: true) == -1)
    Swag.require(Latin1.compare("\u00A0", "\u0080", ignoreCase: true) == 1)
    Swag.require(Latin1.compare("\u00D7", "\u00F7", ignoreCase: true) == -1)
    Swag.require(Latin1.compare("", "", ignoreCase: true) == 0)
    Swag.require(Latin1.compare("a", "AB", ignoreCase: true) == -1)
    Swag.require(Latin1.compare("AB", "a", ignoreCase: true) == 1)
}

#test
{
    Swag.require(Latin1.compareNatural("Caf\u00E92", "CAF\u00C910", ignoreCase: true) == -1)
    Swag.require(Latin1.compareNatural("Caf\u00E92", "CAF\u00C92", ignoreCase: true) == 0)
    Swag.require(Latin1.compareNatural("\u0100file2", "\u0120file2", ignoreCase: true) == -1)
    Swag.require(Latin1.compareNatural("\u0105", "\u0120", ignoreCase: true) == -1)
    Swag.require(Latin1.compareNatural("\u0080", "\u00A0", ignoreCase: true) == 1)
    Swag.require(Latin1.compareNatural("file2\u00A0", "file2", ignoreCase: true) == 0)
    Swag.require(Latin1.compareNatural(" \u0085\u00A0", "", ignoreCase: true) == 0)
    Swag.require(Latin1.compareNatural(" ", "", ignoreCase: true) == 0)
    Swag.require(Latin1.compareNatural("", " ", ignoreCase: true) == 0)
    Swag.require(Latin1.compareNatural("\u0100", "\u0101", ignoreCase: true) == -1)
    Swag.require(Latin1.compareNatural("a\u0000b", "a\u0000c") == -1)
    Swag.require(Latin1.compareNatural("a\u0000", "a") == 1)
}
