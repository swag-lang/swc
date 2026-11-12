#global public
#global namespace Time

// Opaque ownership of the common timer worker.
internal alias TimerHandle = const *void?

// Owns a timer that invokes a callback on a dedicated worker thread.
//
// Each callback inherits the creating thread's allocator policy and user context values,
// with independent temporary storage and error state. Each timer owns one worker: its callbacks
// are serialized, use a monotonic deadline, and coalesce missed periods. Different timers can
// invoke their callbacks concurrently.
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
    let timer = cast(*Timer, unwrap param)

    // Each callback gets fresh mutable runtime state; the stored timer context contains only
    // inherited policy and user values.
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
    // Releases the timer worker when this value leaves scope.
    mtd opDrop()
    {
        .release()
    }

    // Creates a timer that first fires after `delay`.
    //
    // A periodic timer subsequently fires at the same interval. Scheduling can delay a callback;
    // Elapsed periods are skipped when a callback takes longer than its interval.
    func create(delay: Duration, callback: func(*Timer), periodic = false)->Timer fail
    {
        var result: #returntype
        try result.initialize(delay, callback, periodic)
        return result
    }

    internal mtd initialize(delay: Duration, callback: func(*Timer), periodic: bool) fail
    {
        Swag.assert(.handle == null)
        if not Math.isFinite(delay.seconds) or delay.seconds <= 0 do
            fail Errors.BadParameterError{"timer delay must be positive and finite"}
        if delay.seconds >= cast(f64, Swag.U32.Max) / 1000 do
            fail Errors.OverflowError{"timer delay must be between 1 and 4294967294 milliseconds"}
        let delayMs = delay.millisecondsCeiling()
        if not delayMs or delayMs >= Swag.U32.Max do
            fail Errors.OverflowError{"timer delay must be between 1 and 4294967294 milliseconds"}

        .callback = callback
        .context  = Swag.getContext()[]

        // Keep the inherited policy, but give callbacks independent mutable storage.
        with .context
        {
            let tempCapacity  = .tempAllocator.capacity
            let errorCapacity = .errorAllocator.capacity

            .resetThreadState()

            let allocator = unwrap .allocator
            .tempAllocator.setCapacity(tempCapacity, allocator)
            .errorAllocator.setCapacity(errorCapacity, allocator)
        }

        .handle = try createTimerWorker(me, cast(u32, delayMs), periodic)
    }

    // Stops the timer and joins its worker, waiting for any active callback before returning.
    //
    // Do not call it from the callback of the same timer: the worker would have to join itself.
    // Calls that release the same timer must be serialized. Repeated calls do nothing.
    mtd release()
    {
        if not .handle do
            return
        releaseTimerWorker(.handle)
        .handle = null
    }
}
