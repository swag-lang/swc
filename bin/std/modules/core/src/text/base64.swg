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

// Encodes bytes as standard base64 text, with `=` padding and no line breaks.
func encode(bytes: const [..] u8)->String
{
    const Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    var result: retval
    let count = @countof(bytes)
    result.reserve(((count + 2) / 3) * 4)

    var index = 0'u64
    while index + 3 <= count
    {
        let group = (cast(u32) bytes[index] << 16) | (cast(u32) bytes[index + 1] << 8) | cast(u32) bytes[index + 2]
        result.append(Alphabet[group >> 18])
        result.append(Alphabet[(group >> 12) & 63])
        result.append(Alphabet[(group >> 6) & 63])
        result.append(Alphabet[group & 63])
        index += 3
    }

    let left = count - index
    if left == 1
    {
        let group = cast(u32) bytes[index] << 16
        result.append(Alphabet[group >> 18])
        result.append(Alphabet[(group >> 12) & 63])
        result.append('='u8)
        result.append('='u8)
    }
    elif left == 2
    {
        let group = (cast(u32) bytes[index] << 16) | (cast(u32) bytes[index + 1] << 8)
        result.append(Alphabet[group >> 18])
        result.append(Alphabet[(group >> 12) & 63])
        result.append(Alphabet[(group >> 6) & 63])
        result.append('='u8)
    }

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
    result.reserve((@countof(text) / 4 + 1) * 3)

    var digits: [4] u8
    var count = 0'u32
    var ended = false
    for value in text
    {
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
        count += 1
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
