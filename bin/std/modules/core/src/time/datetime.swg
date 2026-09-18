#global public
#global namespace Time

using Errors

// English month names, used for formatting and parsing.
internal const MonthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

// English day names, used for formatting and parsing.
internal const DayOfWeekNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

// Identifies a day of the week.
enum DayOfWeek
{
    Sunday    = 0
    Monday    = 1
    Tuesday   = 2
    Wednesday = 3
    Thursday  = 4
    Friday    = 5
    Saturday  = 6
}

// Selects the text layout [[Core.Time.DateTime.toString]] produces.
enum DateTimeFormat
{
    DateIso           // 'YYYY-MM-DD'
    TimeIso           // 'HH:MM:SS'
    TimeIsoMs         // 'HH:MM:SS.ZZZ'
    TimeIsoHm         // 'HH:MM'
    Date              // 'DAYOFWEEK MONTH DAY YYYY'
    DateTime          // 'DAYOFWEEK MONTH DAY YYYY HH:MM:SS'
    DateTimeMs        // 'DAYOFWEEK MONTH DAY YYYY HH:MM:SS.ZZZ'
    DateTimeIso       // 'YYYY-MM-DD HH:MM:SS'
    DateTimeIsoMs     // 'YYYY-MM-DD HH:MM:SS.ZZZ'
    DateTimeIsoHm     // 'YYYY-MM-DD HH:MM'
}

internal enum WallClockKind
{
    Utc
    Local
}

internal struct WallClockFields
{
    year:        u16
    month:       u16
    day:         u16
    hour:        u16
    minute:      u16
    second:      u16
    millisecond: u16
}

// Stores a calendar date and a time of day, without a time zone.
#[Swag.Operators(opEquals, opCompare), Serialization.Final]
struct DateTime
{
    public
    {
        year:        u16     // Year component (1 to 9999)
        month:       u16     // Month component (1 to 12)
        day:         u16     // Day component (1 to 31 depending on the month)
        hour:        u16     // Hour component (0 to 23)
        minute:      u16     // Minute component (0 to 59)
        second:      u16     // Second component (0 to 59)
        millisecond: u16     // Millisecond component (0 to 999)
    }
}

impl DateTime
{
    internal mtd setWallClock(fields: WallClockFields)
    {
        .year        = fields.year
        .month       = fields.month
        .day         = fields.day
        .hour        = fields.hour
        .minute      = fields.minute
        .second      = fields.second
        .millisecond = fields.millisecond
    }

    // Returns the current UTC date and time.
    func utcNow()->DateTime
    {
        var result: retval
        result.setWallClock(readWallClock(.Utc))
        return result
    }

    // Returns the current local date and time.
    func now()->DateTime
    {
        var result: retval
        result.setWallClock(readWallClock(.Local))
        return result
    }

    // Replaces this value with the current local date and time.
    mtd setNow()
    {
        .setWallClock(readWallClock(.Local))
    }

    // Returns whether every component is in range and the day exists in its month.
    mtd const isValid()->bool
    {
        if .year == 0 or .year > 9999 do
            return false
        if .month == 0 or .month > 12 do
            return false
        if .day == 0 or .day > daysInMonth(.year, .month) do
            return false
        if .hour >= 24 do
            return false
        if .minute >= 60 do
            return false
        if .second >= 60 do
            return false
        if .millisecond >= 1000 do
            return false
        return true
    }

    // Returns the day of the week of this date.
    mtd const dayOfWeek()->DayOfWeek
    {
        let m: u32 = (.month + 9) % 12
        let y: u32 = .year - m / 10
        var dn     = 365 * y + #wrap y / 4 + #wrap y / 400 + #wrap (m * 306 + 5) / 10 + #wrap .day - 1 - #wrap y / 100
        dn += 3
        return cast(DayOfWeek) (dn % 7)
    }

    // Returns the English name of `month`, numbered from 1 to 12.
    func monthName(month: u16)->string
    {
        Swag.assert(month >= 1 and month <= 12)
        return MonthNames[month - 1]
    }

    // Returns the English name of `day`.
    func dayOfWeekName(day: DayOfWeek)->string => DayOfWeekNames[cast(u32) day]

    // Parses an 8-bit unsigned integer from the buffer and adds the consumed bytes to `eat`.
    internal func parseU8(buf: *string, eat: *u32)->u16 fail
    {
        let {value, eat0, ovf} = try StrConv.parseU8(buf[])
        if ovf do
            fail SyntaxError{}
        eat[] += eat0
        buf[] = Tokenize.eatCount(buf[], cast(u64) eat0)
        return value
    }

