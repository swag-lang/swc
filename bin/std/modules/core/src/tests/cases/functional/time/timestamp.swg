#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func expectDate(ticks: Time.Ticks, year, month, day: u16)
{
    let {year: actualYear, month: actualMonth, day: actualDay} = Time.ticksToDate(ticks)
    Swag.require(actualYear == year)
    Swag.require(actualMonth == month)
    Swag.require(actualDay == day)
}

func expectTime(ticks: Time.Ticks, hour, minute, second, millisecond: u16)
{
    let {hour: actualHour, minute: actualMinute, second: actualSecond, millisecond: actualMillisecond} = Time.ticksToTime(ticks)
    Swag.require(actualHour == hour)
    Swag.require(actualMinute == minute)
    Swag.require(actualSecond == second)
    Swag.require(actualMillisecond == millisecond)
}

func expectDateTime(value: Time.DateTime, year, month, day, hour, minute, second, millisecond: u16)
{
    Swag.require(value.year == year)
    Swag.require(value.month == month)
    Swag.require(value.day == day)
    Swag.require(value.hour == hour)
    Swag.require(value.minute == minute)
    Swag.require(value.second == second)
    Swag.require(value.millisecond == millisecond)
}

#test
{
    Swag.require(Time.TicksPerMillisecond == 10_000'u64)
    Swag.require(Time.TicksPerSecond == 10_000_000'u64)
    Swag.require(Time.TicksPerMinute == 600_000_000'u64)
    Swag.require(Time.TicksPerHour == 36_000_000_000'u64)
    Swag.require(Time.TicksPerDay == 864_000_000_000'u64)

    Swag.require(Time.timeToTicks(0, 0, 0, 0) == 0'u64)
    Swag.require(Time.timeToTicks(0, 0, 0, 1) == Time.TicksPerMillisecond)
    Swag.require(Time.timeToTicks(0, 0, 1, 0) == Time.TicksPerSecond)
    Swag.require(Time.timeToTicks(0, 1, 0, 0) == Time.TicksPerMinute)
    Swag.require(Time.timeToTicks(1, 0, 0, 0) == Time.TicksPerHour)
    Swag.require(Time.timeToTicks(1, 2, 3, 4) == 37_230_040_000'u64)
    Swag.require(Time.timeToTicks(23, 59, 59, 999) == 863_999_990_000'u64)

    expectTime(0, 0, 0, 0, 0)
    expectTime(Time.TicksPerMillisecond, 0, 0, 0, 1)
    expectTime(Time.TicksPerSecond, 0, 0, 1, 0)
    expectTime(Time.TicksPerMinute, 0, 1, 0, 0)
    expectTime(Time.TicksPerHour, 1, 0, 0, 0)
    expectTime(37_230_040_000'u64, 1, 2, 3, 4)
    expectTime(863_999_990_000'u64, 23, 59, 59, 999)
    expectTime(Time.TicksPerDay + 37_230_040_000'u64, 1, 2, 3, 4)
}

#test
{
    Swag.require(not Time.isLeapYear(1))
    Swag.require(Time.isLeapYear(4))
    Swag.require(not Time.isLeapYear(100))
    Swag.require(Time.isLeapYear(400))
    Swag.require(not Time.isLeapYear(1900))
    Swag.require(Time.isLeapYear(2000))
    Swag.require(Time.isLeapYear(2024))
    Swag.require(not Time.isLeapYear(2025))

    Swag.require(Time.daysInMonth(2023, 1) == 31)
    Swag.require(Time.daysInMonth(2023, 2) == 28)
    Swag.require(Time.daysInMonth(2023, 3) == 31)
    Swag.require(Time.daysInMonth(2023, 4) == 30)
    Swag.require(Time.daysInMonth(2023, 5) == 31)
    Swag.require(Time.daysInMonth(2023, 6) == 30)
    Swag.require(Time.daysInMonth(2023, 7) == 31)
    Swag.require(Time.daysInMonth(2023, 8) == 31)
    Swag.require(Time.daysInMonth(2023, 9) == 30)
    Swag.require(Time.daysInMonth(2023, 10) == 31)
    Swag.require(Time.daysInMonth(2023, 11) == 30)
    Swag.require(Time.daysInMonth(2023, 12) == 31)

    Swag.require(Time.daysInMonth(2024, 1) == 31)
    Swag.require(Time.daysInMonth(2024, 2) == 29)
    Swag.require(Time.daysInMonth(2024, 3) == 31)
    Swag.require(Time.daysInMonth(2024, 4) == 30)
    Swag.require(Time.daysInMonth(2024, 5) == 31)
    Swag.require(Time.daysInMonth(2024, 6) == 30)
    Swag.require(Time.daysInMonth(2024, 7) == 31)
    Swag.require(Time.daysInMonth(2024, 8) == 31)
    Swag.require(Time.daysInMonth(2024, 9) == 30)
    Swag.require(Time.daysInMonth(2024, 10) == 31)
    Swag.require(Time.daysInMonth(2024, 11) == 30)
    Swag.require(Time.daysInMonth(2024, 12) == 31)
}

#test
{
    Swag.require(Time.dateToTicks(1, 1, 1) == 0'u64)
    Swag.require(Time.dateToTicks(1, 1, 2) == 864_000_000_000'u64)
    Swag.require(Time.dateToTicks(4, 2, 29) == 997_056_000_000_000'u64)
    Swag.require(Time.dateToTicks(1970, 1, 1) == 621_355_968_000_000_000'u64)
    Swag.require(Time.dateToTicks(2000, 3, 1) == 630_874_656_000_000_000'u64)
    Swag.require(Time.dateToTicks(2024, 2, 29) == 638_447_616_000_000_000'u64)
    Swag.require(Time.dateToTicks(9999, 12, 31) == 3_155_378_112_000_000_000'u64)

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
    let span = Time.Timestamp.fromDateTime({2024, 2, 29, 1, 2, 3, 4})
    Swag.require(span.ticks == Time.dateToTicks(2024, 2, 29) + Time.timeToTicks(1, 2, 3, 4))
    let dateTime = span.toDateTime()
    Swag.require(dateTime.month == 2)
    expectDateTime(dateTime, 2024, 2, 29, 1, 2, 3, 4)

    let twoDays = Time.Timestamp.fromTicks(Time.TicksPerDay * 2)
    Swag.require(twoDays.totalDays() == 2)
    Swag.require(twoDays.totalHours() == 48)
    Swag.require(twoDays.totalMinutes() == 2880)
    Swag.require(twoDays.totalSeconds() == 172800)
    Swag.require(twoDays.totalMilliseconds() == 172800000)

    Swag.require((Time.Timestamp.fromTicks(1) <=> Time.Timestamp.fromTicks(1)) == 0)
    Swag.require(Time.Timestamp.fromTicks(1) < Time.Timestamp.fromTicks(2))
    Swag.require(Time.Timestamp.fromTicks(2) > Time.Timestamp.fromTicks(1))
    Swag.require(Time.Timestamp.fromTicks(2) >= Time.Timestamp.fromTicks(2))
    Swag.require(Time.Timestamp.fromTicks(1) <= Time.Timestamp.fromTicks(1))
}

#test
{
    var span = Time.Timestamp.fromDateTime({2020, 1, 1, 0, 0, 0, 0})
    span.addDays(1)
    span.addHours(2)
    span.addMinutes(3)
    span.addSeconds(4)
    span.addMilliseconds(5)
    var dateTime = span.toDateTime()
    Swag.require(dateTime.month == 1)
    expectDateTime(dateTime, 2020, 1, 2, 2, 3, 4, 5)

    span.addMilliseconds(-5)
    span.addSeconds(-4)
    span.addMinutes(-3)
    span.addHours(-2)
    span.addDays(-1)
    dateTime = span.toDateTime()
    Swag.require(dateTime.month == 1)
    expectDateTime(dateTime, 2020, 1, 1, 0, 0, 0, 0)

    span = Time.Timestamp.fromDateTime({2020, 2, 28, 23, 59, 59, 999})
    span.addMilliseconds(1)
    dateTime = span.toDateTime()
    Swag.require(dateTime.month == 2)
    expectDateTime(dateTime, 2020, 2, 29, 0, 0, 0, 0)
}

#test
{
    var span = Time.Timestamp.fromDateTime({2020, 1, 31, 12, 0, 0, 0})
    span.addMonths(1)
    var dateTime = span.toDateTime()
    Swag.require(dateTime.month == 2)
    expectDateTime(dateTime, 2020, 2, 29, 12, 0, 0, 0)

    span = Time.Timestamp.fromDateTime({2019, 3, 31, 12, 0, 0, 0})
    span.addMonths(-1)
    dateTime = span.toDateTime()
    Swag.require(dateTime.month == 2)
    expectDateTime(dateTime, 2019, 2, 28, 12, 0, 0, 0)

    span = Time.Timestamp.fromDateTime({2020, 1, 31, 12, 0, 0, 0})
    span.addMonths(-1)
    dateTime = span.toDateTime()
    Swag.require(dateTime.month == 12)
    expectDateTime(dateTime, 2019, 12, 31, 12, 0, 0, 0)

    span = Time.Timestamp.fromDateTime({2020, 10, 31, 12, 0, 0, 0})
    span.addMonths(5)
    dateTime = span.toDateTime()
    Swag.require(dateTime.month == 3)
    expectDateTime(dateTime, 2021, 3, 31, 12, 0, 0, 0)

    span = Time.Timestamp.fromDateTime({2020, 12, 31, 12, 0, 0, 0})
    span.addMonths(2)
    dateTime = span.toDateTime()
    Swag.require(dateTime.month == 2)
    expectDateTime(dateTime, 2021, 2, 28, 12, 0, 0, 0)

    span = Time.Timestamp.fromDateTime({2020, 2, 29, 12, 0, 0, 0})
    span.addYears(1)
    dateTime = span.toDateTime()
    Swag.require(dateTime.month == 2)
    expectDateTime(dateTime, 2021, 2, 28, 12, 0, 0, 0)

    span = Time.Timestamp.fromDateTime({2020, 2, 29, 12, 0, 0, 0})
    span.addYears(-1)
    dateTime = span.toDateTime()
    Swag.require(dateTime.month == 2)
    expectDateTime(dateTime, 2019, 2, 28, 12, 0, 0, 0)

    span = Time.Timestamp.fromDateTime({2020, 2, 29, 12, 0, 0, 0})
    span.addYears(4)
    dateTime = span.toDateTime()
    Swag.require(dateTime.month == 2)
    expectDateTime(dateTime, 2024, 2, 29, 12, 0, 0, 0)
}

#test
{
    var lastMillisecond = Time.Timestamp.fromDateTime({9999, 12, 31, 23, 59, 59, 999})
    let dateTime        = lastMillisecond.toDateTime()
    expectDateTime(dateTime, 9999, 12, 31, 23, 59, 59, 999)

    let addOverflow = Swag.catchPanic(func|&lastMillisecond|()
    {
        lastMillisecond.addMilliseconds(1)
    })
    Swag.require(addOverflow.raised and addOverflow.message() == "overflow")

    var epoch = Time.Timestamp.fromDateTime({1, 1, 1, 0, 0, 0, 0})
    let removeOverflow = Swag.catchPanic(func|&epoch|()
    {
        epoch.addMilliseconds(-1)
    })
    Swag.require(removeOverflow.raised and removeOverflow.message() == "ticks overflow")

    let epochTicks    = epoch.ticks
    let minimumOffset = Swag.catchPanic(func|&epoch|()
    {
        epoch.addMilliseconds(Swag.S32.Min)
    })
    Swag.require(minimumOffset.raised and minimumOffset.message() == "ticks overflow")
    Swag.require(epoch.ticks == epochTicks)
}

#test
{
    let dateTime  = Time.DateTime.utcNow()
    let timestamp = Time.Timestamp.utcNow()
    Swag.require(dateTime.isValid())
    Swag.require(timestamp.ticks != 0)
    Swag.require(timestamp.toDateTime().isValid())
}
