#global namespace Swag

// One thread of its own that runs submitted tasks one at a time, in the order they were
// submitted.
//
// Work that has to stay on one thread -- a native rendering context, a codec's allocations, a
// device -- runs here instead of on the shared pool. A task submitted to an executor keeps
// everything a task offers: its outcome, its cancellation request and its notification. Pass the
// executor to [[Swag.Task.submit]].
//
// Start it before submitting to it. Closing it, or leaving its scope, runs every task already
// submitted, then stops its thread. The executor holds a submitted task until it runs, so declare
// the tasks before the executor, as a group's borrowed storage is declared before the group. A task that waits for another task of the same executor never
// finishes: one thread runs them in order. Under compile-time execution there is no thread, and a
// task runs inside its submission.
//
// ```swag
// var renderer: Swag.Executor
// renderer.start()
// defer renderer.close()
//
// var task: Swag.Task'u32
// task.submit(func()->u32 => 42, executor: &renderer)
// let value = try task.take()
// ```
#[Swag.NoCopy]
struct Executor
{
    // Guards the queue and the stop request.
    #[Swag.NoDoc]
    mutex: Mutex

    // Wakes the thread when work arrives or the executor closes.
    #[Swag.NoDoc]
    ready: Condition

    // Submitted work, oldest first.
    #[Swag.NoDoc]
    head: *WorkNode?

    // The newest submitted work.
    #[Swag.NoDoc]
    tail: *WorkNode?

    // Host thread handle while the executor runs.
    #[Swag.NoDoc]
    handle: *void?

    // Set by close, read by the thread once the queue is empty.
    #[Swag.NoDoc]
    stopping: bool

    // How urgently the thread competes with the rest of the process.
    #[Swag.NoDoc]
    priority: TaskPriority

    // The thread's own runtime context.
    #[Swag.NoDoc]
    context: Context
}

impl Executor
{
    // Runs every task already submitted, then stops the thread.
    mtd opDrop()
    {
        .close()
    }

    // Starts the thread. A `Background` executor runs every task below normal priority.
    //
    // Failing to start a host thread raises a panic, as failing to allocate does.
    mtd start(priority = TaskPriority.Normal)
    {
        Swag.assert(not .isStarted(), "the executor is already running")
        .priority = priority
        .stopping = false
        if Swag.jit() do
            return

        prepareWorkerContext(&.context)
        .handle = __hostThreadCreate(&executorEntry, me)
        if not .handle do
            Swag.panic("cannot start the executor thread", #curlocation)
    }

    // Returns whether the executor runs its own thread.
    mtd const isStarted()->bool => .handle != null

    // Runs every task already submitted, then stops and joins the thread. Closing an executor that
    // is not running does nothing.
    mtd close()
    {
        if not .isStarted() do
            return

        .mutex.lock()
        .stopping = true
        .mutex.unlock()
        .ready.wakeAll()

        __hostThreadJoin(.handle)
        .handle = null
    }

    // Queues `node` for the thread, or runs it here when the executor has no thread.
    internal mtd post(node: *WorkNode)
    {
        node.next     = null
        node.previous = null
        if not .isStarted()
        {
            node.state.store(WorkStateRunning)
            runWork(schedulerInstance(), node, false)
            return
        }

        // A dedicated node is never claimed by a join: it is not in the pool's ready list.
        node.state.store(WorkStateDedicated)
        .mutex.lock()
        if .tail do
            .tail.next = node
        else do
            .head = node
        .tail = node
        .mutex.unlock()
        .ready.wake()
    }

    // Takes the oldest submitted node, or returns null once the executor closes with nothing left.
    private mtd nextWork()->*WorkNode?
    {
        .mutex.lock()
        defer .mutex.unlock()

        while not .head and not .stopping do
            .ready.wait(&.mutex)

        let node = .head
        if not node do
            return null

        .head = node.next
        if not .head do
            .tail = null
        node.next = null
        node.state.store(WorkStateRunning)
        return node
    }
}

#[Swag.CallingConvention(.C)]
private func executorEntry(param: *void?)->u32
{
    let executor = cast(*Executor, param!)
    enterWorkerContext(&executor.context)
    if executor.priority == .Background do
        discard __hostThreadEnterBackground()

    let sched = schedulerInstance()
    for
    {
        let node = executor.nextWork()
        if not node do
            break
        runWork(sched, node, false)
    }

    leaveWorkerContext(&executor.context)
    return 0
}
