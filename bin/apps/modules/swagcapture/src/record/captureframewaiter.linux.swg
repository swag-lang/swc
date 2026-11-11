#global if #os == Swag.TargetOs.Linux

using Core, Linux

struct CaptureFrameWaiter
{
}

impl CaptureFrameWaiter
{
    mtd open() {}

    mtd waitUntil(tick: u64)
    {
        let deadline = timespec{cast(s64, tick / 1_000_000),
                                cast(s64, (tick % 1_000_000) * 1_000)}
        discard clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &deadline, null)
    }
}
