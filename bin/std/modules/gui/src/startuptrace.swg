#global public

using Core

#foreignlib("kernel32")

// TEMPORARY startup instrumentation. Remove before committing.
namespace StartupTrace
{
    #[Swag.Foreign("kernel32")]
    {
        func GetCurrentProcess()->*void
        func GetProcessTimes(process: *void, creation, exitTime, kernel, user: *u64)->s32
        func GetSystemTimeAsFileTime(result: *u64)
    }

    private var g_Text:  String
    private var g_Start: u64
    private var g_Last:  u64

    // Milliseconds elapsed since the process was created.
    func processUptimeMs()->u64
    {
        var creation, exitTime, kernel, user: u64
        var now: u64
        if !GetProcessTimes(GetCurrentProcess(), &creation, &exitTime, &kernel, &user) do
            return 0
        GetSystemTimeAsFileTime(&now)
        return (now - creation) / 10_000
    }

    func mark(label: string)
    {
        let now = Time.monotonicMicroseconds()
        if !g_Start
        {
            g_Start = now
            g_Last  = now
            g_Text.appendFormat("process start -> first mark: % ms\n", processUptimeMs())
        }

        g_Text.appendFormat("%\t+%\t%\n", (now - g_Start) / 1000, (now - g_Last) / 1000, label)
        g_Last = Time.monotonicMicroseconds()
    }

    func flush()
    {
        g_Text.appendFormat("--- flush at process uptime % ms ---\n", processUptimeMs())
        discard catch File.writeAllBytes("startup-trace.txt", g_Text.toSlice())
    }
}
