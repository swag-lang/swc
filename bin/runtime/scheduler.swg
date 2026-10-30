#global namespace Swag

// The largest number of worker threads the runtime starts.
//
// The bound is a deliberate policy, not a machine limit. A parallel range reserves one runner per
// worker in the frame that dispatches it, so this number is also the stack every parallel section
// touches. A host with more processors than this uses the first sixty-four of them; raising the
// bound means moving that runner storage off the stack first.
const MaxWorkers = 64'u32

// The number of parked observers a completion can single out.
//
// It must be a power of two, because a node picks its first candidate slot by masking its own address. A
// process with more parked observers than slots keeps the correct but unselective behaviour: completions wake
// every one.
const MaxObservers = 64'u32

// A unit of work the runtime scheduler can run once.
//
// The node is storage the submitter owns and lends to the scheduler: it must stay alive and at
// one address from submission until the work is observed finished. Programs use [[Swag.Task]],
// [[Swag.TaskGroup]], or `parallel for` rather than this node directly.
#[Swag.NoDoc]
#[Swag.DynCast]
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

// The work is queued on an [[Swag.Executor]], which alone may start it: no join claims it.
internal const WorkStateDedicated = 4'u32

// Returns whether a node in `state` still has work to start or finish.
#[Swag.Inline]
internal func isWorkPending(state: u32)->bool => state == WorkStateQueued or state == WorkStateRunning or state == WorkStateDedicated

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
    finished:  Condition           // Wakes completion observers and process drains.
    head:      *WorkNode?          // Ready work, most recently submitted first.
    accepted:  AtomicValue'u32     // Submitted and not yet finished.
    joining:   AtomicValue'u32     // Registered completion waiters; each registration holds the mutex.
    stopping:  AtomicValue'u32     // Set once, at shutdown.
    started:   AtomicValue'u32     // Set once the worker roster exists.
    count:     AtomicValue'u32     // Published worker count; the roster itself stays under the mutex.
    observed:  [MaxObservers] AtomicValue'u64     // The node address each parked observer waits for; zero when the slot is free.
    occupancy: AtomicValue'u64     // One bit per taken slot, so a completion reads one cache line instead of every slot.
    unslotted: AtomicValue'u32     // Parked observers that found no free slot, and therefore still need a broadcast.
    capacity:  u32                 // Worker slots the roster holds.
    requested: u32                 // Worker count the program asked for, zero for automatic.
    workers:   [*] Worker?         // The worker roster, allocated once.
}

// The anchor key of the scheduler inside one process.
private const SchedulerAnchorKey = 1'u32

private var g_Scheduler:      AtomicValue'u64
private var g_SchedulerMutex: Mutex
private var g_SchedulerOwned: bool     // Written before publishing the pointer; read at quiescent shutdown.

