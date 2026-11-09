#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Two two-hour device runs at opposite 100 ppm drifts keep the estimated output clock within 1 ms.
// This isolates clock control and phase arithmetic; the functional feeder test runs actual PCM.
#[Swag.TestTag("stress")]
#test
{
    const Rate = 48_000'u64
    const TickRate = 10_000_000'u64
    const BlocksPerRun = 337_500'u64
    const FractionUnit = 4_294_967_296.0'f64
    var clock = expect CaptureClockDrift.create(cast(u32, Rate), TickRate)
    var resampler = expect Resampler.create(cast(u32, Rate), cast(u32, Rate), 2)
    let tableCapacity = resampler.coefficients.capacity
    let historyCapacity = resampler.history.capacity
    var globalOutput = 0.0'f64
    var globalExpected = 0.0'f64
    for run in 2
    {
        let ppm = run == 0 ? 100 : -100
        let originTick = cast(u64, run) * (2 * 60 * 60 + 5) * TickRate
        if run == 1 do
            resampler.restart()
        clock.reset(originTick, 0)
        Swag.require(not clock.estimateIsReady())
        var outputFrames = 0.0'f64
        var observations = 0'u64
        for block in BlocksPerRun
        {
            let sourceFrame = block * 1_024
            let tick = originTick + cast(u64, Math.round(cast(f64, sourceFrame) * TickRate /
                                                           (Rate * (1.0 + ppm / 1_000_000.0))))
            if block
            {
                if expect clock.observe(tick, sourceFrame)
                {
                    Swag.require(Math.abs(clock.inputClockDriftPpm() - ppm) <= 1)
                    Swag.require(expect clock.applyTo(&resampler))
                    observations += 1
                }
            }
            outputFrames += 1_024.0 * FractionUnit / resampler.step
        }
        let expectedFrames = BlocksPerRun * 1_024.0 / (1.0 + ppm / 1_000_000.0)
        Swag.require(observations > 3_000)
        Swag.require(Math.abs(outputFrames - expectedFrames) < 48.0)
        globalOutput += outputFrames
        globalExpected += expectedFrames
        Swag.require(resampler.coefficients.capacity == tableCapacity and
                     resampler.history.capacity == historyCapacity)
    }
    Swag.require(Math.abs(globalOutput - globalExpected) < 48.0)
}
