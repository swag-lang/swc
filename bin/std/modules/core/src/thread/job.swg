#global namespace Jobs

using Threading, Swag

// Tracks internal scheduler state for one job.
#[Swag.EnumFlags]
enum JobState
{
    Zero    = 0x00000000
    Pending = 0x00000001
    Done    = 0x00000002
}

// Describes one callback that can be submitted to the global job scheduler.
//
// Keep the value alive until [[Core.Jobs.wait]] or [[Core.Jobs.waitAll]] has
// completed. The scheduler borrows both the job and `data`; it owns neither.
public struct Job
{
    public
    {
        lambda: #null func(#null *void)     // Callback invoked once, or `null` for a no-op job.
        data:   #null *void                 // Opaque caller-owned context passed to `lambda`.
    }

    // Scheduling state, owned by the job manager that runs the job.
    state:        u32 = 0                // Encoded scheduler state.
    pendingIndex: u32 = Swag.U32.Max     // Slot of the job in the pending list.
}

// Expansion-only storage used by [[Core.Jobs.parallelVisit]].
#[Swag.NoDoc]
public struct(T) SliceJob
{
    public
    {
        using base:  Job                    // Embedded base state.
        buffer:      #null const [..] T     // Buffer associated with this value.
        offset:      u32                    // Offset associated with this value.
        contextData: #null *void            // Context data associated with this value.
    }
}

// Expansion-only storage used by [[Core.Jobs.parallelFor]].
#[Swag.NoDoc]
public struct ForJob
{
    public
    {
        using base:  Job             // Embedded base state.
        startIndex:  u32             // Index of start.
        endIndex:    u32             // Index of end.
        contextData: #null *void     // Context data associated with this value.
    }
}

var g_Allocator:        #null Swag.IAllocator
var g_mustEnd:          bool
var g_workerCount:      s32
var g_workers:          Array'Thread
var g_pendingJobs:      Array'(*Job)
var g_mutexPendingJobs: Sync.Mutex
var g_eventPendingJobs: Sync.Event
var g_eventDone:        Sync.Event
var g_totalJobs:        u32

#drop
{
    if g_workerCount
    {
        g_mustEnd = true
        g_eventPendingJobs.signal()
        while Atomic.get(&g_workerCount) {}

        for &th in g_workers do
            th.wait()
        g_workers.free()
        g_pendingJobs.free()
    }
}

func workerEntry(_th: Thread)
{
    while !g_mustEnd
    {
        while peekExecJob() {}
        g_eventPendingJobs.wait()
    }

    Atomic.add(&g_workerCount, -1)
    g_eventPendingJobs.signal()
}

