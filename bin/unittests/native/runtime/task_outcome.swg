#global private

// What a task hands back, and how a request to stop reaches the work it started. Compile-time
// execution runs a task inside its submission, so every case here also terminates there.

struct OutcomeFailure
{
    code: u32
}

// A produced value is handed over once; the task can then run again.
#test
{
    var task: Swag.Task'u64
    task.submit(func()->u64 => 6 * 7)
    let first = expect task.take()
    Swag.assert(first == 42 and not task.isDone())

    task.submit(func()->u64 => 9)
    let second = expect task.take()
    Swag.assert(second == 9)
}

// A failing body hands its error over with its dynamic type, on every result type.
#test
{
    var valued: Swag.Task'u64
    valued.submit(func()->u64 fail { fail OutcomeFailure{3} })
    var errorOutcome: Swag.Error
    discard catch valued.take() as errorOutcome
    let error = errorOutcome.value()
    Swag.assert(error is OutcomeFailure)
    if error is OutcomeFailure as failure do
        Swag.assert(failure.code == 3)

    var plain: Swag.Task
    plain.submit(func() fail { fail OutcomeFailure{4} })
    var plainErrorOutcome: Swag.Error
    catch plain.take() as plainErrorOutcome
    let plainError = plainErrorOutcome.value()
    Swag.assert(plainError is OutcomeFailure)
    if plainError is OutcomeFailure as plainFailure do
        Swag.assert(plainFailure.code == 4)

    // The next run starts from a clean outcome.
    plain.submit(func() {})
    expect plain.take()
}

var releasedOutcomes: u32

// A produced value with a destructor, counting the values released.
struct OwnedOutcome
{
    label: u32
}

impl OwnedOutcome
{
    mtd opDrop()
    {
        if .label != 0 do
            releasedOutcomes += 1
    }
}

// An owned result moves out of the task; an outcome nobody took is released by the next run.
#test
{
    releasedOutcomes = 0
    scope
    {
        var task: Swag.Task'OwnedOutcome
        task.submit(func()->OwnedOutcome => OwnedOutcome{1})
        task.wait()
        task.submit(func()->OwnedOutcome => OwnedOutcome{2})
        let taken = expect task.take()
        Swag.assert(taken.label == 2 and releasedOutcomes == 1)
    }

    Swag.assert(releasedOutcomes == 2)
}

// The notification runs once, before the task reads as done.
#test
{
    var notified: Swag.AtomicValue'u32
    var doneSeen: Swag.AtomicValue'u32
    var task:     Swag.Task'u32
    let observed = &task

    task.submit(func()->u32 => 5, func|&notified, &doneSeen, observed|()
    {
        notified.add(1)
        if observed.isDone() do
            doneSeen.add(1)
    })

    let value = expect task.take()
    Swag.assert(value == 5 and notified.load() == 1 and doneSeen.load() == 0)
}

// Outside any task, nothing was asked to stop.
#test
{
    Swag.assert(not Swag.isCancelled())
}

// A request made on a task reaches the body, every partition of a loop it runs, and every child
// of a group it spawns.
#test
{
    var task: Swag.Task'u64
    let self = &task

    task.submit(func|self|()->u64
    {
        self.cancel()
        Swag.assert(Swag.isCancelled())

        var seen: Swag.AtomicValue'u64
        parallel for |&seen| 64
        {
            if Swag.isCancelled() do
                seen.add(1)
        }

        scope
        {
            var group: Swag.TaskGroup
            for 4 do
                group.spawn(func|&seen|() { if Swag.isCancelled() do seen.add(1) })
        }

        return seen.load()
    })

    let seen = expect task.take()
    Swag.assert(seen == 68)
    Swag.assert(not Swag.isCancelled())
}

// A request belongs to one submission: the next run starts without it.
#test
{
    var task: Swag.Task'bool
    let self = &task
    task.submit(func|self|()->bool
    {
        self.cancel()
        return Swag.isCancelled()
    })
    let cancelled = expect task.take()

    task.submit(func()->bool => Swag.isCancelled())
    let fresh = expect task.take()
    Swag.assert(cancelled and not fresh)
}

// A task's own request does not leak into a task its body submits: that task can outlive the body.
#test
{
    var outer: Swag.Task'bool
    let self = &outer
    outer.submit(func|self|()->bool
    {
        self.cancel()
        var inner: Swag.Task'bool
        inner.submit(func()->bool => Swag.isCancelled())
        return expect inner.take()
    })

    let innerSaw = expect outer.take()
    Swag.assert(not innerSaw)
}

// Destroying a running task asks it to stop before waiting for it.
#test
{
    var stopped: Swag.AtomicFlag
    scope
    {
        var task: Swag.Task
        task.submit(func|&stopped|()
        {
            // Compile-time execution runs this inside the submission, before any request exists.
            let attempts = Swag.jit() ? 1'u64 : 2_000_000_000'u64
            for attempts
            {
                if Swag.isCancelled()
                {
                    discard stopped.raise()
                    return
                }
            }
        })
    }

    Swag.assert(Swag.jit() or stopped.isRaised())
}

// A group's own request reaches its children, and so does the request of the work spawning it.
#test
{
    var seen: Swag.AtomicValue'u32
    scope
    {
        var group: Swag.TaskGroup
        group.cancel()
        for 3 do
            group.spawn(func|&seen|() { if Swag.isCancelled() do seen.add(1) })
    }

    Swag.assert(seen.load() == 3)
}

// A background task runs at a lower priority and hands its value over like any other task.
#test
{
    var task: Swag.Task'u32
    task.submit(func()->u32 => 11, priority: .Background)
    let value = expect task.take()
    Swag.assert(value == 11)
}

