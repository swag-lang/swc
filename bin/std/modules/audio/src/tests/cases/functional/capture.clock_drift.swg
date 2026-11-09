#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

// Stable faster and slower capture clocks are measured from raw sample positions.
#test
{
    for direction in 2
    {
        let expected = direction == 0 ? 100 : -100
        var clock = expect CaptureClockDrift.create(48_000, 1_000_000_000)
        Swag.require(not expect clock.observe(0, 0))
        Swag.require(not clock.estimateIsReady() and clock.inputClockDriftPpm() == 0)
        var estimates = 0
        for second in 13
        {
            let frame = (cast(u64, second) + 1) * 48_000
            let tick = cast(u64, Math.round(cast(f64, frame) * 1_000_000_000.0 /
                                              (48_000.0 * (1.0 + expected / 1_000_000.0))))
            if expect clock.observe(tick, frame)
            {
                Swag.require(clock.estimateIsReady())
                Swag.require(Math.abs(clock.inputClockDriftPpm() - expected) <= 1)
                estimates += 1
            }
        }
        Swag.require(estimates >= 6)
    }
}

// Source restarts and jumps need an explicit new anchor; invalid input does not change an estimate.
#test
{
    var clock = expect CaptureClockDrift.create(48_000, 1_000_000)
    Swag.require(not expect clock.observe(100, 500))
    Swag.require(expect clock.observe(1_000_100, 48_500))
    Swag.require(clock.estimateIsReady() and clock.inputClockDriftPpm() == 0)
    var rejected: Swag.Error
    discard catch clock.observe(1_000_100, 49_000) as rejected
    Swag.require(rejected.value() is BadParameterError and clock.inputClockDriftPpm() == 0)
    discard catch clock.observe(2_000_100, 100_000) as rejected
    Swag.require(rejected.value() is BadParameterError and clock.inputClockDriftPpm() == 0)
    Swag.require(expect clock.observe(2_000_100, 96_500))
    Swag.require(clock.inputClockDriftPpm() == 0)
    clock.reset(9_000_000, 0)
    Swag.require(not clock.estimateIsReady() and clock.inputClockDriftPpm() == 0)
    Swag.require(expect clock.observe(10_000_000, 48_000))
    Swag.require(clock.inputClockDriftPpm() == 0)
}

// A longer window suppresses 100-microsecond timestamp jitter around a 100 ppm source.
#test
{
    var clock = expect CaptureClockDrift.create(44_100, 1_000_000_000, 10)
    Swag.require(not expect clock.observe(0, 0))
    var estimates = 0
    for index in 30
    {
        let second = cast(u64, index) + 1
        let tick = second * 1_000_000_000 + (second % 2 == 0 ? 100_000'u64 : 0)
        let frame = cast(u64, Math.round(cast(f64, second) * 44_100.0 * 1.0001))
        if expect clock.observe(tick, frame)
        {
            Swag.require(Math.abs(clock.inputClockDriftPpm() - 100) <= 20)
            estimates += 1
        }
    }
    Swag.require(estimates >= 2)
}

// A measured drift adjusts the resampler's input consumption without moving its sample phase.
#test
{
    var clock = expect CaptureClockDrift.create(48_000, 1_000_000_000)
    var resampler = expect Resampler.create(48_000, 48_000, 1)
    Swag.require(not expect clock.applyTo(&resampler))
    Swag.require(not expect clock.observe(0, 0))
    Swag.require(expect clock.observe(2_000_000_000, 96_010))
    Swag.require(clock.inputClockDriftPpm() == 104)
    Swag.require(expect clock.applyTo(&resampler))
    var input: [48_000] f32
    for index in input.count do
        input[index] = 0.25
    var output: Array'f32
    expect resampler.addFrames(Swag.makeSlice(&input[0], input.count), &output)
    expect resampler.end(&output)
    Swag.require(output.count >= 47_994 and output.count <= 47_996)
    var different = expect Resampler.create(44_100, 48_000, 1)
    var rejected: Swag.Error
    discard catch clock.applyTo(&different) as rejected
    Swag.require(rejected.value() is BadParameterError)
}

// Invalid estimator formats are rejected at construction.
#test
{
    var rejected: Swag.Error
    discard catch CaptureClockDrift.create(0, 1_000_000) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch CaptureClockDrift.create(48_000, 0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch CaptureClockDrift.create(48_000, 1_000_000, 61) as rejected
    Swag.require(rejected.value() is BadParameterError)
}
