#global private
#global if #os == Swag.TargetOs.Windows

#[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
{
    func CreateThread(attributes: *void?, stackSize: u64, entry: func(*void?)->u32, param: *void?, flags: u32, id: *u32?)->*void?
    func WaitForSingleObject(handle: *void?, milliseconds: u32)->u32
    func CloseHandle(handle: *void?)->s32
    func Sleep(milliseconds: u32)
}

func awaitFlag(flag: *Swag.AtomicFlag)->bool
{
    for attempt in 1000
    {
        if flag.isRaised() do
            return true
        Sleep(1)
    }
    return false
}

func awaitParked(count: u32)->bool
{
    let scheduler = Swag.schedulerInstance()
    for attempt in 1000
    {
        if scheduler.joining.load() >= count do
            return true
        Sleep(1)
    }
    return false
}

// A running task's join must park and wake even while unrelated accepted work stays blocked.
// The child has a bounded observation window so the old busy waiter fails without hanging.
#test
{
    if Swag.jit() do
        return
    Swag.setWorkerCount(4)
    var release, blocked, started: Swag.AtomicFlag
    var parked = false
    var blocker, target: Swag.Task
    defer
    {
        release.raise()
        blocker.wait()
    }
    blocker.submit(func|&blocked, &release|()
    {
        blocked.raise()
        while not release.isRaised() do
            Sleep(1)
    })
    target.submit(func|&started, &parked|()
    {
        started.raise()
        parked = awaitParked(1)
    })
    let blockerStarted = awaitFlag(&blocked)
    let targetStarted  = awaitFlag(&started)
    target.wait()
    let blockerPending = blocker.isPending()
    release.raise()
    blocker.wait()
    Swag.assert(blockerStarted and targetStarted and parked)
    Swag.assert(blockerPending)
    Swag.assert(Swag.schedulerInstance().joining.load() == 0)
}

struct Observer
{
    context:     Swag.Context
    handle:      *void?
    late target: *Swag.Task
    finished:    bool
}

func observe(param: *void?)->u32
{
    let observer = cast(*Observer) param!
    Swag.setContext(&observer.context)
    defer
    {
        observer.context.tempAllocator.release()
        observer.context.errorAllocator.release()
        Swag.releaseAllocatorThreadCache()
    }
    observer.target.wait()
    observer.finished = true
    return 0
}

// All observers of one running task wake. The task owner keeps its storage until the host
// observers join, and reuses it only after every previous observer has returned.
#test
{
    if Swag.jit() do
        return
    Swag.setWorkerCount(4)
    var started: Swag.AtomicFlag
    var parked = false
    var target:  Swag.Task
    for round in 8
    {
        started.reset()
        parked = false
        target.submit(func|&started, &parked|()
        {
            started.raise()
            parked = awaitParked(3)
        })
        let targetStarted = awaitFlag(&started)
        var observers: [2] Observer
        let allocator     = Swag.getContext().allocator
        for &observer in observers
        {
            observer.context.allocator        = allocator
            observer.context.defaultAllocator = allocator
            observer.target                   = &target
            observer.handle                   = CreateThread(null, 0, &observe, observer, 0, null)
        }
        target.wait()
        var joined = true
        for &observer in observers
        {
            if not observer.handle
            {
                joined = false
                continue
            }
            let waited = WaitForSingleObject(observer.handle, 0xFFFF_FFFF)
            let closed = CloseHandle(observer.handle)
            joined = joined and waited == 0 and closed != 0 and observer.finished
        }
        Swag.assert(targetStarted and parked and joined)
        Swag.assert(Swag.schedulerInstance().joining.load() == 0)
    }
}
