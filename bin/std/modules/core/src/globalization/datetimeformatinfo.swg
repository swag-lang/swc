#global namespace Globalization

using Swag

// Selects the component order of a short date.
public enum DateOrder
{
    MonthDayYear     // Month, day, then year.
    DayMonthYear     // Day, month, then year.
    YearMonthDay     // Year, month, then day.
}

// Provides culture-specific names and patterns for dates and times.
public struct DateTimeFormatInfo
{
    public
    {
        monthNames:       [12] string = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]     // Full month names borrowed from the culture profile.
        dayNames:         [7] string  = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]                                                 // Full day names borrowed from the culture profile.
        shortDatePattern: string      = "MM/dd/yyyy"                                                                                                                   // Human-readable short-date pattern.
        longDatePattern:  string      = "dddd, MMMM d, yyyy"                                                                                                           // Human-readable long-date pattern.
        shortTimePattern: string      = "h:mm tt"                                                                                                                      // Human-readable short-time pattern.
        longTimePattern:  string      = "h:mm:ss tt"                                                                                                                   // Human-readable long-time pattern.
        dateSeparator:    u8          = '/'                                                                                                                            // Separator used by short numeric dates.
        timeSeparator:    u8          = ':'                                                                                                                            // Separator used by clock values.
        dateOrder:        DateOrder                                                                                                                                    // Component order used by short dates.
        uses24Hour:       bool                                                                                                                                         // Whether clock values use a 24-hour cycle.
        amDesignator:     string      = "AM"                                                                                                                           // Suffix used before noon in a 12-hour cycle.
        pmDesignator:     string      = "PM"                                                                                                                           // Suffix used from noon in a 12-hour cycle.
    }
}

public impl DateTimeFormatInfo
{
    // Returns the localized full name of a month numbered from 1 through 12.
    mtd const monthName(month: u16)->string
    {
        Debug.assert(month >= 1 and month <= 12, "month is outside the supported range")
        return .monthNames[month - 1]
    }

    // Returns the localized full name of a day of the week.
    mtd const dayName(day: Time.DayOfWeek)->string => .dayNames[cast(u32) day]

    internal mtd const matches(pattern: string, index: u64, token: string)->bool
    {
        if index + @countof(token) > @countof(pattern) do
            return false
        return Utf8.compare(@mkslice(@dataof(pattern) + index, @countof(token)), @mkslice(@dataof(token), @countof(token)), .Latin1) == 0
    }

    internal mtd const formatPattern(value: Time.DateTime, pattern: string)->String
    {
        var result: retval
        var index = 0'u64
        while index < @countof(pattern)
        {
            if .matches(pattern, index, "dddd")
            {
                result.append(.dayName(value.dayOfWeek()))
                index += 4
            }
            elif .matches(pattern, index, "MMMM")
            {
                result.append(.monthName(value.month))
                index += 4
            }
            elif .matches(pattern, index, "yyyy")
            {
                result.append(Format.toString("%{04}", value.year))
                index += 4
            }
            elif .matches(pattern, index, "HH")
            {
                result.append(Format.toString("%{02}", value.hour))
                index += 2
            }
            elif .matches(pattern, index, "MM")
            {
                result.append(Format.toString("%{02}", value.month))
                index += 2
            }
            elif .matches(pattern, index, "dd")
            {
                result.append(Format.toString("%{02}", value.day))
                index += 2
            }
            elif .matches(pattern, index, "mm")
            {
                result.append(Format.toString("%{02}", value.minute))
                index += 2
            }
            elif .matches(pattern, index, "ss")
            {
                result.append(Format.toString("%{02}", value.second))
                index += 2
            }
            elif .matches(pattern, index, "tt")
            {
                let designator = value.hour < 12 ? .amDesignator : .pmDesignator
                result.append(designator)
                index += 2
            }
            elif pattern[index] == 'h'
            {
                let hour = value.hour % 12 ? value.hour % 12 : 12
                result.append(Format.toString("%", hour))
                index += 1
            }
            elif pattern[index] == 'H'
            {
                result.append(Format.toString("%", value.hour))
                index += 1
            }
            elif pattern[index] == 'M'
            {
                result.append(Format.toString("%", value.month))
                index += 1
            }
            elif pattern[index] == 'd'
            {
                result.append(Format.toString("%", value.day))
                index += 1
            }
            elif pattern[index] == '/'
            {
                result.append(.dateSeparator)
                index += 1
            }
            elif pattern[index] == ':'
            {
                result.append(.timeSeparator)
                index += 1
            }
            else
            {
                result.append(pattern[index])
                index += 1
            }
        }

        return result
    }

    // Formats a date using [[shortDatePattern]] or [[longDatePattern]].
    mtd const formatDate(value: Time.DateTime, long = false)->String
    {
        Debug.assert(value.isValid(), "cannot format an invalid date")
        let pattern = long ? .longDatePattern : .shortDatePattern
        return .formatPattern(value, pattern)
    }

    // Formats a clock value using [[shortTimePattern]] or [[longTimePattern]].
    mtd const formatTime(value: Time.DateTime, withSeconds = true)->String
    {
        Debug.assert(value.isValid(), "cannot format an invalid time")
        let pattern = withSeconds ? .longTimePattern : .shortTimePattern
        return .formatPattern(value, pattern)
    }

    // Formats a date and time separated by one space.
    mtd const formatDateTime(value: Time.DateTime, longDate = false, withSeconds = true)->String
    {
        return Format.toString("% %", .formatDate(value, longDate), .formatTime(value, withSeconds))
    }
}
