#global namespace Time

private struct TimerWorker
{
    nativeThread:         const *void?
    allocator:            Swag.IAllocator?
    late timer:           *Timer
    mutex:                Swag.Mutex
    changed:              Swag.Condition
    elapsed:              Stopwatch
    intervalMilliseconds: u64
    deadlineMilliseconds: u64
    periodic:             bool
    stopped:              bool
}

#[Swag.CallingConvention(.C)]
private func timerWorkerEntry(param: *void?)->u32
{
    let state = cast(*TimerWorker, unwrap param)
    defer Swag.releaseAllocatorThreadCache()
    for
    {
        state.mutex.lock()
        while not state.stopped
        {
            let now = state.elapsed.elapsedMilliseconds()
            if now >= state.deadlineMilliseconds do
                break
            let remaining = state.deadlineMilliseconds - now
            discard state.changed.waitFor(&state.mutex, cast(u32, remaining))
        }

        let stopped = state.stopped
        state.mutex.unlock()
        if stopped do
            return 0

        timerEntry(state.timer)
        if not state.periodic do
            return 0

        // Preserve the original cadence, coalescing periods missed while the callback ran.
        state.deadlineMilliseconds += state.intervalMilliseconds
        let now = state.elapsed.elapsedMilliseconds()
        if state.deadlineMilliseconds <= now
        {
            let missedPeriods = (now - state.deadlineMilliseconds) / state.intervalMilliseconds + 1
            state.deadlineMilliseconds += missedPeriods * state.intervalMilliseconds
        }
    }
}

private func createTimerWorker(timer: *Timer, delayMilliseconds: u32, periodic: bool)->TimerHandle fail
{
    let allocator = unwrap Swag.getContext().allocator
    let state     = cast(*TimerWorker, Memory.alloc(#sizeof(TimerWorker), allocator))
    Swag.init(state, 1)
    defer if state.nativeThread == null
    {
        Swag.drop(state, 1)
        Memory.free(state, #sizeof(TimerWorker), allocator)
    }

    state.allocator            = allocator
    state.timer                = timer
    state.intervalMilliseconds = delayMilliseconds
    state.deadlineMilliseconds = delayMilliseconds
    state.periodic             = periodic
    state.elapsed.start()
    state.nativeThread = try createTimerThreadNative(state)
    return state
}

private func releaseTimerWorker(handle: TimerHandle)
{
    let state = cast #unconst (*TimerWorker, unwrap handle)
    state.mutex.lock()
    state.stopped = true
    state.changed.wake()
    state.mutex.unlock()
    joinTimerThreadNative(state.nativeThread)
    let allocator = state.allocator
    Swag.drop(state, 1)
    Memory.free(state, #sizeof(TimerWorker), allocator)
}
