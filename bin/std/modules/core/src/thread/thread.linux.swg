#global if #os == Swag.TargetOs.Linux
#global namespace Threading

internal func sleepNative(milliseconds: u32)
{
    var deadline: Linux.timespec
    if Linux.clock_gettime(Linux.CLOCK_MONOTONIC, &deadline) != 0 do
        Swag.panic("cannot read the monotonic clock", #curlocation)
    deadline.tv_sec  += cast(s64, milliseconds / 1000)
    deadline.tv_nsec += cast(s64, milliseconds % 1000) * 1_000_000
    if deadline.tv_nsec >= 1_000_000_000
    {
        deadline.tv_nsec -= 1_000_000_000
        deadline.tv_sec  += 1
    }

    // Retrying the same absolute deadline avoids drift when signals interrupt the wait.
    for
    {
        let error = Linux.clock_nanosleep(Linux.CLOCK_MONOTONIC, Linux.TIMER_ABSTIME, &deadline, null)
        if error == 0 do
            return
        if error != Linux.EINTR do
            Swag.panic("cannot sleep the current thread", #curlocation)
    }
}

internal func yieldNative()
{
    if Linux.sched_yield() != 0 do
        Swag.panic("cannot yield the current thread", #curlocation)
}

internal const MaxThreadWaitCount = 64'u32

#[Swag.CallingConvention(.C)]
private alias ThreadEntry = func(*void?)->u32

private struct NativeThread
{
    thread:     Linux.pthread_t
    allocator:  Swag.IAllocator?
    late entry: ThreadEntry
    param:      *void?
    mutex:      Swag.Mutex
    changed:    Swag.Condition
    id:         s32
    normalNice: s32
    finished:   bool
    started:    bool
    joined:     bool
}

private func nativeThread(handle: ThreadHandle)->*NativeThread => cast #unconst (*NativeThread, unwrap handle)

#[Swag.CallingConvention(.C)]
private func nativeThreadEntry(param: *void?)->*void?
{
    let state = cast(*NativeThread, unwrap param)
    state.mutex.lock()
    state.id = Linux.gettid()
    state.changed.wakeAll()
    while not state.started do
        state.changed.wait(&state.mutex)
    state.mutex.unlock()

    discard state.entry(state.param)

    // Retire the kernel identity before pthread exit can make it available to another thread.
    state.mutex.lock()
    state.finished = true
    state.mutex.unlock()
    return null
}

internal func createSuspendedNative(entry: ThreadEntry, param: *void, id: *u64)->ThreadHandle fail
{
    Linux.errno(0)
    let normalNice = Linux.getpriority(Linux.PRIO_PROCESS, 0)
    let queried    = Linux.errno()
    if queried != 0 do
        try Errors.failLinuxError(queried)
    let allocator = unwrap Swag.getContext().allocator
    let state     = cast(*NativeThread, Memory.alloc(#sizeof(NativeThread), allocator))
    Swag.init(state, 1)
    state.allocator  = allocator
    state.normalNice = normalNice
    state.entry      = entry
    state.param      = param
    let error = Linux.pthread_create(&state.thread, null, &nativeThreadEntry, state)
    if error != 0
    {
        Swag.drop(state, 1)
        Memory.free(state, #sizeof(NativeThread), allocator)
        try Errors.failLinuxError(error)
    }

    // Publish the kernel identity before init returns, but keep the user's body gated.
    state.mutex.lock()
    while state.id == 0 do
        state.changed.wait(&state.mutex)
    id[] = cast(u64, state.id)
    state.mutex.unlock()
    return state
}

internal func startNative(handle: ThreadHandle) fail
{
    let state = nativeThread(handle)
    state.mutex.lock()
    defer state.mutex.unlock()
    if state.started do
        try Errors.failLinuxError(Linux.EINVAL)
    state.started = true
    state.changed.wake()
}

internal func setPriorityNative(handle: ThreadHandle, priority: ThreadPriority) fail
{
    let state = nativeThread(handle)
    state.mutex.lock()
    defer state.mutex.unlock()
    if state.joined or state.finished do
        try Errors.failLinuxError(Linux.ESRCH)

    // Nice levels apply to the ordinary scheduler; do not silently replace a real-time policy.
    var policy:    s32
    var parameter: Linux.sched_param
    let queried = Linux.pthread_getschedparam(state.thread, &policy, &parameter)
    if queried != 0 do
        try Errors.failLinuxError(queried)
    if policy != Linux.SCHED_OTHER do
        try Errors.failLinuxError(Linux.ENOTSUP)
    var offset: s32
    switch #complete priority
    {
    case .Lowest:      offset = 2
    case .BelowNormal: offset = 1
    case .Normal:      offset = 0
    case .AboveNormal: offset = -1
    case .Highest:     offset = -2
    }

    let nice = Math.clamp(state.normalNice + offset, -20, 19)
    if Linux.setpriority(Linux.PRIO_PROCESS, cast(u32, state.id), nice) != 0 do
        try Errors.failLinuxError(Linux.errno())
}

internal func waitOneNative(handle: ThreadHandle)
{
    let state = nativeThread(handle)
    if state.joined do
        return
    let error = Linux.pthread_join(state.thread, null)
    if error != 0 do
        Swag.panic("cannot join the thread", #curlocation)
    state.joined = true
}

internal func waitManyNative(handles: const [..] ThreadHandle)
{
    for handle in handles do
        waitOneNative(handle)
}

internal func isDoneNative(handle: ThreadHandle)->bool
{
    let state = nativeThread(handle)
    if state.joined do
        return true
    let error = Linux.pthread_tryjoin_np(state.thread, null)
    if error == Linux.EBUSY do
        return false
    if error != 0 do
        Swag.panic("cannot query the thread's completion", #curlocation)
    state.joined = true
    return true
}

internal func closeNative(handle: ThreadHandle)
{
    let state = nativeThread(handle)
    Swag.assert(state.joined)
    let allocator = state.allocator
    Swag.drop(state, 1)
    Memory.free(state, #sizeof(NativeThread), allocator)
}
