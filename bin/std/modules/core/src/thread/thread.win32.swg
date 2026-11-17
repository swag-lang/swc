#global if WINDOWS
#global namespace Threading

using Win32, Math, Time

const MaxThreadWaitCount = MAXIMUM_WAIT_OBJECTS

func sleepNative(milliseconds: u32)
{
    Sleep(milliseconds)
}

func yieldNative()
{
    SwitchToThread()
}

func createSuspendedNative(entry: LPTHREAD_START_ROUTINE, param: *void, id: *u64)->ThreadHandle fail
{
    var nativeId: DWORD
    let handle = try CreateThread(null, 0, entry, param, CREATE_SUSPENDED, &nativeId)
    id[] = nativeId
    return cast(ThreadHandle, handle)
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

func waitForNative(handle: ThreadHandle, milliseconds: u64)->bool fail
{
    if not milliseconds
    {
        let status = waitForSingleObjectStatus(handle, 0)
        if status.result == WAIT_OBJECT_0 do
            return true
        if status.result == WAIT_TIMEOUT do
            return false
        try Win32.failWinError(status.errorCode)
    }

    var stopwatch: Time.Stopwatch
    stopwatch.start()
    for
    {
        let elapsed = stopwatch.elapsedMilliseconds()
        if elapsed >= milliseconds do
            return false

        let remaining = milliseconds - elapsed
        let chunk     = Math.min(remaining, cast(u64, Swag.U32.Max - 1))
        let status    = waitForSingleObjectStatus(handle, cast(DWORD, chunk))
        if status.result == WAIT_OBJECT_0 do
            return true
        if status.result == WAIT_FAILED do
            try Win32.failWinError(status.errorCode)
        if status.result != WAIT_TIMEOUT do
            try Win32.failWinError(0)
    }
}

func waitManyNative(handles: const [..] ThreadHandle)
{
    expect WaitForMultipleObjects(cast(u32, handles.count), cast(const *HANDLE, handles.buffer), TRUE, INFINITE)
}

func isDoneNative(handle: ThreadHandle)->bool => expect WaitForSingleObject(handle, 0) != WAIT_TIMEOUT

func closeNative(handle: ThreadHandle)
{
    CloseHandle(handle)
}
