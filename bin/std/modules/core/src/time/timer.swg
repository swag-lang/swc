#global public
#global namespace Time

// Internal native timer handle required by the public value layout.
#[Swag.NoDoc]
alias TimerHandle = #null const *void

// Owns an operating-system timer that invokes a callback on a worker thread.
#[Swag.NoCopy]
struct Timer
{
    internal
    {
        callback: #null func(*Timer)
        handle:   TimerHandle
        context:  Swag.Context
    }
}

private func timerEntry(param: #null *void)
{
    let timer = cast(*Timer) param!

    // The callback runs on an operating-system worker thread, whose context is a default one
    // the runtime creates on first access: install the context of the thread that armed the timer.
    @setcontext(timer.context)
    let callback = timer.callback!
    callback(timer)
}

impl Timer
{
    // Releases the native timer when this value leaves scope.
    mtd opDrop()
    {
        .release()
    }

    // Creates a timer that first fires after `delay`.
    //
    // A periodic timer subsequently fires at the same interval.
    func create(delay: Duration, callback: func(*Timer), periodic = false)->Timer fail
    {
        var result: retval
        result.initialize(delay, callback, periodic)
        return result
    }

    internal mtd initialize(delay: Duration, callback: func(*Timer), periodic: bool) fail
    {
        Debug.assert(.handle == null)
        let delayMs = delay.milliseconds()
        if !delayMs or delayMs >= Swag.U32.Max do
            fail Errors.OverflowError{"timer delay must be between 1 and 4294967294 milliseconds"}

        .callback = callback
        .context  = @getcontext()[]
        .handle   = createTimerNative(me, cast(u32) delayMs, periodic)
    }

    // Stops the timer and waits for any active callback before returning.
    mtd release()
    {
        if !.handle do
            return
        releaseTimerNative(.handle)
        .handle = null
    }
}
