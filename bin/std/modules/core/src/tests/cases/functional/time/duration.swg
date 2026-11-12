#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let zero = Time.Duration.fromSeconds(0)
    Swag.require(zero.seconds == 0)
    Swag.require(zero.milliseconds() == 0)

    let zeroSeconds: Time.Duration = 0's
    Swag.require(zeroSeconds.seconds == 0)
    Swag.require(zeroSeconds.milliseconds() == 0)

    let zeroMilliseconds: Time.Duration = 0'ms
    Swag.require(zeroMilliseconds.seconds == 0)
    Swag.require(zeroMilliseconds.milliseconds() == 0)

    let from250Milliseconds = Time.Duration.fromMilliseconds(250)
    Swag.require(from250Milliseconds.seconds == 0.25)
    Swag.require(from250Milliseconds.milliseconds() == 250)

    let oneMs: Time.Duration = 1'ms
    Swag.require(Math.isEqualEpsilon(oneMs.seconds, 0.001, 0.00001))
    Swag.require(oneMs.milliseconds() == 1)

    let seconds: Time.Duration = 5's
    Swag.require(seconds.seconds == 5)
    Swag.require(seconds.milliseconds() == 5000)

    let milliseconds: Time.Duration = 250'ms
    Swag.require(milliseconds.seconds == 0.25)
    Swag.require(milliseconds.milliseconds() == 250)

    let minutes: Time.Duration = 2'min
    Swag.require(minutes.seconds == 120)
    Swag.require(minutes.milliseconds() == 120000)

    let zeroMinutes: Time.Duration = 0'min
    Swag.require(zeroMinutes.seconds == 0)
    Swag.require(zeroMinutes.milliseconds() == 0)

    let hours: Time.Duration = 1'h
    Swag.require(hours.seconds == 3600)
    Swag.require(hours.milliseconds() == 3600000)

    let zeroHours: Time.Duration = 0'h
    Swag.require(zeroHours.seconds == 0)
    Swag.require(zeroHours.milliseconds() == 0)

    let fromMilliseconds = Time.Duration.fromMilliseconds(1500)
    Swag.require(fromMilliseconds.seconds == 1.5)
    Swag.require(fromMilliseconds.milliseconds() == 1500)

    let fromZeroMilliseconds = Time.Duration.fromMilliseconds(0)
    Swag.require(fromZeroMilliseconds.seconds == 0)
    Swag.require(fromZeroMilliseconds.milliseconds() == 0)

    let fromOneMillisecond = Time.Duration.fromMilliseconds(1)
    Swag.require(Math.isEqualEpsilon(fromOneMillisecond.seconds, 0.001, 0.00001))
    Swag.require(fromOneMillisecond.milliseconds() == 1)
}

#test
{
    Swag.require(Time.Duration.fromSeconds(0).millisecondsCeiling() == 0)
    Swag.require(Time.Duration.fromSeconds(1).millisecondsCeiling() == 1000)
    Swag.require(Time.Duration.fromSeconds(0.0005).millisecondsCeiling() == 1)
    Swag.require(Time.Duration.fromSeconds(0.0015).millisecondsCeiling() == 2)
    Swag.require(Time.Duration.fromSeconds(1.0005).millisecondsCeiling() == 1001)

    let tooLarge = Swag.catchPanic(func||()
    {
        discard Time.Duration.fromSeconds(cast(f64, Swag.U64.Max)).millisecondsCeiling()
    })
    Swag.require(tooLarge.raised and tooLarge.message() == "duration is too large in milliseconds")
}

#test
{
    for value in 1000
    {
        let expectedMilliseconds = cast(u64, value)
        let duration = Time.Duration.fromMilliseconds(expectedMilliseconds)
        Swag.require(duration.milliseconds() == expectedMilliseconds)
        Swag.require(Math.isEqualEpsilon(duration.seconds, cast(f64, value) / 1000.0, 0.00001))
    }

    let exactlyOneSecond = Time.Duration.fromSeconds(1)
    Swag.require(exactlyOneSecond.seconds == 1)
    Swag.require(exactlyOneSecond.milliseconds() == 1000)

    let almostOneSecond = Time.Duration.fromMilliseconds(999)
    Swag.require(almostOneSecond.milliseconds() == 999)
    Swag.require(Math.isEqualEpsilon(almostOneSecond.seconds, 0.999, 0.00001))
}
