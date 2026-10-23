#global private

// A dedicated executor runs its tasks one at a time, in submission order, on a thread of its own.
// Compile-time execution has no thread for it: each task then runs inside its submission.

struct ExecutorFailure
{
    code: u32
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
        Swag.assert(order == cast(u32, index))
    }

    executor.close()
    Swag.assert(not executor.isStarted())
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
    discard catch failing.take() as &errorOutcome
    let error = errorOutcome.value()
    Swag.assert(error is ExecutorFailure)

    let self = &watched
    watched.submit(func|self|()->bool
    {
        self.cancel()
        return Swag.isCancelled()
    }, executor: &executor)
    Swag.assert(watched.waitUnlessCancelled())
    let cancelled = expect watched.take()
    Swag.assert(cancelled)

    executor.close()
}

// Closing runs every task already submitted before the thread stops.
#test
{
    var finished: Swag.AtomicValue'u32
    var tasks:    [4] Swag.Task
    {
        var executor: Swag.Executor
        executor.start()
        for &task in tasks do
            task.submit(func|&finished|() { finished.add(1) }, executor: &executor)
    }

    Swag.assert(finished.load() == 4)
    for &task in tasks do
        Swag.assert(task.isDone())
}
