#global namespace Swag

// The largest number of worker threads the runtime starts.
const MaxWorkers = 64'u32

// A unit of work the runtime scheduler can run once.
//
// The node is storage the submitter owns and lends to the scheduler: it must stay alive and at
// one address from submission until the work is observed finished. Programs use [[Swag.Task]],
// [[Swag.TaskGroup]], or `parallel for` rather than this node directly.
#[Swag.NoDoc]
struct WorkNode
{
    entry:    (func(*WorkNode))?     // Runs the work. Set by the owner before submission.
    next:     *WorkNode?             // Next node in the scheduler's ready stack.
    previous: *WorkNode?             // Previous ready node; permits a joined target to be removed in constant time.
    state:    AtomicValue'u32        // One of the work states below.
}

// The work has never been submitted, or its last run was collected.
internal const WorkStateIdle = 0'u32

// The work is submitted and not started.
internal const WorkStateQueued = 1'u32

// A thread is running the work.
internal const WorkStateRunning = 2'u32

// The work finished. The owner may reuse or destroy the node.
internal const WorkStateDone = 3'u32

// One worker thread and the runtime context it installs.
#[Swag.NoDoc]
struct Worker
{
    scheduler: *Scheduler?     // The pool this worker serves.
    handle:    *void?          // Host thread handle, owned by the scheduler.
    context:   Context         // This thread's own runtime context.
}

// The process-wide pool that runs submitted work.
//
// Every executable and shared library of one process compiles its own copy of the runtime, so
// the instance is published through a process anchor: whichever artifact asks first installs
// the pool, and every other artifact resolves the same one. One process therefore has one
// worker budget, not one per artifact.
#[Swag.NoDoc]
struct Scheduler
{
    mutex:     Mutex               // Guards the ready stack and the worker roster.
    ready:     Condition           // Wakes a worker when work is pushed.
    finished:  Condition           // Wakes a drain when the last accepted work ends.
    head:      *WorkNode?          // Ready work, most recently submitted first.
    accepted:  AtomicValue'u32     // Submitted and not yet finished.
    stopping:  AtomicValue'u32     // Set once, at shutdown.
    started:   AtomicValue'u32     // Set once the worker roster exists.
    count:     AtomicValue'u32     // Published worker count; the roster itself stays under the mutex.
    capacity:  u32                 // Worker slots the roster holds.
    requested: u32                 // Worker count the program asked for, zero for automatic.
    workers:   [*] Worker?         // The worker roster, allocated once.
}

// The anchor key of the scheduler inside one process.
private const SchedulerAnchorKey = 1'u32

private var g_Scheduler:      AtomicValue'u64
private var g_SchedulerMutex: Mutex
private var g_SchedulerOwned: bool     // Written before publishing the pointer; read at quiescent shutdown.

// Observe an existing roster without creating a scheduler or starting workers. A concurrent
// growth can leave this call serial; the next call observes the larger pool. Before startup
// completes, a zero count says nothing about the requested roster.
#[Swag.Inline]
internal func hasSerialWorkerPool()->bool
{
    let known = g_Scheduler.load()
    if known == 0 do
        return false

    let sched = cast(*Scheduler) known
    return sched.count.load() < 2 and sched.started.load() != 0
}

