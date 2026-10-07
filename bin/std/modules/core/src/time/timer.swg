#global public
#global namespace Time

// Internal native timer handle required by the public value layout.
#[Swag.NoDoc]
alias TimerHandle = const *void?

// Owns an operating-system timer that invokes a callback on a worker thread.
//
// Each callback inherits the creating thread's allocator policy and user context values,
// with independent temporary storage and error state. Periodic callbacks can overlap.
// The timer and the allocator or user state its callbacks borrow must stay alive until
// [[Core.Time.Timer.release]] returns. The timer must not move while it is armed.
#[Swag.NoCopy]
struct Timer
{
    internal
    {
        callback: (func(*Timer))?
        handle:   TimerHandle
        context:  Swag.Context
    }
}

private func timerEntry(param: *void?)
{
    let timer = cast(*Timer, param!)

    // A periodic callback can overlap another one. Its mutable runtime state belongs to this
    // invocation; the stored timer context contains only inherited policy and user values.
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    var context = timer.context
    Swag.setContext(context)
    defer context.tempAllocator.release()
    defer context.releaseErrorStorage()
    timer.callback!(timer)
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
        try result.initialize(delay, callback, periodic)
        return result
    }

    internal mtd initialize(delay: Duration, callback: func(*Timer), periodic: bool) fail
    {
        Swag.assert(.handle == null)
        let delayMs = delay.milliseconds()
        if not delayMs or delayMs >= Swag.U32.Max do
            fail Errors.OverflowError{"timer delay must be between 1 and 4294967294 milliseconds"}

        .callback = callback
        .context  = Swag.getContext()[]
        let tempCapacity  = .context.tempAllocator.capacity
        let errorCapacity = .context.errorAllocator.capacity
        Swag.init(&.context.tempAllocator, 1)
        Swag.init(&.context.errorAllocator, 1)
        Swag.init(.context.errors.buffer, .context.errors.count)
        .context.curError      = null
        .context.errorCaptures = null
        .context.hasError      = 0
        .context.errorIndex    = 0
        .context.traceIndex    = 0
        let allocator = .context.allocator!
        .context.tempAllocator.setCapacity(tempCapacity, allocator)
        .context.errorAllocator.setCapacity(errorCapacity, allocator)
        .handle = try createTimerNative(me, cast(u32, delayMs), periodic)
    }

    // Stops the timer and waits for any active callback before returning.
    //
    // Calling it from the callback of the same timer never returns, because it waits for that
    // callback. Repeated calls do nothing.
    mtd release()
    {
        if not .handle do
            return
        releaseTimerNative(.handle)
        .handle = null
    }
}
