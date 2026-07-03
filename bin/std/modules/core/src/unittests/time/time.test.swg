#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

#test
{
    @assert(Time.TicksPerMilliSecond == 10000)
    @assert(Time.TicksPerSecond == 10000000)
    @assert(Time.TicksPerMinute == 600000000)
    @assert(Time.TicksPerHour == 36000000000)
    @assert(Time.TicksPerDay == 864000000000)

    @assert(Time.MillisPerSecond == 1000)
    @assert(Time.MillisPerMinute == 60000)
    @assert(Time.MillisPerHour == 3600000)
    @assert(Time.MillisPerDay == 86400000)

    @assert(Time.DaysPerYear == 365)
    @assert(Time.DaysPer4Years == 1461)
    @assert(Time.DaysPer100Years == 36524)
    @assert(Time.DaysPer400Years == 146097)
}

#test
{
    @assert(!Time.isLeapYear(1))
    @assert(Time.isLeapYear(4))
    @assert(!Time.isLeapYear(100))
    @assert(Time.isLeapYear(400))
    @assert(!Time.isLeapYear(1900))
    @assert(Time.isLeapYear(2000))
    @assert(!Time.isLeapYear(2023))
    @assert(Time.isLeapYear(2024))
}

#test
{
    const days365 = [31'u16, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    const days366 = [31'u16, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    for i in 12
    {
        let month = cast(u16) i + 1
        @assert(Time.daysInMonth(2023, month) == days365[i])
        @assert(Time.daysInMonth(2024, month) == days366[i])
    }
}

#test
{
    @assert(Time.timeToTicks(0, 0, 0, 0) == 0)
    @assert(Time.timeToTicks(0, 0, 0, 1) == Time.TicksPerMilliSecond)
    @assert(Time.timeToTicks(0, 0, 1, 0) == Time.TicksPerSecond)
    @assert(Time.timeToTicks(0, 1, 0, 0) == Time.TicksPerMinute)
    @assert(Time.timeToTicks(1, 0, 0, 0) == Time.TicksPerHour)
    @assert(Time.timeToTicks(1, 2, 3, 4) == 37230040000)
    @assert(Time.timeToTicks(23, 59, 59, 999) == Time.TicksPerDay - Time.TicksPerMilliSecond)

    let midnight = Time.ticksToTime(0)
    @assert(midnight.hour == 0)
    @assert(midnight.minute == 0)
    @assert(midnight.second == 0)
    @assert(midnight.millisecond == 0)

    let time = Time.ticksToTime(Time.timeToTicks(23, 59, 58, 987))
    @assert(time.hour == 23)
    @assert(time.minute == 59)
    @assert(time.second == 58)
    @assert(time.millisecond == 987)

    let wrapped = Time.ticksToTime(Time.TicksPerDay + Time.timeToTicks(1, 2, 3, 4))
    @assert(wrapped.hour == 1)
    @assert(wrapped.minute == 2)
    @assert(wrapped.second == 3)
    @assert(wrapped.millisecond == 4)
}

#test
{
    @assert(Time.dateToTicks(1, 1, 1) == 0)
    @assert(Time.dateToTicks(1970, 1, 1) == Time.DaysTo1970 * Time.TicksPerDay)
    @assert(Time.dateToTicks(1601, 1, 1) == Time.DaysTo1601 * Time.TicksPerDay)

    let first = Time.ticksToDate(0)
    @assert(first.year == 1)
    @assert(first.month == 1)
    @assert(first.day == 1)

    let leapDay = Time.ticksToDate(Time.dateToTicks(2000, 2, 29))
    @assert(leapDay.year == 2000)
    @assert(leapDay.month == 2)
    @assert(leapDay.day == 29)

    let century = Time.ticksToDate(Time.dateToTicks(1900, 3, 1))
    @assert(century.year == 1900)
    @assert(century.month == 3)
    @assert(century.day == 1)

    let end = Time.ticksToDate(Time.dateToTicks(9999, 12, 31))
    @assert(end.year == 9999)
    @assert(end.month == 12)
    @assert(end.day == 31)
}

#test
{
    for monthIdx in 12
    {
        let month = cast(u16) monthIdx + 1
        let day   = Time.daysInMonth(2024, month)
        let date  = Time.ticksToDate(Time.dateToTicks(2024, month, day))
        @assert(date.year == 2024)
        @assert(date.month == month)
        @assert(date.day == day)
    }
}