// Returns the process scheduler, creating it on first use.
//
// Creating it starts no thread and reserves no execution resource: a program that never submits
// work only pays for one small allocation.
internal func schedulerInstance()->*Scheduler
{
    var known = g_Scheduler.load()
    if known != 0 do
        return cast(*Scheduler) known

    // Serialize first use within this artifact, including the host-anchor failure path.
    // Readers acquire the published pointer without locking once initialization is complete.
    g_SchedulerMutex.lock()
    defer g_SchedulerMutex.unlock()
    known = g_Scheduler.load()
    if known != 0 do
        return cast(*Scheduler) known

    let created = cast(*Scheduler?) __bootstrapAlloc(#sizeof(Scheduler))
    if !created do
        Swag.panic("cannot allocate the runtime scheduler", #curlocation)

    let winner = cast(*Scheduler) __hostProcessSingleton(SchedulerAnchorKey, created!)
    if winner == created!
    {
        g_SchedulerOwned = true
    }
    else
    {
        // Another artifact of this process installed the pool first. Nothing has touched this
        // candidate yet, so releasing it is enough.
        __bootstrapFree(cast([*] void?) created)
    }

    g_Scheduler.store(cast(u64) winner)
    return winner
}

// Starts the process worker pool now, if it is not running yet.
//
// The pool starts on its own at the first submission, so this is only useful to move that cost
// out of the first parallel section -- a program whose first parallel work is also its most
// latency-sensitive can pay for the threads earlier.
public func startWorkers()
{
    discard activeScheduler()
}

// Returns the number of worker threads that run submitted work.
//
// Asking starts the pool, because asking is how a program sizes the partitioning it is about to
// submit. The answer is zero under compile-time execution, where work runs on the submitting
// thread.
//
// Use it to size a partitioning, never to decide whether a submitted unit will complete: a
// submitted unit always completes, on a worker or on the submitting thread.
public func workerCount()->u32
{
    let sched = activeScheduler()
    return sched.count.load()
}

// Sets how many worker threads the process runs.
//
// Zero, the default, lets the runtime choose from the host processor count. Asking for more than
// the pool currently runs starts the missing threads, up to one per host processor; asking for
// fewer never stops a running one. One process has one budget, whichever artifact sets it.
//
// Compile-time execution runs no worker at all, so the count stays zero there.
public func setWorkerCount(count: u32)
{
    let sched = schedulerInstance()
    sched.mutex.lock()
    defer sched.mutex.unlock()

    sched.requested = count
    if sched.started.load() != 0 do
        startWorkers(sched, count)
}

// Starts the worker roster once, and returns the scheduler.
private func activeScheduler()->*Scheduler
{
    let sched = schedulerInstance()
    if sched.started.load() != 0 do
        return sched

    sched.mutex.lock()
    defer sched.mutex.unlock()

    if sched.started.load() != 0 do
        return sched

    var wanted = sched.requested
    if wanted == 0
    {
        let hardware = __hostProcessorCount()
        wanted = hardware > 1 ? hardware - 1 : 1
    }

    startWorkers(sched, wanted)
    sched.started.store(1)
    return sched
}

// Brings the roster up to `wanted` threads. The caller holds the scheduler mutex.
private func startWorkers(sched: *Scheduler, wanted: u32)
{
    // Compile-time execution runs inside the compiler's own process, which owns the threads it
    // is willing to have. Work stays on the submitting thread there, which is also the
    // one-worker case every parallel construction must already handle.
    if Swag.jit() do
        return

    var target = wanted
    if target > MaxWorkers do
        target = MaxWorkers
    var count = sched.count.load()
    if target <= count do
        return

    if !sched.workers
    {
        // The roster is allocated once and never moves: a worker's context and its host thread
        // hold its address for the life of the process.
        var capacity = __hostProcessorCount()
        if capacity < target do
            capacity = target
        if capacity > MaxWorkers do
            capacity = MaxWorkers

        let workers = cast([*] Worker?) __bootstrapAlloc(cast(u64) capacity * #sizeof(Worker))
        if !workers do
            return

        sched.workers  = workers
        sched.capacity = capacity
    }

    if target > sched.capacity do
        target = sched.capacity

    let template = Swag.getContext()
    while count < target
    {
        let worker = &sched.workers![count]
        worker.scheduler = sched
        worker.context   = template[]

        // The copy still points at this thread's scratch blocks. Reset both before the worker
        // can allocate, so it owns its own storage instead of releasing the creator's.
        Swag.init(&worker.context.tempAllocator, 1)
        Swag.init(&worker.context.errorAllocator, 1)
        worker.context.hasError   = 0
        worker.context.errorIndex = 0
        worker.context.traceIndex = 0

        worker.handle = __hostThreadCreate(&schedulerWorkerEntry, worker)
        if !worker.handle do
            break
        count += 1
        sched.count.store(count)
    }
}

// Runs one node and publishes its completion.
private func runWork(sched: *Scheduler, node: *WorkNode, accounted: bool)
{
    let entry = node.entry
    if entry
    {
        let safeEntry = entry orelse func(unused: *WorkNode) {}
        safeEntry(node)
    }

    // Past this store the owner may reuse or destroy the node, so nothing may read it again.
    node.state.store(WorkStateDone)

    if accounted and sched.accepted.sub(1) == 1 do
        sched.finished.wakeAll()
}

// Claims the requested ready node, or the stack head when no target was supplied.
// Queue links and the transition to Running share the lock, so a waiter cannot claim a node
// already removed by a worker. Removing a specific target never scans unrelated queued work.
private func popWork(sched: *Scheduler, target: *WorkNode? = null)->*WorkNode?
{
    sched.mutex.lock()
    defer sched.mutex.unlock()

    let node = target orelse sched.head
    if !node do
        return null
    if node.state.load() != WorkStateQueued do
        return null

    if node.previous do
        node.previous.next = node.next
    else do
        sched.head = node.next
    if node.next do
        node.next.previous = node.previous
    node.next     = null
    node.previous = null
    node.state.store(WorkStateRunning)
    return node
}

// Runs one ready node if there is one, and returns whether it ran anything.
internal func runPendingWork()->bool
{
    let sched = schedulerInstance()
    let node  = popWork(sched)
    if !node do
        return false

    runWork(sched, node!, true)
    return true
}

private func schedulerWorkerEntry(param: *void?)->u32
{
    let worker = cast(*Worker) param!
    let sched  = worker.scheduler!

    Swag.setContext(&worker.context)
    worker.context.tempAllocator.setCapacity(__buildCfg.tempAllocatorCapacity, __runtimeAllocator())
    worker.context.errorAllocator.setCapacity(__buildCfg.errorAllocatorCapacity, __runtimeAllocator())

    for
    {
        let node = popWork(sched)
        if node
        {
            runWork(sched, node!, true)
            continue
        }

        sched.mutex.lock()
        if sched.stopping.load() != 0
        {
            sched.mutex.unlock()
            break
        }

        if !sched.head do
            sched.ready.wait(&sched.mutex)
        sched.mutex.unlock()
    }

    worker.context.tempAllocator.release()
    worker.context.errorAllocator.release()
    releaseAllocatorThreadCache()
    return 0
}

// Submits `node` for one execution.
//
// The node and everything its entry reads must stay alive until the work is observed finished.
// With no worker thread the work runs here, so a submitted unit always completes.
internal func submitWork(node: *WorkNode)
{
    let sched = activeScheduler()
    node.next     = null
    node.previous = null
    node.state.store(WorkStateQueued)

    if sched.count.load() == 0
    {
        node.state.store(WorkStateRunning)
        runWork(sched, node, false)
        return
    }

    sched.accepted.add(1)

    sched.mutex.lock()
    node.next = sched.head
    if sched.head do
        sched.head.previous = node
    sched.head = node
    sched.mutex.unlock()

    sched.ready.wake()
}

// Runs `node` if it is still queued, or waits for the thread that already claimed it.
//
// Helping stays on this join's dependency path. Running an unrelated queue entry here could
// reenter code that needs a lock held by the caller. Descendant-only joins still progress when
// every worker is busy: each joining thread can claim the specific child it needs.
internal func waitWork(node: *WorkNode)
{
    var spins = 0'u32
    for
    {
        let state = node.state.load()
        if state != WorkStateQueued and state != WorkStateRunning do
            break

        if state == WorkStateQueued
        {
            let sched   = schedulerInstance()
            let claimed = popWork(sched, node)
            if claimed
            {
                runWork(sched, claimed!, true)
                return
            }
        }

        spins += 1
        if spins >= 256
        {
            __hostThreadYield()
            spins = 0
        }
    }
}

// Runs ready work until every unit submitted to the process has finished.
//
// This is a shutdown and test convenience over the whole process, not a structured join: it
// cannot tell one owner's work from another's. Prefer waiting on the [[Swag.Task]] or
// [[Swag.TaskGroup]] that owns the work.
public func drainWork()
{
    let sched = schedulerInstance()
    while sched.accepted.load() != 0
    {
        if runPendingWork() do
            continue

        sched.mutex.lock()
        if sched.accepted.load() != 0 do
            discard sched.finished.waitFor(&sched.mutex, 1)
        sched.mutex.unlock()
    }
}

// Stops the worker threads of the artifact that installed the pool.
internal func __shutdownScheduler()
{
    let sched = g_Scheduler.load()
    if sched == 0 or !g_SchedulerOwned do
        return

    drainWork()

    let pool = cast(*Scheduler) sched
    pool.mutex.lock()
    pool.stopping.store(1)
    pool.mutex.unlock()
    pool.ready.wakeAll()

    for index in pool.count.load() do
        __hostThreadJoin(pool.workers![index].handle)

    pool.count.store(0)
    g_Scheduler.store(0)
}
