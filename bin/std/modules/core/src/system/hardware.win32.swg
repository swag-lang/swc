#global if WINDOWS
#global namespace Hardware

using Win32

// Returns the number of logical processors available to the process.
public func processorCount()->u32 => cast(u32) Env.g_SysInfo.dwNumberOfProcessors

// Returns the first adapter MAC address packed into the low bytes, or zero when unavailable.
public func macAddress()->u64
{
    var info:   [16] IP_ADAPTER_INFO
    var length: DWORD = #sizeof(info)
    if GetAdaptersInfo(&info, &length) != 0 do
        return 0
    return dref cast(*u64) &info[0].address[0]
}
