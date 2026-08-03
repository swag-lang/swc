#global if WINDOWS
#global namespace Time

using Win32

impl DateTime
{
    mtd setSystemTime(systemTime: SYSTEMTIME)
    {
        .day         = systemTime.wDay
        .month       = systemTime.wMonth
        .year        = systemTime.wYear
        .hour        = systemTime.wHour
        .minute      = systemTime.wMinute
        .second      = systemTime.wSecond
        .millisecond = systemTime.wMilliseconds
    }
}

public impl DateTime
{
    // Returns the current UTC date and time.
    func utcNow()->DateTime
    {
        var systemTime: SYSTEMTIME = undefined
        GetSystemTime(&systemTime)

        var result: retval = undefined
        result.setSystemTime(systemTime)
        return result
    }

    // Returns a DateTime containing the current date and time
    func now()->DateTime
    {
        var systemTime: SYSTEMTIME = undefined
        GetLocalTime(&systemTime)

        var result: retval = undefined
        result.setSystemTime(systemTime)
        return result
    }

    // Initialize the structure with the current local date and time
    mtd setNow()
    {
        var systemTime: SYSTEMTIME = undefined
        GetLocalTime(&systemTime)
        .setSystemTime(systemTime)
    }
}
