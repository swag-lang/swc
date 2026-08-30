#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let zero = Time.Duration.fromSeconds(0)
    Swag.assert(zero.seconds == 0)
    Swag.assert(zero.milliseconds() == 0)

    let zeroSeconds: Time.Duration = 0's
    Swag.assert(zeroSeconds.seconds == 0)
    Swag.assert(zeroSeconds.milliseconds() == 0)

    let zeroMilliseconds: Time.Duration = 0'ms
    Swag.assert(zeroMilliseconds.seconds == 0)
    Swag.assert(zeroMilliseconds.milliseconds() == 0)

    let from250Milliseconds = Time.Duration.fromMilliseconds(250)
    Swag.assert(from250Milliseconds.seconds == 0.25)
    Swag.assert(from250Milliseconds.milliseconds() == 250)

    let oneMs: Time.Duration = 1'ms
    Swag.assert(Math.isEqualEpsilon(oneMs.seconds, 0.001, 0.00001))
    Swag.assert(oneMs.milliseconds() == 1)

    let seconds: Time.Duration = 5's
    Swag.assert(seconds.seconds == 5)
    Swag.assert(seconds.milliseconds() == 5000)

    let milliseconds: Time.Duration = 250'ms
    Swag.assert(milliseconds.seconds == 0.25)
    Swag.assert(milliseconds.milliseconds() == 250)

    let minutes: Time.Duration = 2'min
    Swag.assert(minutes.seconds == 120)
    Swag.assert(minutes.milliseconds() == 120000)

    let zeroMinutes: Time.Duration = 0'min
    Swag.assert(zeroMinutes.seconds == 0)
    Swag.assert(zeroMinutes.milliseconds() == 0)

    let hours: Time.Duration = 1'h
    Swag.assert(hours.seconds == 3600)
    Swag.assert(hours.milliseconds() == 3600000)

    let zeroHours: Time.Duration = 0'h
    Swag.assert(zeroHours.seconds == 0)
    Swag.assert(zeroHours.milliseconds() == 0)

    let fromMilliseconds = Time.Duration.fromMilliseconds(1500)
    Swag.assert(fromMilliseconds.seconds == 1.5)
    Swag.assert(fromMilliseconds.milliseconds() == 1500)

    let fromZeroMilliseconds = Time.Duration.fromMilliseconds(0)
    Swag.assert(fromZeroMilliseconds.seconds == 0)
    Swag.assert(fromZeroMilliseconds.milliseconds() == 0)

    let fromOneMillisecond = Time.Duration.fromMilliseconds(1)
    Swag.assert(Math.isEqualEpsilon(fromOneMillisecond.seconds, 0.001, 0.00001))
    Swag.assert(fromOneMillisecond.milliseconds() == 1)
}

#test
{
    for value in 1000
    {
        let expectedMilliseconds = cast(u64) value
        let duration             = Time.Duration.fromMilliseconds(expectedMilliseconds)
        Swag.assert(duration.milliseconds() == expectedMilliseconds)
        Swag.assert(Math.isEqualEpsilon(duration.seconds, cast(f64) value / 1000.0, 0.00001))
    }

    let exactlyOneSecond = Time.Duration.fromSeconds(1)
    Swag.assert(exactlyOneSecond.seconds == 1)
    Swag.assert(exactlyOneSecond.milliseconds() == 1000)

    let almostOneSecond = Time.Duration.fromMilliseconds(999)
    Swag.assert(almostOneSecond.milliseconds() == 999)
    Swag.assert(Math.isEqualEpsilon(almostOneSecond.seconds, 0.999, 0.00001))
}
