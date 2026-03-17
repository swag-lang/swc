#global fileprivate // swc-option sema-only
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
