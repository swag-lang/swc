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
    // Starts or resumes measuring elapsed time
    mtd start()
    {
        if !.running
        {
            .running        = true
            .startTimestamp = monotonicTicks()
        }
    }

    // Stops measuring elapsed time and accumulates the result
    mtd stop()
    {
        if .running
        {
            .accumulated += monotonicTicks() - .startTimestamp
            .running      = false
        }
    }

    // Resets the stopwatch and clears the elapsed time
    mtd reset()
    {
        @init(me, 1)
    }

    // Resets the stopwatch and immediately starts measuring elapsed time
    mtd restart()
    {
        @init(me, 1)
        .start()
    }

    // Returns whether the stopwatch is currently running.
    mtd const isRunning() => .running

    // Returns elapsed ticks, including the current running period.
    mtd const elapsedTicks()->u64
    {
        return .running ? .accumulated + monotonicTicks() - .startTimestamp : .accumulated
    }

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

    // Measures elapsed time for the current scope and prints the result when the scope ends
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
