#global namespace Time

// Measures elapsed monotonic time across one or more start/stop periods.
public struct Stopwatch
{
    internal
    {
        running:        bool
        startTimestamp: u64
        accumulated:    u64
    }
}

public impl Stopwatch
{
    // Starts or resumes measuring elapsed time; a running stopwatch is unchanged.
    mtd start()
    {
        if not .running
        {
            .running        = true
            .startTimestamp = monotonicTicks()
        }
    }

    // Stops measuring and adds the current period to the elapsed time.
    mtd stop()
    {
        if .running
        {
            .accumulated += monotonicTicks() - .startTimestamp
            .running     = false
        }
    }

    // Stops the stopwatch and clears the elapsed time.
    mtd reset()
    {
        Swag.init(me, 1)
    }

    // Clears the elapsed time and starts measuring again.
    mtd restart()
    {
        .reset()
        .start()
    }

    // Returns whether the stopwatch is currently running.
    mtd const isRunning()->bool => .running

    // Returns the elapsed time in ticks of [[Core.Time.monotonicFrequency]], including the current running period.
    mtd const elapsedTicks()->u64 => .running ? .accumulated + monotonicTicks() - .startTimestamp : .accumulated

    // Returns total elapsed time in milliseconds.
    mtd const elapsedMilliseconds()->u64
    {
        let ticks     = .elapsedTicks()
        let frequency = monotonicFrequency()
        return (ticks / frequency) * 1000 + ((ticks % frequency) * 1000) / frequency
    }

    // Returns total elapsed time in microseconds.
    mtd const elapsedMicroseconds()->u64
    {
        let ticks     = .elapsedTicks()
        let frequency = monotonicFrequency()
        return (ticks / frequency) * 1000000 + ((ticks % frequency) * 1000000) / frequency
    }

    // Measures the rest of the calling scope and prints `name` with the elapsed milliseconds when it ends.
    #[Swag.Mixin]
    func scopeMeasure(name: string = "stopwatch")
    {
        var #uniq0: Time.Stopwatch
        #uniq0.start()
        defer
        {
            #uniq0.stop()
            Console.printf("%: %ms\n", name, #uniq0.elapsedMilliseconds())
        }
    }
}
