#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertRuneArray(values: Array'rune, expected: const [..] rune)->bool => Slice.equals(values.toSlice(), expected)

#test
{
    Swag.require(Unicode.isAscii('A'rune))
    Swag.require(not Unicode.isAscii('\u00E9'rune))
    Swag.require(Unicode.isLatin1('\u00E9'rune))
    Swag.require(not Unicode.isLatin1('\u20AC'rune))

    Swag.require(Unicode.isDigit('5'rune))
    Swag.require(Unicode.isNumber('5'rune))
    Swag.require(Unicode.isNumber('\u2167'rune))
    Swag.require(not Unicode.isDigit('A'rune))

    Swag.require(Unicode.isLetter('A'rune))
    Swag.require(Unicode.isLetter('\u03A9'rune))
    Swag.require(Unicode.isLetter('\u4E2D'rune))
    Swag.require(not Unicode.isLetter('7'rune))

    Swag.require(Unicode.isLetterOrDigit('\u03A9'rune))
    Swag.require(Unicode.isLetterOrDigit('7'rune))
    Swag.require(not Unicode.isLetterOrDigit('_'rune))
    Swag.require(Unicode.isWord('_'rune))
    Swag.require(Unicode.isWord('\u03A9'rune))
}

#test
{
    Swag.require(Unicode.isSpace(' 'rune))
    Swag.require(Unicode.isSpace('\u2003'rune))
    Swag.require(not Unicode.isSpace('A'rune))

    Swag.require(Unicode.isControl(0x1F'rune))
    Swag.require(not Unicode.isControl('A'rune))

    Swag.require(Unicode.isSymbol('$'rune))
    Swag.require(Unicode.isSymbol('\u2603'rune))
    Swag.require(Unicode.isSymbolMath('+'rune))
    Swag.require(Unicode.isSymbolMath('\u2211'rune))
    Swag.require(not Unicode.isSymbolMath('A'rune))
}

#test
{
    Swag.require(Unicode.isUpper('A'rune))
    Swag.require(Unicode.isUpper('\u00C9'rune))
    Swag.require(Unicode.isUpper('\u03A9'rune))
    Swag.require(not Unicode.isUpper('\u03C9'rune))

    Swag.require(Unicode.isLower('a'rune))
    Swag.require(Unicode.isLower('\u00E9'rune))
    Swag.require(Unicode.isLower('\u03C9'rune))
    Swag.require(not Unicode.isLower('\u03A9'rune))

    Swag.require(Unicode.isTitle('\u01C5'rune))
    Swag.require(not Unicode.isTitle('\u01C6'rune))
}

#test
{
    Swag.require(Unicode.toLower('A'rune) == 'a'rune)
    Swag.require(Unicode.toUpper('a'rune) == 'A'rune)
    Swag.require(Unicode.toTitle('a'rune) == 'A'rune)

    Swag.require(Unicode.toLower('\u00C9'rune) == '\u00E9'rune)
    Swag.require(Unicode.toUpper('\u00E9'rune) == '\u00C9'rune)
    Swag.require(Unicode.toUpper('\u00B5'rune) == '\u039C'rune)
    Swag.require(Unicode.toUpper('\u00FF'rune) == '\u0178'rune)
    Swag.require(Unicode.toTitle('\u00B5'rune) == '\u039C'rune)
    Swag.require(Unicode.toTitle('\u00FF'rune) == '\u0178'rune)
    Swag.require(Unicode.toTitle('\u00DF'rune) == '\u00DF'rune)

    Swag.require(Unicode.toLower('\u03A9'rune) == '\u03C9'rune)
    Swag.require(Unicode.toUpper('\u03C9'rune) == '\u03A9'rune)

    Swag.require(Unicode.toTitle('\u01C6'rune) == '\u01C5'rune)
    Swag.require(Unicode.toLower('\u0130'rune) == 'i'rune)
    Swag.require(Unicode.toUpper('\u00DF'rune) == '\u00DF'rune)
    Swag.require(Unicode.toUpper('i'rune) == 'I'rune)
    Swag.require(Unicode.toUpper('\u0130'rune) == '\u0130'rune)
    Swag.require(Unicode.toUpper('\u0131'rune) == 'I'rune)
    Swag.require(Unicode.toUpper('\u03C2'rune) == '\u03A3'rune)
}

#test
{
    let text = "A\u00E9\u03A9\U0001F642"
    let expected: [4] rune = ['A'rune, '\u00E9'rune, '\u03A9'rune, '\U0001F642'rune]

    var dest: [8] rune
    let count = Unicode.fromUtf8(dest, text)
    Swag.require(count == 4)
    for i in count do
        Swag.require(dest[i] == expected[i])

    let result = Unicode.fromUtf8(text)
    Swag.require(assertRuneArray(result, expected))

    let invalid:         [1] u8   = [0x80]
    let invalidResult = Unicode.fromUtf8(invalid)
    let expectedInvalid: [1] rune = [Utf8.RuneError]
    Swag.require(assertRuneArray(invalidResult, expectedInvalid))
}

#test
{
    var values: [5] rune = ['a'rune, '\u00E9'rune, '\u03C9'rune, '7'rune, '\u2603'rune]

    Unicode.makeUpper(values)
    Swag.require(values[0] == 'A'rune)
    Swag.require(values[1] == '\u00C9'rune)
    Swag.require(values[2] == '\u03A9'rune)
    Swag.require(values[3] == '7'rune)
    Swag.require(values[4] == '\u2603'rune)

    Unicode.makeLower(values)
    Swag.require(values[0] == 'a'rune)
    Swag.require(values[1] == '\u00E9'rune)
    Swag.require(values[2] == '\u03C9'rune)
    Swag.require(values[3] == '7'rune)
    Swag.require(values[4] == '\u2603'rune)
}

#test
{
    let lower: [3] rune = ['a'rune, '\u00E9'rune, '\u03C9'rune]
    let upper: [3] rune = ['A'rune, '\u00C9'rune, '\u03A9'rune]
    let tail:  [4] rune = ['A'rune, '\u00C9'rune, '\u03A9'rune, 'Z'rune]

    Swag.require(Unicode.compare(lower, lower) == 0)
    Swag.require(Unicode.compare(lower, upper) == 1)
    Swag.require(Unicode.compare(upper, lower) == -1)
    Swag.require(Unicode.compare(lower, upper, ignoreCase: true) == 0)
    Swag.require(Unicode.compare(upper, tail, len: 3) == 0)
    Swag.require(Unicode.compare(upper, tail) == -1)
}

// Alternating case ranges select the right member of both their first and last pair.
#test
{
    for upper in [0x0100'rune, 0x012E'rune]
    {
        let lower = upper + 1
        Swag.require(Unicode.toLower(upper) == lower)
        Swag.require(Unicode.toLower(lower) == lower)
        Swag.require(Unicode.toUpper(lower) == upper)
        Swag.require(Unicode.toUpper(upper) == upper)
        Swag.require(Unicode.toTitle(lower) == upper)
        Swag.require(Unicode.toTitle(upper) == upper)
    }
}
