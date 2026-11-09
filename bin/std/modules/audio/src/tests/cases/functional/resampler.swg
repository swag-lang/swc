#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

func sineFrames(count, rate: u64, frequency: f64)->Array'f32
{
    var result: Array'f32
    result.reserve(count)
    for frame in count do
        result.add(cast(f32, Math.sin(Math.ConstF64.TwoPi * frequency * frame / rate)))
    return result
}

func rootMeanSquare(samples: const [..] f32, startIndex, endIndex: u64)->f64
{
    var power = 0.0'f64
    for index in startIndex until endIndex
    {
        let sample = cast(f64, samples[index])
        power += sample * sample
    }
    return Math.sqrt(power / (endIndex - startIndex))
}

// Chunk boundaries preserve the exact output sequence, including a short final block.
#test
{
    let input = sineFrames(4_800, 48_000, 1_000.0)
    var whole = expect Resampler.create(48_000, 44_100, 1)
    var parts = expect Resampler.create(48_000, 44_100, 1)
    var one: Array'f32
    var many: Array'f32
    expect whole.addFrames(input.toSlice(), &one)
    expect whole.end(&one)
    var start = 0'u64
    while start < input.count
    {
        let count = Math.min(137'u64, input.count - start)
        expect parts.addFrames(input.toSlice()[start until start + count], &many)
        start += count
    }
    expect parts.end(&many)
    Swag.require(one.count == 4_410 and many.count == one.count)
    for index in one.count do
        Swag.require(one[index] == many[index])
}

// The low-pass filter preserves audible passband energy and suppresses out-of-band aliasing.
#test
{
    let passband = sineFrames(9_600, 48_000, 18_000.0)
    var pass = expect Resampler.create(48_000, 44_100, 1)
    var passed: Array'f32
    expect pass.addFrames(passband.toSlice(), &passed)
    expect pass.end(&passed)
    let inputPower  = rootMeanSquare(passband.toSlice(), 200, 9_400)
    let outputPower = rootMeanSquare(passed.toSlice(), 200, passed.count - 200)
    Swag.require(outputPower / inputPower > 0.94 and outputPower / inputPower < 1.02)

    let stopband = sineFrames(9_600, 96_000, 30_000.0)
    var stop = expect Resampler.create(96_000, 48_000, 1)
    var stopped: Array'f32
    expect stop.addFrames(stopband.toSlice(), &stopped)
    expect stop.end(&stopped)
    Swag.require(rootMeanSquare(stopped.toSlice(), 200, stopped.count - 200) < 0.01)
}

// Stereo channels stay separate, and finishing an empty stream produces no samples.
#test
{
    var empty = expect Resampler.create(48_000, 48_000, 2)
    var output: Array'f32
    expect empty.end(&output)
    expect empty.end(&output)
    Swag.require(output.isEmpty())

    var stereo = expect Resampler.create(48_000, 48_000, 2)
    var input: [192] f32
    for frame in 96 do
        input[frame * 2] = 1
    expect stereo.addFrames(Swag.makeSlice(&input[0], input.count), &output)
    expect stereo.end(&output)
    Swag.require(output.count == input.count)
    for frame in 96
    {
        Swag.require(Math.abs(output[frame * 2] - 1.0'f32) < 0.0001)
        Swag.require(output[frame * 2 + 1] == 0)
    }
}

// A drift update changes the running ratio without restarting or reversing sample time.
#test
{
    var resampler = expect Resampler.create(48_000, 48_000, 1)
    var input: [4_800] f32
    var output: Array'f32
    expect resampler.addFrames(Swag.makeSlice(&input[0], input.count), &output)
    let firstCount = output.count
    expect resampler.setInputClockDriftPpm(1_000)
    expect resampler.addFrames(Swag.makeSlice(&input[0], input.count), &output)
    expect resampler.end(&output)
    Swag.require(firstCount == 4_752 and output.count == 9_596)
    for sample in output do
        Swag.require(sample == 0)
}

// Rejected configurations and partial frames leave a stream usable.
#test
{
    var rejected: Swag.Error
    discard catch Resampler.create(0, 48_000, 1) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch Resampler.create(48_000, 48_000, 9) as rejected
    Swag.require(rejected.value() is BadParameterError)

    var resampler = expect Resampler.create(48_000, 48_000, 2)
    discard catch resampler.setInputClockDriftPpm(1_001) as rejected
    Swag.require(rejected.value() is BadParameterError)
    const Odd: [1] f32 = [1]
    var output: Array'f32
    discard catch resampler.addFrames(Swag.makeSlice(&Odd[0], 1), &output) as rejected
    Swag.require(rejected.value() is BadParameterError and output.isEmpty())
    const Pair: [2] f32 = [1, 0]
    expect resampler.addFrames(Swag.makeSlice(&Pair[0], 2), &output)
    expect resampler.end(&output)
    Swag.require(output.count == 2)
    discard catch resampler.addFrames(Swag.makeSlice(&Pair[0], 2), &output) as rejected
    Swag.require(rejected.value() is BadParameterError)
}
