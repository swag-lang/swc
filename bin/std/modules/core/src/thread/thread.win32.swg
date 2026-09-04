#global if WINDOWS
#global namespace Threading

using Win32

const MaxThreadWaitCount = MAXIMUM_WAIT_OBJECTS

func sleepNative(milliseconds: u32)
{
    Sleep(milliseconds)
}

func yieldNative()
{
    SwitchToThread()
}

func createSuspendedNative(entry: func(*void?)->u32, param: *void, id: *u64)->ThreadHandle fail
{
    var nativeId: DWORD
    let handle = try CreateThread(null, 0, entry, param, CREATE_SUSPENDED, &nativeId)
    id[] = nativeId
    return cast(ThreadHandle) handle
}

func startNative(handle: ThreadHandle) fail
{
    try ResumeThread(handle)
}

func setPriorityNative(handle: ThreadHandle, priority: ThreadPriority) fail
{
    var nativePriority = 0
    switch #complete priority
    {
    case .Lowest:      nativePriority = THREAD_PRIORITY_LOWEST
    case .BelowNormal: nativePriority = THREAD_PRIORITY_BELOW_NORMAL
    case .Normal:      nativePriority = THREAD_PRIORITY_NORMAL
    case .AboveNormal: nativePriority = THREAD_PRIORITY_ABOVE_NORMAL
    case .Highest:     nativePriority = THREAD_PRIORITY_HIGHEST
    }

    try SetThreadPriority(handle, nativePriority)
}

func waitOneNative(handle: ThreadHandle)
{
    expect WaitForSingleObject(handle, INFINITE)
}

func waitManyNative(handles: const [..] ThreadHandle)
{
    expect WaitForMultipleObjects(cast(u32) handles.count, cast(const *HANDLE) handles.buffer, TRUE, INFINITE)
}

func isDoneNative(handle: ThreadHandle)->bool
{
    return expect WaitForSingleObject(handle, 0) != WAIT_TIMEOUT
}

func closeNative(handle: ThreadHandle)
{
    CloseHandle(handle)
}
