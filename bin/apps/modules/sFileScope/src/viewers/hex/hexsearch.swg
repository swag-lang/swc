#global internal

using Core

// State of a hexadecimal search query while it is being edited.
enum HexSearchParseState
{
    Incomplete     // A prefix or half-byte can still become a valid query.
    Valid          // The query names at least one source byte.
    Invalid        // The query contains a token that no supported search form accepts.
}

// Explanation attached to an invalid hexadecimal search query.
enum HexSearchError
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
struct HexSearchPattern
{
    values: Array'u8
    masks:  Array'u8
}

impl HexSearchPattern
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
    mtd collectMatches(source: string, baseOffset: u64, result: *Array'ViewerSearchMatch)
    {
        if !.values.count or source.count < .values.count do
            return

        let last = source.count - .values.count
        for offset in last + 1 where .matches(source, offset) do
            result.add({offset: baseOffset + offset, length: .values.count})
    }
}

// Parsed query with enough state for an edit box to distinguish an unfinished prefix from an
// invalid pattern.
struct HexSearchParse
{
    pattern: HexSearchPattern
    state:   HexSearchParseState
    error:   HexSearchError
}

private func hexSearchNibble(value: u8)->u8
{
    if value >= '0'u8 and value <= '9'u8 do
        return value - '0'u8
    if value >= 'a'u8 and value <= 'f'u8 do
        return value - 'a'u8 + 10
    if value >= 'A'u8 and value <= 'F'u8 do
        return value - 'A'u8 + 10
    return 16
}

private func appendHexSearchByte(pattern: *HexSearchPattern, high, low: u8)
{
    let highWildcard = high == '?'u8
    let lowWildcard  = low == '?'u8
    let highValue    = highWildcard ? 0'u8 : hexSearchNibble(high)
    let lowValue     = lowWildcard ? 0'u8 : hexSearchNibble(low)
    pattern.values.add((highValue << 4) | lowValue)
    pattern.masks.add((highWildcard ? 0'u8 : 0xF0'u8) | (lowWildcard ? 0'u8 : 0x0F'u8))
}

private func parseHexBytePattern(source: string)->HexSearchParse
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

        if value != '?'u8 and hexSearchNibble(value) == 16
        {
            result.state = .Invalid
            result.error = .Pattern
            return result
        }

        if !hasHigh
        {
            high    = value
            hasHigh = true
            continue
        }

        appendHexSearchByte(&result.pattern, high, value)
        hasHigh = false
    }

    if hasHigh or !result.pattern.length()
    {
        result.state = .Incomplete
        return result
    }

    result.state = .Valid
    return result
}

private func parseHexTextPattern(source: string)->HexSearchParse
{
    var result: retval
    if !source.count
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

private func appendHexScalarPattern(pattern: *HexSearchPattern, raw, size: u64, bigEndian: bool)
{
    for index in size
    {
        let byteIndex = bigEndian ? size - 1 - index : index
        pattern.values.add(cast(u8) ((raw >> (byteIndex * 8)) & 0xFF))
        pattern.masks.add(0xFF)
    }
}

private func parseHexValuePattern(source: string, grouping: HexGrouping, bigEndian: bool)->HexSearchParse
{
    var result: retval
    if !source.count or source == "+" or source == "-" or source == "0x" or source == "0X"
    {
        result.state = .Incomplete
        return result
    }

    let size = hexGroupingSize(grouping)
    var raw  = 0'u64
    var valid: bool
    switch grouping
    {
    case .Signed8, .Signed16, .Signed32, .Signed64:
        let parsed = catch StrConv.parseS64(source) as parseError
        if parseError == null and parsed.eat == source.count and !parsed.ovf
        {
            let bits = size * 8
            let min  = bits == 64 ? Swag.S64.Min : -(1's64 << (bits - 1))
            let max  = bits == 64 ? Swag.S64.Max : (1's64 << (bits - 1)) - 1
            valid = parsed.value >= min and parsed.value <= max
            raw   = cast #bit (u64) parsed.value
        }

    case .Unsigned8, .Unsigned16, .Unsigned32, .Unsigned64:
        let parsed = catch StrConv.parseU64(source) as parseError
        if parseError == null and parsed.eat == source.count and !parsed.ovf
        {
            let max = size == 8 ? Swag.U64.Max : (1'u64 << (size * 8)) - 1
            valid = parsed.value <= max
            raw   = parsed.value
        }

    case .Float32:
        let parsed = catch StrConv.parseF64(source) as parseError
        if parseError == null and parsed.eat == source.count and !parsed.ovf
        {
            valid = true
            raw   = cast #bit (u32) cast(f32) parsed.value
        }

    case .Float64:
        let parsed = catch StrConv.parseF64(source) as parseError
        if parseError == null and parsed.eat == source.count and !parsed.ovf
        {
            valid = true
            raw   = cast #bit (u64) parsed.value
        }

    case .Bytes, .Hex16, .Hex32, .Hex64:
        let digits = Utf8.startsWith(source, "0x", .Latin1NoCase) ? cast(string) source[2 to] : source
        let parsed = catch StrConv.parseX64(digits) as parseError
        if parseError == null and parsed.eat == digits.count and !parsed.ovf
        {
            let max = size == 8 ? Swag.U64.Max : (1'u64 << (size * 8)) - 1
            valid = parsed.value <= max
            raw   = parsed.value
        }
    }

    if !valid
    {
        result.state = .Invalid
        result.error = .Value
        return result
    }

    appendHexScalarPattern(&result.pattern, raw, size, bigEndian)
    result.state = .Valid
    return result
}

// Parses the three hexadecimal-viewer search forms:
//
// - `4D 5A ?? ?0` or `hex: 4D 5A` for byte and nibble patterns;
// - `text: MZ` or `"MZ"` for exact UTF-8 bytes;
// - `value: 42` for the active scalar representation and byte order.
func parseHexSearch(query: string, grouping: HexGrouping, bigEndian: bool)->HexSearchParse
{
    let trimmed = Latin1.trim(query)
    if !trimmed.count
    {
        var result: retval
        result.state = .Incomplete
        return result
    }

    if Utf8.startsWith(trimmed, "text:", .Latin1NoCase) do
        return parseHexTextPattern(Latin1.trim(cast(string) trimmed[5 to]))
    if Utf8.startsWith(trimmed, "value:", .Latin1NoCase) do
        return parseHexValuePattern(Latin1.trim(cast(string) trimmed[6 to]), grouping, bigEndian)
    if Utf8.startsWith(trimmed, "hex:", .Latin1NoCase) do
        return parseHexBytePattern(Latin1.trim(cast(string) trimmed[4 to]))

    if trimmed[0] == '"'u8
    {
        if trimmed.count == 1 or trimmed[trimmed.count - 1] != '"'u8
        {
            var result: retval
            result.state = .Incomplete
            return result
        }

        return parseHexTextPattern(cast(string) trimmed[1 until trimmed.count - 1])
    }

    return parseHexBytePattern(trimmed)
}
