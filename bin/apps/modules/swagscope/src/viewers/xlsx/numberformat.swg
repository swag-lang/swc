#global internal
#global namespace Viewers.Xlsx

using Core

// A stored value and whether its authored number format could be represented.
struct FormattedCell
{
    text:    String
    omitted: bool
}

private struct FormatToken
{
    value:   u8
    literal: bool
}

private const ShortMonthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
private const FullMonthNames = ["January", "February", "March", "April", "May", "June",
                                "July", "August", "September", "October", "November", "December"]

// A bounded, declarative Excel number format; formulas and conditions never execute.
struct NumberFormat
{
    code: String
}

impl NumberFormat
{
    func builtIn(id: u32)->NumberFormat
    {
        var code: string
        switch id
        {
        case 0:  code = "General"
        case 1:  code = "0"
        case 2:  code = "0.00"
        case 3:  code = "#,##0"
        case 4:  code = "#,##0.00"
        case 5:  code = "\"$\"#,##0;(\"$\"#,##0)"
        case 6:  code = "\"$\"#,##0;[Red](\"$\"#,##0)"
        case 7:  code = "\"$\"#,##0.00;(\"$\"#,##0.00)"
        case 8:  code = "\"$\"#,##0.00;[Red](\"$\"#,##0.00)"
        case 9:  code = "0%"
        case 10: code = "0.00%"
        case 11: code = "0.00E+00"
        case 14: code = "m/d/yy"
        case 15: code = "d-mmm-yy"
        case 16: code = "d-mmm"
        case 17: code = "mmm-yy"
        case 18: code = "h:mm AM/PM"
        case 19: code = "h:mm:ss AM/PM"
        case 20: code = "h:mm"
        case 21: code = "h:mm:ss"
        case 22: code = "m/d/yy h:mm"
        case 37: code = "#,##0;(#,##0)"
        case 38: code = "#,##0;[Red](#,##0)"
        case 39: code = "#,##0.00;(#,##0.00)"
        case 40: code = "#,##0.00;[Red](#,##0.00)"
        case 45: code = "mm:ss"
        case 46: code = "[h]:mm:ss"
        case 49: code = "@"
        default: return {}
        }

        return NumberFormat{String.from(code)}
    }

    // Splits only unquoted sections, then decodes literal and display-only format tokens.
    private mtd const tokens(number: f64)->{items: Array!{FormatToken}, negativeSection: bool, valid: bool}
    {
        var result:   #returntype
        let source  = .code.toString()
        var sections: Array!{string}
        var quoted  = false
        var escaped = false
        var start   = 0_u64
        for value, index in source
        {
            if escaped
            {
                escaped = false
                continue
            }

            if value == '\\'_u8
            {
                escaped = true
                continue
            }

            if value == '"'_u8
            {
                quoted = not quoted
            }

            if value == ';'_u8 and not quoted
            {
                sections.add(source[start until index])
                start = index + 1
            }
        }

        sections.add(source[start to])
        if quoted or escaped or sections.count > 4
        {
            return result
        }

        var section = 0_u64
        if number < 0 and sections.count >= 2
        {
            section = 1
            result.negativeSection = true
        }
        else if number == 0 and sections.count >= 3
        {
            section = 2
        }

        let selected = sections[section]
        var at       = 0_u64
        quoted = false
        while at < selected.count
        {
            let value = selected[at]
            at += 1
            if value == '"'_u8
            {
                quoted = not quoted
                continue
            }

            if quoted
            {
                result.items.add(FormatToken{value, true})
                continue
            }

            if value == '\\'_u8
            {
                if at >= selected.count
                {
                    return result
                }

                result.items.add(FormatToken{selected[at], true})
                at += 1
            }
            else if value == '_'_u8 or value == '*'_u8
            {
                if at >= selected.count
                {
                    return result
                }

                at += 1     // Accounting alignment does not change the displayed quantity.
            }
            else if value == '['_u8
            {
                let end = Utf8.indexOf(selected[at to], ']'_rune)
                if end == Swag.U64.Max
                {
                    return result
                }

                let option = selected[at until at + end]
                at += end + 1
                if option == "h" or
                   option == "hh" or
                   option == "m" or
                   option == "mm" or
                   option == "s" or
                   option == "ss"
                {
                    result.items.add(FormatToken{'['_u8})
                    for byte in option
                    {
                        result.items.add(FormatToken{byte})
                    }

                    result.items.add(FormatToken{']'_u8})
                }
                else if Utf8.startsWith(option, "$")
                {
                    let dash   = Utf8.indexOf(option, '-'_rune)
                    let symbol = dash == Swag.U64.Max ? option[1 to] : option[1 until dash]
                    if not symbol.count
                    {
                        return result
                    }     // Locale-specific long-date formats need a separate contract.
                    for byte in symbol
                    {
                        result.items.add(FormatToken{byte, true})
                    }
                }
                else if option != "Black" and
                        option != "Blue" and
                        option != "Cyan" and
                        option != "Green" and
                        option != "Magenta" and
                        option != "Red" and
                        option != "White" and
                        option != "Yellow"
                {
                    return result
                }
            }
            else
            {
                result.items.add(FormatToken{value})
            }
        }

        result.valid = not quoted
        return result
    }

