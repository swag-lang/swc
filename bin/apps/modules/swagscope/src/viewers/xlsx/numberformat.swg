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
    private mtd const tokens(number: f64)->{items: Array'FormatToken, negativeSection: bool, valid: bool}
    {
        var result:   #returntype
        let source  = .code.toString()
        var sections: Array'string
        var quoted  = false
        var escaped = false
        var start   = 0'u64
        for value, index in source
        {
            if escaped
            {
                escaped = false
                continue
            }

            if value == '\\'u8
            {
                escaped = true
                continue
            }

            if value == '"'u8 do
                quoted = not quoted
            if value == ';'u8 and not quoted
            {
                sections.add(source[start until index])
                start = index + 1
            }
        }

        sections.add(source[start to])
        if quoted or escaped or sections.count > 4 do
            return result
        var section = 0'u64
        if number < 0 and sections.count >= 2
        {
            section = 1
            result.negativeSection = true
        }
        elif number == 0 and sections.count >= 3
        {
            section = 2
        }

        let selected = sections[section]
        var at       = 0'u64
        quoted = false
        while at < selected.count
        {
            let value = selected[at]
            at += 1
            if value == '"'u8
            {
                quoted = not quoted
                continue
            }

            if quoted
            {
                result.items.add(FormatToken{value, true})
                continue
            }

            if value == '\\'u8
            {
                if at >= selected.count do
                    return result
                result.items.add(FormatToken{selected[at], true})
                at += 1
            }
            elif value == '_'u8 or value == '*'u8
            {
                if at >= selected.count do
                    return result
                at += 1     // Accounting alignment does not change the displayed quantity.
            }
            elif value == '['u8
            {
                let end = Utf8.indexOf(selected[at to], ']'rune)
                if end == Swag.U64.Max do
                    return result
                let option = selected[at until at + end]
                at += end + 1
                if option == "h" or
                   option == "hh" or
                   option == "m" or
                   option == "mm" or
                   option == "s" or
                   option == "ss"
                {
                    result.items.add(FormatToken{'['u8})
                    for byte in option do
                        result.items.add(FormatToken{byte})
                    result.items.add(FormatToken{']'u8})
                }
                elif Utf8.startsWith(option, "$")
                {
                    let dash   = Utf8.indexOf(option, '-'rune)
                    let symbol = dash == Swag.U64.Max ? option[1 to] : option[1 until dash]
                    if not symbol.count do
                        return result     // Locale-specific long-date formats need a separate contract.
                    for byte in symbol do
                        result.items.add(FormatToken{byte, true})
                }
                elif option != "Black" and
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
            if number < 0 or number >= maximum + 1 do
                return result
            let totalSeconds = cast(u64, Math.round(number * 86400))
            let days         = totalSeconds / 86400
            if days > cast(u64, maximum) do
                return result
            let seconds = totalSeconds % 86400
            var date: Time.DateTime
            if not date1904 and days == 0
            {
                // Excel formats serial zero as day zero of January 1900.
                date = Time.DateTime{year: 1900, month: 1, day: 0}
            }
            elif not date1904 and days == 60
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
            for token, index in items where not token.literal and token.value == 'A'u8 and index + 4 < items.count do
                amPm = items[index + 1].value == 'M'u8 and
                       items[index + 2].value == '/'u8 and
                       items[index + 3].value == 'P'u8 and
                       items[index + 4].value == 'M'u8
            let months     = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            let fullMonths = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
            var afterHour  = false
            var at         = 0'u64
            while at < items.count
            {
                let token = items[at]
                if token.literal
                {
                    result.text += token.value
                    at += 1
                    continue
                }

                if token.value == 'A'u8 and amPm and at + 4 < items.count
                {
                    result.text += hour < 12 ? "AM" : "PM"
                    at += 5
                    continue
                }

                if token.value == '['u8
                {
                    let start = at + 1
                    at = start
                    while at < items.count and items[at].value != ']'u8 do
                        at += 1
                    if at >= items.count or start == at do
                        return result
                    let unit  = items[start].value
                    let value = unit == 'h'u8 ? totalSeconds / 3600 : unit == 'm'u8 ? totalSeconds / 60 : totalSeconds
                    result.text += Format.toString("%", value)
                    afterHour   = unit == 'h'u8
                    at          += 1
                    continue
                }

                var end = at + 1
                while end < items.count and not items[end].literal and items[end].value == token.value do
                    end += 1
                let count = end - at
                switch token.value
                {
                case 'y':
                    if count == 2 do
                        result.text += Format.toString("%{02}", date.year % 100)
                    elif count == 4 do
                        result.text += Format.toString("%{04}", date.year)
                    else do
                        return result

                case 'd':
                    if count == 1 do
                        result.text += Format.toString("%", date.day)
                    elif count == 2 do
                        result.text += Format.toString("%{02}", date.day)
                    else do
                        return result
                    afterHour = false

                case 'm':
                    var isMinute = afterHour
                    if end + 1 < items.count and
                       items[end].value == ':'u8 and
                       items[end + 1].value == 's'u8 do
                        isMinute = true
                    if isMinute
                    {
                        if count == 1 do
                            result.text += Format.toString("%", minute)
                        elif count == 2 do
                            result.text += Format.toString("%{02}", minute)
                        else do
                            return result
                    }
                    elif count == 1
                    {
                        result.text += Format.toString("%", date.month)
                    }
                    elif count == 2
                    {
                        result.text += Format.toString("%{02}", date.month)
                    }
                    elif count == 3
                    {
                        result.text += months[date.month - 1]
                    }
                    elif count == 4
                    {
                        result.text += fullMonths[date.month - 1]
                    }
                    else
                    {
                        return result
                    }

                    afterHour = false

                case 'h':
                    let displayed = amPm ? (hour % 12 ? hour % 12 : 12) : hour
                    if count == 1 do
                        result.text += Format.toString("%", displayed)
                    elif count == 2 do
                        result.text += Format.toString("%{02}", displayed)
                    else do
                        return result
                    afterHour = true

                case 's':
                    if count == 1 do
                        result.text += Format.toString("%", second)
                    elif count == 2 do
                        result.text += Format.toString("%{02}", second)
                    else do
                        return result
                    afterHour = false

                case '/', '-', ':', ' ', ',':
                    for count do
                        result.text += token.value

                default:
                    return result
                }

                at = end
            }

            result.omitted = false
            return result
        }

        var result = FormattedCell{String.from(stored)}
        if .code == "General" or .code == "@" or not stored.count do
            return result
        result.omitted = true
        let number = catch StrConv.toF64(stored) { return result; }
        if not Math.isFinite(number) or .code.isEmpty() do
            return result
        let decoded = .tokens(number)
        if not decoded.valid do
            return result
        let items = decoded.items.toSlice()
        var date  = false
        for token in items where not token.literal and
                                 (token.value == 'y'u8 or token.value == 'm'u8 or token.value == 'd'u8 or token.value == 'h'u8 or token.value == 's'u8) do
            date = true
        if date
        {
            let formatted = dateText(items, number, date1904)
            return formatted.omitted ? result : formatted
        }

        var first   = Swag.U64.Max
        var last    = 0'u64
        var percent = 0'u32
        for token, index in items where not token.literal
        {
            if token.value == '%'u8 do
                percent += 1
            if token.value == '0'u8 or token.value == '#'u8
            {
                if first == Swag.U64.Max do
                    first = index
                last = index
            }
        }

        if percent > 1 do
            return result

        // An unescaped fraction, exponent or text placeholder must not masquerade as a suffix.
        for token, index in items where not token.literal and
                                        (first == Swag.U64.Max or index < first or index > last)
        {
            let value = token.value
            if value == ','u8 and (first == Swag.U64.Max or index < first) do
                return result
            if value < 128 and
               value != ' 'u8 and
               value != '$'u8 and
               value != '%'u8 and
               value != '('u8 and
               value != ')'u8 and
               value != '+'u8 and
               value != '-'u8 and
               value != ','u8 do
                return result
        }

        if first == Swag.U64.Max
        {
            result.text.clear()
            for token in items do
                result.text += token.value
            result.omitted = false
            return result
        }

        var decimals         = 0'u8
        var requiredDecimals = 0'u8
        var integerZeros     = 0'u32
        var fractional       = false
        var grouped          = false
        for index in first until last + 1
        {
            let token = items[index]
            if token.literal do
                return result
            switch token.value
            {
            case '.':
                if fractional do
                    return result
                fractional = true

            case ',':
                if fractional do
                    return result
                grouped = true

            case '0', '#':
                if fractional
                {
                    decimals += 1
                    if token.value == '0'u8
                    {
                        if requiredDecimals + 1 != decimals do
                            return result
                        requiredDecimals += 1
                    }

                    if decimals > 12 do
                        return result
                }
                elif token.value == '0'u8
                {
                    integerZeros += 1
                }

            default:
                return result
            }
        }

        if not integerZeros or integerZeros >= 32 or (grouped and integerZeros > 1) do
            return result
        var magnitude   = Math.abs(number) * (percent ? 100.0'f64 : 1.0'f64)
        var suffixStart = last + 1

        // Trailing commas scale thousands; interior commas group digits.
        while suffixStart < items.count and
              not items[suffixStart].literal and
              items[suffixStart].value == ','u8
        {
            magnitude   /= 1000
            suffixStart += 1
        }

        var scale = 1.0'f64
        for decimals do
            scale *= 10
        if magnitude > 1.0e18 / scale do
            return result
        let info: Globalization.NumberFormatInfo
        var digits = info.format(magnitude, decimals, grouped)
        if decimals > requiredDecimals
        {
            var end      = digits.count
            var optional = decimals - requiredDecimals
            while optional and end and digits[end - 1] == '0'u8
            {
                end      -= 1
                optional -= 1
            }

            if end and digits[end - 1] == '.'u8 do
                end -= 1
            digits.removeBack(digits.count - end)
        }

        if not grouped and integerZeros > 1 and integerZeros < 32
        {
            let dot   = Utf8.indexOf(digits, '.'rune)
            let whole = dot == Swag.U64.Max ? digits.count : dot
            if whole < integerZeros
            {
                var padded: String
                for integerZeros - whole do
                    padded += '0'u8
                padded += digits
                digits = #move padded
            }
        }

        result.text.clear()
        if number < 0 and not decoded.negativeSection do
            result.text += '-'
        for index in 0 until first do
            result.text += items[index].value
        result.text += digits
        for index in suffixStart until items.count do
            result.text += items[index].value
        result.omitted = false
        return result
    }
}
