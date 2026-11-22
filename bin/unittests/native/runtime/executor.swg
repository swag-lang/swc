#global private

// A dedicated executor runs its tasks one at a time, in submission order, on a thread of its own.
// Compile-time execution has no thread for it: each task then runs inside its submission.

struct ExecutorFailure
{
    code: u32
}

var g_ClosingExecutorNode: Swag.WorkNode

func awaitExecutorFlag(flag: *Swag.AtomicFlag)->bool
{
    for 1_000_000
    {
        if flag.isRaised() do
            return true
    }
    return flag.isRaised()
}

func awaitExecutorStopping(executor: *Swag.Executor)->bool
{
    for 1000
    {
        executor.mutex.lock()
        let stopping = executor.stopping
        if not stopping do
            discard executor.ready.waitFor(&executor.mutex, 1)
        let stopped = executor.stopping
        executor.mutex.unlock()
        if stopped do
            return true
    }
    return false
}

// Tasks run in the order they were submitted, and each hands its value over.
#test
{
    var next:     Swag.AtomicValue'u32
    var tasks:    [8] Swag.Task'u32
    var executor: Swag.Executor
    executor.start()

    for &task in tasks do
        task.submit(func|&next|()->u32 => next.add(1), executor: &executor)

    for &task, index in tasks
    {
        let order = expect task.take()
        Swag.require(order == cast(u32, index))
    }

    executor.close()
    Swag.require(not executor.isStarted())
}

// A failing task hands its error over; a cancelled one sees the request; joins never run it.
#test
{
    var failing:  Swag.Task'u32
    var watched:  Swag.Task'bool
    var executor: Swag.Executor
    executor.start(.Background)

    failing.submit(func()->u32 fail { fail ExecutorFailure{9} }, executor: &executor)
    var errorOutcome: Swag.Error
    discard catch failing.take() as errorOutcome
    let error = errorOutcome.value()
    Swag.require(error is ExecutorFailure)

    let self = &watched
    watched.submit(func|self|()->bool
    {
        self.cancel()
        return Swag.isCancelled()
    }, executor: &executor)
    Swag.require(watched.waitUnlessCancelled())
    let cancelled = expect watched.take()
    Swag.require(cancelled)

    executor.close()
}

// Closing runs every task already submitted before the thread stops.
#test
{
    var finished: Swag.AtomicValue'u32
    var tasks:    [4] Swag.Task
    scope
    {
        var executor: Swag.Executor
        executor.start()
        for &task in tasks do
            task.submit(func|&finished|() { finished.add(1) }, executor: &executor)
    }

    Swag.require(finished.load() == 4)
    for &task in tasks do
        Swag.require(task.isDone())
}

// Closing from the executor's own thread is rejected instead of joining itself.
struct ExecutorCloseProbe
{
    caught:   Swag.AtomicFlag
    task:     Swag.Task
    executor: Swag.Executor
}

#test
{
    var probe: ExecutorCloseProbe
    probe.executor.start()
    probe.task.submit(func|&probe|()
    {
        let result = Swag.catchPanic(func|&probe|() { probe.executor.close() })
        if result.raised do
            discard probe.caught.raise()
    }, executor: &probe.executor)
    expect probe.task.take()
    Swag.require(probe.caught.isRaised() == (not Swag.jit()))
    probe.executor.close()
}

// A submission during close is rejected while a task holds the executor thread open.
#test
{
    if Swag.jit() do
        return

    Swag.setWorkerCount(2)
    var started, release, closeStarted: Swag.AtomicFlag
    var blocker:  Swag.Task
    var executor: Swag.Executor
    var closer:   Swag.Task
    executor.start()
    defer
    {
        release.raise()
        blocker.wait()
        closer.wait()
        executor.close()
    }

    blocker.submit(func|&started, &release|()
    {
        started.raise()
        while not release.isRaised() {}
    }, executor: &executor)
    Swag.require(awaitExecutorFlag(&started))

    closer.submit(func|&executor, &closeStarted|()
    {
        closeStarted.raise()
        executor.close()
    })
    Swag.require(awaitExecutorFlag(&closeStarted))
    Swag.require(awaitExecutorStopping(&executor))
    Swag.require(blocker.isPending())

    let accepted = executor.post(&g_ClosingExecutorNode)
    Swag.require(not accepted)
    Swag.require(executor.head == null and g_ClosingExecutorNode.state.load() == Swag.WorkStateIdle)

    release.raise()
    blocker.wait()
    closer.wait()
    Swag.require(not executor.isStarted())
}
