#global private

func roomySample()->Swag.WorkPressure
{
    const GiB = 1024'u64 * 1024 * 1024
    return {cpuValid: true, memoryValid: true, totalTicks: 1000, idleTicks: 900,
            physicalBytes: 32 * GiB, availableBytes: 24 * GiB,
            commitBytes: 48 * GiB, availableCommitBytes: 32 * GiB}
}

// A capable host grows past six; external CPU, physical memory and commit pressure each contract it.
#test
{
    var budget: Swag.BackgroundBudget
    var sample = roomySample()
    for 12
    {
        budget.update(sample, 22, 0)
        sample.totalTicks += 1000
        sample.idleTicks  += 900
    }
    Swag.assert(budget.limit > 6 and budget.limit <= 22)

    // This process's productive CPU is not external contention.
    sample.idleTicks    = budget.previous.idleTicks
    sample.processTicks += 1000
    budget.update(sample, 22, 0)
    Swag.assert(budget.limit > 6)

    sample.totalTicks += 1000
    budget.update(sample, 22, 0)
    Swag.assert(budget.limit == 1)

    sample = roomySample()
    for 12
    {
        budget.update(sample, 22, 0)
        sample.totalTicks += 1000
        sample.idleTicks  += 900
    }
    Swag.assert(budget.limit > 6)
    sample.availableBytes = sample.physicalBytes / 16
    budget.update(sample, 22, 12)
    Swag.assert(budget.limit == 1)

    sample = roomySample()
    for 12
    {
        budget.update(sample, 22, 0)
        sample.totalTicks += 1000
        sample.idleTicks  += 900
    }
    Swag.assert(budget.limit > 6)
    sample.availableCommitBytes = sample.commitBytes / 16
    budget.update(sample, 22, 12)
    Swag.assert(budget.limit == 1)

    sample = roomySample()
    budget.update(sample, 22, 0)
    Swag.assert(budget.limit <= 3)
    sample.cpuValid    = false
    sample.memoryValid = false
    let previous = budget.limit
    budget.update(sample, 22, 0)
    Swag.assert(budget.limit == previous)
    budget.update(sample, 1, 0)
    Swag.assert(budget.limit == 1)
}

func pauseObserver()
{
    var mutex:     Swag.Mutex
    var condition: Swag.Condition
    mutex.lock()
    defer mutex.unlock()
    discard condition.waitFor(&mutex, 1)
}

func awaitValue(value: *Swag.AtomicValue'u32, expected: u32)->bool
{
    for 3000
    {
        if value.load() == expected do
            return true
        pauseObserver()
    }
    return false
}

// Reuse nodes across both queues while workers race targeted joins and nested background work.
#test
{
    Swag.setWorkerCount(4)
    var tasks: [16] Swag.Task'u32
    for round in 32
    {
        for index in 16
        {
            tasks[index].submit(func|index|()->u32
            {
                var child: Swag.Task'u32
                child.submit(func|index|()->u32 => cast(u32, index) + 1, priority: .Background)
                return expect child.take()
            }, priority: round % 2 == 0 ? Swag.TaskPriority.Background : Swag.TaskPriority.Normal)
        }
        for index in 16
        {
            let value = expect tasks[15 - index].take()
            Swag.assert(value == 16 - index)
        }
    }
    Swag.drainWork()
    let scheduler = Swag.schedulerInstance()
    scheduler.mutex.lock()
    let running = scheduler.backgroundRunning
    let empty   = scheduler.backgroundHead == null and scheduler.backgroundTail == null
    scheduler.mutex.unlock()
    Swag.assert(running == 0 and empty)
}

// A held background slot cannot occupy the remaining workers or let newer background tasks
// pass older ones. Targeted joins still help their child while the shared budget is full.
#test
{
    if Swag.jit() do
        return
    Swag.setWorkerCount(4)
    Swag.startWorkers()
    Swag.drainWork()
    let scheduler = Swag.schedulerInstance()
    scheduler.mutex.lock()
    let savedBudget     = scheduler.backgroundBudget
    let savedPressureAt = scheduler.pressureAt
    scheduler.backgroundBudget.limit = 1
    scheduler.pressureAt = Swag.U64.Max
    scheduler.mutex.unlock()
    defer
    {
        scheduler.mutex.lock()
        scheduler.backgroundBudget = savedBudget
        scheduler.pressureAt       = savedPressureAt
        scheduler.mutex.unlock()
    }

    var release: Swag.AtomicFlag
    var running, foreground, completed: Swag.AtomicValue'u32
    var order: [8] u32
    var first, normal, helped: Swag.Task
    var queued:  [8] Swag.Task
    defer
    {
        release.raise()
        first.wait()
        normal.wait()
        helped.wait()
        for &task in queued do
            task.wait()
    }

    first.submit(func|&running, &release|()
    {
        running.store(1)
        while not release.isRaised() do
            pauseObserver()
    }, priority: .Background)
    let started = awaitValue(&running, 1)
    for index in 8
    {
        queued[index].submit(func|index, &completed, &order|()
        {
            let position = completed.load()
            order[position] = cast(u32, index)
            completed.store(position + 1)
        }, priority: .Background)
    }
    normal.submit(func|&foreground|() { foreground.store(1) })
    let foregroundRan = awaitValue(&foreground, 1)
    Swag.assert(started and foregroundRan and completed.load() == 0)

    helped.submit(func|&foreground|() { foreground.store(2) }, priority: .Background)
    helped.wait()
    Swag.assert(foreground.load() == 2 and completed.load() == 0)

    helped.submit(func|&foreground|() { foreground.store(3) }, priority: .Background)
    let waited = helped.waitUnlessCancelled()
    Swag.assert(waited and foreground.load() == 3 and completed.load() == 0)

    var demanded: [2] Swag.Task'u32
    for index in 2 do
        demanded[index].submit(func|index|()->u32 => cast(u32, index), priority: .Background)
    expect Swag.whenAll(demanded)
    for index in 2
    {
        let value = expect demanded[index].take()
        Swag.assert(value == index)
    }
    for index in 2 do
        demanded[index].submit(func|index|()->u32 => cast(u32, index), priority: .Background)
    let winner = expect Swag.whenAny(demanded)
    Swag.assert(winner < 2)
    for &task in demanded do
        task.wait()
    Swag.assert(completed.load() == 0)

    release.raise()
    // Observe completion without claiming queued nodes, so the worker admission path is tested.
    let drained = awaitValue(&completed, 8)
    Swag.assert(drained)
    for index in 8 do
        Swag.assert(order[index] == index)
    first.wait()
    for &task in queued do
        task.wait()
    scheduler.mutex.lock()
    let remaining = scheduler.backgroundRunning
    scheduler.mutex.unlock()
    Swag.assert(remaining == 0)
}
