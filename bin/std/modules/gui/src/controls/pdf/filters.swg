#global namespace Pdf

using Core, Core.Errors

// Stream filters that PDF defines itself, decoded here rather than delegated.
//
// Flate is the one filter that comes from Core; every other representation a stream
// dictionary can name is implemented in this file so the module never depends on an
// external decoder.

func isWhite(c: u8)->bool     => c == 0 or c == 9 or c == 10 or c == 12 or c == 13 or c == 32
func isDelimiter(c: u8)->bool => isWhite(c) or c == '(' or c == ')' or c == '<' or c == '>' or c == '[' or c == ']' or c == '{' or c == '}' or c == '/' or c == '%'
func isDigit(c: u8)->bool     => c >= '0' and c <= '9'
func isHex(c: u8)->bool       => isDigit(c) or (c >= 'A' and c <= 'F') or (c >= 'a' and c <= 'f')

func hexValue(c: u8)->u8
{
    if isDigit(c) do
        return c - '0'
    if c >= 'A' and c <= 'F' do
        return c - 'A' + 10
    return c - 'a' + 10
}

internal func decodeAsciiHex(data: const [..] u8)->Array'u8 fail
{
    var result: retval
    var high = Swag.U8.Max
    for c in data
    {
        if isWhite(c) do
            continue
        if c == '>' do
            break
        if !isHex(c) do
            fail InvalidFormatError{"ASCIIHexDecode stream contains a non-hexadecimal byte"}
        let value = hexValue(c)
        if high == Swag.U8.Max do
            high = value
        else
        {
            result.add(high * 16 + value)
            high = Swag.U8.Max
        }
    }

    // A trailing odd digit is completed with a zero, as the format prescribes.
    if high != Swag.U8.Max do
        result.add(high * 16)
    return result
}

