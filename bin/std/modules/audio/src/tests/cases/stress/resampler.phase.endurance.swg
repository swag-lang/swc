#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Simulates four hours of phase updates. It does not run the filter or stream real PCM.
func checkPhaseEndurance(driftPpm: s32, referenceClockParts: u64)
{
    const Rate            = 48_000'u64
    const FractionUnit    = 4_294_967_296'u64
    const InputFrames     = 4 * 60 * 60 * Rate
    let referenceFrames = (InputFrames * 1_000_000 + referenceClockParts - 1) / referenceClockParts

    var resampler = expect Resampler.create(cast(u32, Rate), cast(u32, Rate), 1)
    expect resampler.setInputClockDriftPpm(driftPpm)
    let historyCapacity      = resampler.history.capacity
    let coefficientCapacity  = resampler.coefficients.capacity
    let historyCount         = resampler.history.count
    let coefficientCount     = resampler.coefficients.count

    // No output samples are needed to test the clock. A zero-channel test fixture makes emit
    // skip only the filter; end still advances positionFrame and positionPart for every frame.
    resampler.channels       = 0
    resampler.receivedFrames = InputFrames
    var output: Array'f32
    expect resampler.end(&output)

    let accumulated = resampler.positionFrame * FractionUnit + resampler.positionPart
    Swag.require(accumulated % resampler.step == 0)
    let actualFrames = accumulated / resampler.step
    let errorFrames  = cast(s64, actualFrames) - cast(s64, referenceFrames)
    Swag.require(Math.abs(errorFrames) < 48) // Forty-eight samples at 48 kHz are one millisecond.
    Swag.require(resampler.positionFrame >= InputFrames)
    Swag.require(accumulated - InputFrames * FractionUnit < resampler.step)
    Swag.require(output.isEmpty() and output.capacity == 0)
    Swag.require(resampler.history.count == historyCount and resampler.history.capacity == historyCapacity)
    Swag.require(resampler.coefficients.count == coefficientCount and resampler.coefficients.capacity == coefficientCapacity)
}

// Both faster and slower source clocks retain their accumulated phase over four simulated hours.
#[Swag.TestTag("stress")]
#test
{
    checkPhaseEndurance(100, 1_000_100)
    checkPhaseEndurance(-100, 999_900)
}