func runJob(job: *Job)
{
    // Execute job
    let lambda = job.lambda
    if !lambda do
        return
    let safeLambda = lambda orelse func(data: #null *void) {}
    safeLambda(job.data)

    // Done
    Sync.scopedLock(&g_mutexPendingJobs)
    setState(job, .Done)
    Debug.assert(g_totalJobs != 0)
    g_totalJobs -= 1
    if g_totalJobs == 0 do
        g_eventDone.signal()
}

func peekExecJob()->bool
{
    let job = getJobToExec()
    if !job do
        return false
    runJob(job)
    return true
}

func getJobToExec()->#null *Job
{
    Sync.scopedLock(&g_mutexPendingJobs)
    if g_pendingJobs.isEmpty() do
        return null
    let job = g_pendingJobs.popBack()
    Debug.assert(job.testState(.Pending))
    job.clearState(.Pending)
    return job
}

func removeJobNoLock(job: *Job)
{
    g_pendingJobs.removeAt(cast(u64) job.pendingIndex)
    if job.pendingIndex < g_pendingJobs.count do
        g_pendingJobs[job.pendingIndex].pendingIndex = job.pendingIndex
    job.pendingIndex = Swag.U32.Max
    job.clearState(.Pending)
}

#[Swag.Discardable]
func clearState(job: *Job, state: JobState) => Atomic.logicAnd(&job.state, ~cast(u32) state)
#[Swag.Discardable]
func setState(job: *Job, state: JobState)  => Atomic.logicOr(&job.state, cast(u32) state)
func testState(job: *Job, state: JobState) => Atomic.get(&job.state) & cast(u32) state != 0

// Returns whether jobs execute synchronously on a waiting thread.
public func isSynchronous()->bool => g_workerCount == 0

// Returns the number of active worker threads.
public func workerCount()->u32 => cast(u32) g_workerCount

// Returns whether `job` completed its most recent scheduled execution.
//
// Keep the job and its borrowed data alive until this returns true or
// [[Core.Jobs.wait]] completes.
public func isDone(job: *Job)->bool => Atomic.get(&job.state) & cast(u32) JobState.Done != 0

// Initializes the global scheduler with a fixed worker count.
//
// Pass zero to use the host processor count. Call this once, before submitting
// jobs; otherwise the scheduler remains synchronous.
public func initialize(workerCount: u32 = 0) fail
{
    Debug.assert(g_workerCount == 0)

    g_Allocator             = @getcontext().allocator
    g_workers.allocator     = g_Allocator
    g_pendingJobs.allocator = g_Allocator

    g_eventPendingJobs.init()
    g_eventDone.init(true, true)

    g_workerCount = workerCount != 0 ? workerCount : Hardware.processorCount()
    g_workers.resize(cast(u64) g_workerCount)
    for &th in g_workers do
        try th.init(&workerEntry)
    for &th in g_workers do
        try th.start()
}

// Submits a borrowed job for one execution.
public func schedule(job: *Job)
{
    Sync.scopedLock(&g_mutexPendingJobs)
    job.clearState(.Done)
    job.setState(.Pending)
    g_totalJobs += 1
    g_eventDone.reset()
    job.pendingIndex = cast(u32) g_pendingJobs.count
    g_pendingJobs.add(job)
    g_eventPendingJobs.signal()
}

// Executes available work and waits until every submitted job has completed.
public func waitAll()
{
    while peekExecJob() {}
    g_eventDone.wait()
}

// Executes available work and waits until `job` has completed.
public func wait(job: *Job)
{
    // Fast exit, without lock
    if job.testState(.Done) do
        return

    g_mutexPendingJobs.lock()

    // Job already done
    if job.testState(.Done)
    {
        g_mutexPendingJobs.unlock()
        return
    }

    // Job still in pending list, we can execute it right away
    // and leave
    if job.testState(.Pending)
    {
        removeJobNoLock(job)
        g_mutexPendingJobs.unlock()
        runJob(job)
        return
    }

    // Here, job is being processed by another thread, so we participate
    // to job execution until done flag is set
    g_mutexPendingJobs.unlock()
    while !job.testState(.Done)
    {
        discard peekExecJob()
    }
}

// Operate on a range in parallel chunks.
// Block parameters:
// - 'buffer': address of the element of the range to process
// - 'data':   contextData as passed to the macro
#[Swag.Macro]
public func(T) parallelVisit(range: [..] T, offset: u32 = 1, contextData: #null *void = null, stmt: #code(var buffer, data))
{
    if !@countof(range) do
        return
    Debug.assert(offset != 0)

    func jobEntry(jobData: #null *void)
    {
        let oneJob = cast(*SliceJob'T) jobData!
        visitSlice(oneJob.buffer, oneJob.offset, oneJob.contextData)
    }

    func visitSlice(sliceBuffer: #null const [..] T, sliceOffset: u32, sliceContextData: #null *void)
    {
        let scan = @dataof(sliceBuffer)
        if !scan do
            return
        var safeScan = scan!
        let countof  = @countof(sliceBuffer)
        for countof / sliceOffset
        {
            #inject(stmt, buffer = cast #unconst (*T) safeScan, data = sliceContextData)

            safeScan += sliceOffset
        }
    }

    // Force synchronous execution if range is too small
    let wh      = @countof(range) / offset
    let workers = Math.min(workerCount(), cast(u32) wh)
    if isSynchronous() or workers <= 1
    {
        visitSlice(range, offset, contextData)
        return
    }

    // Compute size of each chunk (and size of the last one)
    var splitSize     = wh / workers
    var lastSplitSize = splitSize + (wh - (splitSize * workers))
    splitSize     *= offset
    lastSplitSize *= offset

    // Launch jobs
    var sliceJobs: Array'(SliceJob'T)
    sliceJobs.resize(cast(u64) workers)

    var ptr = @dataof(range)
    for &j in sliceJobs
    {
        let sizeSlice = @index == sliceJobs.count - 1 ? lastSplitSize : splitSize

        j.base.lambda = &jobEntry
        j.base.data   = j
        j.offset      = offset
        j.contextData = contextData
        j.buffer      = @mkslice(ptr, sizeSlice)
        ptr           += sizeSlice

        schedule(j)
    }

    // Sync
    for &j in sliceJobs do
        wait(j)
}

// Do a for in parallel chunks.
// Block parameters:
// - 'index': current for index
// - 'data':  contextData as passed to the macro
#[Swag.Macro]
public func parallelFor(count: u32, contextData: #null *void = null, stmt: #code(index: u32, data))
{
    if !count do
        return

    func jobEntry(jobData: #null *void)
    {
        let oneJob = cast(*ForJob) jobData!
        visitFor(oneJob.startIndex, oneJob.endIndex, oneJob.contextData)
    }

    func visitFor(forStart, forEnd: u32, forContextData: #null *void)
    {
        var curIndex = forStart
        for (forEnd - forStart) + 1
        {
            #inject(stmt, index = curIndex, data = forContextData)

            curIndex += 1
        }
    }

    // Force synchronous execution if range is too small
    let workers = Math.min(workerCount(), count)
    if isSynchronous() or workers <= 1
    {
        visitFor(0, count - 1, contextData)
        return
    }

    // Compute size of each chunk (and size of the last one)
    let splitSize     = count / workers
    let lastSplitSize = splitSize + (count - (splitSize * workers))

    // Launch jobs
    var sliceJobs: Array'ForJob
    sliceJobs.resize(cast(u64) workers)

    var startIndex = 0'u32
    for &j in sliceJobs
    {
        let sizeSlice = @index == sliceJobs.count - 1 ? lastSplitSize : splitSize

        j.base.lambda = &jobEntry
        j.base.data   = j
        j.startIndex  = startIndex
        j.endIndex    = startIndex + sizeSlice - 1
        j.contextData = contextData
        startIndex    += sizeSlice

        schedule(j)
    }

    // Sync
    for &j in sliceJobs do
        wait(j)
}
