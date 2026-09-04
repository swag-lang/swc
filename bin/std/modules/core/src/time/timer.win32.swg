#global if WINDOWS
#global namespace Time

using Win32

private func timerEntryNative(param: *void?, _timerOrWaitFired: BOOL)
{
    timerEntry(param)
}

func createTimerNative(param: *void, delayMilliseconds: u32, periodic: bool)->TimerHandle fail
{
    var result: TimerHandle
    try CreateTimerQueueTimer(&result, null, &timerEntryNative, param, delayMilliseconds, periodic ? delayMilliseconds : 0, 0)
    return result
}

func releaseTimerNative(handle: TimerHandle)
{
    let event = expect CreateEventA(null, FALSE, FALSE, null)
    defer CloseHandle(event)

    DeleteTimerQueueTimer(null, handle, event)
    expect WaitForSingleObject(event, INFINITE)
}