// A task answers whether its current submission was asked to stop; the next one starts clear.
#test
{
    var task: Swag.Task
    let self = &task
    task.submit(func|self|() { self.cancel() })
    task.wait()
    Swag.assert(task.isCancelled())

    task.submit(func() {})
    task.wait()
    Swag.assert(not task.isCancelled())
}

// A cancellable join returns, with false, once the waiting work is asked to stop, while the
// awaited task keeps running; a plain join of the same task still waits for its end.
#test
{
    var release: Swag.AtomicFlag
    var awaited: Swag.Task
    awaited.submit(func|&release|()
    {
        // Compile-time execution runs this during its submission, where nothing could release it.
        while not Swag.jit() and not release.isRaised() {}
    })

    let target = &awaited
    var waiter: Swag.Task'bool
    waiter.submit(func|target|()->bool => target.waitUnlessCancelled())
    waiter.cancel()
    let finished = expect waiter.take()

    discard release.raise()
    awaited.wait()
    Swag.assert(Swag.jit() or not finished)
    Swag.assert(awaited.isDone())
}

// Outside a cancelled task, a cancellable join waits for the end like a plain one.
#test
{
    var task: Swag.Task'u32
    task.submit(func()->u32 => 3)
    Swag.assert(task.waitUnlessCancelled())
    let value = expect task.take()
    Swag.assert(value == 3)
}

// The first error a group child raises asks the other children to stop, and joining raises it.
// A joined group starts empty, without the stop request.
#test
{
    var stopped: Swag.AtomicValue'u32
    var fresh:   Swag.AtomicValue'u32
    var group:   Swag.TaskGroup
    group.spawn(func() fail { fail OutcomeFailure{7} })
    for 3
    {
        group.spawn(func|&stopped|()
        {
            // Compile-time execution runs each child during its spawn, after the failure.
            let attempts = Swag.jit() ? 1'u64 : 2_000_000_000'u64
            for attempts
            {
                if Swag.isCancelled()
                {
                    stopped.add(1)
                    return
                }
            }
        })
    }

    var errorOutcome: Swag.Error
    catch group.join() as errorOutcome
    let error = errorOutcome.value()
    Swag.assert(error is OutcomeFailure and stopped.load() == 3)

    group.spawn(func|&fresh|() { if not Swag.isCancelled() do fresh.add(1) })
    expect group.join()
    Swag.assert(fresh.load() == 1)
}

// 'whenAll' waits for every task and leaves each value to take.
#test
{
    var tasks: [3] Swag.Task'u32
    for &task, index in tasks
    {
        let value = cast(u32, index) * 10
        task.submit(func|value|()->u32 => value)
    }

    expect Swag.whenAll(tasks)
    var total = 0'u32
    for &task in tasks do
        total += expect task.take()
    Swag.assert(total == 30)
}

// 'whenAll' raises the first failure and asks the other tasks to stop.
#test
{
    var stopped: Swag.AtomicValue'u32
    var tasks:   [3] Swag.Task'u32
    tasks[0].submit(func()->u32 fail { fail OutcomeFailure{1} })
    for index in 1 until 3
    {
        tasks[index].submit(func|&stopped|()->u32
        {
            let attempts = Swag.jit() ? 1'u64 : 2_000_000_000'u64
            for attempts
            {
                if Swag.isCancelled()
                {
                    stopped.add(1)
                    return 0
                }
            }

            return 1
        })
    }

    var errorOutcome: Swag.Error
    catch Swag.whenAll(tasks) as errorOutcome
    let error = errorOutcome.value()
    Swag.assert(error is OutcomeFailure)
    Swag.assert(Swag.jit() or stopped.load() == 2)
}

// 'whenAny' returns the first task that succeeded, and raises the first error when all fail.
#test
{
    var tasks: [2] Swag.Task'u32
    tasks[0].submit(func()->u32 fail { fail OutcomeFailure{2} })
    tasks[1].submit(func()->u32 => 5)
    let winner = expect Swag.whenAny(tasks)
    Swag.assert(winner == 1)
    let value = expect tasks[1].take()
    Swag.assert(value == 5)

    var failing: [2] Swag.Task'u32
    failing[0].submit(func()->u32 fail { fail OutcomeFailure{3} })
    failing[1].submit(func()->u32 fail { fail OutcomeFailure{4} })
    var errorOutcome: Swag.Error
    discard catch Swag.whenAny(failing) as errorOutcome
    let error = errorOutcome.value()
    Swag.assert(error is OutcomeFailure)
    if error is OutcomeFailure as failure do
        Swag.assert(failure.code == 3)
}

// The task's capture ends before take() reads its copied message.
func failWithTaskMessage()->s32 fail
{
    let context = Swag.getContext()
    if not context.errorAllocator.capacity do
        context.errorAllocator.setCapacity(64, unwrap context.allocator)
    let allocator = Swag.makeInterface(&context.errorAllocator, Swag.ScratchAllocator, Swag.IAllocator)
    let text      = "a task retains the copied text of its failure"
    var request: Swag.AllocatorRequest
    request.size = text.count
    allocator.alloc(&request)
    let bytes = cast([*] u8, unwrap request.address)
    Swag.memcpy(bytes, text.buffer, text.count)
    fail Swag.BaseError{Swag.makeString(bytes, text.count)}
}

#test
{
    var task: Swag.Task's32
    task.submit(func()->s32 fail { return try failWithTaskMessage() })
    task.wait()
    var handled = false
    discard catch task.take()
    {
        handled = true
        let failure = assume cast(Swag.BaseError, Swag.err)
        Swag.assert(failure.message == "a task retains the copied text of its failure")
    }
    Swag.assert(handled)
}
