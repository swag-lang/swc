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

private struct FileOffsetParser
{
    source:       string
    index:        u64
    current:      u64
    fileSize:     u64
    baseAddress:  u64
    bookmark:     u64
    hasAddressContext: bool
    usedBase:     bool
    valid:        bool = true
}

private impl FileOffsetParser
{
    mtd skipSpace()
    {
        while .index < .source.count and (.source[.index] == ' 'u8 or .source[.index] == '\t'u8) do
            .index += 1
    }

    mtd accept(value: u8)->bool
    {
        .skipSpace()
        if .index >= .source.count or .source[.index] != value do
            return false
        .index += 1
        return true
    }

    mtd parseExpression()->u64 => .parseSum()

    mtd parseSum()->u64
    {
        var value = .parseProduct()
        while .valid
        {
            .skipSpace()
            if .index >= .source.count or (.source[.index] != '+'u8 and .source[.index] != '-'u8) do
                break

            let operation = .source[.index]
            .index += 1
            let right = .parseProduct()
            if operation == '+'u8
            {
                if value > Swag.U64.Max - right
                {
                    .valid = false
                    return 0
                }
                value += right
            }
            else
            {
                value = right >= value ? 0 : value - right
            }
        }

        return value
    }

    mtd parseProduct()->u64
    {
        var value = .parseUnary()
        while .valid
        {
            .skipSpace()
            if .index >= .source.count or (.source[.index] != '*'u8 and .source[.index] != '/'u8) do
                break

            let operation = .source[.index]
            .index += 1
            let right = .parseUnary()
            if operation == '/'u8
            {
                if not right
                {
                    .valid = false
                    return 0
                }
                value /= right
            }
            else
            {
                if right and value > Swag.U64.Max / right
                {
                    .valid = false
                    return 0
                }
                value *= right
            }
        }

        return value
    }

    mtd parseUnary()->u64
    {
        .skipSpace()
        if .accept('+'u8) do
            return .parseUnary()
        if .accept('-'u8)
        {
            .valid = false
            return 0
        }

        return .parseAtom()
    }

    mtd parseAtom()->u64
    {
        .skipSpace()
        if .index >= .source.count
        {
            .valid = false
            return 0
        }

        if .accept('('u8)
        {
            let value = .parseExpression()
            if not .accept(')'u8) do .valid = false
            return value
        }

        let first = .source[.index]
        if (first >= 'A'u8 and first <= 'Z'u8) or (first >= 'a'u8 and first <= 'z'u8)
            do return .parseName()
        return .parseNumber()
    }

    mtd parseName()->u64
    {
        let start = .index
        while .index < .source.count
        {
            let value = .source[.index]
            if not ((value >= 'A'u8 and value <= 'Z'u8) or (value >= 'a'u8 and value <= 'z'u8) or (value >= '0'u8 and value <= '9'u8) or value == '_'u8) do
                break
            .index += 1
        }

        let name = cast(string, .source[start until .index])
        if Utf8.compare(name, "caret", .Latin1NoCase) == 0 do
            return .current
        if Utf8.compare(name, "filesize", .Latin1NoCase) == 0
        {
            if not .fileSize
            {
                .valid = false
                return 0
            }
            return .fileSize - 1
        }
        if Utf8.compare(name, "bookmark", .Latin1NoCase) == 0
        {
            if not .hasAddressContext or .bookmark == Swag.U64.Max
            {
                .valid = false
                return 0
            }
            return .bookmark
        }
        if Utf8.compare(name, "base", .Latin1NoCase) == 0
        {
            if not .hasAddressContext
            {
                .valid = false
                return 0
            }
            .usedBase = true
            return .baseAddress
        }
        if Utf8.compare(name, "align", .Latin1NoCase) == 0
            do return .parseAlignment()

        var number = 0'u64
        if name.count
        {
            for digitIndex in name.count
            {
                let digit = hexDigitValue(name[digitIndex])
                if digit >= 16 or number > (Swag.U64.Max - digit) / 16
                {
                    .valid = false
                    return 0
                }
                number = number * 16 + digit
            }
            return number
        }

        .valid = false
        return 0
    }

    mtd parseAlignment()->u64
    {
        if not .accept('('u8)
        {
            .valid = false
            return 0
        }

        let value = .parseExpression()
        if not .accept(','u8)
        {
            .valid = false
            return 0
        }

        let boundary = .parseExpression()
        if not .accept(')'u8) or not boundary
        {
            .valid = false
            return 0
        }

        let remainder = value % boundary
        if not remainder do
            return value
        let adjustment = boundary - remainder
        if value > Swag.U64.Max - adjustment
        {
            .valid = false
            return 0
        }
        return value + adjustment
    }

