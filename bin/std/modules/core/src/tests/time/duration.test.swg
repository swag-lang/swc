#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let zero = Time.Duration.fromSeconds(0)
    @assert(zero.seconds == 0)
    @assert(zero.milliseconds() == 0)

    let zeroSeconds: Time.Duration = 0's
    @assert(zeroSeconds.seconds == 0)
    @assert(zeroSeconds.milliseconds() == 0)

    let zeroMilliseconds: Time.Duration = 0'ms
    @assert(zeroMilliseconds.seconds == 0)
    @assert(zeroMilliseconds.milliseconds() == 0)

    let from250Milliseconds = Time.Duration.fromMilliseconds(250)
    @assert(from250Milliseconds.seconds == 0.25)
    @assert(from250Milliseconds.milliseconds() == 250)

    let oneMs: Time.Duration = 1'ms
    @assert(Math.isEqualEpsilon(oneMs.seconds, 0.001, 0.00001))
    @assert(oneMs.milliseconds() == 1)

    let seconds: Time.Duration = 5's
    @assert(seconds.seconds == 5)
    @assert(seconds.milliseconds() == 5000)

    let milliseconds: Time.Duration = 250'ms
    @assert(milliseconds.seconds == 0.25)
    @assert(milliseconds.milliseconds() == 250)

    let minutes: Time.Duration = 2'min
    @assert(minutes.seconds == 120)
    @assert(minutes.milliseconds() == 120000)

    let zeroMinutes: Time.Duration = 0'min
    @assert(zeroMinutes.seconds == 0)
    @assert(zeroMinutes.milliseconds() == 0)

    let hours: Time.Duration = 1'h
    @assert(hours.seconds == 3600)
    @assert(hours.milliseconds() == 3600000)

    let zeroHours: Time.Duration = 0'h
    @assert(zeroHours.seconds == 0)
    @assert(zeroHours.milliseconds() == 0)

    let fromMilliseconds = Time.Duration.fromMilliseconds(1500)
    @assert(fromMilliseconds.seconds == 1.5)
    @assert(fromMilliseconds.milliseconds() == 1500)

    let fromZeroMilliseconds = Time.Duration.fromMilliseconds(0)
    @assert(fromZeroMilliseconds.seconds == 0)
    @assert(fromZeroMilliseconds.milliseconds() == 0)

    let fromOneMillisecond = Time.Duration.fromMilliseconds(1)
    @assert(Math.isEqualEpsilon(fromOneMillisecond.seconds, 0.001, 0.00001))
    @assert(fromOneMillisecond.milliseconds() == 1)
}

#test
{
    for value in 1000
    {
        let expectedMilliseconds = cast(u64) value
        let duration             = Time.Duration.fromMilliseconds(expectedMilliseconds)
        @assert(duration.milliseconds() == expectedMilliseconds)
        @assert(Math.isEqualEpsilon(duration.seconds, cast(f64) value / 1000.0, 0.00001))
    }

    let exactlyOneSecond = Time.Duration.fromSeconds(1)
    @assert(exactlyOneSecond.seconds == 1)
    @assert(exactlyOneSecond.milliseconds() == 1000)

    let almostOneSecond = Time.Duration.fromMilliseconds(999)
    @assert(almostOneSecond.milliseconds() == 999)
    @assert(Math.isEqualEpsilon(almostOneSecond.seconds, 0.999, 0.00001))
}
