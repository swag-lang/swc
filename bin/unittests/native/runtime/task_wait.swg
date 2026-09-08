#global private

// Workers and joining callers race to claim nodes while several parents submit and reuse them.
#test
{
    var total: Swag.AtomicValue'u32
    parallel for |&total| parent in 16
    {
        var tasks: [8] Swag.Task
        for round in 16
        {
            for index in 8 do
                tasks[index].submit(func|&total, index|() { total.add(cast(u32) index + 1) })
            for index in 8 do
                tasks[(index * 5) % 8].wait()
        }
    }
    Swag.assert(total.load() == 9216)
}

// Hold every worker on an external gate so only the calling thread can execute queued work.
// The caller opens the gate before joining the blockers; no pooled task must release a peer.
func withBlockedWorkers(body: func||())->bool
{
    if Swag.jit() do
        return true

    Swag.setWorkerCount(2)
    let workers = Swag.workerCount()
    var mutex:    Swag.Mutex
    var gate:     Swag.Condition
    var open    = false
    var started:  Swag.AtomicValue'u32
    var blockers: [Swag.MaxWorkers] Swag.Task
    defer
    {
        mutex.lock()
        open = true
        mutex.unlock()
        gate.wakeAll()
        for index in workers do
            blockers[index].wait()
    }

    for index in workers
    {
        blockers[index].submit(func|&mutex, &gate, &open, &started|()
        {
            mutex.lock()
            started.add(1)
            while !open do
                gate.wait(&mutex)
            mutex.unlock()
        })
    }

    for attempt in 5000
    {
        mutex.lock()
        let ready = started.load() == workers
        if !ready do
            discard gate.waitFor(&mutex, 1)
        mutex.unlock()
        if ready
        {
            body()
            return true
        }
    }
    return false
}

// Waiting under a lock must not run an unrelated task that needs that lock. tryLock records
// the reentrant execution instead of deadlocking the test on the old scheduler.
#test
{
    var invalid = false
    let ready   = withBlockedWorkers(func|&invalid|()
    {
        var lock:      Swag.Mutex
        var premature: Swag.AtomicFlag
        var completed: Swag.AtomicValue'u32
        var target:    Swag.Task
        var unrelated: Swag.Task
        lock.lock()
        target.submit(func|&completed|() { completed.add(1) })
        unrelated.submit(func|&lock, &premature|()
        {
            let acquired = lock.tryLock()
            if acquired do
                lock.unlock()
            else do
                discard premature.raise()
        })

        target.wait()
        lock.unlock()
        unrelated.wait()
        invalid = completed.load() != 1 or premature.isRaised()
    })
    Swag.assert(ready)
    Swag.assert(!invalid)
}

// Remove queued targets from the middle, tail, and head, then reuse their storage. No other
// task may run as a side effect of a wait, and every submitted node must still run once.
#test
{
    var invalid = false
    let ready   = withBlockedWorkers(func|&invalid|()
    {
        var tasks:    [5] Swag.Task
        var runs:     [5] Swag.AtomicValue'u32
        var expected: [5] u32
        let order:    [5] u32 = [2, 0, 4, 1, 3]
        for round in 3
        {
            for index in 5 do
                tasks[index].submit(func|&runs, index|() { runs[index].add(1) })
            for index in order
            {
                tasks[index].wait()
                expected[index] += 1
                for other in 5 do
                    invalid = invalid or runs[other].load() != expected[other]
            }
        }
    })
    Swag.assert(ready)
    Swag.assert(!invalid)
}

// Descendant-only joins and structured loops must progress even while every worker is busy.
#test
{
    var invalid = false
    let ready   = withBlockedWorkers(func|&invalid|()
    {
        var total:  Swag.AtomicValue'u32
        var parent: Swag.Task
        parent.submit(func|&total|()
        {
            var group: Swag.TaskGroup
            for index in 40 do
                group.spawn(func|&total|() { total.add(1) })
        })
        parent.wait()
        parallel for |&total| row in 7
        {
            parallel for |&total| column in 5 do
                total.add(1)
        }
        invalid = total.load() != 75
    })
    Swag.assert(ready)
    Swag.assert(!invalid)
}
