#global if WINDOWS
#global public
#global namespace Time

using Win32

private func timerEntry(param: #null *void, _timerOrWaitFired: BOOL)
{
    let safeParam = param!
    let t         = cast(*Timer) safeParam
    if !@getcontext() do
        @setcontext(t.context)
    let callback = t.callback!
    callback(t)
}

impl Timer
{
    // Releases the native timer when this value leaves scope.
    mtd opDrop()
    {
        .release()
    }

    // Creates a timer that first fires after `delay`.
    // A periodic timer subsequently fires at the same interval.
    func create(delay: Duration, callback: func(*Timer), periodic = false)->Timer fail
    {
        var result: retval
        try result.initialize(delay, callback, periodic)
        return result
    }

    internal mtd initialize(delay: Duration, callback: func(*Timer), periodic: bool) fail
    {
        Debug.assert(.handle == null)
        let delayMs = delay.milliseconds()
        if !delayMs or delayMs >= Swag.U32.Max do
            fail Errors.OverflowError{"timer delay must be between 1 and 4294967294 milliseconds"}

        .callback = callback
        .context  = dref @getcontext()
        let nativeDelay = cast(u32) delayMs
        try CreateTimerQueueTimer(&.handle, null, &timerEntry, me, nativeDelay, periodic ? nativeDelay : 0, 0)
    }

    // Stops the timer and waits for any active callback before returning.
    mtd release()
    {
        if !.handle do
            return

        let evt = expect CreateEventA(null, FALSE, FALSE, null)
        defer CloseHandle(evt)

        DeleteTimerQueueTimer(null, .handle, evt)
        expect WaitForSingleObject(evt, INFINITE)

        .handle = null
    }
}