    mtd parseNumber()->u64
    {
        var radix = 16'u64
        if not (.index + 1 < .source.count and .source[.index] == '0'u8 and (.source[.index + 1] == 'x'u8 or .source[.index + 1] == 'X'u8 or .source[.index + 1] == 'd'u8 or .source[.index + 1] == 'D'u8))
        {
            var preview = .index
            while preview < .source.count and ((.source[preview] >= '0'u8 and .source[preview] <= '9'u8) or .source[preview] == '_'u8 or .source[preview] == ' 'u8 or .source[preview] == '\t'u8) do
                preview += 1
            if preview < .source.count and .source[preview] == '%'u8 do
                radix = 10
        }
        if .index + 1 < .source.count and .source[.index] == '0'u8
        {
            let prefix = .source[.index + 1]
            if prefix == 'x'u8 or prefix == 'X'u8
            {
                .index += 2
            }
            elif prefix == 'd'u8 or prefix == 'D'u8
            {
                radix = 10
                .index += 2
            }
        }

        var value: u64
        var digits: u64
        while .index < .source.count
        {
            let digit = hexDigitValue(.source[.index])
            if digit < radix
            {
                if value > (Swag.U64.Max - digit) / radix
                {
                    .valid = false
                    return 0
                }
                value *= radix
                value += digit
                digits += 1
                .index += 1
                continue
            }

            if .source[.index] == '_'u8
            {
                .index += 1
                continue
            }

            // Space groups remain valid in a hexadecimal literal (`00 1F`), but do not absorb
            // a later expression term (`caret + 10`).
            if radix == 16 and (.source[.index] == ' 'u8 or .source[.index] == '\t'u8)
            {
                let beforeSpace = .index
                .skipSpace()
                if .index < .source.count and hexDigitValue(.source[.index]) < radix
                {
                    continue
                }
                if .index == .source.count or (.source[.index] != '+'u8 and .source[.index] != '-'u8 and .source[.index] != '*'u8 and .source[.index] != '/'u8 and .source[.index] != ')'u8 and .source[.index] != ','u8) do
                    .valid = false
                if .index == beforeSpace do .index += 1
            }
            break
        }

        if not digits
        {
            .valid = false
            return 0
        }

        .skipSpace()
        if .accept('%'u8)
        {
            if value > 100 or not .fileSize
            {
                .valid = false
                return 0
            }
            let last = .fileSize - 1
            return last / 100 * value + last % 100 * value / 100
        }

        return value
    }
}

// Returns the offset `text` names in a `fileSize`-byte file, or `Swag.U64.Max` when it names none.
// Unprefixed values are hexadecimal, `0d` selects decimal, `%` selects file percentage, and
// leading `+` or `-` keeps its caret-relative meaning. Expressions add `+`, `-`, `*`, `/`, and
// parentheses; `align(value, boundary)` rounds up. `bookmark` names the optional session bookmark,
// while `base` names the configured virtual base address and maps it back to file offset zero when
// `hasAddressContext` is true. Viewers without that context retain the original grammar and reject
// both names.
func parseFileOffset(text: string, current, fileSize: u64, baseAddress: u64 = 0, bookmark: u64 = Swag.U64.Max, hasAddressContext: bool = false)->u64
{
    let trimmed = Latin1.trim(text)
    if not trimmed.count or not fileSize do
        return Swag.U64.Max

    var parser = FileOffsetParser{source: cast(string, trimmed), current: current, fileSize: fileSize, baseAddress: baseAddress, bookmark: bookmark, hasAddressContext: hasAddressContext}
    var relative: s32
    parser.skipSpace()
    if parser.index < parser.source.count and (parser.source[parser.index] == '+'u8 or parser.source[parser.index] == '-'u8)
    {
        relative = parser.source[parser.index] == '+'u8 ? 1 : -1
        parser.index += 1
    }

    var value = parser.parseExpression()
    parser.skipSpace()
    if not parser.valid or parser.index != parser.source.count do
        return Swag.U64.Max

    if relative > 0
    {
        if current > Swag.U64.Max - value do
            return Swag.U64.Max
        value += current
    }
    elif relative < 0
    {
        value = value >= current ? 0 : current - value
    }

    if parser.usedBase
    {
        if value < baseAddress do
            return Swag.U64.Max
        value -= baseAddress
    }
    return Math.min(value, fileSize - 1)
}