    mtd const format(stored: string, date1904 = false)->FormattedCell
    {
        func dateText(items: const [..] FormatToken, number: f64, date1904: bool)->FormattedCell
        {
            var result: #returntype = {omitted: true}
            let maximum = date1904 ? 2_957_003.0 : 2_958_465.0
            if number < 0 or number >= maximum + 1
            {
                return result
            }

            let totalSeconds = cast(u64, Math.round(number * 86400))
            let days         = totalSeconds / 86400
            if days > cast(u64, maximum)
            {
                return result
            }

            let seconds = totalSeconds % 86400
            var date: Time.DateTime
            if not date1904 and days == 0
            {
                // Excel formats serial zero as day zero of January 1900.
                date = Time.DateTime{year: 1900, month: 1, day: 0}
            }
            else if not date1904 and days == 60
            {
                // Excel intentionally retains Lotus's non-existent 1900 leap day.
                date = Time.DateTime{year: 1900, month: 2, day: 29}
            }
            else
            {
                let epoch    = Time.Timestamp.fromDateTime(date1904 ? Time.DateTime{year: 1904, month: 1, day: 1} : Time.DateTime{year: 1899, month: 12, day: 31})
                let realDays = not date1904 and days > 60 ? days - 1 : days
                date = Time.Timestamp.fromTicks(epoch.ticks + realDays * Time.TicksPerDay).toDateTime()
            }

            let hour   = seconds / 3600
            let minute = seconds / 60 % 60
            let second = seconds % 60
            var amPm   = false
            for token, index in items where not token.literal and token.value == 'A'_u8 and index + 4 < items.count
            {
                amPm = items[index + 1].value == 'M'_u8 and
                       items[index + 2].value == '/'_u8 and
                       items[index + 3].value == 'P'_u8 and
                       items[index + 4].value == 'M'_u8
            }

            var afterHour = false
            var at        = 0_u64
            while at < items.count
            {
                let token = items[at]
                if token.literal
                {
                    result.text += token.value
                    at += 1
                    continue
                }

                if token.value == 'A'_u8 and amPm and at + 4 < items.count
                {
                    result.text += hour < 12 ? "AM" : "PM"
                    at += 5
                    continue
                }

                if token.value == '['_u8
                {
                    let start = at + 1
                    at = start
                    while at < items.count and items[at].value != ']'_u8
                    {
                        at += 1
                    }

                    if at >= items.count or start == at
                    {
                        return result
                    }

                    let unit  = items[start].value
                    let value = unit == 'h'_u8 ? totalSeconds / 3600 : unit == 'm'_u8 ? totalSeconds / 60 : totalSeconds
                    result.text += Format.toString("%", value)
                    afterHour   = unit == 'h'_u8
                    at          += 1
                    continue
                }

                var end = at + 1
                while end < items.count and not items[end].literal and items[end].value == token.value
                {
                    end += 1
                }

                let count = end - at
                switch token.value
                {
                case 'y':
                    if count == 2
                    {
                        result.text += Format.toString("%{02}", date.year % 100)
                    }
                    else if count == 4
                    {
                        result.text += Format.toString("%{04}", date.year)
                    }
                    else
                    {
                        return result
                    }

                case 'd':
                    if count == 1
                    {
                        result.text += Format.toString("%", date.day)
                    }
                    else if count == 2
                    {
                        result.text += Format.toString("%{02}", date.day)
                    }
                    else
                    {
                        return result
                    }

                    afterHour = false

                case 'm':
                    var isMinute = afterHour
                    if end + 1 < items.count and
                       items[end].value == ':'_u8 and
                       items[end + 1].value == 's'_u8
                    {
                        isMinute = true
                    }

                    if isMinute
                    {
                        if count == 1
                        {
                            result.text += Format.toString("%", minute)
                        }
                        else if count == 2
                        {
                            result.text += Format.toString("%{02}", minute)
                        }
                        else
                        {
                            return result
                        }
                    }
                    else if count == 1
                    {
                        result.text += Format.toString("%", date.month)
                    }
                    else if count == 2
                    {
                        result.text += Format.toString("%{02}", date.month)
                    }
                    else if count == 3
                    {
                        result.text += ShortMonthNames[date.month - 1]
                    }
                    else if count == 4
                    {
                        result.text += FullMonthNames[date.month - 1]
                    }
                    else
                    {
                        return result
                    }

                    afterHour = false

                case 'h':
                    let displayed = amPm ? (hour % 12 ? hour % 12 : 12) : hour
                    if count == 1
                    {
                        result.text += Format.toString("%", displayed)
                    }
                    else if count == 2
                    {
                        result.text += Format.toString("%{02}", displayed)
                    }
                    else
                    {
                        return result
                    }

                    afterHour = true

                case 's':
                    if count == 1
                    {
                        result.text += Format.toString("%", second)
                    }
                    else if count == 2
                    {
                        result.text += Format.toString("%{02}", second)
                    }
                    else
                    {
                        return result
                    }

                    afterHour = false

                case '/', '-', ':', ' ', ',':
                    for count
                    {
                        result.text += token.value
                    }

                default:
                    return result
                }

                at = end
            }

            result.omitted = false
            return result
        }

        var result = FormattedCell{String.from(stored)}
        if .code == "General" or .code == "@" or not stored.count
        {
            return result
        }

        result.omitted = true
        let number = catch StrConv.toF64(stored) { return result; }
        if not Math.isFinite(number) or .code.isEmpty()
        {
            return result
        }

        let decoded = .tokens(number)
        if not decoded.valid
        {
            return result
        }

        let items = decoded.items.toSlice()
        var date  = false
        for token in items where not token.literal and
                                 (token.value == 'y'_u8 or token.value == 'm'_u8 or token.value == 'd'_u8 or token.value == 'h'_u8 or token.value == 's'_u8)
        {
            date = true
        }

        if date
        {
            let formatted = dateText(items, number, date1904)
            return formatted.omitted ? result : formatted
        }

        var first   = Swag.U64.Max
        var last    = 0_u64
        var percent = 0_u32
        for token, index in items where not token.literal
        {
            if token.value == '%'_u8
            {
                percent += 1
            }

            if token.value == '0'_u8 or token.value == '#'_u8
            {
                if first == Swag.U64.Max
                {
                    first = index
                }

                last = index
            }
        }

        if percent > 1
        {
            return result
        }

        // An unescaped fraction, exponent or text placeholder must not masquerade as a suffix.
        for token, index in items where not token.literal and
                                        (first == Swag.U64.Max or index < first or index > last)
        {
            let value = token.value
            if value == ','_u8 and (first == Swag.U64.Max or index < first)
            {
                return result
            }

            if value < 128 and
               value != ' '_u8 and
               value != '$'_u8 and
               value != '%'_u8 and
               value != '('_u8 and
               value != ')'_u8 and
               value != '+'_u8 and
               value != '-'_u8 and
               value != ','_u8
            {
                return result
            }
        }

        if first == Swag.U64.Max
        {
            result.text.clear()
            for token in items
            {
                result.text += token.value
            }

            result.omitted = false
            return result
        }

        var decimals         = 0_u8
        var requiredDecimals = 0_u8
        var integerZeros     = 0_u32
        var fractional       = false
        var grouped          = false
        for index in first until last + 1
        {
            let token = items[index]
            if token.literal
            {
                return result
            }

            switch token.value
            {
            case '.':
                if fractional
                {
                    return result
                }

                fractional = true

            case ',':
                if fractional
                {
                    return result
                }

                grouped = true

            case '0', '#':
                if fractional
                {
                    decimals += 1
                    if token.value == '0'_u8
                    {
                        if requiredDecimals + 1 != decimals
                        {
                            return result
                        }

                        requiredDecimals += 1
                    }

                    if decimals > 12
                    {
                        return result
                    }
                }
                else if token.value == '0'_u8
                {
                    integerZeros += 1
                }

            default:
                return result
            }
        }

        if not integerZeros or integerZeros >= 32 or (grouped and integerZeros > 1)
        {
            return result
        }

        var magnitude   = Math.abs(number) * (percent ? 100.0_f64 : 1.0_f64)
        var suffixStart = last + 1

        // Trailing commas scale thousands; interior commas group digits.
        while suffixStart < items.count and
              not items[suffixStart].literal and
              items[suffixStart].value == ','_u8
        {
            magnitude   /= 1000
            suffixStart += 1
        }

        var scale = 1.0_f64
        for decimals
        {
            scale *= 10
        }

        if magnitude > 1.0e18 / scale
        {
            return result
        }

        let info: Globalization.NumberFormatInfo
        var digits = info.format(magnitude, decimals, grouped)
        if decimals > requiredDecimals
        {
            var end      = digits.count
            var optional = decimals - requiredDecimals
            while optional and end and digits[end - 1] == '0'_u8
            {
                end      -= 1
                optional -= 1
            }

            if end and digits[end - 1] == '.'_u8
            {
                end -= 1
            }

            digits.removeBack(digits.count - end)
        }

        if not grouped and integerZeros > 1 and integerZeros < 32
        {
            let dot   = Utf8.indexOf(digits, '.'_rune)
            let whole = dot == Swag.U64.Max ? digits.count : dot
            if whole < integerZeros
            {
                var padded: String
                for integerZeros - whole
                {
                    padded += '0'_u8
                }

                padded += digits
                digits = #move padded
            }
        }

        result.text.clear()
        if number < 0 and not decoded.negativeSection
        {
            result.text += '-'
        }

        for index in 0 until first
        {
            result.text += items[index].value
        }

        result.text += digits
        for index in suffixStart until items.count
        {
            result.text += items[index].value
        }

        result.omitted = false
        return result
    }
}
