#global public
#global namespace Time

// Stores a calendar instant as 100-nanosecond ticks since 0001-01-01 00:00:00.
#[Swag.Operators(opCompare)]
struct Timestamp
{
    public readonly ticks: Ticks     // Number of ticks since the documented epoch.
}

impl Timestamp
{
    // Captures the current wall-clock time.
    func now()->Timestamp
    {
        return fromDateTime(DateTime.now())
    }

    // Captures the current UTC wall-clock time.
    func utcNow()->Timestamp
    {
        return fromDateTime(DateTime.utcNow())
    }

    // Replaces this value with the current wall-clock time.
    mtd setNow()
    {
        me = now()
    }

    // Creates a timestamp from raw ticks since 0001-01-01 00:00:00.
    func fromTicks(ticks: Ticks)->Timestamp
    {
        Debug.assert(ticks <= MaxTicks)
        return Timestamp{ticks}
    }

    // Creates a timestamp from a valid calendar date and time.
    func fromDateTime(dateTime: DateTime)->Timestamp
    {
        Debug.assert(dateTime.isValid())
        var result: retval = undefined
        result.ticks = dateToTicks(dateTime.year, dateTime.month, dateTime.day)
        result.ticks += timeToTicks(dateTime.hour, dateTime.minute, dateTime.second, dateTime.millisecond)
        return result
    }

    // Converts the timestamp to calendar components.
    mtd const toDateTime()->DateTime
    {
        var dateTime: retval = undefined
        {dateTime.year, dateTime.month, dateTime.day} = ticksToDate(.ticks)
        {dateTime.hour, dateTime.minute, dateTime.second, dateTime.millisecond} = ticksToTime(.ticks)
        return dateTime
    }

    // Shifts the calendar year, clamping a leap day when necessary.
    mtd addYears(years: s32)
    {
        Debug.assert(-10000 <= years and years <= 10000, "overflow")
        .addMonths(years * 12)
    }

    // Shifts the calendar month, clamping the day when necessary.
    mtd addMonths(months: s32)
    {
        Debug.assert(-120000 <= months and months <= 120000, "overflow")
        var {y, m, d} = ticksToDate(.ticks)
        var year      = cast(s32) y
        let i         = cast(s32) (m - 1) + months
        if i >= 0
        {
            m    = cast(u16) (i % 12 + 1)
            year += i / 12
        }
        else
        {
            m    = cast(u16) (12 + (i + 1) % 12)
            year += (i - 11) / 12
        }

        Debug.assert(1 <= year and year <= 9999, "overflow")
        y = cast(u16) year
        let days = daysInMonth(y, m)
        if d > days do
            d = days
        .ticks = dateToTicks(y, m, d) + (.ticks % TicksPerDay)
    }

    // Shifts the timestamp by whole 24-hour days.
    mtd addDays(days: s32)
    {
        if days > 0 do
            .add(cast(u32) days, MillisecondsPerDay)
        else do
            .remove(cast(u32) -cast(s64) days, MillisecondsPerDay)
    }

    // Shifts the timestamp by whole hours.
    mtd addHours(hours: s32)
    {
        if hours > 0 do
            .add(cast(u32) hours, MillisecondsPerHour)
        else do
            .remove(cast(u32) -cast(s64) hours, MillisecondsPerHour)
    }

    // Shifts the timestamp by whole minutes.
    mtd addMinutes(minutes: s32)
    {
        if minutes > 0 do
            .add(cast(u32) minutes, MillisecondsPerMinute)
        else do
            .remove(cast(u32) -cast(s64) minutes, MillisecondsPerMinute)
    }

    // Shifts the timestamp by whole seconds.
    mtd addSeconds(seconds: s32)
    {
        if seconds > 0 do
            .add(cast(u32) seconds, MillisecondsPerSecond)
        else do
            .remove(cast(u32) -cast(s64) seconds, MillisecondsPerSecond)
    }

    // Shifts the timestamp by whole milliseconds.
    mtd addMilliseconds(milliseconds: s32)
    {
        if milliseconds > 0 do
            .add(cast(u32) milliseconds, 1)
        else do
            .remove(cast(u32) -cast(s64) milliseconds, 1)
    }

    // Returns days elapsed since the timestamp epoch.
    mtd const totalDays()->f64 => .ticks * (1.0'f64 / TicksPerDay)

    // Returns hours elapsed since the timestamp epoch.
    mtd const totalHours()->f64 => .ticks * (1.0'f64 / TicksPerHour)

    // Returns minutes elapsed since the timestamp epoch.
    mtd const totalMinutes()->f64 => .ticks * (1.0'f64 / TicksPerMinute)

    // Returns seconds elapsed since the timestamp epoch.
    mtd const totalSeconds()->f64 => .ticks * (1.0'f64 / TicksPerSecond)

    // Returns milliseconds elapsed since the timestamp epoch.
    mtd const totalMilliseconds()->f64 => .ticks * (1.0'f64 / TicksPerMillisecond)

    // Adds a scaled millisecond interval.
    private mtd add(value: u32, scale: u64)
    {
        var millis = value * scale
        Debug.assert(millis <= MaxMillisecondsToYear10000, "overflow")
        millis *= TicksPerMillisecond
        Debug.assert(millis <= (MaxTicks - .ticks), "overflow")
        .ticks += millis
    }

    // Subtracts a scaled millisecond interval.
    private mtd remove(value: u32, scale: u64)
    {
        var millis = value * scale
        Debug.assert(millis <= MaxMillisecondsToYear10000, "overflow")
        millis *= TicksPerMillisecond
        Debug.assert(millis <= .ticks, "ticks overflow")
        .ticks -= millis
    }
}
