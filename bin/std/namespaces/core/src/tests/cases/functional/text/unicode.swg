#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertRuneArray(values: Array!{rune}, expected: const [..] rune)->bool => Slice.equals(values.toSlice(), expected)

#test
{
    Swag.require(Unicode.isAscii('A'_rune))
    Swag.require(not Unicode.isAscii('\u00E9'_rune))
    Swag.require(Unicode.isLatin1('\u00E9'_rune))
    Swag.require(not Unicode.isLatin1('\u20AC'_rune))

    Swag.require(Unicode.isDigit('5'_rune))
    Swag.require(Unicode.isNumber('5'_rune))
    Swag.require(Unicode.isNumber('\u2167'_rune))
    Swag.require(not Unicode.isDigit('A'_rune))

    Swag.require(Unicode.isLetter('A'_rune))
    Swag.require(Unicode.isLetter('\u03A9'_rune))
    Swag.require(Unicode.isLetter('\u4E2D'_rune))
    Swag.require(not Unicode.isLetter('7'_rune))

    Swag.require(Unicode.isLetterOrDigit('\u03A9'_rune))
    Swag.require(Unicode.isLetterOrDigit('7'_rune))
    Swag.require(not Unicode.isLetterOrDigit('_'_rune))
    Swag.require(Unicode.isWord('_'_rune))
    Swag.require(Unicode.isWord('\u03A9'_rune))
}

#test
{
    Swag.require(Unicode.isSpace(' '_rune))
    Swag.require(Unicode.isSpace('\u2003'_rune))
    Swag.require(not Unicode.isSpace('A'_rune))

    Swag.require(Unicode.isControl(0x1F_rune))
    Swag.require(not Unicode.isControl('A'_rune))

    Swag.require(Unicode.isSymbol('$'_rune))
    Swag.require(Unicode.isSymbol('\u2603'_rune))
    Swag.require(Unicode.isSymbolMath('+'_rune))
    Swag.require(Unicode.isSymbolMath('\u2211'_rune))
    Swag.require(not Unicode.isSymbolMath('A'_rune))
}

#test
{
    Swag.require(Unicode.isUpper('A'_rune))
    Swag.require(Unicode.isUpper('\u00C9'_rune))
    Swag.require(Unicode.isUpper('\u03A9'_rune))
    Swag.require(not Unicode.isUpper('\u03C9'_rune))

    Swag.require(Unicode.isLower('a'_rune))
    Swag.require(Unicode.isLower('\u00E9'_rune))
    Swag.require(Unicode.isLower('\u03C9'_rune))
    Swag.require(not Unicode.isLower('\u03A9'_rune))

    Swag.require(Unicode.isTitle('\u01C5'_rune))
    Swag.require(not Unicode.isTitle('\u01C6'_rune))
}

#test
{
    Swag.require(Unicode.toLower('A'_rune) == 'a'_rune)
    Swag.require(Unicode.toUpper('a'_rune) == 'A'_rune)
    Swag.require(Unicode.toTitle('a'_rune) == 'A'_rune)

    Swag.require(Unicode.toLower('\u00C9'_rune) == '\u00E9'_rune)
    Swag.require(Unicode.toUpper('\u00E9'_rune) == '\u00C9'_rune)
    Swag.require(Unicode.toUpper('\u00B5'_rune) == '\u039C'_rune)
    Swag.require(Unicode.toUpper('\u00FF'_rune) == '\u0178'_rune)
    Swag.require(Unicode.toTitle('\u00B5'_rune) == '\u039C'_rune)
    Swag.require(Unicode.toTitle('\u00FF'_rune) == '\u0178'_rune)
    Swag.require(Unicode.toTitle('\u00DF'_rune) == '\u00DF'_rune)

    Swag.require(Unicode.toLower('\u03A9'_rune) == '\u03C9'_rune)
    Swag.require(Unicode.toUpper('\u03C9'_rune) == '\u03A9'_rune)

    Swag.require(Unicode.toTitle('\u01C6'_rune) == '\u01C5'_rune)
    Swag.require(Unicode.toLower('\u0130'_rune) == 'i'_rune)
    Swag.require(Unicode.toUpper('\u00DF'_rune) == '\u00DF'_rune)
    Swag.require(Unicode.toUpper('i'_rune) == 'I'_rune)
    Swag.require(Unicode.toUpper('\u0130'_rune) == '\u0130'_rune)
    Swag.require(Unicode.toUpper('\u0131'_rune) == 'I'_rune)
    Swag.require(Unicode.toUpper('\u03C2'_rune) == '\u03A3'_rune)
}

#test
{
    let text = "A\u00E9\u03A9\U0001F642"
    let expected: [4] rune = ['A'_rune, '\u00E9'_rune, '\u03A9'_rune, '\U0001F642'_rune]

    var dest: [8] rune
    let count = Unicode.fromUtf8(dest, text)
    Swag.require(count == 4)
    for i in count
    {
        Swag.require(dest[i] == expected[i])
    }

    let result = Unicode.fromUtf8(text)
    Swag.require(assertRuneArray(result, expected))

    let invalid:         [1] u8   = [0x80]
    let invalidResult = Unicode.fromUtf8(invalid)
    let expectedInvalid: [1] rune = [Utf8.RuneError]
    Swag.require(assertRuneArray(invalidResult, expectedInvalid))
}

#test
{
    var values: [5] rune = ['a'_rune, '\u00E9'_rune, '\u03C9'_rune, '7'_rune, '\u2603'_rune]

    Unicode.makeUpper(values)
    Swag.require(values[0] == 'A'_rune)
    Swag.require(values[1] == '\u00C9'_rune)
    Swag.require(values[2] == '\u03A9'_rune)
    Swag.require(values[3] == '7'_rune)
    Swag.require(values[4] == '\u2603'_rune)

    Unicode.makeLower(values)
    Swag.require(values[0] == 'a'_rune)
    Swag.require(values[1] == '\u00E9'_rune)
    Swag.require(values[2] == '\u03C9'_rune)
    Swag.require(values[3] == '7'_rune)
    Swag.require(values[4] == '\u2603'_rune)
}

#test
{
    let lower: [3] rune = ['a'_rune, '\u00E9'_rune, '\u03C9'_rune]
    let upper: [3] rune = ['A'_rune, '\u00C9'_rune, '\u03A9'_rune]
    let tail:  [4] rune = ['A'_rune, '\u00C9'_rune, '\u03A9'_rune, 'Z'_rune]

    Swag.require(Unicode.compare(lower, lower) == 0)
    Swag.require(Unicode.compare(lower, upper) == 1)
    Swag.require(Unicode.compare(upper, lower) == -1)
    Swag.require(Unicode.compare(lower, upper, ignoreCase: true) == 0)
    Swag.require(Unicode.compare(upper, tail, len: 3) == 0)
    Swag.require(Unicode.compare(upper, tail) == -1)

    let higherValues: [2] rune = [2, 3]
    let lowerValues:  [2] rune = [1, 3]
    Swag.require(Unicode.compare(higherValues, lowerValues, len: 5) == 1)
    Swag.require(Unicode.compare(lowerValues, higherValues, len: 5) == -1)

    let shorter: [2] rune = [1, 3]
    let longer:  [3] rune = [1, 3, 4]
    Swag.require(Unicode.compare(shorter, longer, len: 5) == -1)
    Swag.require(Unicode.compare(longer, shorter, len: 5) == 1)
}

// Alternating case ranges select the right member of both their first and last pair.
#test
{
    for upper in [0x0100_rune, 0x012E_rune]
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
