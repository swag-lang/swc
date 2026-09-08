#global private

var dropPanics: u32

func recordDropPanic(message: string?, location: Swag.SourceCodeLocation)
{
    dropPanics += 1
}

// Keep storage alive after an explicit destructor call so the old assert-only destructor can
// fail this test without leaving a queued node in an abandoned test frame.
#test
{
    var joined = false
    dropPanics = 0
    let ready = withBlockedWorkers(func|&joined|()
    {
        var completed: Swag.AtomicFlag
        var task:      Swag.Task
        task.submit(func|&completed|() { discard completed.raise() })

        let context       = Swag.getContext()
        let previousPanic = context.panic
        context.panic = &recordDropPanic
        task.opDrop()
        context.panic = previousPanic
        joined        = completed.isRaised() and task.isDone()
        task.wait()
    })
    Swag.assert(ready)
    Swag.assert(Swag.jit() or (joined and dropPanics == 0))
}

struct ParentFailure
{
    value: u64
}

func joinWhileFailing(succeeded, failed: *Swag.AtomicValue'u32) fail
{
    var task: Swag.Task
    task.submit(func|succeeded, failed|()
    {
        defer #nofail succeeded.add(1)
        defer #fail failed.add(1)
    })
    defer task.wait()
    fail ParentFailure{42}
}

func leaveTaskScope(completed, succeeded, failed, parentFailed: *Swag.AtomicValue'u32, path: u32) fail
{
    defer #fail parentFailed.add(1)
    var task: Swag.Task
    task.submit(func|completed, succeeded, failed|()
    {
        defer #nofail succeeded.add(1)
        defer #fail failed.add(1)
        completed.add(1)
    })
    if path == 1 do
        return
    if path == 2 do
        fail ParentFailure{42}
}

func raiseParentFailure(value: u64) fail
{
    fail ParentFailure{value}
}

func completeDescendants(depth: u32, completed: *Swag.AtomicValue'u32)
{
    if depth == 0
    {
        completed.add(1)
        return
    }
    var child: Swag.Task
    child.submit(func|depth, completed|() { completeDescendants(depth - 1, completed) })
}

// Successful nesting uses task frames, not the fixed-size error propagation stack.
#test
{
    var completed: Swag.AtomicValue'u32
    completeDescendants(cast(u32) Swag.MaxErrors + 8, &completed)
    Swag.assert(completed.load() == 1)
}

func dropGroupWhileFailing(succeeded, failed: *Swag.AtomicValue'u32) fail
{
    var group: Swag.TaskGroup
    group.spawn(func|succeeded, failed|()
    {
        defer #nofail succeeded.add(1)
        defer #fail failed.add(1)
        catch raiseParentFailure(7) else do
            succeeded.add(10)
    })
    fail ParentFailure{42}
}

// A child's handled failure must neither overwrite the parent's error nor change its outcome.
#test
{
    var valid = false
    let ready = withBlockedWorkers(func|&valid|()
    {
        var succeeded: Swag.AtomicValue'u32
        var failed:    Swag.AtomicValue'u32
        catch dropGroupWhileFailing(&succeeded, &failed) as error
        valid = error != null and error is ParentFailure
        if valid do
            valid = (cast(const *ParentFailure) error!).value == 42
        valid = valid and succeeded.load() == 11 and failed.load() == 0
    })
    Swag.assert(ready)
    Swag.assert(Swag.jit() or valid)
}

// Implicit destruction joins on normal exit, early return and failure, before outer cleanup.
#test
{
    var completed:    Swag.AtomicValue'u32
    var succeeded:    Swag.AtomicValue'u32
    var failed:       Swag.AtomicValue'u32
    var parentFailed: Swag.AtomicValue'u32
    for path in 3'u32
    {
        catch leaveTaskScope(&completed, &succeeded, &failed, &parentFailed, path) as error
        Swag.assert((error != null) == (path == 2))
        Swag.assert(completed.load() == path + 1)
        Swag.assert(succeeded.load() == path + 1 and failed.load() == 0)
        Swag.assert(parentFailed.load() == (path == 2 ? 1'u32 : 0'u32))
    }
}

// Array element destruction joins nested tasks too; no explicit wait is needed at either level.
#test
{
    var completed: Swag.AtomicValue'u32
    {
        var tasks: [16] Swag.Task
        for &task in tasks
        {
            task.submit(func|&completed|()
            {
                var child: Swag.Task
                child.submit(func|&completed|() { completed.add(1) })
            })
        }
    }
    Swag.assert(completed.load() == 16)
}

// Helping executes a different logical computation, even when the caller is unwinding.
#test
{
    var valid = false
    let ready = withBlockedWorkers(func|&valid|()
    {
        var succeeded: Swag.AtomicValue'u32
        var failed:    Swag.AtomicValue'u32
        catch joinWhileFailing(&succeeded, &failed) as error
        valid = error != null and error is ParentFailure
        if valid do
            valid = (cast(const *ParentFailure) error!).value == 42
        valid = valid and succeeded.load() == 1 and failed.load() == 0
    })
    Swag.assert(ready)
    Swag.assert(Swag.jit() or valid)
}

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
