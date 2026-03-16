#global #if #os == Swag.TargetOs.Windows // swc-option suite-jit

alias HANDLE     = const [*] void
alias DWORD      = u32
alias BOOL       = s32
alias ThreadProc = func(*void)->DWORD

const WAIT_OBJECT_0 = 0'u32
const INFINITE      = 0xFFFFFFFF'u32

#[Swag.Foreign("kernel32")]
{
    func CreateThread(lpThreadAttributes: #null *void, dwStackSize: u64, lpStartAddress: ThreadProc, lpParameter: *void, dwCreationFlags: DWORD, lpThreadId: *DWORD)->HANDLE;
    func WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD)->DWORD;
    func CloseHandle(handle: HANDLE)->BOOL;
}

struct CallbackData
{
    value:    u64
    observed: u64
}

func threadCallback(param: *void)->DWORD
{
    let data = cast(*CallbackData) param
    data.observed = data.value
    return 0
}

func runThreadCallback()->u64
{
    var data: CallbackData
    data.value = 0x12345678AABBCCDD'u64

    let callback: ThreadProc = &threadCallback

    var id = 0'u32
    let thread = CreateThread(null, 0, callback, &data, 0, &id)
    if thread == null do
        return 0

    let waitRes = WaitForSingleObject(thread, INFINITE)
    discard CloseHandle(thread)
    if waitRes != WAIT_OBJECT_0 do
        return 0

    return data.observed
}

#test
{
    const observed = #run runThreadCallback()
    #assert(observed == 0x12345678AABBCCDD'u64)
}
