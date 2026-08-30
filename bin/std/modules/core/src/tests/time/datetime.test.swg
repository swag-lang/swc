#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertDateTime(value: Time.DateTime, year, month, day, hour, minute, second, millisecond: u16)
{
    Swag.assert(value.year == year)
    Swag.assert(value.month == month)
    Swag.assert(value.day == day)
    Swag.assert(value.hour == hour)
    Swag.assert(value.minute == minute)
    Swag.assert(value.second == second)
    Swag.assert(value.millisecond == millisecond)
}

#test
{
    using Time.DayOfWeek

    Swag.assert(cast(u32) Sunday == 0)
    Swag.assert(cast(u32) Monday == 1)
    Swag.assert(cast(u32) Tuesday == 2)
    Swag.assert(cast(u32) Wednesday == 3)
    Swag.assert(cast(u32) Thursday == 4)
    Swag.assert(cast(u32) Friday == 5)
    Swag.assert(cast(u32) Saturday == 6)
    Swag.assert(Time.DayOfWeek.count == 7)

    Swag.assert(Time.DateTime.dayOfWeekName(Sunday) == "Sunday")
    Swag.assert(Time.DateTime.dayOfWeekName(Monday) == "Monday")
    Swag.assert(Time.DateTime.dayOfWeekName(Tuesday) == "Tuesday")
    Swag.assert(Time.DateTime.dayOfWeekName(Wednesday) == "Wednesday")
    Swag.assert(Time.DateTime.dayOfWeekName(Thursday) == "Thursday")
    Swag.assert(Time.DateTime.dayOfWeekName(Friday) == "Friday")
    Swag.assert(Time.DateTime.dayOfWeekName(Saturday) == "Saturday")
}

#test
{
    using Time.DateTimeFormat

    Swag.assert(cast(u32) DateIso == 0)
    Swag.assert(cast(u32) TimeIso == 1)
    Swag.assert(cast(u32) TimeIsoMs == 2)
    Swag.assert(cast(u32) TimeIsoHm == 3)
    Swag.assert(cast(u32) Date == 4)
    Swag.assert(cast(u32) DateTime == 5)
    Swag.assert(cast(u32) DateTimeMs == 6)
    Swag.assert(cast(u32) DateTimeIso == 7)
    Swag.assert(cast(u32) DateTimeIsoMs == 8)
    Swag.assert(cast(u32) DateTimeIsoHm == 9)
    Swag.assert(Time.DateTimeFormat.count == 10)
}

#test
{
    Swag.assert(Time.DateTime.monthName(1) == "January")
    Swag.assert(Time.DateTime.monthName(2) == "February")
    Swag.assert(Time.DateTime.monthName(3) == "March")
    Swag.assert(Time.DateTime.monthName(4) == "April")
    Swag.assert(Time.DateTime.monthName(5) == "May")
    Swag.assert(Time.DateTime.monthName(6) == "June")
    Swag.assert(Time.DateTime.monthName(7) == "July")
    Swag.assert(Time.DateTime.monthName(8) == "August")
    Swag.assert(Time.DateTime.monthName(9) == "September")
    Swag.assert(Time.DateTime.monthName(10) == "October")
    Swag.assert(Time.DateTime.monthName(11) == "November")
    Swag.assert(Time.DateTime.monthName(12) == "December")
}

