#global public
#global namespace Tokenize

// Returns `str` without its surrounding double quotes, or `str` itself when it is not quoted.
func eatQuotes(str: string)->string
{
    let countof = str.count
    if countof < 2 do
        return str
    if str[0] == '"' and str[countof - 1] == '"' do
        return str[1 until countof - 1]
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
    let countof = str.count
    if not countof do
        return str

    var cpt = 0'u64
    while cpt < countof and Latin1.isSpace(str[cpt]) do
        cpt += 1
    return str[cpt to]
}

// Splits `src` into lines, each ended by a line feed, a carriage return, or both.
//
// The lines are views that borrow the bytes of `src`, which must outlive them.
func splitLines(src: string)->Array'(string)
{
    var result: retval
    let countof = src.count
    if not countof do
        return result

    var dataof = src.buffer
    var cpt    = 0
    var end    = dataof
    while cpt < countof
    {
        while cpt < countof and end[] != '\r' and end[] != '\n'
        {
            end += 1
            cpt += 1
        }

        result.add(Swag.makeString(dataof, cast(u64) (end - dataof)))
        if cpt < countof - 1 and end[] == '\r' and end[1] == '\n' do
            end, cpt += 1
        end, cpt += 1
        dataof   = end
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
    let countof = src.count
    var result: retval
    if not countof do
        return result

    var startbyteIdx: u64
    var splitCount:   u32

    while startbyteIdx != countof and (not maxSplit or splitCount != maxSplit)
    {
        var endbyteIdx = startbyteIdx
        while endbyteIdx != countof and src[endbyteIdx] != separator do
            endbyteIdx += 1

        addSplitPart(&result, src[startbyteIdx until endbyteIdx], removeEmpty)
        if endbyteIdx == countof do
            return result

        startbyteIdx = endbyteIdx + 1
        splitCount   += 1
    }

    addSplitPart(&result, src[startbyteIdx until countof], removeEmpty)
    return result
}

// Splits `src` at each occurrence of `separator`, like the byte overload.
//
// An empty `separator` leaves `src` whole.
func split(src: string, separator: string, maxSplit: u32 = 0, removeEmpty = true)->Array'(string)
{
    let countof = src.count
    let separatorCountof = separator.count

    var result: retval
    if not countof do
        return result
    if not separatorCountof
    {
        addSplitPart(&result, src, removeEmpty)
        return result
    }

    var startbyteIdx: u64
    var splitCount:   u32

    while startbyteIdx != countof and (not maxSplit or splitCount != maxSplit)
    {
        var endbyteIdx = startbyteIdx
        while endbyteIdx != countof
        {
            if Utf8.startsWith(src[endbyteIdx until countof], separator) do
                break
            endbyteIdx += 1
        }

        addSplitPart(&result, src[startbyteIdx until endbyteIdx], removeEmpty)
        if endbyteIdx == countof do
            return result

        startbyteIdx = endbyteIdx + separatorCountof
        splitCount   += 1
    }

    addSplitPart(&result, src[startbyteIdx until countof], removeEmpty)
    return result
}

// Splits `src` at each rune `separator`, like the byte overload.
func split(src: string, separator: rune, maxSplit: u32 = 0, removeEmpty = true)->Array'(string) => splitAny(src, [separator], maxSplit, removeEmpty)

// Splits `src` at each rune that is one of `separators`, like [[Core.Tokenize.split]].
func splitAny(src: string, separators: const [..] rune, maxSplit: u32 = 0, removeEmpty = true)->Array'(string)
{
    let countof = src.count

    var result: retval
    if not countof do
        return result

    var c: rune
    var startbyteIdx, eat: u64
    var splitCount:        u32

    while startbyteIdx != countof and (not maxSplit or splitCount != maxSplit)
    {
        var endbyteIdx = startbyteIdx
        while endbyteIdx != countof
        {
            {c, eat} = Utf8.decodeRune(src[endbyteIdx until countof])
            if Slice.contains(separators, c) do
                break
            endbyteIdx += eat
        }

        addSplitPart(&result, src[startbyteIdx until endbyteIdx], removeEmpty)
        if endbyteIdx == countof do
            return result

        startbyteIdx = endbyteIdx + eat
        splitCount   += 1
    }

    addSplitPart(&result, src[startbyteIdx until countof], removeEmpty)
    return result
}

// Returns the part of `str` before its first Latin-1 white space.
func prefixToWhitespace(str: string)->string
{
    let countof = str.count
    var cpt     = 0'u64
    while cpt < countof and not Latin1.isSpace(str[cpt]) do
        cpt += 1
    return str[until cpt]
}

// Returns the leading Latin-1 letters and digits of `str`.
func alphanumericPrefix(str: string)->string
{
    let countof = str.count
    var cpt     = 0'u64
    while cpt < countof and (Latin1.isDigit(str[cpt]) or Latin1.isLetter(str[cpt])) do
        cpt += 1
    return str[until cpt]
}

// Returns bytes from `startByteIndex` through the next `delimiter`.
//
// The delimiter is omitted when `includeDelimiter` is false. When no delimiter
// remains, the result extends to the end of `source`.
func sliceToDelimiter(source: string, delimiter: u8, startByteIndex = 0'u64, includeDelimiter = true)->string
{
    var dataof = source.buffer
    var length = source.count
    if startByteIndex >= length do
        return Swag.makeString(dataof, 0)

    length -= startByteIndex
    dataof += startByteIndex
    var scan = dataof
    while length
    {
        if scan[] == delimiter
        {
            if includeDelimiter do
                scan += 1
            return Swag.makeString(dataof, cast(u64) (scan - dataof))
        }

        scan   += 1
        length -= 1
    }

    return Swag.makeString(dataof, cast(u64) (scan - dataof))
}
