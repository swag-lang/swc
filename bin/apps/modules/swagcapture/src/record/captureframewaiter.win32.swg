#global if #os == Swag.TargetOs.Windows

using Core, Win32

// Waits for the next video slot without a busy yield loop on Windows.
#[Swag.NoCopy]
struct CaptureFrameWaiter
{
    timer: HANDLE
}

impl CaptureFrameWaiter
{
    mtd open()
    {
        .timer = CreateWaitableTimerExW(null, null, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
                                        SYNCHRONIZE | TIMER_MODIFY_STATE)
        if not .timer do
            .timer = CreateWaitableTimerW(null, FALSE, null)
    }

    mtd waitUntil(tick: u64)
    {
        let now = Time.monotonicMicroseconds()
        if tick <= now do
            return
        if .timer
        {
            let dueTime: LARGE_INTEGER = -cast(s64, (tick - now) * 10)
            if SetWaitableTimer(.timer, &dueTime, 0, null, null, FALSE)
            {
                let result = catch WaitForSingleObject(.timer, 100) { return; }
                if result == WAIT_OBJECT_0 do
                    return
            }
        }

        // The native timer may be unavailable. Avoid a full sleep quantum near the slot.
        if tick > now + 20_000 do
            Threading.Thread.sleep(1'ms)
        else do
            Threading.Thread.yield()
    }

    mtd opDrop()
    {
        if .timer do
            CloseHandle(.timer)
    }
}
