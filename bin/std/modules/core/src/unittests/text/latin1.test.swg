#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

#test
{
    @assert(Latin1.isAscii(0x00))
    @assert(Latin1.isAscii(0x7F))
    @assert(!Latin1.isAscii(0x80))

    @assert(Latin1.isDigit('5''u8))
    @assert(Latin1.isNumber('5''u8))
    @assert(!Latin1.isDigit('a''u8))
    @assert(Latin1.isBinDigit('0''u8))
    @assert(Latin1.isBinDigit('1''u8))
    @assert(!Latin1.isBinDigit('2''u8))
    @assert(Latin1.isHexDigit('0''u8))
    @assert(Latin1.isHexDigit('9''u8))
    @assert(Latin1.isHexDigit('a''u8))
    @assert(Latin1.isHexDigit('F''u8))
    @assert(!Latin1.isHexDigit('g''u8))

    @assert(Latin1.isUpper('A''u8))
    @assert(!Latin1.isUpper('a''u8))
    @assert(Latin1.isLower('a''u8))
    @assert(!Latin1.isLower('A''u8))
    @assert(Latin1.isLetter('Z''u8))
    @assert(Latin1.isLetter('z''u8))
    @assert(!Latin1.isLetter('5''u8))
    @assert(Latin1.isLetterOrDigit('Z''u8))
    @assert(Latin1.isLetterOrDigit('5''u8))
    @assert(!Latin1.isLetterOrDigit('_''u8))
    @assert(Latin1.isWord('Z''u8))
    @assert(Latin1.isWord('5''u8))
    @assert(Latin1.isWord('_''u8))
    @assert(!Latin1.isWord('-''u8))

    @assert(Latin1.isSpace(' ''u8))
    @assert(Latin1.isSpace(0x09))
    @assert(!Latin1.isSpace('A''u8))
    @assert(Latin1.isControl(0x1F))
    @assert(!Latin1.isControl('A''u8))
    @assert(Latin1.isPunctuation('.''u8))
    @assert(!Latin1.isPunctuation('A''u8))
    @assert(Latin1.isSymbol('$''u8))
    @assert(!Latin1.isSymbol('A''u8))
}

#test
{
    @assert(Latin1.toLower('A''u8) == 'a''u8)
    @assert(Latin1.toLower('a''u8) == 'a''u8)
    @assert(Latin1.toLower(0xC0) == 0xE0)
    @assert(Latin1.toUpper('a''u8) == 'A''u8)
    @assert(Latin1.toUpper('A''u8) == 'A''u8)
    @assert(Latin1.toUpper(0xE0) == 0xC0)

    var bytes: [6] u8 = ['a''u8, 'Z''u8, 0xC3, 0xA9, '0''u8, '_''u8]
    Latin1.makeUpper(bytes)
    @assert(bytes[0] == 'A''u8)
    @assert(bytes[1] == 'Z''u8)
    @assert(bytes[2] == 0xC3)
    @assert(bytes[3] == 0x89)
    @assert(bytes[4] == '0''u8)
    @assert(bytes[5] == '_''u8)

    Latin1.makeLower(bytes)
    @assert(bytes[0] == 'a''u8)
    @assert(bytes[1] == 'z''u8)
    @assert(bytes[2] == 0xC3)
    @assert(bytes[3] == 0xA9)
    @assert(bytes[4] == '0''u8)
    @assert(bytes[5] == '_''u8)
}

#test
{
    @assert(Latin1.compare("abc", "abc") == 0)
    @assert(Latin1.compare("abc", "abd") == -1)
    @assert(Latin1.compare("abd", "abc") == 1)
    @assert(Latin1.compare("abc", "abcd") == -1)
    @assert(Latin1.compare("abcd", "abc") == 1)

    @assert(Latin1.compare("AbC", "aBc", ignoreCase: true) == 0)
    @assert(Latin1.compare("abc", "ABd", ignoreCase: true) == -1)
    @assert(Latin1.compare("ABd", "abc", ignoreCase: true) == 1)
}

#test
{
    @assert(Latin1.compareNatural("file2", "file10") == -1)
    @assert(Latin1.compareNatural("file10", "file2") == 1)
    @assert(Latin1.compareNatural("file02", "file2") == -1)
    @assert(Latin1.compareNatural("file2", "file02") == 1)
    @assert(Latin1.compareNatural("file2", "file2") == 0)
    @assert(Latin1.compareNatural("  file2", "file2") == 0)
    @assert(Latin1.compareNatural("File2", "file2", ignoreCase: true) == 0)
    @assert(Latin1.compareNatural("File2", "file2") == -1)
}

#test
{
    @assert(Latin1.trim("  abc  ") == "abc")
    @assert(Latin1.trim("\t abc\n") == "abc")
    @assert(Latin1.trim("abc") == "abc")
    @assert(Latin1.trim("   ") == "")
    @assert(Latin1.trim("") == "")
}
