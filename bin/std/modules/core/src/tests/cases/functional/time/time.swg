#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.require(Time.TicksPerMillisecond == 10000)
    Swag.require(Time.TicksPerSecond == 10000000)
    Swag.require(Time.TicksPerMinute == 600000000)
    Swag.require(Time.TicksPerHour == 36000000000)
    Swag.require(Time.TicksPerDay == 864000000000)

    Swag.require(Time.MillisecondsPerSecond == 1000)
    Swag.require(Time.MillisecondsPerMinute == 60000)
    Swag.require(Time.MillisecondsPerHour == 3600000)
    Swag.require(Time.MillisecondsPerDay == 86400000)

    Swag.require(Time.DaysPerYear == 365)
    Swag.require(Time.DaysPer4Years == 1461)
    Swag.require(Time.DaysPer100Years == 36524)
    Swag.require(Time.DaysPer400Years == 146097)
}

#test
{
    Swag.require(not Time.isLeapYear(1))
    Swag.require(Time.isLeapYear(4))
    Swag.require(not Time.isLeapYear(100))
    Swag.require(Time.isLeapYear(400))
    Swag.require(not Time.isLeapYear(1900))
    Swag.require(Time.isLeapYear(2000))
    Swag.require(not Time.isLeapYear(2023))
    Swag.require(Time.isLeapYear(2024))
}

#test
{
    const days365 = [31'u16, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    const days366 = [31'u16, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    for i in 12
    {
        let month = cast(u16, i) + 1
        Swag.require(Time.daysInMonth(2023, month) == days365[i])
        Swag.require(Time.daysInMonth(2024, month) == days366[i])
    }
}

#test
{
    Swag.require(Time.timeToTicks(0, 0, 0, 0) == 0)
    Swag.require(Time.timeToTicks(0, 0, 0, 1) == Time.TicksPerMillisecond)
    Swag.require(Time.timeToTicks(0, 0, 1, 0) == Time.TicksPerSecond)
    Swag.require(Time.timeToTicks(0, 1, 0, 0) == Time.TicksPerMinute)
    Swag.require(Time.timeToTicks(1, 0, 0, 0) == Time.TicksPerHour)
    Swag.require(Time.timeToTicks(1, 2, 3, 4) == 37230040000)
    Swag.require(Time.timeToTicks(23, 59, 59, 999) == Time.TicksPerDay - Time.TicksPerMillisecond)

    let midnight = Time.ticksToTime(0)
    Swag.require(midnight.hour == 0)
    Swag.require(midnight.minute == 0)
    Swag.require(midnight.second == 0)
    Swag.require(midnight.millisecond == 0)

    let time = Time.ticksToTime(Time.timeToTicks(23, 59, 58, 987))
    Swag.require(time.hour == 23)
    Swag.require(time.minute == 59)
    Swag.require(time.second == 58)
    Swag.require(time.millisecond == 987)

    let wrapped = Time.ticksToTime(Time.TicksPerDay + Time.timeToTicks(1, 2, 3, 4))
    Swag.require(wrapped.hour == 1)
    Swag.require(wrapped.minute == 2)
    Swag.require(wrapped.second == 3)
    Swag.require(wrapped.millisecond == 4)
}

#test
{
    Swag.require(Time.dateToTicks(1, 1, 1) == 0)
    Swag.require(Time.dateToTicks(1970, 1, 1) == Time.DaysTo1970 * Time.TicksPerDay)
    Swag.require(Time.dateToTicks(1601, 1, 1) == Time.DaysTo1601 * Time.TicksPerDay)

    let first = Time.ticksToDate(0)
    Swag.require(first.year == 1)
    Swag.require(first.month == 1)
    Swag.require(first.day == 1)

    let leapDay = Time.ticksToDate(Time.dateToTicks(2000, 2, 29))
    Swag.require(leapDay.year == 2000)
    Swag.require(leapDay.month == 2)
    Swag.require(leapDay.day == 29)

    let century = Time.ticksToDate(Time.dateToTicks(1900, 3, 1))
    Swag.require(century.year == 1900)
    Swag.require(century.month == 3)
    Swag.require(century.day == 1)

    let end = Time.ticksToDate(Time.dateToTicks(9999, 12, 31))
    Swag.require(end.year == 9999)
    Swag.require(end.month == 12)
    Swag.require(end.day == 31)
}

#test
{
    let outOfRangeTicks  = Time.MaxTicks + 1
    let rejectedOverflow = Swag.catchPanic(func|outOfRangeTicks|() { discard Time.ticksToDate(outOfRangeTicks) }).raised
    Swag.require(rejectedOverflow)
}

#test
{
    for monthIdx in 12
    {
        let month = cast(u16, monthIdx) + 1
        let day   = Time.daysInMonth(2024, month)
        let date  = Time.ticksToDate(Time.dateToTicks(2024, month, day))
        Swag.require(date.year == 2024)
        Swag.require(date.month == month)
        Swag.require(date.day == day)
    }
}
