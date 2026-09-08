#global if #os == Swag.TargetOs.Windows

using Core

#[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
{
    func GetCurrentThread()->*void?
    func GetThreadTimes(thread: *void?, created, exited, kernel, user: *u64)->s32
    func Sleep(milliseconds: u32)
}

#[Swag.Safety(.Assert, true)]
func cpuMicroseconds()->u64
{
    var created, exited, kernel, user: u64
    let queried = GetThreadTimes(GetCurrentThread(), &created, &exited, &kernel, &user)
    Swag.assert(queried != 0)
    return (kernel + user) / 10
}

#[Swag.Safety(.Assert, true)]
func measure(sleeping: bool, repeats: u32)
{
    var completed: Swag.AtomicValue'u32
    var started:   Swag.AtomicFlag
    var task:      Swag.Task
    for sample in 3
    {
        var watch: Time.Stopwatch
        let before = cpuMicroseconds()
        watch.start()
        for repeat in repeats
        {
            started.reset()
            task.submit(func|&completed, &started, sleeping|()
            {
                started.raise()
                if sleeping do
                    Sleep(50)
                completed.add(1)
            })

            // Force the long join to observe a worker already executing the task. Tiny
            // tasks keep the normal race between worker execution and caller assistance.
            if sleeping
            {
                while !started.isRaised() do
                    Sleep(1)
            }

            task.wait()
        }

        watch.stop()
        let cpu = cpuMicroseconds() - before
        Swag.assert(completed.load() == (sample + 1) * repeats)
        Console.println(sleeping ? "long" : "short", " sample=", sample, " repeats=", repeats, " wall-us=", watch.elapsedMicroseconds(), " caller-cpu-us=", cpu)
    }
}

#main
{
    Swag.setWorkerCount(4)
    Swag.startWorkers()
    measure(false, 20000)
    measure(true, 10)
}