// Observe an existing roster without creating a scheduler or starting workers.
//
// A concurrent growth can leave this call serial; the next call observes the larger pool. Before startup
// completes, a zero count says nothing about the requested roster.
#[Swag.Inline]
internal func hasSerialWorkerPool()->bool
{
    let known = g_Scheduler.load()
    if known == 0 do
        return false

    let sched = cast(*Scheduler, known)
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
        return cast(*Scheduler, known)

    // Serialize first use within this artifact, including the host-anchor failure path.
    // Readers acquire the published pointer without locking once initialization is complete.
    g_SchedulerMutex.lock()
    defer g_SchedulerMutex.unlock()
    known = g_Scheduler.load()
    if known != 0 do
        return cast(*Scheduler, known)

    let created = cast(*Scheduler?, __bootstrapAlloc(#sizeof(Scheduler)))
    if not created do
        Swag.panic("cannot allocate the runtime scheduler", #curlocation)

    let winner = cast(*Scheduler, __hostProcessSingleton(SchedulerAnchorKey, created))
    if winner == created
    {
        g_SchedulerOwned = true
    }
    else
    {
        // Another artifact of this process installed the pool first. Nothing has touched this
        // candidate yet, so releasing it is enough.
        __bootstrapFree(cast([*] void?, created))
    }

    g_Scheduler.store(cast(u64, winner))
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

    startWorkers(sched, sched.requested)
    sched.started.store(1)
    return sched
}

// Resolve every request through the same policy, including a return to automatic after startup.
internal func schedulerWorkerTarget(requested, hardware: u32)->u32
{
    var available = hardware == 0 ? 1'u32 : hardware
    var target    = requested
    if target == 0 do
        target = available > 1 ? available - 1 : 1
    if available > MaxWorkers do
        available = MaxWorkers
    return target > available ? available : target
}

// Brings the roster up to `wanted` threads. The caller holds the scheduler mutex.
private func startWorkers(sched: *Scheduler, wanted: u32)
{
    // Compile-time execution runs inside the compiler's own process, which owns the threads it
    // is willing to have. Work stays on the submitting thread there, which is also the
    // one-worker case every parallel construction must already handle.
    if Swag.jit() do
        return

    let hardware = __hostProcessorCount()
    var target   = schedulerWorkerTarget(wanted, hardware)
    var count    = sched.count.load()
    if target <= count do
        return

    if not sched.workers
    {
        // The roster is allocated once and never moves: a worker's context and its host thread
        // hold its address for the life of the process.
        var capacity = hardware
        if capacity > MaxWorkers do
            capacity = MaxWorkers

        let workers = cast([*] Worker?, __bootstrapAlloc(cast(u64, capacity) * #sizeof(Worker)))
        if not workers do
            return

        sched.workers  = workers
        sched.capacity = capacity
    }

    if target > sched.capacity do
        target = sched.capacity

    while count < target
    {
        let worker = &sched.workers![count]
        worker.scheduler = sched
        prepareWorkerContext(&worker.context)

        worker.handle = __hostThreadCreate(&schedulerWorkerEntry, worker)
        if not worker.handle do
            break
        count += 1
        sched.count.store(count)
    }
}

// Gives a thread the runtime is about to start a context of its own, copied from this thread's.
//
// The copy keeps the settings but still points at this thread's scratch blocks; resetting it
// lets the new thread own its storage instead of releasing the creator's. The thread serves
// every later task, whatever allocator was active where it started, so it starts from the default
// one.
internal func prepareWorkerContext(context: *Context)
{
    context[] = Swag.getContext()[]
    context.resetThreadState()
    if let allocator = context.defaultAllocator do
        context.allocator = allocator
}

// Installs a prepared context on the calling thread and gives its scratch allocators their capacity.
internal func enterWorkerContext(context: *Context)
{
    Swag.setContext(context)
    context.tempAllocator.setCapacity(__buildCfg.tempAllocatorCapacity, __runtimeAllocator())
    context.errorAllocator.setCapacity(__buildCfg.errorAllocatorCapacity, __runtimeAllocator())
}

// Releases what a worker context owns before its thread ends.
internal func leaveWorkerContext(context: *Context)
{
    context.tempAllocator.release()
    __releaseErrContext(context)
    releaseAllocatorThreadCache()
}

// Runs one node and publishes its completion.
private func runWork(sched: *Scheduler, node: *WorkNode, accounted: bool)
{
    // The address is kept before the work runs, because the registry below is consulted after
    // this node may already belong to someone else.
    let address = cast(u64, node)
    let entry   = node.entry
    if entry
    {
        let safeEntry = entry orelse func(unused: *WorkNode) {}
        safeEntry(node)
    }

    // Past this store the owner may reuse or destroy the node, so nothing may read it again.
    //
    // It stays sequentially consistent: this store and the observer reads below pair with an
    // observer's registration and its own read of the state. A release store would let both
    // threads read the old value, and a parked observer would miss this completion.
    node.state.store(WorkStateDone)

    let drained = accounted and sched.accepted.sub(1) == 1
    if sched.joining.load() != 0 and hasWorkObserver(sched, address)
    {
        wakeWorkObservers(sched)
        return
    }

    if drained do
        sched.finished.wakeAll()
}

// Whether a parked observer is waiting for this node.
//
// The registry is the scheduler's own storage and holds addresses, never node contents, so it
// stays readable after a completion has released its node. An address that a new node reused
// only produces an extra wake, and every observer rechecks its own state after one.
#[Swag.NoInline]
private func hasWorkObserver(sched: *Scheduler, address: u64)->bool
{
    if sched.unslotted.load() != 0 do
        return true

    // Walking the taken slots keeps an idle registry to one load, which is what most completions
    // see: a parked observer is rare, and a completion must not pay for the slots nobody uses.
    var taken = sched.occupancy.load()
    while taken != 0
    {
        let index = Swag.trailingZeros(taken)
        if sched.observed[index].load() == address do
            return true
        taken &= taken - 1
    }

    return false
}

// Publishes `address` in a free registry slot, and returns the slot that must be released after
// the wait. `MaxObservers` means every slot was taken: that observer is counted separately and
// every completion broadcasts while it waits.
//
// The publication precedes the observer's own state check, and a completion publishes Done before
// reading the registry. One of the two therefore always observes the other.
private func claimObserverSlot(sched: *Scheduler, address: u64)->u32
{
    let first = cast(u32, ((address >> 5) & cast(u64, (MaxObservers - 1))))
    for offset in MaxObservers
    {
        let index = (first + offset) & (MaxObservers - 1)
        if sched.observed[index].load() != 0 do
            continue
        if sched.observed[index].compareExchange(0, address) == 0
        {
            discard sched.occupancy.bitOr(1'u64 << index)
            return index
        }
    }

    discard sched.unslotted.add(1)
    return MaxObservers
}

private func releaseObserverSlot(sched: *Scheduler, slot: u32)
{
    if slot >= MaxObservers
    {
        discard sched.unslotted.sub(1)
        return
    }

    // The bit goes first: a completion that still sees it reads an address the observer no longer
    // waits for, which costs one extra wake and nothing else.
    discard sched.occupancy.bitAnd(~(1'u64 << slot))
    sched.observed[slot].store(0)
}

// Only registered observers need the completion lock. Registration precedes the observer's
// state check, and Done precedes this registration check: sequential consistency guarantees
// either a wake under the mutex or observation of Done before sleeping. No access to the
// completed node is permitted here; its owner may already have reused or released it.
#[Swag.NoInline]
private func wakeWorkObservers(sched: *Scheduler)
{
    sched.mutex.lock()
    sched.finished.wakeAll()
    sched.mutex.unlock()
}

// Claims the requested ready node, or the stack head when no target was supplied.
// Queue links and the transition to Running share the lock, so a waiter cannot claim a node
// already removed by a worker. Removing a specific target never scans unrelated queued work.
private func popWork(sched: *Scheduler, target: *WorkNode? = null)->*WorkNode?
{
    sched.mutex.lock()
    defer sched.mutex.unlock()

    let node = target orelse sched.head
    if not node do
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
    if not node do
        return false

    runWork(sched, node, true)
    return true
}

#[Swag.CallingConvention(.C)]
private func schedulerWorkerEntry(param: *void?)->u32
{
    let worker = cast(*Worker, unwrap param)
    let sched  = unwrap worker.scheduler

    enterWorkerContext(&worker.context)

    for
    {
        let node = popWork(sched)
        if node
        {
            runWork(sched, node, true)
            continue
        }

        sched.mutex.lock()
        if sched.stopping.load() != 0
        {
            sched.mutex.unlock()
            break
        }

        if not sched.head do
            sched.ready.wait(&sched.mutex)
        sched.mutex.unlock()
    }

    leaveWorkerContext(&worker.context)
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
        if not isWorkPending(state) do
            break

        if state == WorkStateQueued
        {
            let sched   = schedulerInstance()
            let claimed = popWork(sched, node)
            if claimed
            {
                runWork(sched, claimed, true)
                return
            }
        }

        spins += 1
        if spins >= 256
        {
            discard parkWorkObserver(node, cancellable: false)
            return
        }
    }
}

// Waits like `waitWork`, but returns false as soon as the work running on this thread is asked
// to stop, and true once `node` has finished.
//
// It never runs `node` itself: a thread running the work it waits for could not notice the request
// until that work ends. A worker runs it instead; with no worker, it already ran when submitted.
internal func waitWorkUnlessCancelled(node: *WorkNode)->bool
{
    var spins = 0'u32
    for
    {
        let state = node.state.load()
        if not isWorkPending(state) do
            return true
        if isCancelled() do
            return false

        spins += 1
        if spins >= 256 do
            return parkWorkObserver(node, cancellable: true)
    }
}

// Parks until `check` answers true, which is how a thread waits on several nodes at once.
//
// While it waits, every completion and every cancellation request wakes it to ask again, so
// `check` must only read state those publish. The caller counts as an observer without a slot
// before asking, and a completion publishes Done before reading that count: one of the two always
// sees the other. It never runs the nodes itself.
internal func waitWorkChange(check: func||()->bool)
{
    if check() do
        return

    let sched = schedulerInstance()
    discard sched.unslotted.add(1)
    sched.mutex.lock()
    sched.joining.add(1)
    defer
    {
        sched.joining.sub(1)
        sched.mutex.unlock()
        discard sched.unslotted.sub(1)
    }

    while not check() do
        sched.finished.wait(&sched.mutex)
}

// Wakes the parked observers so a cancellable one can notice that its work was asked to stop.
//
// A request names no node, and requests are rare, so every parked observer wakes and rechecks.
// The request is raised before this reads the parked count, and an observer counts itself before
// reading the request, so one of the two always sees the other.
internal func wakeCancelledObservers()
{
    let known = g_Scheduler.load()
    if known == 0 do
        return

    let sched = cast(*Scheduler, known)
    if sched.joining.load() != 0 do
        wakeWorkObservers(sched)
}

// Queued descendants are claimed above before parking is considered. A long-running child
// therefore does not burn its observer's CPU, while short joins retain the lock-free poll.
// Returns whether `node` finished; a `cancellable` observer also returns, with false, once the
// work running on this thread is asked to stop.
#[Swag.NoInline]
private func parkWorkObserver(node: *WorkNode, cancellable: bool)->bool
{
    let sched = schedulerInstance()
    let slot  = claimObserverSlot(sched, cast(u64, node))

    sched.mutex.lock()
    sched.joining.add(1)
    defer
    {
        sched.joining.sub(1)
        sched.mutex.unlock()
        releaseObserverSlot(sched, slot)
    }

    for
    {
        let state = node.state.load()
        if not isWorkPending(state) do
            return true
        if cancellable and isCancelled() do
            return false
        sched.finished.wait(&sched.mutex)
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
    if sched == 0 or not g_SchedulerOwned do
        return

    drainWork()

    let pool = cast(*Scheduler, sched)
    pool.mutex.lock()
    pool.stopping.store(1)
    pool.mutex.unlock()
    pool.ready.wakeAll()

    for index in pool.count.load() do
        __hostThreadJoin(pool.workers![index].handle)

    pool.count.store(0)
    g_Scheduler.store(0)
}
