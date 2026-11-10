#global export

#foreignlib("avrt")

namespace Win32Priv
{
    #[Swag.Foreign("avrt", callconv: Swag.CallConv.C)]
    {
        func AvSetMmThreadCharacteristicsW(TaskName: LPCWSTR, TaskIndex: *DWORD)->HANDLE
        func AvRevertMmThreadCharacteristics(AvrtHandle: HANDLE)->BOOL
    }
}

// Reports a native scheduling-registration failure as a Swag error.
func AvSetMmThreadCharacteristicsW(TaskName: LPCWSTR, TaskIndex: *DWORD)->HANDLE fail
{
    let result = Win32Priv.AvSetMmThreadCharacteristicsW(TaskName, TaskIndex)
    if not result do
        try failWinError(GetLastError())
    return result
}

// Reports a native scheduling-restoration failure as a Swag error.
func AvRevertMmThreadCharacteristics(AvrtHandle: HANDLE) fail
{
    if not Win32Priv.AvRevertMmThreadCharacteristics(AvrtHandle) do
        try failWinError(GetLastError())
}
