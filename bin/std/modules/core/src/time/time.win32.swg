#global if WINDOWS
#global namespace Time

using Win32

var g_PerfCounterFreq: u64

#init
{
    QueryPerformanceFrequency(cast() &g_PerfCounterFreq)
}

// Returns the current value of the monotonic high-resolution counter, in ticks of [[Core.Time.monotonicFrequency]].
public func monotonicTicks()->u64
{
    var counter: u64
    QueryPerformanceCounter(cast() &counter)
    return counter
}

// Returns the frequency of the monotonic counter, in ticks per second.
public func monotonicFrequency()->u64 => g_PerfCounterFreq
