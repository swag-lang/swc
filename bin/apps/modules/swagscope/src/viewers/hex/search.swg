#global internal
#global namespace Viewers.Hex

using Core

// State of a hexadecimal search query while it is being edited.
enum SearchParseState
{
    Incomplete     // A prefix or half-byte can still become a valid query.
    Valid          // The query names at least one source byte.
    Invalid        // The query contains a token that no supported search form accepts.
}

// Explanation attached to an invalid hexadecimal search query.
enum SearchError
{
    None        // The query is valid or merely incomplete.
    Pattern     // A hexadecimal pattern contains something other than byte pairs and wildcards.
    Value       // A scalar does not parse or fit the active reading.
}

// One byte pattern and the bits of each byte that have to match.
//
// A zero mask is `??`, a half mask is one wildcard nibble, and `0xFF` is an exact byte. Keeping
// those three forms in the same representation makes matching independent from how the query was
// written and lets a pattern cross any streamed file-window boundary.
struct SearchPattern
{
    values: Array'u8
    masks:  Array'u8
}

impl SearchPattern
{
    mtd length()->u64 => .values.count

    mtd matches(source: string, offset: u64)->bool
    {
        if offset + .values.count > source.count do
            return false

        for index in .values.count where source[offset + index] & .masks[index] != .values[index] do
            return false
        return true
    }

