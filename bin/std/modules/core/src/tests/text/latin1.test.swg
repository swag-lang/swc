#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.assert(Latin1.isAscii(0x00))
    Swag.assert(Latin1.isAscii(0x7F))
    Swag.assert(!Latin1.isAscii(0x80))

    Swag.assert(Latin1.isDigit('5'u8))
    Swag.assert(Latin1.isNumber('5'u8))
    Swag.assert(!Latin1.isDigit('a'u8))
    Swag.assert(Latin1.isBinDigit('0'u8))
    Swag.assert(Latin1.isBinDigit('1'u8))
    Swag.assert(!Latin1.isBinDigit('2'u8))
    Swag.assert(Latin1.isHexDigit('0'u8))
    Swag.assert(Latin1.isHexDigit('9'u8))
    Swag.assert(Latin1.isHexDigit('a'u8))
    Swag.assert(Latin1.isHexDigit('F'u8))
    Swag.assert(!Latin1.isHexDigit('g'u8))

    Swag.assert(Latin1.isUpper('A'u8))
    Swag.assert(!Latin1.isUpper('a'u8))
    Swag.assert(Latin1.isLower('a'u8))
    Swag.assert(!Latin1.isLower('A'u8))
    Swag.assert(Latin1.isLetter('Z'u8))
    Swag.assert(Latin1.isLetter('z'u8))
    Swag.assert(!Latin1.isLetter('5'u8))
    Swag.assert(Latin1.isLetterOrDigit('Z'u8))
    Swag.assert(Latin1.isLetterOrDigit('5'u8))
    Swag.assert(!Latin1.isLetterOrDigit('_'u8))
    Swag.assert(Latin1.isWord('Z'u8))
    Swag.assert(Latin1.isWord('5'u8))
    Swag.assert(Latin1.isWord('_'u8))
    Swag.assert(!Latin1.isWord('-'u8))

    Swag.assert(Latin1.isSpace(' 'u8))
    Swag.assert(Latin1.isSpace(0x09))
    Swag.assert(!Latin1.isSpace('A'u8))
    Swag.assert(Latin1.isControl(0x1F))
    Swag.assert(!Latin1.isControl('A'u8))
    Swag.assert(Latin1.isPunctuation('.'u8))
    Swag.assert(!Latin1.isPunctuation('A'u8))
    Swag.assert(Latin1.isSymbol('$'u8))
    Swag.assert(!Latin1.isSymbol('A'u8))
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

// Trimming recognizes every Latin-1 spacing byte across packed blocks and
// preserves the exact first and last non-space byte.
#test
{
    const Spaces: [8] u8 = [9, 10, 11, 12, 13, 32, 0x85, 0xA0]
    var buffer: [96] u8
    for leading in 33
    {
        for trailing in 33
        {
            for &value in buffer do
                value[] = 'x'
            for index in leading do
                buffer[index] = Spaces[index % Spaces.count]
            for index in trailing do
                buffer[buffer.count - index - 1] = Spaces[index % Spaces.count]

            let text    = Swag.makeString(buffer.buffer, buffer.count)
            let trimmed = Latin1.trim(text)
            Swag.assert(trimmed.count == buffer.count - leading - trailing)
            for value in trimmed do
                Swag.assert(value == 'x')
        }
    }

    for index in buffer.count do
        buffer[index] = Spaces[index % Spaces.count]
    Swag.assert(Latin1.trim(Swag.makeString(buffer.buffer, buffer.count)) == "")
}

// Packed casing stays byte-for-byte identical to the scalar tables for the
// complete Latin-1 domain, including the multiplication and division signs.
#test
{
    var original: [256] u8
    var upper:    [256] u8
    var lower:    [256] u8
    for i in 256
    {
        original[i] = cast(u8) i
        upper[i]    = cast(u8) i
        lower[i]    = cast(u8) i
        Latin1.makeUpper(upper[i until i + 1])
        Latin1.makeLower(lower[i until i + 1])
    }

    var transformed = original
    Latin1.makeUpper(transformed)
    Swag.assert(Slice.equals(transformed, upper))
    transformed = original
    Latin1.makeLower(transformed)
    Swag.assert(Slice.equals(transformed, lower))

    Swag.assert(Latin1.compare(upper, lower, ignoreCase: true) == 0)
    for position in 64
    {
        var other = lower
        other[position] = position ? 0 : 1
        if Latin1.toLower(upper[position]) != Latin1.toLower(other[position]) do
            Swag.assert(Latin1.compare(upper, other, ignoreCase: true) != 0)
    }
}
