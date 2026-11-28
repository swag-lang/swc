#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows

#[Swag.Foreign("kernel32", "Sleep", callconv: Swag.CallConv.C)]
private func sleep(milliseconds: u32)

// Registration in the executable and completion in the source dependency must use the same
// condition and waiter count and resolve to the executable's runtime state.
#test
{
    if Swag.jit()
    {
        return
    }
    Swag.setWorkerCount(4)
    Swag.startWorkers()
    let scheduler = Swag.schedulerInstance()
    Swag.require(SchedulerProvider.schedulerAddress() == cast(u64, scheduler))
    let limit = scheduler.threadLimit
    if limit != 0
    {
        Swag.require(Swag.workerCount() <= limit)
    }
    var started: Swag.AtomicFlag
    var parked = false
    var task:    Swag.Task
    for round in 16
    {
        started.reset()
        parked = false
        SchedulerProvider.submitObserved(&task, &started, &parked,
                                    priority: round % 2 == 0 ? Swag.TaskPriority.Background : Swag.TaskPriority.Normal)
        for 1000
        {
            if started.isRaised()
            {
                break
            }
            sleep(1)
        }
        task.wait()
        Swag.require(started.isRaised() and parked and task.isDone())
        if limit != 0
        {
            Swag.require(Swag.workerCount() <= limit)
        }
        Swag.require(scheduler.joining.load() == 0)
        scheduler.mutex.lock()
        let backgroundRunning = scheduler.backgroundRunning
        scheduler.mutex.unlock()
        Swag.require(backgroundRunning == 0)
    }
}
