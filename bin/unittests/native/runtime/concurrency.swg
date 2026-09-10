#global private

// The runtime concurrency surface, exercised where it has real worker threads. Compile-time
// execution runs every unit on the submitting thread, so only a native run can tell the two
// apart.

// A lock keeps one writer at a time on storage several partitions write.
#test
{
    var mutex: Swag.Mutex
    var count = 0'u64

    parallel for |&mutex, &count| index in 500
    {
        Swag.scopedLock(&mutex)
        count += 1
    }

    Swag.assert(count == 500)
}

// A read-write lock admits readers together and a writer alone.
#test
{
    var lock:    Swag.RWLock
    var value = 0'u64
    var readSum: Swag.AtomicValue'u64

    lock.lock()
    value = 7
    lock.unlock()

    parallel for |&lock, &value, &readSum| index in 200
    {
        Swag.scopedLockShared(&lock)
        readSum.add(value)
    }

    Swag.assert(readSum.load() == 1400)
    Swag.assert(lock.tryLock())
    lock.unlock()
}

// A condition publishes a state change to a waiter that rechecks its predicate.
#test
{
    var mutex:     Swag.Mutex
    var published: Swag.Condition
    var ready = false
    var task:      Swag.Task

    task.submit(func|&mutex, &published, &ready|()
    {
        mutex.lock()
        ready = true
        mutex.unlock()
        published.wakeAll()
    })

    // The wait is bounded: the submitting thread cannot run ready work while it is blocked on a
    // condition, so a test that waits forever would depend on a worker being free.
    mutex.lock()
    var rounds = 0
    while not ready and rounds < 5000
    {
        discard published.waitFor(&mutex, 1)
        rounds += 1
    }

    mutex.unlock()

    task.wait()
    Swag.assert(ready)
}

// A semaphore hands out exactly its permits.
#test
{
    var permits:  Swag.Semaphore
    var inFlight: Swag.AtomicValue'u32
    var peak:     Swag.AtomicValue'u32
    permits.setPermits(2)

    parallel for |&permits, &inFlight, &peak| index in 64
    {
        permits.acquire()
        let now = inFlight.add(1) + 1

        var seen = peak.load()
        while now > seen and peak.compareExchange(seen, now) != seen do
            seen = peak.load()

        inFlight.sub(1)
        permits.release()
    }

    Swag.assert(inFlight.load() == 0)
    Swag.assert(peak.load() >= 1 and peak.load() <= 2)
}

// A barrier with one participant completes each phase on arrival.
//
// A barrier among several participants belongs to threads that are all running, not to pooled
// tasks: the pool decides how many run at once, so participants that wait for each other can
// wait for one that has not started. That case is exercised where dedicated executors exist.
#test
{
    var barrier: Swag.Barrier
    var phases = 0'u32
    barrier.setParticipants(1)

    for phase in 3
    {
        if barrier.arrive() do
            phases += 1
    }

    Swag.assert(phases == 3)
}

// A group joins every child before its scope ends, and a cancelled group is a request its
// children read.
#test
{
    var done: Swag.AtomicValue'u32

    {
        var group: Swag.TaskGroup
        for index in 40 do
            group.spawn(func|&done|() { done.add(1) })
    }

    Swag.assert(done.load() == 40)

    var started: Swag.AtomicValue'u32
    {
        var group: Swag.TaskGroup
        group.cancel()
        Swag.assert(group.isCancelled())
        for index in 8
        {
            group.spawn(func|&group, &started|()
            {
                if group.isCancelled() do
                    return
                started.add(1)
            })
        }
    }

    Swag.assert(started.load() == 0)
}

// A task reports its own completion, and can be submitted again once it finished.
#test
{
    var runs: Swag.AtomicValue'u32
    var task: Swag.Task

    Swag.assert(not task.isPending() and not task.isDone())

    for round in 50
    {
        task.submit(func|&runs|() { runs.add(1) })
        task.wait()
        Swag.assert(task.isDone() and not task.isPending())
    }

    Swag.assert(runs.load() == 50)
}

// A drain covers submitted work nobody is waiting on.
#test
{
    var done:  Swag.AtomicValue'u32
    var tasks: [24] Swag.Task

    for index in 24 do
        tasks[index].submit(func|&done|() { done.add(1) })

    Swag.drainWork()

    for index in 24 do
        Swag.assert(tasks[index].isDone())
    Swag.assert(done.load() == 24)
}

// The pool exists, and asking for more workers than it runs starts them.
//
// Compile-time execution runs no worker at all, which is its own contract: the count stays zero
// and every unit runs on the submitting thread.
#test
{
    Swag.startWorkers()
    if Swag.jit()
    {
        Swag.assert(Swag.workerCount() == 0)
        return
    }

    Swag.assert(Swag.workerCount() >= 1)
    Swag.setWorkerCount(2)
    Swag.assert(Swag.workerCount() >= 2)
}
