#global if #os == Swag.TargetOs.Linux
#global namespace Time

private func wallClockFields(value: Linux.tm, millisecond: u16)->WallClockFields
{
    return WallClockFields{cast(u16, value.tm_year + 1900),
                           cast(u16, value.tm_mon + 1),
                           cast(u16, value.tm_mday),
                           cast(u16, value.tm_hour),
                           cast(u16, value.tm_min),
                           cast(u16, value.tm_sec),
                           millisecond}
}

internal func readWallClock(kind: WallClockKind)->WallClockFields
{
    var now: Linux.timespec
    if Linux.clock_gettime(Linux.CLOCK_REALTIME, &now) != 0 do
        Swag.panic("cannot read the wall clock", #curlocation)

    var calendar: Linux.tm
    let converted = kind == .Utc ? Linux.gmtime_r(&now.tv_sec, &calendar) : Linux.localtime_r(&now.tv_sec, &calendar)
    if not converted or calendar.tm_year < -1899 or calendar.tm_year > 8099 or calendar.tm_sec > 59 do
        Swag.panic("wall clock is outside the supported calendar range", #curlocation)
    return wallClockFields(calendar, cast(u16, now.tv_nsec / 1_000_000))
}

internal func localWallClock(utc: WallClockFields)->WallClockFields
{
    let value = DateTime{utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second, utc.millisecond}
    if not value.isValid() do
        return utc

    var universal: Linux.tm
    universal.tm_year = cast(s32, utc.year) - 1900
    universal.tm_mon  = cast(s32, utc.month) - 1
    universal.tm_mday = utc.day
    universal.tm_hour = utc.hour
    universal.tm_min  = utc.minute
    universal.tm_sec  = utc.second

    // Valid Core dates fit 64-bit time_t. -1 is also a valid instant in 1969.
    let seconds   = Linux.timegm(&universal)
    var local: Linux.tm
    let converted = Linux.localtime_r(&seconds, &local)
    if not converted or local.tm_year < -1899 or local.tm_year > 8099 or local.tm_sec > 59 do
        return utc
    return wallClockFields(local, utc.millisecond)
}

internal func dateTimeFromUnix(seconds: s64, nanoseconds: u32)->DateTime
{
    var result:   #returntype
    var calendar: Linux.tm
    if not Linux.gmtime_r(&seconds, &calendar) or
       calendar.tm_year < -1899 or
       calendar.tm_year > 8099 or
       calendar.tm_sec > 59 do
        return result
    result.setWallClock(wallClockFields(calendar, cast(u16, nanoseconds / 1_000_000)))
    return result
}