internal func decodeAscii85(data: const [..] u8)->Array'u8 fail
{
    var result: retval
    var group:  [5] u8
    var groupCount = 0'u32
    var pos        = 0'u64
    while pos < @countof(data)
    {
        let c = data[pos]
        pos += 1
        if isWhite(c) do
            continue
        if c == '<' and pos < @countof(data) and data[pos] == '~'
        {
            pos += 1
            continue
        }

        if c == '~'
        {
            if pos >= @countof(data) or data[pos] != '>' do
                fail InvalidFormatError{"ASCII85Decode stream has an invalid terminator"}
            break
        }

        if c == 'z'
        {
            if groupCount do
                fail InvalidFormatError{"ASCII85Decode stream has a misplaced zero group"}
            result.add([0'u8, 0, 0, 0])
            continue
        }

        if c < '!' or c > 'u' do
            fail InvalidFormatError{"ASCII85Decode stream contains an invalid byte"}
        group[groupCount] = c - '!'
        groupCount        += 1
        if groupCount != 5 do
            continue

        var value = 0'u64
        for digit in group do
            value = value * 85 + digit
        if value > Swag.U32.Max do
            fail InvalidFormatError{"ASCII85Decode group exceeds 32 bits"}
        result.add([cast(u8) ((value >> 24) & 0xFF), cast(u8) ((value >> 16) & 0xFF), cast(u8) ((value >> 8) & 0xFF), cast(u8) (value & 0xFF)])
        groupCount = 0
    }

    if groupCount == 1 do
        fail InvalidFormatError{"ASCII85Decode stream has an incomplete group"}
    if groupCount
    {
        let outputCount = groupCount - 1
        for i in groupCount until 5 do
            group[i] = 84
        var value = 0'u64
        for digit in group do
            value = value * 85 + digit
        if value > Swag.U32.Max do
            fail InvalidFormatError{"ASCII85Decode group exceeds 32 bits"}
        let decoded: [4] u8 = [cast(u8) ((value >> 24) & 0xFF), cast(u8) ((value >> 16) & 0xFF), cast(u8) ((value >> 8) & 0xFF), cast(u8) (value & 0xFF)]
        for i in outputCount do
            result.add(decoded[i])
    }

    return result
}

internal func decodeRunLength(data: const [..] u8)->Array'u8 fail
{
    var result: retval
    var pos = 0'u64
    while pos < @countof(data)
    {
        let length = data[pos]
        pos += 1
        if length == 128 do
            break
        if length <= 127
        {
            let count = cast(u64) length + 1
            if pos + count > @countof(data) do
                fail InvalidFormatError{"RunLengthDecode literal run is truncated"}
            result.add(data[pos until pos + count])
            pos += count
            continue
        }

        if pos >= @countof(data) do
            fail InvalidFormatError{"RunLengthDecode repeated run is truncated"}
        let value = data[pos]
        pos += 1
        for cast(u64) (257 - cast(u32) length) do
            result.add(value)
    }

    return result
}

// Codes the LZW variable-width code stream reserves for itself.
private const LzwClearCode = 256'u32
private const LzwEndCode   = 257'u32
private const LzwFirstCode = 258'u32
private const LzwMaxCode   = 4096'u32

// Dictionary entries chain to their prefix instead of storing whole sequences, so the
// table stays a fixed 4096 entries whatever the stream expands to.
private struct LzwDictionary
{
    prefix: [LzwMaxCode] u32
    suffix: [LzwMaxCode] u8
    length: [LzwMaxCode] u32
}

private impl LzwDictionary
{
    mtd reset()
    {
        for i in LzwClearCode
        {
            .suffix[i] = cast(u8) i
            .length[i] = 1
        }
    }

    // Appends the byte sequence of `code`, written back to front through the prefix chain.
    mtd const expand(code: u32, result: *Array'u8)
    {
        let start = result.count
        result.resize(start + .length[code])
        var write = result.count
        var walk  = code
        for
        {
            write         -= 1
            result[write] = .suffix[walk]
            if walk < LzwClearCode do
                break
            walk = .prefix[walk]
        }
    }

    mtd const firstByte(code: u32)->u8
    {
        var walk = code
        while walk >= LzwClearCode do
            walk = .prefix[walk]
        return cast(u8) walk
    }
}

// Decodes an LZWDecode stream.
//
// `earlyChange` matches the filter parameter of the same name: when set, the code width
// grows one code before the dictionary is actually full, which is what almost every
// producer emits.
internal func decodeLzw(data: const [..] u8, earlyChange = true)->Array'u8 fail
{
    var result:     retval
    var dictionary: LzwDictionary
    dictionary.reset()

    var next      = LzwFirstCode
    var codeBits  = 9'u32
    var previous  = Swag.U32.Max
    var bitBuffer = 0'u32
    var bitCount  = 0'u32
    var pos       = 0'u64

    for
    {
        while bitCount < codeBits and pos < @countof(data)
        {
            bitBuffer = bitBuffer << 8 | data[pos]
            bitCount  += 8
            pos       += 1
        }

        // A stream that stops mid-code is padding, not a failure.
        if bitCount < codeBits do
            break
        bitCount -= codeBits
        let code = (bitBuffer >> bitCount) & ((1'u32 << codeBits) - 1)
        if code == LzwEndCode do
            break
        if code == LzwClearCode
        {
            next     = LzwFirstCode
            codeBits = 9
            previous = Swag.U32.Max
            continue
        }

        if previous == Swag.U32.Max
        {
            if code >= LzwClearCode do
                fail InvalidFormatError{"LZWDecode stream starts with an undefined code"}
            dictionary.expand(code, &result)
            previous = code
            continue
        }

        if code < next do
            dictionary.expand(code, &result)
        elif code == next
        {
            dictionary.expand(previous, &result)
            result.add(dictionary.firstByte(previous))
        }
        else do
            fail InvalidFormatError{"LZWDecode stream uses an undefined code"}

        if next < LzwMaxCode
        {
            dictionary.prefix[next] = previous
            dictionary.suffix[next] = code < next ? dictionary.firstByte(code) : dictionary.firstByte(previous)
            dictionary.length[next] = dictionary.length[previous] + 1
            next += 1
        }

        previous = code

        let limit = earlyChange ? next + 1 : next
        codeBits = limit >= 2048 ? 12 : limit >= 1024 ? 11 : limit >= 512 ? 10 : 9
    }

    return result
}
