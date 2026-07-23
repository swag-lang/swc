#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertRuneArray(values: const &Array'rune, expected: const [..] rune)->bool
{
    if values.count != @countof(expected) do
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
    @assert(Unicode.isAscii('A''rune))
    @assert(!Unicode.isAscii('\u00E9''rune))
    @assert(Unicode.isLatin1('\u00E9''rune))
    @assert(!Unicode.isLatin1('\u20AC''rune))

    @assert(Unicode.isDigit('5''rune))
    @assert(Unicode.isNumber('5''rune))
    @assert(Unicode.isNumber('\u2167''rune))
    @assert(!Unicode.isDigit('A''rune))

    @assert(Unicode.isLetter('A''rune))
    @assert(Unicode.isLetter('\u03A9''rune))
    @assert(Unicode.isLetter('\u4E2D''rune))
    @assert(!Unicode.isLetter('7''rune))

    @assert(Unicode.isLetterOrDigit('\u03A9''rune))
    @assert(Unicode.isLetterOrDigit('7''rune))
    @assert(!Unicode.isLetterOrDigit('_''rune))
    @assert(Unicode.isWord('_''rune))
    @assert(Unicode.isWord('\u03A9''rune))
}

#test
{
    @assert(Unicode.isSpace(' ''rune))
    @assert(Unicode.isSpace('\u2003''rune))
    @assert(!Unicode.isSpace('A''rune))

    @assert(Unicode.isControl(0x1F'rune))
    @assert(!Unicode.isControl('A''rune))

    @assert(Unicode.isSymbol('$''rune))
    @assert(Unicode.isSymbol('\u2603''rune))
    @assert(Unicode.isSymbolMath('+''rune))
    @assert(Unicode.isSymbolMath('\u2211''rune))
    @assert(!Unicode.isSymbolMath('A''rune))
}

#test
{
    @assert(Unicode.isUpper('A''rune))
    @assert(Unicode.isUpper('\u00C9''rune))
    @assert(Unicode.isUpper('\u03A9''rune))
    @assert(!Unicode.isUpper('\u03C9''rune))

    @assert(Unicode.isLower('a''rune))
    @assert(Unicode.isLower('\u00E9''rune))
    @assert(Unicode.isLower('\u03C9''rune))
    @assert(!Unicode.isLower('\u03A9''rune))

    @assert(Unicode.isTitle('\u01C5''rune))
    @assert(!Unicode.isTitle('\u01C6''rune))
}

#test
{
    @assert(Unicode.toLower('A''rune) == 'a''rune)
    @assert(Unicode.toUpper('a''rune) == 'A''rune)
    @assert(Unicode.toTitle('a''rune) == 'A''rune)

    @assert(Unicode.toLower('\u00C9''rune) == '\u00E9''rune)
    @assert(Unicode.toUpper('\u00E9''rune) == '\u00C9''rune)

    @assert(Unicode.toLower('\u03A9''rune) == '\u03C9''rune)
    @assert(Unicode.toUpper('\u03C9''rune) == '\u03A9''rune)

    @assert(Unicode.toTitle('\u01C6''rune) == '\u01C5''rune)
    @assert(Unicode.toLower('\u0130''rune) == 'i''rune)
    @assert(Unicode.toUpper('\u00DF''rune) == '\u00DF''rune)
}

#test
{
    let text = "A\u00E9\u03A9\U0001F642"
    let expected: [4] rune = ['A''rune, '\u00E9''rune, '\u03A9''rune, '\U0001F642''rune]

    var dest: [8] rune
    let count = Unicode.fromUtf8(dest, text)
    @assert(count == 4)
    for i in count do
        @assert(dest[i] == expected[i])

    let result = Unicode.fromUtf8(text)
    @assert(assertRuneArray(result, expected))

    let invalid: [1] u8 = [0x80]
    let invalidResult = Unicode.fromUtf8(invalid)
    let expectedInvalid: [1] rune = [Utf8.RuneError]
    @assert(assertRuneArray(invalidResult, expectedInvalid))
}

#test
{
    var values: [5] rune = ['a''rune, '\u00E9''rune, '\u03C9''rune, '7''rune, '\u2603''rune]

    Unicode.makeUpper(values)
    @assert(values[0] == 'A''rune)
    @assert(values[1] == '\u00C9''rune)
    @assert(values[2] == '\u03A9''rune)
    @assert(values[3] == '7''rune)
    @assert(values[4] == '\u2603''rune)

    Unicode.makeLower(values)
    @assert(values[0] == 'a''rune)
    @assert(values[1] == '\u00E9''rune)
    @assert(values[2] == '\u03C9''rune)
    @assert(values[3] == '7''rune)
    @assert(values[4] == '\u2603''rune)
}

#test
{
    let lower: [3] rune = ['a''rune, '\u00E9''rune, '\u03C9''rune]
    let upper: [3] rune = ['A''rune, '\u00C9''rune, '\u03A9''rune]
    let tail:  [4] rune = ['A''rune, '\u00C9''rune, '\u03A9''rune, 'Z''rune]

    @assert(Unicode.compare(lower, lower) == 0)
    @assert(Unicode.compare(lower, upper) == 1)
    @assert(Unicode.compare(upper, lower) == -1)
    @assert(Unicode.compare(lower, upper, ignoreCase: true) == 0)
    @assert(Unicode.compare(upper, tail, len: 3) == 0)
    @assert(Unicode.compare(upper, tail) == -1)
}
