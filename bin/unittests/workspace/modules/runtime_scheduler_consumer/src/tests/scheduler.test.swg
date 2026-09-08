#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows

#[Swag.Foreign("kernel32", "Sleep")]
private func sleep(milliseconds: u32)

// Registration in the executable and completion in the DLL must use the same condition and
// waiter count, even though each artifact compiles its own runtime implementation.
#test
{
    if Swag.jit() do
        return
    Swag.setWorkerCount(4)
    let scheduler = Swag.schedulerInstance()
    Swag.assert(SchedulerDll.schedulerAddress() == cast(u64) scheduler)
    var started: Swag.AtomicFlag
    var parked = false
    var task:    Swag.Task
    for round in 16
    {
        started.reset()
        parked = false
        SchedulerDll.submitObserved(&task, &started, &parked)
        for attempt in 1000
        {
            if started.isRaised() do
                break
            sleep(1)
        }
        task.wait()
        Swag.assert(started.isRaised() and parked and task.isDone())
        Swag.assert(scheduler.joining.load() == 0)
    }
}
