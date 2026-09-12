#global public
#global namespace Threading

// Names the thread handle type.
alias ThreadHandle = const *void?

// Selects thread priority.
enum ThreadPriority
{
    Lowest          // Selects lowest.
    BelowNormal     // Selects below normal.
    Normal          // Selects normal.
    AboveNormal     // Selects above normal.
    Highest         // Selects highest.
}

// Represents thread.
#[Swag.NoCopy]
struct Thread
{
    public
    {
        userLambda: (func||(Thread))?     // User lambda associated with this value.

        context:   Swag.Context     // Context associated with this value.
        userParam: *void?           // User param associated with this value.

        priority   = ThreadPriority.Normal     // Priority associated with this value.
        requestEnd = false                     // Cooperative stop flag the thread body polls.

        // Identity of the running thread, established when it starts.
        readonly id: u64
    }

    // Platform handle of the thread, owned by this value.
    handle: ThreadHandle
}

impl Thread
{
    // Releases resources owned by this value.
    mtd opDrop()
    {
        Swag.assert(not .isValid(), "thread is not terminated")
    }

    // Returns true if the thread is valid
    mtd const isValid()->bool
    {
        return .handle != null
    }

    // Force the thread to safely exist
    // User code needs to check for 'requestEnd'
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

    // Creates a suspended thread with a cloned runtime context.
    mtd init(lambda: func||(Thread), userParam: *void? = null, priority = ThreadPriority.Normal, tempAllocSize: s32 = -1) fail
    {
        Swag.assert(not .isValid(), "thread already created")

        .context = Swag.getContext()[]
        Swag.init(&.context.tempAllocator, 1)
        let allocator = .context.allocator!
        if tempAllocSize < 0 do
            .context.tempAllocator.setCapacity(.context.tempAllocator.capacity, allocator)
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
    if lambda
    {
        let safeLambda = lambda orelse func(th: Thread) {}
        safeLambda(thread[])
    }

    thread.context.tempAllocator.release()
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

        waitManyNative(Swag.makeSlice(&handles[0], cast(u64) count))
        start += count
    }

    for thread in threads
    {
        closeNative(thread.handle)
        thread.handle = null
    }
}
