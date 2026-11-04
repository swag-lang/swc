#global public
#global namespace Threading

// Opaque platform handle of a thread.
alias ThreadHandle = const *void?

// Selects the scheduling priority of a thread.
//
// On Linux, these are per-thread nice levels under POSIX `SCHED_OTHER`, relative to the
// creator's nice value sampled during initialization: Lowest adds 2, BelowNormal adds 1,
// Normal adds 0, AboveNormal subtracts 1, and Highest subtracts 2, clamped to -20 through 19.
// Raising priority, including returning to Normal after lowering it, can fail without the
// required host permission or resource limit. Other scheduling policies are not changed.
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
// runs it. Calls that change or query the same thread's native handle must be serialized by
// the owner. The body can read its published context, user data and cooperative stop flag.
// The value must be waited for, with [[Core.Threading.Thread.wait]] or
// [[Core.Threading.wait]], before it is dropped, and it must not move while the thread runs.
#[Swag.NoCopy]
struct Thread
{
    public
    {
        userLambda: (func||(const *Thread))?     // Body the thread runs; it receives a pointer to this value.

        context:   Swag.Context     // Inherited settings with thread-owned temporary and error storage.
        userParam: *void?           // Caller data the body can read back.

        priority = ThreadPriority.Normal     // Current scheduling priority.
        requestEnd: Swag.AtomicFlag          // Cooperative stop flag; the body polls it with [[Swag.AtomicFlag.isRaised]].

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

    // Asks the thread to stop by raising `requestEnd`, which its body must poll.
    mtd safeForceEnd()
    {
        .requestEnd.raise()
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

        sleepNative(cast(u32, remaining))
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
    // creating thread. The body receives a pointer to this value: it reads `userParam` through
    // it and polls `requestEnd` to stop when [[Core.Threading.Thread.safeForceEnd]] asks. Call
    // [[Core.Threading.Thread.start]] to run the thread. On failure, the body never runs and
    // the value owns no thread; it can be initialized again.
    mtd init(lambda: func||(const *Thread), userParam: *void? = null, priority = ThreadPriority.Normal, tempAllocSize: s32 = -1) fail
    {
        Swag.assert(not .isValid(), "thread already created")

        .context = Swag.getContext()[]
        let inheritedCapacity = .context.tempAllocator.capacity

        // A worker inherits allocator policy, not the creator's live scratch blocks or errors.
        .context.resetThreadState()

        var initialized = false
        defer if not initialized
        {
            if .handle
            {
                // The suspended native thread owns the context only after it starts. Run an
                // empty body so its usual teardown releases all per-thread state, then join it.
                .userLambda = null
                expect startNative(.handle)
                .wait()
            }
            else
            {
                .context.tempAllocator.release()
            }

            .id = 0
        }

        let allocator = unwrap .context.allocator
        if tempAllocSize < 0 do
            .context.tempAllocator.setCapacity(inheritedCapacity, allocator)
        elif tempAllocSize != 0 do
            .context.tempAllocator.setCapacity(cast(u64, tempAllocSize), allocator)
        .handle     = try createSuspendedNative(&threadEntry, me, &.id)
        .userLambda = lambda
        .userParam  = userParam
        .requestEnd.reset()
        try .setPriority(priority)
        initialized = true
    }

    // Starts this suspended thread.
    mtd start() fail
    {
        Swag.assert(.isValid())
        try startNative(.handle)
    }

    // Changes this thread's scheduling priority.
    //
    // On Linux, only this thread's nice value changes; the caller and sibling threads keep
    // theirs. An exited thread or a denied change fails without updating `priority`.
    mtd setPriority(priority: ThreadPriority) fail
    {
        Swag.assert(.isValid())
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

#[Swag.CallingConvention(.C)]
private func threadEntry(param: *void?)->u32
{
    let thread = cast(*Thread, unwrap param)
    Swag.setContext(thread.context)
    let lambda = thread.userLambda
    if lambda do
        lambda(thread)

    thread.context.tempAllocator.release()
    thread.context.releaseErrorStorage()
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
        let count = Math.min(MaxThreadWaitCount, cast(u32, (threads.count - start)))
        for i in count
        {
            let thread = threads[start + cast(u64, i)]
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
