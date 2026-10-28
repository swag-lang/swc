#global if WINDOWS
#global namespace Time

using Win32

internal func wallClockFields(systemTime: SYSTEMTIME)->WallClockFields
{
    return WallClockFields{systemTime.wYear,
                           systemTime.wMonth,
                           systemTime.wDay,
                           systemTime.wHour,
                           systemTime.wMinute,
                           systemTime.wSecond,
                           systemTime.wMilliseconds}
}

internal func readWallClock(kind: WallClockKind)->WallClockFields
{
    var systemTime: SYSTEMTIME
    switch kind
    {
    case .Utc:   GetSystemTime(&systemTime)
    case .Local: GetLocalTime(&systemTime)
    }

    return wallClockFields(systemTime)
}

internal func localWallClock(utc: WallClockFields)->WallClockFields
{
    var universal: SYSTEMTIME
    universal.wYear         = utc.year
    universal.wMonth        = utc.month
    universal.wDay          = utc.day
    universal.wHour         = utc.hour
    universal.wMinute       = utc.minute
    universal.wSecond       = utc.second
    universal.wMilliseconds = utc.millisecond

    var local: SYSTEMTIME
    if not SystemTimeToTzSpecificLocalTime(null, &universal, &local) do
        return utc
    return wallClockFields(local)
}
