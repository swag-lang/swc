#global fileprivate
#global skip
const WINDOWS = true
#if WINDOWS
{
    namespace std.environment
    {
        {
            func getProcessorCount() => g_SysInfo
        }

        var g_SysInfo: s32
    }
}