#test
{
    let value = Time.DateTime{2024, 2, 29, 1, 2, 3, 456}
    Swag.assert(value.isValid())
    Swag.assert(value.dayOfWeek() == Time.DayOfWeek.Thursday)

    var invalid = value
    invalid.year = 0
    Swag.assert(!invalid.isValid())
    invalid      = value
    invalid.year = 10000
    Swag.assert(!invalid.isValid())
    invalid       = value
    invalid.month = 0
    Swag.assert(!invalid.isValid())
    invalid       = value
    invalid.month = 13
    Swag.assert(!invalid.isValid())
    invalid     = value
    invalid.day = 0
    Swag.assert(!invalid.isValid())
    invalid     = value
    invalid.day = 30
    Swag.assert(!invalid.isValid())
    invalid      = value
    invalid.hour = 24
    Swag.assert(!invalid.isValid())
    invalid        = value
    invalid.minute = 60
    Swag.assert(!invalid.isValid())
    invalid        = value
    invalid.second = 60
    Swag.assert(!invalid.isValid())
    invalid             = value
    invalid.millisecond = 1000
    Swag.assert(!invalid.isValid())

    Swag.assert(Time.DateTime{1970, 1, 1, 0, 0, 0, 0}.dayOfWeek() == Time.DayOfWeek.Thursday)
    Swag.assert(Time.DateTime{2000, 2, 29, 0, 0, 0, 0}.dayOfWeek() == Time.DayOfWeek.Tuesday)
    Swag.assert(Time.DateTime{2024, 4, 29, 0, 0, 0, 0}.dayOfWeek() == Time.DayOfWeek.Monday)
}

#test
{
    let value    = Time.DateTime{2024, 2, 29, 1, 2, 3, 456}
    let paddedMs = Time.DateTime{2024, 2, 29, 1, 2, 3, 4}

    Swag.assert(value.toString(.DateIso) == "2024-02-29")
    Swag.assert(value.toString(.TimeIso) == "01:02:03")
    Swag.assert(value.toString(.TimeIsoMs) == "01:02:03.456")
    Swag.assert(value.toString(.TimeIsoHm) == "01:02")
    Swag.assert(value.toString(.Date) == "Thursday February 29 2024")
    Swag.assert(value.toString(.DateTime) == "Thursday February 29 2024 01:02:03")
    Swag.assert(value.toString(.DateTimeMs) == "Thursday February 29 2024 01:02:03.456")
    Swag.assert(value.toString(.DateTimeIso) == "2024-02-29 01:02:03")
    Swag.assert(value.toString(.DateTimeIsoMs) == "2024-02-29 01:02:03.456")
    Swag.assert(value.toString(.DateTimeIsoHm) == "2024-02-29 01:02")
    Swag.assert(value.toString() == "Thursday February 29 2024 01:02:03")

    Swag.assert(paddedMs.toString(.TimeIsoMs) == "01:02:03.004")
    Swag.assert(paddedMs.toString(.DateTimeMs) == "Thursday February 29 2024 01:02:03.004")
    Swag.assert(paddedMs.toString(.DateTimeIsoMs) == "2024-02-29 01:02:03.004")
}

#test
{
    let dateOnly = expect Time.DateTime.parse("2024-02-29")
    assertDateTime(dateOnly.value, 2024, 2, 29, 0, 0, 0, 0)
    Swag.assert(dateOnly.eat == 10)

    let hourMinute = expect Time.DateTime.parse("2024-02-29 01:02")
    assertDateTime(hourMinute.value, 2024, 2, 29, 1, 2, 0, 0)
    Swag.assert(hourMinute.eat == 16)

    let fullIso = expect Time.DateTime.parse("2024-02-29 01:02:03.456")
    assertDateTime(fullIso.value, 2024, 2, 29, 1, 2, 3, 456)
    Swag.assert(fullIso.eat == 23)

    let named = expect Time.DateTime.parse("Thursday February 29 2024 01:02:03")
    assertDateTime(named.value, 2024, 2, 29, 1, 2, 3, 0)
    Swag.assert(named.eat == 34)
}

#test
{
    let a = Time.DateTime{2024, 2, 29, 1, 2, 3, 456}
    let b = Time.DateTime{2024, 2, 29, 1, 2, 3, 456}
    let c = Time.DateTime{2024, 3, 1, 0, 0, 0, 0}

    Swag.assert(a == b)
    Swag.assert(a != c)
    Swag.assert(a < c)
    Swag.assert(c > a)
}
