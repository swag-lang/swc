#global if #os == Swag.TargetOs.Linux
#global namespace Threading

internal func sleepNative(milliseconds: u32)
{
    var deadline: Linux.timespec
    if Linux.clock_gettime(Linux.CLOCK_MONOTONIC, &deadline) != 0 do
        Swag.panic("cannot read the monotonic clock", #curlocation)
    deadline.tv_sec  += cast(s64, milliseconds / 1000)
    deadline.tv_nsec += cast(s64, milliseconds % 1000) * 1_000_000
    if deadline.tv_nsec >= 1_000_000_000
    {
        deadline.tv_nsec -= 1_000_000_000
        deadline.tv_sec  += 1
    }

    // Retrying the same absolute deadline avoids drift when signals interrupt the wait.
    for
    {
        let error = Linux.clock_nanosleep(Linux.CLOCK_MONOTONIC, Linux.TIMER_ABSTIME, &deadline, null)
        if error == 0 do
            return
        if error != Linux.EINTR do
            Swag.panic("cannot sleep the current thread", #curlocation)
    }
}

internal func yieldNative()
{
    if Linux.sched_yield() != 0 do
        Swag.panic("cannot yield the current thread", #curlocation)
}
