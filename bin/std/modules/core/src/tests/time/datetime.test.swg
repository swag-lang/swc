#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func assertDateTime(value: Time.DateTime, year, month, day, hour, minute, second, millisecond: u16)
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
    using Time.DayOfWeek

    @assert(cast(u32) Sunday == 0)
    @assert(cast(u32) Monday == 1)
    @assert(cast(u32) Tuesday == 2)
    @assert(cast(u32) Wednesday == 3)
    @assert(cast(u32) Thursday == 4)
    @assert(cast(u32) Friday == 5)
    @assert(cast(u32) Saturday == 6)
    @assert(@countof(Time.DayOfWeek) == 7)

    @assert(Time.DateTime.dayOfWeekName(Sunday) == "Sunday")
    @assert(Time.DateTime.dayOfWeekName(Monday) == "Monday")
    @assert(Time.DateTime.dayOfWeekName(Tuesday) == "Tuesday")
    @assert(Time.DateTime.dayOfWeekName(Wednesday) == "Wednesday")
    @assert(Time.DateTime.dayOfWeekName(Thursday) == "Thursday")
    @assert(Time.DateTime.dayOfWeekName(Friday) == "Friday")
    @assert(Time.DateTime.dayOfWeekName(Saturday) == "Saturday")
}

#test
{
    using Time.DateTimeFormat

    @assert(cast(u32) DateIso == 0)
    @assert(cast(u32) TimeIso == 1)
    @assert(cast(u32) TimeIsoMs == 2)
    @assert(cast(u32) TimeIsoHM == 3)
    @assert(cast(u32) Date == 4)
    @assert(cast(u32) DateTime == 5)
    @assert(cast(u32) DateTimeMs == 6)
    @assert(cast(u32) DateTimeIso == 7)
    @assert(cast(u32) DateTimeIsoMs == 8)
    @assert(cast(u32) DateTimeIsoHM == 9)
    @assert(@countof(Time.DateTimeFormat) == 10)
}

#test
{
    @assert(Time.DateTime.monthName(1) == "January")
    @assert(Time.DateTime.monthName(2) == "February")
    @assert(Time.DateTime.monthName(3) == "March")
    @assert(Time.DateTime.monthName(4) == "April")
    @assert(Time.DateTime.monthName(5) == "May")
    @assert(Time.DateTime.monthName(6) == "June")
    @assert(Time.DateTime.monthName(7) == "July")
    @assert(Time.DateTime.monthName(8) == "August")
    @assert(Time.DateTime.monthName(9) == "September")
    @assert(Time.DateTime.monthName(10) == "October")
    @assert(Time.DateTime.monthName(11) == "November")
    @assert(Time.DateTime.monthName(12) == "December")
}

#test
{
    let value = Time.DateTime{2024, 2, 29, 1, 2, 3, 456}
    @assert(value.isValid())
    @assert(value.dayOfWeek() == Time.DayOfWeek.Thursday)

    var invalid = value
    invalid.year = 0
    @assert(!invalid.isValid())
    invalid = value
    invalid.year = 10000
    @assert(!invalid.isValid())
    invalid = value
    invalid.month = 0
    @assert(!invalid.isValid())
    invalid = value
    invalid.month = 13
    @assert(!invalid.isValid())
    invalid = value
    invalid.day = 0
    @assert(!invalid.isValid())
    invalid = value
    invalid.day = 30
    @assert(!invalid.isValid())
    invalid = value
    invalid.hour = 24
    @assert(!invalid.isValid())
    invalid = value
    invalid.minute = 60
    @assert(!invalid.isValid())
    invalid = value
    invalid.second = 60
    @assert(!invalid.isValid())
    invalid = value
    invalid.millisecond = 1000
    @assert(!invalid.isValid())

    @assert(Time.DateTime{1970, 1, 1, 0, 0, 0, 0}.dayOfWeek() == Time.DayOfWeek.Thursday)
    @assert(Time.DateTime{2000, 2, 29, 0, 0, 0, 0}.dayOfWeek() == Time.DayOfWeek.Tuesday)
    @assert(Time.DateTime{2024, 4, 29, 0, 0, 0, 0}.dayOfWeek() == Time.DayOfWeek.Monday)
}

#test
{
    let value = Time.DateTime{2024, 2, 29, 1, 2, 3, 456}

    @assert(value.toString(.DateIso) == "2024-02-29")
    @assert(value.toString(.TimeIso) == "01:02:03")
    @assert(value.toString(.TimeIsoMs) == "01:02:03.456")
    @assert(value.toString(.TimeIsoHM) == "01:02")
    @assert(value.toString(.Date) == "Thursday February 29 2024")
    @assert(value.toString(.DateTime) == "Thursday February 29 2024 01:02:03")
    @assert(value.toString(.DateTimeMs) == "Thursday February 29 2024 01:02:03.456")
    @assert(value.toString(.DateTimeIso) == "2024-02-29 01:02:03")
    @assert(value.toString(.DateTimeIsoMs) == "2024-02-29 01:02:03.456")
    @assert(value.toString(.DateTimeIsoHM) == "2024-02-29 01:02")
    @assert(value.toString() == "Thursday February 29 2024 01:02:03")
}

#test
{
    let dateOnly = catch Time.DateTime.parse("2024-02-29")
    assertDateTime(dateOnly.value, 2024, 2, 29, 0, 0, 0, 0)
    @assert(dateOnly.eat == 10)

    let hourMinute = catch Time.DateTime.parse("2024-02-29 01:02")
    assertDateTime(hourMinute.value, 2024, 2, 29, 1, 2, 0, 0)
    @assert(hourMinute.eat == 16)

    let fullIso = catch Time.DateTime.parse("2024-02-29 01:02:03.456")
    assertDateTime(fullIso.value, 2024, 2, 29, 1, 2, 3, 456)
    @assert(fullIso.eat == 23)

    let named = catch Time.DateTime.parse("Thursday February 29 2024 01:02:03")
    assertDateTime(named.value, 2024, 2, 29, 1, 2, 3, 0)
    @assert(named.eat == 34)
}

#test
{
    let a = Time.DateTime{2024, 2, 29, 1, 2, 3, 456}
    let b = Time.DateTime{2024, 2, 29, 1, 2, 3, 456}
    let c = Time.DateTime{2024, 3, 1, 0, 0, 0, 0}

    @assert(a == b)
    @assert(a != c)
    @assert(a < c)
    @assert(c > a)
}
