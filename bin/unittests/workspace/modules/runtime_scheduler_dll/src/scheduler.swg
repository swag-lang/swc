#global if #os == Swag.TargetOs.Windows

#[Swag.Foreign("kernel32", "Sleep")]
private func sleep(milliseconds: u32)

public func schedulerAddress()->u64 => cast(u64) Swag.schedulerInstance()

// The entry and completion publisher belong to this DLL; the observer belongs to its importer.
public func submitObserved(task: *Swag.Task, started: *Swag.AtomicFlag, parked: *bool)
{
    task.submit(func|started, parked|()
    {
        started.raise()
        let scheduler = Swag.schedulerInstance()
        for attempt in 1000
        {
            if scheduler.joining.load() != 0
            {
                parked[] = true
                return
            }
            sleep(1)
        }
    })
}
