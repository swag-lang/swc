#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertRuneArray(values: Array'rune, expected: const [..] rune)->bool
{
    if values.count != expected.count do
        return false

    for i in values.count
    {
        if values[i] != expected[i] do
            return false
    }

    return true
}

#test
{
    Swag.assert(Unicode.isAscii('A'rune))
    Swag.assert(!Unicode.isAscii('\u00E9'rune))
    Swag.assert(Unicode.isLatin1('\u00E9'rune))
    Swag.assert(!Unicode.isLatin1('\u20AC'rune))

    Swag.assert(Unicode.isDigit('5'rune))
    Swag.assert(Unicode.isNumber('5'rune))
    Swag.assert(Unicode.isNumber('\u2167'rune))
    Swag.assert(!Unicode.isDigit('A'rune))

    Swag.assert(Unicode.isLetter('A'rune))
    Swag.assert(Unicode.isLetter('\u03A9'rune))
    Swag.assert(Unicode.isLetter('\u4E2D'rune))
    Swag.assert(!Unicode.isLetter('7'rune))

    Swag.assert(Unicode.isLetterOrDigit('\u03A9'rune))
    Swag.assert(Unicode.isLetterOrDigit('7'rune))
    Swag.assert(!Unicode.isLetterOrDigit('_'rune))
    Swag.assert(Unicode.isWord('_'rune))
    Swag.assert(Unicode.isWord('\u03A9'rune))
}

#test
{
    Swag.assert(Unicode.isSpace(' 'rune))
    Swag.assert(Unicode.isSpace('\u2003'rune))
    Swag.assert(!Unicode.isSpace('A'rune))

    Swag.assert(Unicode.isControl(0x1F'rune))
    Swag.assert(!Unicode.isControl('A'rune))

    Swag.assert(Unicode.isSymbol('$'rune))
    Swag.assert(Unicode.isSymbol('\u2603'rune))
    Swag.assert(Unicode.isSymbolMath('+'rune))
    Swag.assert(Unicode.isSymbolMath('\u2211'rune))
    Swag.assert(!Unicode.isSymbolMath('A'rune))
}

#test
{
    Swag.assert(Unicode.isUpper('A'rune))
    Swag.assert(Unicode.isUpper('\u00C9'rune))
    Swag.assert(Unicode.isUpper('\u03A9'rune))
    Swag.assert(!Unicode.isUpper('\u03C9'rune))

    Swag.assert(Unicode.isLower('a'rune))
    Swag.assert(Unicode.isLower('\u00E9'rune))
    Swag.assert(Unicode.isLower('\u03C9'rune))
    Swag.assert(!Unicode.isLower('\u03A9'rune))

    Swag.assert(Unicode.isTitle('\u01C5'rune))
    Swag.assert(!Unicode.isTitle('\u01C6'rune))
}

#test
{
    Swag.assert(Unicode.toLower('A'rune) == 'a'rune)
    Swag.assert(Unicode.toUpper('a'rune) == 'A'rune)
    Swag.assert(Unicode.toTitle('a'rune) == 'A'rune)

    Swag.assert(Unicode.toLower('\u00C9'rune) == '\u00E9'rune)
    Swag.assert(Unicode.toUpper('\u00E9'rune) == '\u00C9'rune)

    Swag.assert(Unicode.toLower('\u03A9'rune) == '\u03C9'rune)
    Swag.assert(Unicode.toUpper('\u03C9'rune) == '\u03A9'rune)

    Swag.assert(Unicode.toTitle('\u01C6'rune) == '\u01C5'rune)
    Swag.assert(Unicode.toLower('\u0130'rune) == 'i'rune)
    Swag.assert(Unicode.toUpper('\u00DF'rune) == '\u00DF'rune)
}

#test
{
    let text               = "A\u00E9\u03A9\U0001F642"
    let expected: [4] rune = ['A'rune, '\u00E9'rune, '\u03A9'rune, '\U0001F642'rune]

    var dest: [8] rune
    let count = Unicode.fromUtf8(dest, text)
    Swag.assert(count == 4)
    for i in count do
        Swag.assert(dest[i] == expected[i])

    let result = Unicode.fromUtf8(text)
    Swag.assert(assertRuneArray(result, expected))

    let invalid:         [1] u8   = [0x80]
    let invalidResult             = Unicode.fromUtf8(invalid)
    let expectedInvalid: [1] rune = [Utf8.RuneError]
    Swag.assert(assertRuneArray(invalidResult, expectedInvalid))
}

#test
{
    var values: [5] rune = ['a'rune, '\u00E9'rune, '\u03C9'rune, '7'rune, '\u2603'rune]

    Unicode.makeUpper(values)
    Swag.assert(values[0] == 'A'rune)
    Swag.assert(values[1] == '\u00C9'rune)
    Swag.assert(values[2] == '\u03A9'rune)
    Swag.assert(values[3] == '7'rune)
    Swag.assert(values[4] == '\u2603'rune)

    Unicode.makeLower(values)
    Swag.assert(values[0] == 'a'rune)
    Swag.assert(values[1] == '\u00E9'rune)
    Swag.assert(values[2] == '\u03C9'rune)
    Swag.assert(values[3] == '7'rune)
    Swag.assert(values[4] == '\u2603'rune)
}

#test
{
    let lower: [3] rune = ['a'rune, '\u00E9'rune, '\u03C9'rune]
    let upper: [3] rune = ['A'rune, '\u00C9'rune, '\u03A9'rune]
    let tail:  [4] rune = ['A'rune, '\u00C9'rune, '\u03A9'rune, 'Z'rune]

    Swag.assert(Unicode.compare(lower, lower) == 0)
    Swag.assert(Unicode.compare(lower, upper) == 1)
    Swag.assert(Unicode.compare(upper, lower) == -1)
    Swag.assert(Unicode.compare(lower, upper, ignoreCase: true) == 0)
    Swag.assert(Unicode.compare(upper, tail, len: 3) == 0)
    Swag.assert(Unicode.compare(upper, tail) == -1)
}