    // Appends every occurrence, including overlaps, inside one streamed source window.
    mtd collectMatches(source: string, baseOffset: u64, result: *Array'Viewer.SearchMatch)
    {
        if .values.isEmpty() or source.count < .values.count do
            return

        let last = source.count - .values.count
        for offset in last + 1 where .matches(source, offset) do
            result.add({offset: baseOffset + offset, length: .values.count})
    }
}

// Parsed query with enough state for an edit box to distinguish an unfinished prefix from an
// invalid pattern.
struct SearchParse
{
    pattern: SearchPattern
    state:   SearchParseState
    error:   SearchError
}

private func appendSearchByte(pattern: *SearchPattern, high, low: u8)
{
    let highWildcard = high == '?'u8
    let lowWildcard  = low == '?'u8
    let highValue    = highWildcard ? 0'u8 : hexDigitValue(high)
    let lowValue     = lowWildcard ? 0'u8 : hexDigitValue(low)
    pattern.values.add((highValue << 4) | lowValue)
    pattern.masks.add((highWildcard ? 0'u8 : 0xF0'u8) | (lowWildcard ? 0'u8 : 0x0F'u8))
}

// Parses hexadecimal bytes such as `4D 5A ?? 00`, where `?` matches any nibble. Separators may only
// fall between bytes; an unpaired digit or an empty pattern is incomplete rather than invalid.
private func parseBytePattern(source: string)->SearchParse
{
    var result:  retval
    var high = 0'u8
    var hasHigh: bool

    for index in source.count
    {
        let value = source[index]
        if value == ' 'u8 or value == '\t'u8 or value == '_'u8
        {
            if hasHigh
            {
                result.state = .Invalid
                result.error = .Pattern
                return result
            }

            continue
        }

        if value != '?'u8 and hexDigitValue(value) == 16
        {
            result.state = .Invalid
            result.error = .Pattern
            return result
        }

        if not hasHigh
        {
            high    = value
            hasHigh = true
            continue
        }

        appendSearchByte(&result.pattern, high, value)
        hasHigh = false
    }

    if hasHigh or not result.pattern.length()
    {
        result.state = .Incomplete
        return result
    }

    result.state = .Valid
    return result
}

// Turns `source` into an exact pattern of its UTF-8 bytes; an empty text is incomplete.
private func parseTextPattern(source: string)->SearchParse
{
    var result: retval
    if not source.count
    {
        result.state = .Incomplete
        return result
    }

    result.pattern.values.reserve(source.count)
    result.pattern.masks.reserve(source.count)
    for index in source.count
    {
        result.pattern.values.add(source[index])
        result.pattern.masks.add(0xFF)
    }

    result.state = .Valid
    return result
}

private func appendScalarPattern(pattern: *SearchPattern, raw, size: u64, bigEndian: bool)
{
    for index in size
    {
        let byteIndex = bigEndian ? size - 1 - index : index
        pattern.values.add(cast(u8, ((raw >> (byteIndex * 8)) & 0xFF)))
        pattern.masks.add(0xFF)
    }
}

// Parses one number in the current `grouping` into the bytes of that value in the chosen byte
// order. A value outside the grouping's range is invalid; a lone sign or `0x` prefix is incomplete.
private func parseValuePattern(source: string, grouping: Grouping, bigEndian: bool)->SearchParse
{
    var result: retval
    if not source.count or source == "+" or source == "-" or source == "0x" or source == "0X"
    {
        result.state = .Incomplete
        return result
    }

    let size = groupingSize(grouping)
    var raw  = 0'u64
    var valid: bool
    switch grouping
    {
    case .Signed8, .Signed16, .Signed32, .Signed64:
        let parsed = catch StrConv.parseS64(source) as parseError
        if parseError == null and parsed.eat == source.count and not parsed.ovf
        {
            let bits = size * 8
            let min  = bits == 64 ? Swag.S64.Min : -(1's64 << (bits - 1))
            let max  = bits == 64 ? Swag.S64.Max : (1's64 << (bits - 1)) - 1
            valid = parsed.value >= min and parsed.value <= max
            raw   = cast #bit (u64, parsed.value)
        }

    case .Unsigned8, .Unsigned16, .Unsigned32, .Unsigned64:
        let parsed = catch StrConv.parseU64(source) as parseError
        if parseError == null and parsed.eat == source.count and not parsed.ovf
        {
            let max = size == 8 ? Swag.U64.Max : (1'u64 << (size * 8)) - 1
            valid = parsed.value <= max
            raw   = parsed.value
        }

    case .Float32:
        let parsed = catch StrConv.parseF64(source) as parseError
        if parseError == null and parsed.eat == source.count and not parsed.ovf
        {
            valid = true
            raw   = cast #bit (u32, cast(f32, parsed.value))
        }

    case .Float64:
        let parsed = catch StrConv.parseF64(source) as parseError
        if parseError == null and parsed.eat == source.count and not parsed.ovf
        {
            valid = true
            raw   = cast #bit (u64, parsed.value)
        }

    case .Bytes, .Hex16, .Hex32, .Hex64:
        let digits = Utf8.startsWith(source, "0x", .Latin1NoCase) ? cast(string, source[2 to]) : source
        let parsed = catch StrConv.parseX64(digits) as parseError
        if parseError == null and parsed.eat == digits.count and not parsed.ovf
        {
            let max = size == 8 ? Swag.U64.Max : (1'u64 << (size * 8)) - 1
            valid = parsed.value <= max
            raw   = parsed.value
        }
    }

    if not valid
    {
        result.state = .Invalid
        result.error = .Value
        return result
    }

    appendScalarPattern(&result.pattern, raw, size, bigEndian)
    result.state = .Valid
    return result
}

// Parses `query` in one of the three search forms of the hexadecimal viewer.
//
// - `4D 5A ?? ?0` or `hex: 4D 5A` for byte and nibble patterns;
// - `text: MZ` or `"MZ"` for exact UTF-8 bytes;
// - `value: 42` for a scalar spelled as `grouping` reads it, in the byte order `bigEndian` selects.
func parseSearch(query: string, grouping: Grouping, bigEndian: bool)->SearchParse
{
    let trimmed = Latin1.trim(query)
    if not trimmed.count
    {
        var result: retval
        result.state = .Incomplete
        return result
    }

    if Utf8.startsWith(trimmed, "text:", .Latin1NoCase) do
        return parseTextPattern(Latin1.trim(cast(string, trimmed[5 to])))
    if Utf8.startsWith(trimmed, "value:", .Latin1NoCase) do
        return parseValuePattern(Latin1.trim(cast(string, trimmed[6 to])), grouping, bigEndian)
    if Utf8.startsWith(trimmed, "hex:", .Latin1NoCase) do
        return parseBytePattern(Latin1.trim(cast(string, trimmed[4 to])))

    if trimmed[0] == '"'u8
    {
        if trimmed.count == 1 or trimmed[trimmed.count - 1] != '"'u8
        {
            var result: retval
            result.state = .Incomplete
            return result
        }

        return parseTextPattern(cast(string, trimmed[1 until trimmed.count - 1]))
    }

    return parseBytePattern(trimmed)
}