    // Parses a 16-bit unsigned integer from the buffer and adds the consumed bytes to `eat`.
    internal func parseU16(buf: *string, eat: *u32)->u16 fail
    {
        let {value, eat0, ovf} = try StrConv.parseU16(buf[])
        if ovf do
            fail SyntaxError{}
        eat[] += eat0
        buf[] = Tokenize.eatCount(buf[], cast(u64) eat0)
        return value
    }

    // Parses the separator `sep` from the buffer and adds the consumed byte to `eat`.
    internal func parseSep(buf: *string, sep: u8, eat: *u32) fail
    {
        let view = buf[]
        if not view.count or view[0] != sep do
            fail SyntaxError{}
        buf[] = Tokenize.eatCount(view, 1)
        eat[] += 1
    }

    // Parses a date, optionally followed by a time, at the start of `str` and returns it with the number of bytes consumed.
    //
    // The date is either `YYYY-MM-DD` or `DAYOFWEEK MONTH DAY YYYY` with English names, and the
    // time, after one space, is `HH:MM`, optionally followed by `:SS` and `.ZZZ`. These are the
    // layouts [[Core.Time.DateTime.toString]] writes. With `checkDate`, the day of the week
    // must match the date and every component must be in range. Fails with a
    // [[Core.Errors.SyntaxError]] otherwise.
    func parse(str: string, checkDate = true)->{ value: DateTime, eat: u32 } fail
    {
        var result: retval
        var buf = str

        if not buf.count do
            fail SyntaxError{}

        if buf.count >= 1 and
           Latin1.isLetter(buf[0])
        {
            // Day of week name
            var done = false
            var dayOfWeek: DayOfWeek
            for dow, idx in DayOfWeekNames
            {
                let len = dow.count
                if buf[until Math.min(buf.count, len)] == dow
                {
                    dayOfWeek  = cast() idx
                    buf        = Tokenize.eatCount(buf, cast(u64) len)
                    result.eat += cast(u32) len
                    done       = true
                    break
                }
            }

            if not done do
                fail SyntaxError{}

            done = false
            try parseSep(&buf, ' ', &result.eat)

            // Month name
            for name, idx in MonthNames
            {
                let len = name.count
                if buf[until Math.min(buf.count, len)] == name
                {
                    result.value.month = cast(u16) idx + 1
                    buf                = Tokenize.eatCount(buf, cast(u64) len)
                    result.eat         += cast(u32) len
                    done               = true
                    break
                }
            }

            if not done do
                fail SyntaxError{}

            try parseSep(&buf, ' ', &result.eat)
            result.value.day = try parseU8(&buf, &result.eat)
            try parseSep(&buf, ' ', &result.eat)
            result.value.year = try parseU16(&buf, &result.eat)

            // Check day of week
            if checkDate and dayOfWeek != result.value.dayOfWeek() do
                fail SyntaxError{}
        }
        elif buf.count >= 10 and
             Latin1.isDigit(buf[0]) and
             Latin1.isDigit(buf[1]) and
             Latin1.isDigit(buf[2]) and
             Latin1.isDigit(buf[3]) and
             buf[4] == '-' and
             Latin1.isDigit(buf[5]) and
             Latin1.isDigit(buf[6]) and
             buf[7] == '-' and
             Latin1.isDigit(buf[8]) and
             Latin1.isDigit(buf[9])
        {
            result.value.year = try parseU16(&buf, &result.eat)
            try parseSep(&buf, '-', &result.eat)
            result.value.month = try parseU8(&buf, &result.eat)
            try parseSep(&buf, '-', &result.eat)
            result.value.day = try parseU8(&buf, &result.eat)
        }
        else
        {
            fail SyntaxError{}
        }

        if buf.count >= 1 and
           buf[0] == ' '
        {
            try parseSep(&buf, ' ', &result.eat)
        }

        // Time
        if buf.count >= 5 and
           Latin1.isDigit(buf[0]) and
           Latin1.isDigit(buf[1]) and
           buf[2] == ':' and
           Latin1.isDigit(buf[3]) and
           Latin1.isDigit(buf[4])
        {
            result.value.hour = try parseU8(&buf, &result.eat)
            try parseSep(&buf, ':', &result.eat)
            result.value.minute = try parseU8(&buf, &result.eat)

            // Seconds
            if buf.count >= 3 and
               buf[0] == ':' and
               Latin1.isDigit(buf[1]) and
               Latin1.isDigit(buf[2])
            {
                try parseSep(&buf, ':', &result.eat)
                result.value.second = try parseU8(&buf, &result.eat)
            }

            // Milliseconds
            if buf.count >= 2 and
               buf[0] == '.' and
               Latin1.isDigit(buf[1])
            {
                try parseSep(&buf, '.', &result.eat)
                let start    = result.eat
                var fraction = cast(u32) (try parseU16(&buf, &result.eat))
                var digits   = result.eat - start
                while digits < 3
                {
                    fraction *= 10
                    digits += 1
                }

                while digits > 3
                {
                    fraction /= 10
                    digits -= 1
                }

                result.value.millisecond = cast(u16) fraction
            }
        }

        if checkDate and not result.value.isValid() do
            fail SyntaxError{}

        return result
    }

