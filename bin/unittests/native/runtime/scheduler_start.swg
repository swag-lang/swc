#global private
#global if #os == Swag.TargetOs.Windows

#[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
{
    func CreateThread(lpThreadAttributes: *void?, dwStackSize: u64, lpStartAddress: func(*void?)->u32, lpParameter: *void?, dwCreationFlags: u32, lpThreadId: *u32?)->*void?
    func WaitForSingleObject(hHandle: *void?, dwMilliseconds: u32)->u32
    func CloseHandle(hObject: *void?)->s32
    func SwitchToThread()->s32
    func Sleep(dwMilliseconds: u32)
}

// Host threads are needed here: using a Task to race first use would already start the pool.
struct SchedulerProbe
{
    context:      Swag.Context
    handle:       *void?
    start:        Swag.AtomicFlag
    ready:        Swag.AtomicFlag
    grow:         Swag.AtomicFlag
    scheduler:    u64
    initialCount: u32
    completed:    Swag.AtomicValue'u32
    invalid:      bool
}

impl SchedulerProbe
{
    mtd join()
    {
        if not .handle do
            return
        let waited = WaitForSingleObject(.handle, 0xFFFF_FFFF)
        let closed = CloseHandle(.handle)
        .handle  = null
        .invalid = .invalid or waited != 0 or closed == 0
    }
}

func accumulateParallelProbe(values: *[4] u32)
{
    parallel for |values| index in 4 do
        values[][index] += cast(u32) index + 1
}

func probeScheduler(param: *void?)->u32
{
    let probe = cast(*SchedulerProbe) param!
    Swag.setContext(&probe.context)
    defer
    {
        probe.context.tempAllocator.release()
        probe.context.errorAllocator.release()
        Swag.releaseAllocatorThreadCache()
    }

    while not probe.start.isRaised() do
        discard SwitchToThread()

    probe.scheduler = cast(u64) Swag.schedulerInstance()
    Swag.setWorkerCount(1)
    probe.initialCount = Swag.workerCount()
    var values: [4] u32
    accumulateParallelProbe(&values)
    probe.ready.raise()
    while not probe.grow.isRaised() do
        discard SwitchToThread()

    let maximum  = probe.initialCount > 6 ? probe.initialCount : 6'u32
    var previous = probe.initialCount
    var tasks: [4] Swag.Task
    for round in 96
    {
        if round % 8 == 0 do
            Swag.setWorkerCount(1 + cast(u32) (round / 8) % 6)
        let count = Swag.workerCount()
        probe.invalid = probe.invalid or count < previous or count > maximum
        previous      = count

        // Reuse a body first called with one worker while other callers grow the pool.
        accumulateParallelProbe(&values)

        for index in 4 do
            tasks[index].submit(func|probe|() { probe.completed.add(1) })
        for index in 4 do
            tasks[3 - index].wait()
    }
    for index in 4 do
        probe.invalid = probe.invalid or values[index] != 97 * (index + 1)
    return 0
}

// Race first publication, then grow the same pool while callers submit, join and read its size.
// Smaller requests must not shrink a running pool. Completion counts check every accepted task.
// A focused run starts cold; a full suite may already have started a larger pool.
func checkSchedulerPublication()
{
    if Swag.jit() do
        return

    var probes: [4] SchedulerProbe
    defer
    {
        for &probe in probes
        {
            probe.start.raise()
            probe.grow.raise()
        }
        for &probe in probes do
            probe.join()
    }

    let allocator = Swag.getContext().allocator
    var created   = true
    for &probe in probes
    {
        probe.context.allocator        = allocator
        probe.context.defaultAllocator = allocator
        probe.handle = CreateThread(null, 0, &probeScheduler, probe, 0, null)
        if not probe.handle
        {
            created = false
            break
        }
    }
    for &probe in probes do
        probe.start.raise()

    var ready = false
    for attempt in 5000
    {
        if not created do
            break
        ready = true
        for probe in probes do
            ready = ready and probe.ready.isRaised()
        if ready do
            break
        Sleep(1)
    }

    for &probe in probes do
        probe.grow.raise()
    for &probe in probes do
        probe.join()

    Swag.assert(created and ready)
    let initialCount = probes[0].initialCount
    Swag.assert(Swag.workerCount() == (initialCount > 6 ? initialCount : 6'u32))
    for probe in probes
    {
        Swag.assert(probe.scheduler == probes[0].scheduler)
        Swag.assert(probe.initialCount >= 1 and probe.initialCount == initialCount)
        Swag.assert(not probe.invalid)
        Swag.assert(probe.completed.load() == 384)
    }
}

#test
{
    checkSchedulerPublication()
    checkSchedulerPublication()
}
