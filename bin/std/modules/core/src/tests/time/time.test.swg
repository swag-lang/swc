#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.assert(Time.TicksPerMillisecond == 10000)
    Swag.assert(Time.TicksPerSecond == 10000000)
    Swag.assert(Time.TicksPerMinute == 600000000)
    Swag.assert(Time.TicksPerHour == 36000000000)
    Swag.assert(Time.TicksPerDay == 864000000000)

    Swag.assert(Time.MillisecondsPerSecond == 1000)
    Swag.assert(Time.MillisecondsPerMinute == 60000)
    Swag.assert(Time.MillisecondsPerHour == 3600000)
    Swag.assert(Time.MillisecondsPerDay == 86400000)

    Swag.assert(Time.DaysPerYear == 365)
    Swag.assert(Time.DaysPer4Years == 1461)
    Swag.assert(Time.DaysPer100Years == 36524)
    Swag.assert(Time.DaysPer400Years == 146097)
}

#test
{
    Swag.assert(!Time.isLeapYear(1))
    Swag.assert(Time.isLeapYear(4))
    Swag.assert(!Time.isLeapYear(100))
    Swag.assert(Time.isLeapYear(400))
    Swag.assert(!Time.isLeapYear(1900))
    Swag.assert(Time.isLeapYear(2000))
    Swag.assert(!Time.isLeapYear(2023))
    Swag.assert(Time.isLeapYear(2024))
}

#test
{
    const days365 = [31'u16, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    const days366 = [31'u16, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    for i in 12
    {
        let month = cast(u16) i + 1
        Swag.assert(Time.daysInMonth(2023, month) == days365[i])
        Swag.assert(Time.daysInMonth(2024, month) == days366[i])
    }
}

#test
{
    Swag.assert(Time.timeToTicks(0, 0, 0, 0) == 0)
    Swag.assert(Time.timeToTicks(0, 0, 0, 1) == Time.TicksPerMillisecond)
    Swag.assert(Time.timeToTicks(0, 0, 1, 0) == Time.TicksPerSecond)
    Swag.assert(Time.timeToTicks(0, 1, 0, 0) == Time.TicksPerMinute)
    Swag.assert(Time.timeToTicks(1, 0, 0, 0) == Time.TicksPerHour)
    Swag.assert(Time.timeToTicks(1, 2, 3, 4) == 37230040000)
    Swag.assert(Time.timeToTicks(23, 59, 59, 999) == Time.TicksPerDay - Time.TicksPerMillisecond)

    let midnight = Time.ticksToTime(0)
    Swag.assert(midnight.hour == 0)
    Swag.assert(midnight.minute == 0)
    Swag.assert(midnight.second == 0)
    Swag.assert(midnight.millisecond == 0)

    let time = Time.ticksToTime(Time.timeToTicks(23, 59, 58, 987))
    Swag.assert(time.hour == 23)
    Swag.assert(time.minute == 59)
    Swag.assert(time.second == 58)
    Swag.assert(time.millisecond == 987)

    let wrapped = Time.ticksToTime(Time.TicksPerDay + Time.timeToTicks(1, 2, 3, 4))
    Swag.assert(wrapped.hour == 1)
    Swag.assert(wrapped.minute == 2)
    Swag.assert(wrapped.second == 3)
    Swag.assert(wrapped.millisecond == 4)
}

#test
{
    Swag.assert(Time.dateToTicks(1, 1, 1) == 0)
    Swag.assert(Time.dateToTicks(1970, 1, 1) == Time.DaysTo1970 * Time.TicksPerDay)
    Swag.assert(Time.dateToTicks(1601, 1, 1) == Time.DaysTo1601 * Time.TicksPerDay)

    let first = Time.ticksToDate(0)
    Swag.assert(first.year == 1)
    Swag.assert(first.month == 1)
    Swag.assert(first.day == 1)

    let leapDay = Time.ticksToDate(Time.dateToTicks(2000, 2, 29))
    Swag.assert(leapDay.year == 2000)
    Swag.assert(leapDay.month == 2)
    Swag.assert(leapDay.day == 29)

    let century = Time.ticksToDate(Time.dateToTicks(1900, 3, 1))
    Swag.assert(century.year == 1900)
    Swag.assert(century.month == 3)
    Swag.assert(century.day == 1)

    let end = Time.ticksToDate(Time.dateToTicks(9999, 12, 31))
    Swag.assert(end.year == 9999)
    Swag.assert(end.month == 12)
    Swag.assert(end.day == 31)
}

#test
{
    for monthIdx in 12
    {
        let month = cast(u16) monthIdx + 1
        let day   = Time.daysInMonth(2024, month)
        let date  = Time.ticksToDate(Time.dateToTicks(2024, month, day))
        Swag.assert(date.year == 2024)
        Swag.assert(date.month == month)
        Swag.assert(date.day == day)
    }
}
