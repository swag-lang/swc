#global public
#global namespace Threading

// Opaque platform handle of a thread.
alias ThreadHandle = const *void?

// Selects the scheduling priority of a thread.
enum ThreadPriority
{
    Lowest          // Two steps below normal
    BelowNormal     // One step below normal
    Normal          // Default priority
    AboveNormal     // One step above normal
    Highest         // Two steps above normal
}

// Owns an operating-system thread with inherited context settings and independent scratch storage.
//
// [[Core.Threading.Thread.init]] creates the thread suspended and [[Core.Threading.Thread.start]]
// runs it. The value must be waited for, with [[Core.Threading.Thread.wait]] or
// [[Core.Threading.wait]], before it is dropped, and it must not move while the thread runs.
#[Swag.NoCopy]
struct Thread
{
    public
    {
        userLambda: (func||(Thread))?     // Body the thread runs; it receives this value.

        context:   Swag.Context     // Inherited settings with thread-owned temporary and error storage.
        userParam: *void?           // Caller data the body can read back.

        priority   = ThreadPriority.Normal     // Current scheduling priority.
        requestEnd = false                     // Cooperative stop flag the thread body polls.

        // Identity of the running thread, established when it starts.
        readonly id: u64
    }

    // Platform handle of the thread, owned by this value.
    handle: ThreadHandle
}

impl Thread
{
    // Asserts that the thread was waited for before its owner goes away.
    mtd opDrop()
    {
        Swag.assert(not .isValid(), "thread is not terminated")
    }

    // Returns whether this value owns a thread, from [[Core.Threading.Thread.init]] until it is waited for.
    mtd const isValid()->bool => .handle != null

    // Asks the thread to stop by setting `requestEnd`, which its body must poll.
    mtd safeForceEnd()
    {
        .requestEnd = true
    }

    // Suspends the current thread for at least `duration`.
    func sleep(duration: Time.Duration)
    {
        var remaining = duration.milliseconds()
        while remaining > Swag.U32.Max - 1
        {
            sleepNative(Swag.U32.Max - 1)
            remaining -= Swag.U32.Max - 1
        }

        sleepNative(cast(u32) remaining)
    }

    // Yields the remainder of the current thread's time slice.
    func yield()
    {
        yieldNative()
    }

    // Creates a suspended thread that runs `lambda` with the calling thread's context settings.
    //
    // `tempAllocSize` sets the capacity of the thread's temporary allocator in bytes; zero
    // leaves it without capacity. Error storage and propagation state are never shared with the
    // creating thread. Call [[Core.Threading.Thread.start]] to run the thread.
    mtd init(lambda: func||(Thread), userParam: *void? = null, priority = ThreadPriority.Normal, tempAllocSize: s32 = -1) fail
    {
        Swag.assert(not .isValid(), "thread already created")

        .context = Swag.getContext()[]
        let inheritedCapacity = .context.tempAllocator.capacity
        Swag.init(&.context.tempAllocator, 1)

        // A worker inherits allocator policy, not the creator's live scratch blocks or errors.
        Swag.init(&.context.errorAllocator, 1)
        Swag.init(.context.errors.buffer, .context.errors.count)
        Swag.init(&.context.curError, 1)
        .context.errorIndex = 0
        .context.traceIndex = 0
        .context.hasError   = 0
        let allocator = .context.allocator!
        if tempAllocSize < 0 do
            .context.tempAllocator.setCapacity(inheritedCapacity, allocator)
        elif tempAllocSize != 0 do
            .context.tempAllocator.setCapacity(cast(u64) tempAllocSize, allocator)
        .handle     = try createSuspendedNative(&threadEntry, me, &.id)
        .userLambda = lambda
        .userParam  = userParam
        .requestEnd = false
        try .setPriority(priority)
    }

    // Starts this suspended thread.
    mtd start() fail
    {
        Swag.assert(.isValid())
        try startNative(.handle)
    }

    // Changes this thread's scheduling priority.
    mtd setPriority(priority: ThreadPriority) fail
    {
        Swag.assert(.isValid())
        if .priority == priority do
            return
        try setPriorityNative(.handle, priority)
        .priority = priority
    }

    // Waits for this thread to finish and releases its handle.
    mtd wait()
    {
        Swag.assert(.isValid())
        waitOneNative(.handle)
        closeNative(.handle)
        .handle = null
    }

    // Returns whether this thread has finished without blocking.
    mtd isDone()->bool
    {
        Swag.assert(.isValid())
        return isDoneNative(.handle)
    }
}

private func threadEntry(param: *void?)->u32
{
    let thread = cast(*Thread) param!
    Swag.setContext(thread.context)
    let lambda = thread.userLambda
    if lambda do
        lambda(thread[])

    thread.context.tempAllocator.release()
    thread.context.errorAllocator.release()
    Swag.releaseAllocatorThreadCache()
    return 0
}

// Waits for every thread and releases all their native handles.
func wait(threads: *Thread...)
{
    var handles: [MaxThreadWaitCount] ThreadHandle
    var start = 0'u64
    while start < threads.count
    {
        let count = Math.min(MaxThreadWaitCount, cast(u32) (threads.count - start))
        for i in count
        {
            let thread = threads[start + cast(u64) i]
            Swag.assert(thread.isValid())
            handles[i] = thread.handle
        }

        waitManyNative(handles[until count])
        start += count
    }

    for thread in threads
    {
        closeNative(thread.handle)
        thread.handle = null
    }
}
