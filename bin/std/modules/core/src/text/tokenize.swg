#global public
#global namespace Tokenize

// Returns `str` without its surrounding double quotes, or `str` itself when it is not quoted.
func eatQuotes(str: string)->string
{
    let byteCount = str.count
    if byteCount < 2 do
        return str
    if str[0] == '"' and str[byteCount - 1] == '"' do
        return str[1 until byteCount - 1]
    return str
}

// Returns `str` without its first `count` bytes, or an empty view when it is not longer.
func eatCount(str: string, count: u64)->string
{
    if str == null do
        return str
    return str[Math.min(count, str.count) to]
}

// Returns `str` without its leading Latin-1 white space.
func eatSpaces(str: string)->string
{
    let byteCount = str.count
    if not byteCount do
        return str

    var offset = 0'u64
    while offset < byteCount and Latin1.isSpace(str[offset]) do
        offset += 1
    return str[offset to]
}

// Splits `src` into lines, each ended by a line feed, a carriage return, or both.
//
// The lines are views that borrow the bytes of `src`, which must outlive them.
func splitLines(src: string)->Array'(string)
{
    var result: retval
    let byteCount = src.count
    if not byteCount do
        return result

    var lineStart     = src.buffer
    var consumedBytes = 0
    var lineEnd       = lineStart
    while consumedBytes < byteCount
    {
        while consumedBytes < byteCount and lineEnd[] != '\r' and lineEnd[] != '\n'
        {
            lineEnd       += 1
            consumedBytes += 1
        }

        result.add(Swag.makeString(lineStart, cast(u64, (lineEnd - lineStart))))
        if consumedBytes < byteCount - 1 and lineEnd[] == '\r' and lineEnd[1] == '\n' do
            lineEnd, consumedBytes += 1
        lineEnd, consumedBytes += 1
        lineStart = lineEnd
    }

    return result
}

private func addSplitPart(result: *Array'(string), value: string, removeEmpty: bool)
{
    if removeEmpty and not value.count do
        return
    result.add(value)
}

// Splits `src` at each byte `separator`.
//
// When `maxSplit` is not 0, at most `maxSplit` cuts are made and the last part holds the rest.
// Empty parts are dropped when `removeEmpty` is true. The parts are views that borrow the bytes
// of `src`, which must outlive them.
func split(src: string, separator: u8, maxSplit: u32 = 0, removeEmpty = true)->Array'(string)
{
    let byteCount = src.count
    var result: retval
    if not byteCount do
        return result

    var startByte:  u64
    var splitCount: u32

    while startByte != byteCount and (not maxSplit or splitCount != maxSplit)
    {
        var endByte = startByte
        while endByte != byteCount and src[endByte] != separator do
            endByte += 1

        addSplitPart(&result, src[startByte until endByte], removeEmpty)
        if endByte == byteCount do
            return result

        startByte  = endByte + 1
        splitCount += 1
    }

    addSplitPart(&result, src[startByte until byteCount], removeEmpty)
    return result
}

// Splits `src` at each occurrence of `separator`, like the byte overload.
//
// An empty `separator` leaves `src` whole.
func split(src: string, separator: string, maxSplit: u32 = 0, removeEmpty = true)->Array'(string)
{
    let byteCount      = src.count
    let separatorBytes = separator.count

    var result: retval
    if not byteCount do
        return result
    if not separatorBytes
    {
        addSplitPart(&result, src, removeEmpty)
        return result
    }

    var startByte:  u64
    var splitCount: u32

    while startByte != byteCount and (not maxSplit or splitCount != maxSplit)
    {
        var endByte = startByte
        while endByte != byteCount
        {
            if Utf8.startsWith(src[endByte until byteCount], separator) do
                break
            endByte += 1
        }

        addSplitPart(&result, src[startByte until endByte], removeEmpty)
        if endByte == byteCount do
            return result

        startByte  = endByte + separatorBytes
        splitCount += 1
    }

    addSplitPart(&result, src[startByte until byteCount], removeEmpty)
    return result
}

// Splits `src` at each rune `separator`, like the byte overload.
func split(src: string, separator: rune, maxSplit: u32 = 0, removeEmpty = true)->Array'(string)
{
    return splitAny(src, [separator], maxSplit, removeEmpty)
}

// Splits `src` at each rune that is one of `separators`, like [[Core.Tokenize.split]].
func splitAny(src: string, separators: const [..] rune, maxSplit: u32 = 0, removeEmpty = true)->Array'(string)
{
    let byteCount = src.count

    var result: retval
    if not byteCount do
        return result

    var character:  rune
    var startByte:  u64
    var runeBytes:  u64
    var splitCount: u32

    while startByte != byteCount and (not maxSplit or splitCount != maxSplit)
    {
        var endByte = startByte
        while endByte != byteCount
        {
            {character, runeBytes} = Utf8.decodeRune(src[endByte until byteCount])
            if Slice.contains(separators, character) do
                break
            endByte += runeBytes
        }

        addSplitPart(&result, src[startByte until endByte], removeEmpty)
        if endByte == byteCount do
            return result

        startByte  = endByte + runeBytes
        splitCount += 1
    }

    addSplitPart(&result, src[startByte until byteCount], removeEmpty)
    return result
}

// Returns the part of `str` before its first Latin-1 white space.
func prefixToWhitespace(str: string)->string
{
    let byteCount = str.count
    var offset    = 0'u64
    while offset < byteCount and not Latin1.isSpace(str[offset]) do
        offset += 1
    return str[until offset]
}

// Returns the leading Latin-1 letters and digits of `str`.
func alphanumericPrefix(str: string)->string
{
    let byteCount = str.count
    var offset    = 0'u64
    while offset < byteCount and (Latin1.isDigit(str[offset]) or Latin1.isLetter(str[offset])) do
        offset += 1
    return str[until offset]
}

// Returns bytes from `startByteIndex` through the next `delimiter`.
//
// The delimiter is omitted when `includeDelimiter` is false. When no delimiter
// remains, the result extends to the end of `source`.
func sliceToDelimiter(source: string, delimiter: u8, startByteIndex = 0'u64, includeDelimiter = true)->string
{
    var start  = source.buffer
    var length = source.count
    if startByteIndex >= length do
        return Swag.makeString(start, 0)

    length -= startByteIndex
    start  += startByteIndex
    var scan = start
    while length
    {
        if scan[] == delimiter
        {
            if includeDelimiter do
                scan += 1
            return Swag.makeString(start, cast(u64, (scan - start)))
        }

        scan   += 1
        length -= 1
    }

    return Swag.makeString(start, cast(u64, (scan - start)))
}
