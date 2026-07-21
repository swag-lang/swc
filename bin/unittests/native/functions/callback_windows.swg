#global private
#global #if #os == Swag.TargetOs.Windows

alias HANDLE     = #null const [*] void
alias DWORD      = u32
alias BOOL       = s32
alias ThreadProc = func(#null *void)->DWORD

const WAIT_OBJECT_0 = 0'u32
const INFINITE      = 0xFFFFFFFF'u32

#[Swag.Foreign("kernel32")]
{
    func CreateThread(lpThreadAttributes: #null *void, dwStackSize: u64, lpStartAddress: ThreadProc, lpParameter: #null *void, dwCreationFlags: DWORD, lpThreadId: #null *DWORD)->HANDLE;
    func WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD)->DWORD;
    func CloseHandle(handle: HANDLE)->BOOL;
}

struct CallbackData
{
    value:    u64
    observed: u64
}

func threadCallback(param: #null *void)->DWORD
{
    let data = cast(*CallbackData) (notnull param)
    data.observed = data.value
    return 0
}

#test
{
    var data: CallbackData
    data.value = 0x12345678AABBCCDD'u64

    let callback: ThreadProc = &threadCallback

    var id = 0'u32
    let thread = CreateThread(null, 0, callback, &data, 0, &id)
    @assert(thread != null)

    let waitRes = WaitForSingleObject(thread, INFINITE)
    let closeRes = CloseHandle(thread)

    @assert(waitRes == WAIT_OBJECT_0)
    @assert(closeRes != 0)
    @assert(data.observed == data.value)
}
