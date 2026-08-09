#global if WINDOWS
#global namespace Time

using Win32

internal func wallClockFields(systemTime: SYSTEMTIME)->WallClockFields
{
    return {systemTime.wYear,
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
