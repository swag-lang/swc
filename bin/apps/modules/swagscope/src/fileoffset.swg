#global internal

using Core

// Returns the value of the hexadecimal digit `value`, or 16 when `value` is not one.
func hexDigitValue(value: u8)->u8
{
    if value >= '0'u8 and value <= '9'u8 do
        return value - '0'u8
    if value >= 'a'u8 and value <= 'f'u8 do
        return value - 'a'u8 + 10
    if value >= 'A'u8 and value <= 'F'u8 do
        return value - 'A'u8 + 10
    return 16
}

// Returns the offset `text` names in a `fileSize`-byte file, or `Swag.U64.Max` when it names none.
//
// `text` is an absolute offset, a percentage, `caret` (the `current` position), `filesize` (the
// last byte), or an offset relative to `current` after `+` or `-`. Unprefixed numbers are
// hexadecimal; `0d` opts into decimal explicitly. A number past the end names the last byte. Every
// viewer that asks for a file offset reads it with this one grammar, so the same text names the
// same place in each of them.
func parseFileOffset(text: string, current, fileSize: u64)->u64
{
    let trimmed = Latin1.trim(text)
    let count   = trimmed.count
    if not count or not fileSize do
        return Swag.U64.Max

    var index    = 0'u64
    var relative = 0's32
    if trimmed[index] == '+'u8 or trimmed[index] == '-'u8
    {
        relative = trimmed[index] == '+'u8 ? 1 : -1
        index    += 1
    }

    if index >= count do
        return Swag.U64.Max

    let valueText = cast(string, trimmed[index to])
    if not relative and Utf8.compare(valueText, "caret", .Latin1NoCase) == 0 do
        return current
    if not relative and Utf8.compare(valueText, "filesize", .Latin1NoCase) == 0 do
        return fileSize - 1

    let percentage = not relative and trimmed[count - 1] == '%'u8
    let end        = percentage ? count - 1 : count
    if index >= end do
        return Swag.U64.Max

    var radix = percentage ? 10'u64 : 16'u64
    if index + 1 < end and trimmed[index] == '0'u8 and (trimmed[index + 1] == 'x'u8 or trimmed[index + 1] == 'X'u8)
    {
        index += 2
    }
    elif index + 1 < end and trimmed[index] == '0'u8 and (trimmed[index + 1] == 'd'u8 or trimmed[index + 1] == 'D'u8)
    {
        radix = 10
        index += 2
    }

    var value  = 0'u64
    var digits = 0'u64
    while index < end
    {
        let c = trimmed[index]
        if c == ' 'u8 or c == '_'u8
        {
            index += 1
            continue
        }

        let digit = hexDigitValue(c)
        if digit >= radix do
            return Swag.U64.Max

        // A value wider than the address space is a typing accident, not an offset.
        if value > (Swag.U64.Max - digit) / radix do
            return Swag.U64.Max
        value  = value * radix + digit
        digits += 1
        index  += 1
    }

    if not digits do
        return Swag.U64.Max

    if percentage
    {
        if value > 100 do
            return Swag.U64.Max
        let last = fileSize - 1
        return last / 100 * value + last % 100 * value / 100
    }

    var target = value
    if relative > 0 do
        target = current + Math.min(value, Swag.U64.Max - current)
    elif relative < 0 do
        target = value >= current ? 0 : current - value
    return Math.min(target, fileSize - 1)
}
