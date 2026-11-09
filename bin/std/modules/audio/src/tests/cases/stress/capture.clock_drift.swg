#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A four-hour capture clock at either drift limit remains aligned to less than one millisecond.
#test
{
    for direction in 2
    {
        let actualPpm = direction == 0 ? 100 : -100
        var clock = expect CaptureClockDrift.create(48_000, 1_000_000_000)
        Swag.require(not expect clock.observe(0, 0))
        var outputFrames = 0.0'f64
        var estimates = 0'u64
        var lastFrame = 0'u64
        for index in 14_400
        {
            let frame = (cast(u64, index) + 1) * 48_000
            let tick = cast(u64, Math.round(cast(f64, frame) * 1_000_000_000.0 /
                                              (48_000.0 * (1.0 + actualPpm / 1_000_000.0))))
            outputFrames += cast(f64, frame - lastFrame) /
                            (1.0 + clock.inputClockDriftPpm() / 1_000_000.0)
            if expect clock.observe(tick, frame)
            {
                Swag.require(Math.abs(clock.inputClockDriftPpm() - actualPpm) <= 1)
                estimates += 1
            }
            lastFrame = frame
            if index == 14_399
            {
                let expected = cast(f64, tick) * 48_000.0 / 1_000_000_000.0
                Swag.require(Math.abs(outputFrames - expected) < 48.0)
            }
        }
        Swag.require(estimates >= 7_000)
    }
}
