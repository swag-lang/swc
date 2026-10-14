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
    discard catch valued.take() as error
    Swag.assert(error is OutcomeFailure)
    if error is OutcomeFailure as failure do
        Swag.assert(failure.code == 3)

    var plain: Swag.Task
    plain.submit(func() fail { fail OutcomeFailure{4} })
    catch plain.take() as plainError
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
