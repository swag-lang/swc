#global if #os == Swag.TargetOs.Linux
#global namespace Time

// Returns the current value of the monotonic high-resolution counter, in ticks of [[Core.Time.monotonicFrequency]].
public func monotonicTicks()->u64
{
    var value: Linux.timespec
    if Linux.clock_gettime(Linux.CLOCK_MONOTONIC, &value) != 0 do
        Swag.panic("cannot read the monotonic clock", #curlocation)
    return cast(u64, value.tv_sec) * 1_000_000_000 + cast(u64, value.tv_nsec)
}

// Returns the frequency of the monotonic counter, in ticks per second.
public func monotonicFrequency()->u64 => 1_000_000_000
