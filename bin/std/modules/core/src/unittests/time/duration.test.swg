#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

#test
{
    let zero: Time.Duration = 0
    @assert(zero.timeInSeconds == 0)
    @assert(zero.toMs() == 0)

    let zeroSeconds: Time.Duration = 0's
    @assert(zeroSeconds.timeInSeconds == 0)
    @assert(zeroSeconds.toMs() == 0)

    let zeroMilliseconds: Time.Duration = 0'ms
    @assert(zeroMilliseconds.timeInSeconds == 0)
    @assert(zeroMilliseconds.toMs() == 0)

    let assignedFromMs: Time.Duration = 250
    @assert(assignedFromMs.timeInSeconds == 0.25)
    @assert(assignedFromMs.toMs() == 250)

    let oneMs: Time.Duration = 1'ms
    @assert(Math.isEqualEpsilon(oneMs.timeInSeconds, 0.001, 0.00001))
    @assert(oneMs.toMs() == 1)

    let seconds: Time.Duration = 5's
    @assert(seconds.timeInSeconds == 5)
    @assert(seconds.toMs() == 5000)

    let milliseconds: Time.Duration = 250'ms
    @assert(milliseconds.timeInSeconds == 0.25)
    @assert(milliseconds.toMs() == 250)

    let minutes: Time.Duration = 2'min
    @assert(minutes.timeInSeconds == 120)
    @assert(minutes.toMs() == 120000)

    let zeroMinutes: Time.Duration = 0'min
    @assert(zeroMinutes.timeInSeconds == 0)
    @assert(zeroMinutes.toMs() == 0)

    let hours: Time.Duration = 1'h
    @assert(hours.timeInSeconds == 3600)
    @assert(hours.toMs() == 3600000)

    let zeroHours: Time.Duration = 0'h
    @assert(zeroHours.timeInSeconds == 0)
    @assert(zeroHours.toMs() == 0)

    let fromMs = Time.Duration.fromMs(1500)
    @assert(fromMs.timeInSeconds == 1.5)
    @assert(fromMs.toMs() == 1500)

    let fromZeroMs = Time.Duration.fromMs(0)
    @assert(fromZeroMs.timeInSeconds == 0)
    @assert(fromZeroMs.toMs() == 0)

    let fromOneMs = Time.Duration.fromMs(1)
    @assert(Math.isEqualEpsilon(fromOneMs.timeInSeconds, 0.001, 0.00001))
    @assert(fromOneMs.toMs() == 1)
}

#test
{
    for value in 1000
    {
        let expectedMs = cast(u32) value

        let assigned: Time.Duration = cast(s32) value
        @assert(assigned.toMs() == expectedMs)

        let fromMs = Time.Duration.fromMs(expectedMs)
        @assert(fromMs.toMs() == expectedMs)
        @assert(Math.isEqualEpsilon(fromMs.timeInSeconds, cast(f32) value / 1000.0, 0.00001))
    }

    let exactlyOneSecond: Time.Duration = 1000
    @assert(exactlyOneSecond.timeInSeconds == 1)
    @assert(exactlyOneSecond.toMs() == 1000)

    let almostOneSecond = Time.Duration.fromMs(999)
    @assert(almostOneSecond.toMs() == 999)
    @assert(Math.isEqualEpsilon(almostOneSecond.timeInSeconds, 0.999, 0.00001))
}
