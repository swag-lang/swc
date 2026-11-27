#global private
#global if #os == Swag.TargetOs.Windows

alias HANDLE     = const [*] void
alias DWORD      = u32
alias BOOL       = s32
#[Swag.CallingConvention(.C)]
alias ThreadProc = func(*void)->DWORD

const WAIT_OBJECT_0 = 0_u32
const INFINITE      = 0xFFFFFFFF_u32

#[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
{
    func CreateThread(lpThreadAttributes: *void?, dwStackSize: u64, lpStartAddress: ThreadProc, lpParameter: *void, dwCreationFlags: DWORD, lpThreadId: *DWORD)->HANDLE
    func WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD)->DWORD
    func CloseHandle(handle: HANDLE)->BOOL
}

struct CallbackData
{
    value:    u64
    observed: u64
}

#[Swag.CallingConvention(.C)]
func threadCallback(param: *void)->DWORD
{
    let data = cast(*CallbackData, param)
    data.observed = data.value
    return 0
}

func runThreadCallback()->u64
{
    var data: CallbackData
    data.value = 0x12345678AABBCCDD_u64

    let callback: ThreadProc = &threadCallback

    var id     = 0_u32
    let thread = CreateThread(null, 0, callback, &data, 0, &id)
    if thread == null
    {
        return 0
    }

    let waitRes = WaitForSingleObject(thread, INFINITE)
    discard CloseHandle(thread)
    if waitRes != WAIT_OBJECT_0
    {
        return 0
    }

    return data.observed
}

#test
{
    const observed = #run runThreadCallback()
    #assert(observed == 0x12345678AABBCCDD_u64)
}