    // Returns this value as text in the layout `fmt` selects.
    mtd const toString(fmt = DateTimeFormat.DateTime)->String
    {
        switch #complete fmt
        {
        case .DateIso:       return Format.toString("%-%{02}-%{02}", .year, .month, .day)
        case .TimeIso:       return Format.toString("%{02}:%{02}:%{02}", .hour, .minute, .second)
        case .TimeIsoMs:     return Format.toString("%{02}:%{02}:%{02}.%{03}", .hour, .minute, .second, .millisecond)
        case .TimeIsoHm:     return Format.toString("%{02}:%{02}", .hour, .minute)
        case .Date:          return Format.toString("% % % %", dayOfWeekName(.dayOfWeek()), monthName(.month), .day, .year)
        case .DateTime:      return Format.toString("% % % % %{02}:%{02}:%{02}", dayOfWeekName(.dayOfWeek()), monthName(.month), .day, .year, .hour, .minute, .second)
        case .DateTimeMs:    return Format.toString("% % % % %{02}:%{02}:%{02}.%{03}", dayOfWeekName(.dayOfWeek()), monthName(.month), .day, .year, .hour, .minute, .second, .millisecond)
        case .DateTimeIso:   return Format.toString("%-%{02}-%{02} %{02}:%{02}:%{02}", .year, .month, .day, .hour, .minute, .second)
        case .DateTimeIsoMs: return Format.toString("%-%{02}-%{02} %{02}:%{02}:%{02}.%{03}", .year, .month, .day, .hour, .minute, .second, .millisecond)
        case .DateTimeIsoHm: return Format.toString("%-%{02}-%{02} %{02}:%{02}", .year, .month, .day, .hour, .minute)
        }
    }
}

impl Serialization.ISerialize for DateTime
{
    // Reads the value from the text written by `write`; a binary decoder reads the fields instead.
    mtd impl read(decoder: Serialization.IDecoder)->bool fail
    {
        if decoder.isTextual()
        {
            let val = try decoder.readString()
            me[] = try parse(val).value
            return true
        }

        return false
    }

    // Writes the value as [[Core.Time.DateTimeFormat.DateTimeIsoMs]] text; a binary encoder writes the fields instead.
    mtd impl write(encoder: Serialization.IEncoder)->bool fail
    {
        if not encoder.isTextual() do
            return false
        encoder.writeString(.toString(.DateTimeIsoMs))
        return true
    }

    mtd impl readElement(type: Swag.TypeValue, data: *void?, decoder: Serialization.IDecoder)->bool fail => false

    mtd impl writeElement(type: Swag.TypeValue, data: const *void?, decoder: Serialization.IEncoder)->bool fail => false

    mtd impl postRead(data: *void?, decoder: Serialization.IDecoder) fail {}
}

impl StrConv.IConvert for DateTime
{
    // Appends the layout a one-letter format selects, [[Core.Time.DateTimeFormat.DateTime]] by default.
    //
    // The letters `a` to `j` select, in order, `DateTime`, `DateTimeMs`, `DateTimeIso`,
    // `DateTimeIsoMs`, `DateTimeIsoHm`, `DateIso`, `TimeIso`, `TimeIsoMs`, `TimeIsoHm`, and
    // `Date`. Any other format uses the default.
    mtd const impl convert(buf: *ConcatBuffer, convFormat: StrConv.ConvertFormat, strFormat: string?)
    {
        var fmt = DateTimeFormat.DateTime
        if strFormat.count == 1
        {
            switch strFormat![0]
            {
            case 'b': fmt = .DateTimeMs
            case 'c': fmt = .DateTimeIso
            case 'd': fmt = .DateTimeIsoMs
            case 'e': fmt = .DateTimeIsoHm
            case 'f': fmt = .DateIso
            case 'g': fmt = .TimeIso
            case 'h': fmt = .TimeIsoMs
            case 'i': fmt = .TimeIsoHm
            case 'j': fmt = .Date
            }
        }

        buf.addBytes(.toString(fmt))
    }
}
