#global public
#global namespace Base64

using Swag

// The sextet one text byte spells, 255 for a byte outside both alphabets.
private func digitValue(value: u8)->u8
{
    if value >= 'A' and value <= 'Z' do
        return value - 'A'
    if value >= 'a' and value <= 'z' do
        return value - 'a' + 26
    if value >= '0' and value <= '9' do
        return value - '0' + 52
    if value == '+' or value == '-' do
        return 62
    if value == '/' or value == '_' do
        return 63
    return 255
}

private const EncodeGather  = cast(Math.Simd.U8x16) [2'u8, 1, 0, 0x80, 5, 4, 3, 0x80, 8, 7, 6, 0x80, 11, 10, 9, 0x80]
private const DecodeScatter = cast(Math.Simd.U8x16) [0'u8, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 0x80, 0x80, 0x80, 0x80]

#[Swag.Inline]
private func encodeBlock(input: const [*] u8)->Math.Simd.U8x16
{
    let gathered = cast #bit(Math.Simd.U32x4) Math.Simd.shuffle(Math.Simd.load(input), EncodeGather)
    let sextets  = (gathered >> 18) | (((gathered >> 12) & 63) << 8) | (((gathered >> 6) & 63) << 16) | ((gathered & 63) << 24)
    let values   = cast #bit(Math.Simd.U8x16) sextets

    var encoded = values + 'A'
    encoded += Math.Simd.select(values > Math.Simd.splat(25'u8), Math.Simd.splat(6'u8), Math.Simd.splat(0'u8))
    encoded += Math.Simd.select(values > Math.Simd.splat(51'u8), Math.Simd.splat(181'u8), Math.Simd.splat(0'u8))
    encoded = Math.Simd.select(values == Math.Simd.splat(62'u8), Math.Simd.splat('+'u8), encoded)
    return Math.Simd.select(values == Math.Simd.splat(63'u8), Math.Simd.splat('/'u8), encoded)
}

#[Swag.Inline]
private func decodeBlock(input: const [*] u8)->{ decoded: Math.Simd.U8x16, valid: bool }
{
    let bytes      = Math.Simd.load(input)
    let upperMask  = (bytes >= Math.Simd.splat('A'u8)) & (bytes <= Math.Simd.splat('Z'u8))
    let lowerMask  = (bytes >= Math.Simd.splat('a'u8)) & (bytes <= Math.Simd.splat('z'u8))
    let digitMask  = (bytes >= Math.Simd.splat('0'u8)) & (bytes <= Math.Simd.splat('9'u8))
    let symbolMask = (bytes == Math.Simd.splat('+'u8)) | (bytes == Math.Simd.splat('-'u8)) |
                     (bytes == Math.Simd.splat('/'u8)) | (bytes == Math.Simd.splat('_'u8))
    if !Math.Simd.allTrue(upperMask | lowerMask | digitMask | symbolMask) do
        return {decoded: Math.Simd.splat(0'u8), valid: false}

    var values = Math.Simd.splat(0'u8)
    values = Math.Simd.select(upperMask, bytes - 'A', values)
    values = Math.Simd.select(lowerMask, bytes - 'a' + 26, values)
    values = Math.Simd.select(digitMask, bytes - '0' + 52, values)
    values = Math.Simd.select((bytes == Math.Simd.splat('+'u8)) | (bytes == Math.Simd.splat('-'u8)), Math.Simd.splat(62'u8), values)
    values = Math.Simd.select((bytes == Math.Simd.splat('/'u8)) | (bytes == Math.Simd.splat('_'u8)), Math.Simd.splat(63'u8), values)

    let sextets = cast #bit(Math.Simd.U32x4) values
    let packed  = ((sextets & 63) << 2) | (((sextets >> 8) & 63) >> 4) |
                  ((((sextets >> 8) & 15) << 4) | (((sextets >> 16) & 63) >> 2)) << 8 |
                  (((((sextets >> 16) & 3) << 6) | ((sextets >> 24) & 63)) << 16)
    return {decoded: Math.Simd.shuffle(cast #bit(Math.Simd.U8x16) packed, DecodeScatter), valid: true}
}

// Encodes bytes as standard base64 text, with `=` padding and no line breaks.
func encode(bytes: const [..] u8)->String
{
    const Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    var result: retval
    let count       = @countof(bytes)
    let resultCount = ((count + 2) / 3) * 4
    result.reserve(resultCount + 1)

    var index    = 0'u64
    var outIndex = 0'u64
    while count - index >= 16
    {
        Math.Simd.store(result.buffer! + outIndex, encodeBlock(@dataof(bytes) + index))
        index    += 12
        outIndex += 16
    }

    let output = result.buffer!
    while index + 3 <= count
    {
        let group = (cast(u32) bytes[index] << 16) | (cast(u32) bytes[index + 1] << 8) | cast(u32) bytes[index + 2]
        output[outIndex + 0] = Alphabet[group >> 18]
        output[outIndex + 1] = Alphabet[(group >> 12) & 63]
        output[outIndex + 2] = Alphabet[(group >> 6) & 63]
        output[outIndex + 3] = Alphabet[group & 63]
        index                += 3
        outIndex             += 4
    }

    let left = count - index
    if left == 1
    {
        let group = cast(u32) bytes[index] << 16
        output[outIndex + 0] = Alphabet[group >> 18]
        output[outIndex + 1] = Alphabet[(group >> 12) & 63]
        output[outIndex + 2] = '='
        output[outIndex + 3] = '='
    }
    elif left == 2
    {
        let group = (cast(u32) bytes[index] << 16) | (cast(u32) bytes[index + 1] << 8)
        output[outIndex + 0] = Alphabet[group >> 18]
        output[outIndex + 1] = Alphabet[(group >> 12) & 63]
        output[outIndex + 2] = Alphabet[(group >> 6) & 63]
        output[outIndex + 3] = '='
    }

    result.length       = resultCount
    output[resultCount] = 0
    return result
}

// Decodes base64 text into the bytes it spells.
//
// Both the standard and the URL-safe alphabets are accepted, embedded ASCII white space is
// skipped, and the trailing `=` padding is optional. A character outside those sets, data after
// the padding, or a final group of a single digit reports [[Core.Errors.InvalidFormatError]].
func decode(text: string)->Array'u8 fail
{
    var result: retval
    result.reserve((@countof(text) / 4 + 1) * 3 + 16)

    var digits: [4] u8
    var count = 0'u32
    var ended = false
    var index = 0'u64
    while index < @countof(text)
    {
        if !count and !ended and @countof(text) - index >= 16
        {
            let block = decodeBlock(@dataof(text) + index)
            if block.valid
            {
                Math.Simd.store(result.buffer! + result.count, block.decoded)
                result.count += 12
                index        += 16
                continue
            }
        }

        let value = text[index]
        index += 1
        if value == ' ' or value == '\t' or value == '\r' or value == '\n' do
            continue
        if value == '='
        {
            ended = true
            continue
        }

        if ended do
            fail Errors.InvalidFormatError{"base64 data continues after its padding"}

        let digit = digitValue(value)
        if digit == 255 do
            fail Errors.InvalidFormatError{"invalid base64 character"}

        digits[count] = digit
        count         += 1
        if count == 4
        {
            result.add(cast(u8) ((cast(u32) digits[0] << 2) | (cast(u32) digits[1] >> 4)))
            result.add(cast(u8) ((cast(u32) (digits[1] & 15) << 4) | (cast(u32) digits[2] >> 2)))
            result.add(cast(u8) ((cast(u32) (digits[2] & 3) << 6) | digits[3]))
            count = 0
        }
    }

    // A final group of two or three digits spells one or two bytes; a lone digit spells nothing.
    if count == 1 do
        fail Errors.InvalidFormatError{"truncated base64 data"}
    if count >= 2 do
        result.add(cast(u8) ((cast(u32) digits[0] << 2) | (cast(u32) digits[1] >> 4)))
    if count == 3 do
        result.add(cast(u8) ((cast(u32) (digits[1] & 15) << 4) | (cast(u32) digits[2] >> 2)))

    return result
}
