#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func expectDate(ticks: Time.Ticks, year, month, day: u16)
{
    let (actualYear, actualMonth, actualDay) = Time.ticksToDate(ticks)
    @assert(actualYear == year)
    @assert(actualMonth == month)
    @assert(actualDay == day)
}

func expectTime(ticks: Time.Ticks, hour, minute, second, millisecond: u16)
{
    let (actualHour, actualMinute, actualSecond, actualMillisecond) = Time.ticksToTime(ticks)
    @assert(actualHour == hour)
    @assert(actualMinute == minute)
    @assert(actualSecond == second)
    @assert(actualMillisecond == millisecond)
}

func expectDateTime(value: Time.DateTime, year, month, day, hour, minute, second, millisecond: u16)
{
    @assert(value.year == year)
    @assert(value.month == month)
    @assert(value.day == day)
    @assert(value.hour == hour)
    @assert(value.minute == minute)
    @assert(value.second == second)
    @assert(value.millisecond == millisecond)
}

#test
{
    @assert(Time.TicksPerMilliSecond == 10_000'u64)
    @assert(Time.TicksPerSecond == 10_000_000'u64)
    @assert(Time.TicksPerMinute == 600_000_000'u64)
    @assert(Time.TicksPerHour == 36_000_000_000'u64)
    @assert(Time.TicksPerDay == 864_000_000_000'u64)

    @assert(Time.timeToTicks(0, 0, 0, 0) == 0'u64)
    @assert(Time.timeToTicks(0, 0, 0, 1) == Time.TicksPerMilliSecond)
    @assert(Time.timeToTicks(0, 0, 1, 0) == Time.TicksPerSecond)
    @assert(Time.timeToTicks(0, 1, 0, 0) == Time.TicksPerMinute)
    @assert(Time.timeToTicks(1, 0, 0, 0) == Time.TicksPerHour)
    @assert(Time.timeToTicks(1, 2, 3, 4) == 37_230_040_000'u64)
    @assert(Time.timeToTicks(23, 59, 59, 999) == 863_999_990_000'u64)

    expectTime(0, 0, 0, 0, 0)
    expectTime(Time.TicksPerMilliSecond, 0, 0, 0, 1)
    expectTime(Time.TicksPerSecond, 0, 0, 1, 0)
    expectTime(Time.TicksPerMinute, 0, 1, 0, 0)
    expectTime(Time.TicksPerHour, 1, 0, 0, 0)
    expectTime(37_230_040_000'u64, 1, 2, 3, 4)
    expectTime(863_999_990_000'u64, 23, 59, 59, 999)
    expectTime(Time.TicksPerDay + 37_230_040_000'u64, 1, 2, 3, 4)
}

#test
{
    @assert(!Time.isLeapYear(1))
    @assert(Time.isLeapYear(4))
    @assert(!Time.isLeapYear(100))
    @assert(Time.isLeapYear(400))
    @assert(!Time.isLeapYear(1900))
    @assert(Time.isLeapYear(2000))
    @assert(Time.isLeapYear(2024))
    @assert(!Time.isLeapYear(2025))

    @assert(Time.daysInMonth(2023, 1) == 31)
    @assert(Time.daysInMonth(2023, 2) == 28)
    @assert(Time.daysInMonth(2023, 3) == 31)
    @assert(Time.daysInMonth(2023, 4) == 30)
    @assert(Time.daysInMonth(2023, 5) == 31)
    @assert(Time.daysInMonth(2023, 6) == 30)
    @assert(Time.daysInMonth(2023, 7) == 31)
    @assert(Time.daysInMonth(2023, 8) == 31)
    @assert(Time.daysInMonth(2023, 9) == 30)
    @assert(Time.daysInMonth(2023, 10) == 31)
    @assert(Time.daysInMonth(2023, 11) == 30)
    @assert(Time.daysInMonth(2023, 12) == 31)

    @assert(Time.daysInMonth(2024, 1) == 31)
    @assert(Time.daysInMonth(2024, 2) == 29)
    @assert(Time.daysInMonth(2024, 3) == 31)
    @assert(Time.daysInMonth(2024, 4) == 30)
    @assert(Time.daysInMonth(2024, 5) == 31)
    @assert(Time.daysInMonth(2024, 6) == 30)
    @assert(Time.daysInMonth(2024, 7) == 31)
    @assert(Time.daysInMonth(2024, 8) == 31)
    @assert(Time.daysInMonth(2024, 9) == 30)
    @assert(Time.daysInMonth(2024, 10) == 31)
    @assert(Time.daysInMonth(2024, 11) == 30)
    @assert(Time.daysInMonth(2024, 12) == 31)
}

#test
{
    @assert(Time.dateToTicks(1, 1, 1) == 0'u64)
    @assert(Time.dateToTicks(1, 1, 2) == 864_000_000_000'u64)
    @assert(Time.dateToTicks(4, 2, 29) == 997_056_000_000_000'u64)
    @assert(Time.dateToTicks(1970, 1, 1) == 621_355_968_000_000_000'u64)
    @assert(Time.dateToTicks(2000, 3, 1) == 630_874_656_000_000_000'u64)
    @assert(Time.dateToTicks(2024, 2, 29) == 638_447_616_000_000_000'u64)
    @assert(Time.dateToTicks(9999, 12, 31) == 3_155_378_112_000_000_000'u64)

    expectDate(0, 1, 1, 1)
    expectDate(864_000_000_000'u64, 1, 1, 2)
    expectDate(997_056_000_000_000'u64, 4, 2, 29)
    expectDate(621_355_968_000_000_000'u64, 1970, 1, 1)
    expectDate(630_874_656_000_000_000'u64, 2000, 3, 1)
    expectDate(638_447_616_000_000_000'u64, 2024, 2, 29)
    expectDate(3_155_378_112_000_000_000'u64, 9999, 12, 31)
}

#test
{
    let span = Time.TimeSpan.from(Time.DateTime{2024, 2, 29, 1, 2, 3, 4})
    @assert(span.ticks == Time.dateToTicks(2024, 2, 29) + Time.timeToTicks(1, 2, 3, 4))
    let dateTime = span.toDateTime()
    @assert(dateTime.month == 2)
    expectDateTime(dateTime, 2024, 2, 29, 1, 2, 3, 4)

    let twoDays = Time.TimeSpan{Time.TicksPerDay * 2}
    @assert(twoDays.totalDays() == 2)
    @assert(twoDays.totalHours() == 48)
    @assert(twoDays.totalMinutes() == 2880)
    @assert(twoDays.totalSeconds() == 172800)
    @assert(twoDays.totalMilliSeconds() == 172800000)

    @assert((Time.TimeSpan{1} <=> Time.TimeSpan{1}) == 0)
    @assert(Time.TimeSpan{1} < Time.TimeSpan{2})
    @assert(Time.TimeSpan{2} > Time.TimeSpan{1})
    @assert(Time.TimeSpan{2} >= Time.TimeSpan{2})
    @assert(Time.TimeSpan{1} <= Time.TimeSpan{1})
}

#test
{
    var span = Time.TimeSpan.from(Time.DateTime{2020, 1, 1, 0, 0, 0, 0})
    span.addDays(1)
    span.addHours(2)
    span.addMinutes(3)
    span.addSeconds(4)
    span.addMilliSeconds(5)
    var dateTime = span.toDateTime()
    @assert(dateTime.month == 1)
    expectDateTime(dateTime, 2020, 1, 2, 2, 3, 4, 5)

    span.addMilliSeconds(-5)
    span.addSeconds(-4)
    span.addMinutes(-3)
    span.addHours(-2)
    span.addDays(-1)
    dateTime = span.toDateTime()
    @assert(dateTime.month == 1)
    expectDateTime(dateTime, 2020, 1, 1, 0, 0, 0, 0)

    span = Time.TimeSpan.from(Time.DateTime{2020, 2, 28, 23, 59, 59, 999})
    span.addMilliSeconds(1)
    dateTime = span.toDateTime()
    @assert(dateTime.month == 2)
    expectDateTime(dateTime, 2020, 2, 29, 0, 0, 0, 0)
}

#test
{
    var span = Time.TimeSpan.from(Time.DateTime{2020, 1, 31, 12, 0, 0, 0})
    span.addMonths(1)
    var dateTime = span.toDateTime()
    @assert(dateTime.month == 2)
    expectDateTime(dateTime, 2020, 2, 29, 12, 0, 0, 0)

    span = Time.TimeSpan.from(Time.DateTime{2019, 3, 31, 12, 0, 0, 0})
    span.addMonths(-1)
    dateTime = span.toDateTime()
    @assert(dateTime.month == 2)
    expectDateTime(dateTime, 2019, 2, 28, 12, 0, 0, 0)

    span = Time.TimeSpan.from(Time.DateTime{2020, 1, 31, 12, 0, 0, 0})
    span.addMonths(-1)
    dateTime = span.toDateTime()
    @assert(dateTime.month == 12)
    expectDateTime(dateTime, 2019, 12, 31, 12, 0, 0, 0)

    span = Time.TimeSpan.from(Time.DateTime{2020, 10, 31, 12, 0, 0, 0})
    span.addMonths(5)
    dateTime = span.toDateTime()
    @assert(dateTime.month == 3)
    expectDateTime(dateTime, 2021, 3, 31, 12, 0, 0, 0)

    span = Time.TimeSpan.from(Time.DateTime{2020, 12, 31, 12, 0, 0, 0})
    span.addMonths(2)
    dateTime = span.toDateTime()
    @assert(dateTime.month == 2)
    expectDateTime(dateTime, 2021, 2, 28, 12, 0, 0, 0)

    span = Time.TimeSpan.from(Time.DateTime{2020, 2, 29, 12, 0, 0, 0})
    span.addYears(1)
    dateTime = span.toDateTime()
    @assert(dateTime.month == 2)
    expectDateTime(dateTime, 2021, 2, 28, 12, 0, 0, 0)

    span = Time.TimeSpan.from(Time.DateTime{2020, 2, 29, 12, 0, 0, 0})
    span.addYears(-1)
    dateTime = span.toDateTime()
    @assert(dateTime.month == 2)
    expectDateTime(dateTime, 2019, 2, 28, 12, 0, 0, 0)

    span = Time.TimeSpan.from(Time.DateTime{2020, 2, 29, 12, 0, 0, 0})
    span.addYears(4)
    dateTime = span.toDateTime()
    @assert(dateTime.month == 2)
    expectDateTime(dateTime, 2024, 2, 29, 12, 0, 0, 0)
}
