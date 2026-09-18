#global public
#global namespace Time

// Number of 100-nanosecond ticks in one millisecond.
const TicksPerMillisecond: u64 = 10000

// Number of 100-nanosecond ticks in one second.
const TicksPerSecond: u64 = TicksPerMillisecond * 1000

// Number of 100-nanosecond ticks in one minute.
const TicksPerMinute: u64 = TicksPerSecond * 60

// Number of 100-nanosecond ticks in one hour.
const TicksPerHour: u64 = TicksPerMinute * 60

// Number of 100-nanosecond ticks in one day.
const TicksPerDay: u64 = TicksPerHour * 24

// Number of milliseconds in one second.
const MillisecondsPerSecond = 1000'u64

// Number of milliseconds in one minute.
const MillisecondsPerMinute = MillisecondsPerSecond * 60

// Number of milliseconds in one hour.
const MillisecondsPerHour = MillisecondsPerMinute * 60

// Number of milliseconds in one day.
const MillisecondsPerDay = MillisecondsPerHour * 24

// Number of days in a common year.
const DaysPerYear = 365

// Number of days in four consecutive years, one of them a leap year.
const DaysPer4Years = (DaysPerYear * 4) + 1

// Number of days in a century that does not start a 400-year cycle.
const DaysPer100Years = (DaysPer4Years * 25) - 1

// Number of days in one 400-year cycle of the Gregorian calendar.
const DaysPer400Years = (DaysPer100Years * 4) + 1

internal const DaysToMonth365 = [0'u16, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365]

internal const DaysToMonth366 = [0'u16, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366]

internal const MaxMilliseconds = Swag.U64.Max / TicksPerMillisecond

internal const DaysTo1601:  u64 = (DaysPer400Years * 4)                                                                  // Number of days from 1/1/0001 to 12/31/1600
internal const DaysTo1899:  u64 = ((DaysPer400Years * 4) + (DaysPer100Years * 3)) - 367                                  // Number of days from 1/1/0001 to 12/30/1899
internal const DaysTo1970:  u64 = (DaysPer400Years * 4) + (DaysPer100Years * 3) + (DaysPer4Years * 17) + DaysPerYear     // Number of days from 1/1/0001 to 12/31/1969
internal const DaysTo10000: u64 = (DaysPer400Years * 25) - 366                                                           // Number of days from 1/1/0001 to 12/31/9999
internal const MaxTicks:    u64 = (DaysTo10000 * TicksPerDay) - 1

internal const MaxMillisecondsToYear10000: u64 = DaysTo10000 * MillisecondsPerDay

// Returns monotonic milliseconds from an unspecified origin.
func monotonicMilliseconds()->u64 => scaleMonotonic(1000)

// Returns monotonic microseconds from an unspecified origin.
func monotonicMicroseconds()->u64 => scaleMonotonic(1_000_000)

// Converts the monotonic counter to `unitsPerSecond` units without losing the fraction of the frequency.
private func scaleMonotonic(unitsPerSecond: u64)->u64
{
    let ticks     = monotonicTicks()
    let frequency = monotonicFrequency()
    return (ticks / frequency) * unitsPerSecond + ((ticks % frequency) * unitsPerSecond) / frequency
}

// Counts 100-nanosecond intervals.
alias Ticks = u64

// Returns the ticks from midnight to the given time of day.
func timeToTicks(hour, minute, second, millisecond: u16)->Ticks
{
    Swag.assert(0 <= hour and hour < 24)
    Swag.assert(0 <= minute and minute < 60)
    Swag.assert(0 <= second and second < 60)
    Swag.assert(0 <= millisecond and millisecond < 1000)

    // The asserted ranges keep the total below one day, so the arithmetic cannot overflow.
    var totalMilli = (hour * 3600'u32 + minute * 60'u32 + second) * 1000'u64
    totalMilli += millisecond
    Swag.assert(totalMilli <= MaxMilliseconds)
    return totalMilli * TicksPerMillisecond
}

// Returns the time of day of `ticks`.
func ticksToTime(ticks: Ticks)->{ hour: u16, minute: u16, second: u16, millisecond: u16 }
{
    var result: retval
    result.hour        = cast() ((ticks / TicksPerHour) % 24)
    result.minute      = cast() ((ticks / TicksPerMinute) % 60)
    result.second      = cast() ((ticks / TicksPerSecond) % 60)
    result.millisecond = cast() ((ticks / TicksPerMillisecond) % 1000)
    return result
}

// Returns the ticks from 0001-01-01 to midnight of the given Gregorian date.
func dateToTicks(year, month, day: u16)->Ticks
{
    Swag.assert(1 <= year and year <= 9999)
    Swag.assert(1 <= month and month <= 12)
    Swag.assert(1 <= day and day <= daysInMonth(year, month))

    let days = isLeapYear(year) ? DaysToMonth366.buffer : DaysToMonth365.buffer
    let y    = cast(u64) (year - 1)
    let n    = y * 365 + #wrap y / 4 + #wrap y / 400 + #wrap days[month - 1] + #wrap day - 1 - #wrap y / 100
    return n * TicksPerDay
}

// Returns the Gregorian date that contains `ticks`.
func ticksToDate(ticks: Ticks)->{ year: u16, month: u16, day: u16 }
{
    // n = number of days since 1/1/0001
    var n = ticks / TicksPerDay

    // y400 = number of whole 400-year periods since 1/1/0001
    let y400 = n / DaysPer400Years

    // n = day number within 400-year period
    n -= y400 * DaysPer400Years

    // y100 = number of whole 100-year periods within 400-year period
    var y100 = n / DaysPer100Years

    // Last 100-year period has an extra day, so decrement result if 4
    if y100 == 4 do
        y100 = 3

    // n = day number within 100-year period
    n -= y100 * DaysPer100Years

    // y4 = number of whole 4-year periods within 100-year period
    let y4 = n / DaysPer4Years

    // n = day number within 4-year period
    n -= y4 * DaysPer4Years

    // y1 = number of whole years within 4-year period
    var y1 = n / DaysPerYear

    // Last year has an extra day, so decrement result if 4
    if y1 == 4 do
        y1 = 3

    // n = day number within year
    n -= y1 * DaysPerYear

    // dayOfYear = n + 1;
    // Leap year calculation looks different from IsLeapYear since y1, y4,
    // and y100 are relative to year 1, not year 0
    let leapYear = y1 == 3 and (y4 != 24 or y100 == 3)
    let days     = leapYear ? DaysToMonth366.buffer : DaysToMonth365.buffer

    // All months have less than 32 days, so n >> 5 is a good conservative
    // estimate for the month
    var m = (n >> 5) + 1

    // m = 1-based month number
    while n >= days[m] do
        m += 1

    var result: retval
    result.year  = cast() (y400 * 400 + y100 * 100 + y4 * 4 + y1 + 1)
    result.month = cast() m
    result.day   = cast() (n - days[m - 1] + 1)
    return result
}

// Returns whether `year` is a leap year of the Gregorian calendar.
func isLeapYear(year: u16)->bool => year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

// Returns the number of days of `month` in `year`.
func daysInMonth(year, month: u16)->u16
{
    Swag.assert(1 <= month and month <= 12)
    if isLeapYear(year) do
        return cast() (DaysToMonth366[month] - DaysToMonth366[month - 1])
    return cast() (DaysToMonth365[month] - DaysToMonth365[month - 1])
}
