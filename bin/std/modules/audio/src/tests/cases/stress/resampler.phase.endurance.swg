#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Exercises the filter and its final phase carry at the end of a four-hour input.
func checkPhaseEndurance(driftPpm: s32, referenceClockParts: u64)
{
    const Rate         = 48_000'u64
    const FractionUnit = 4_294_967_296'u64
    const InputFrames  = 4 * 60 * 60 * Rate
    let referenceFrames = (InputFrames * 1_000_000 + referenceClockParts - 1) / referenceClockParts

    var resampler = expect Resampler.create(cast(u32, Rate), cast(u32, Rate), 1)
    expect resampler.setInputClockDriftPpm(driftPpm)
    let historyCapacity     = resampler.history.capacity
    let coefficientCapacity = resampler.coefficients.capacity
    let historyCount        = resampler.history.count
    let coefficientCount    = resampler.coefficients.count

    // The prefix is silent, so the initialized history already holds its samples.
    // Start with 48 samples of lookahead, as the streaming filter does between input blocks.
    let prefixFrames = referenceFrames - 128
    let prefixPhase  = prefixFrames * resampler.step
    resampler.positionFrame  = prefixPhase / FractionUnit
    resampler.positionPart   = prefixPhase % FractionUnit
    resampler.receivedFrames = resampler.positionFrame + 48
    var tail: [256] f32
    Swag.require(resampler.receivedFrames < InputFrames)
    let tailCount = InputFrames - resampler.receivedFrames
    Swag.require(tailCount <= tail.count)
    var output: Array'f32
    expect resampler.addFrames(Swag.makeSlice(&tail[0], tailCount), &output)
    expect resampler.end(&output)

    let accumulated = resampler.positionFrame * FractionUnit + resampler.positionPart
    Swag.require(accumulated % resampler.step == 0)
    let actualFrames = accumulated / resampler.step
    let errorFrames  = cast(s64, actualFrames) - cast(s64, referenceFrames)
    Swag.require(Math.abs(errorFrames) < 48)     // Forty-eight samples at 48 kHz are one millisecond.
    Swag.require(resampler.positionFrame >= InputFrames)
    Swag.require(accumulated - InputFrames * FractionUnit < resampler.step)
    Swag.require(output.count == actualFrames - prefixFrames)
    for sample in output do
        Swag.require(sample == 0)
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
