#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

func collectCaptureSamples(queue: *CaptureQueue)->Array's16
{
    var output: Array's16
    var block: Array's16
    var info: CaptureBlock
    var expected = 0'u64
    while queue.pop(&block, &info)
    {
        Swag.require(info.startSample == expected and info.gapFrames == 0)
        expected += info.frameCount
        output.add(block.toSlice())
    }
    return output
}

// A mono PCM16 replacement microphone can feed the existing stereo AAC timeline.
#test
{
    var queue = expect CaptureQueue.create(48_000, 2, 0, 10_000_000, slots: 8)
    var feeder = expect CaptureResampledFeeder.create(&queue, 48_000, 1)
    var source: [1_024] s16
    for frame in source.count do
        source[frame] = cast(s16, Math.round(10_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                 1_000.0 * frame / 48_000.0)))
    expect feeder.pushPcm16(Swag.makeSlice(&source[0], source.count), 0, 0)
    expect feeder.finish()
    let output = collectCaptureSamples(&queue)
    Swag.require(output.count == 2 * 1_024 and queue.sampleEnd() == 1_024)
    var sourcePower = 0.0'f64
    var outputPower = 0.0'f64
    var cross = 0.0'f64
    for frame in 200 until 800
    {
        Swag.require(output[frame * 2] == output[frame * 2 + 1])
        sourcePower += cast(f64, source[frame]) * source[frame]
        outputPower += cast(f64, output[frame * 2]) * output[frame * 2]
        cross += cast(f64, source[frame]) * output[frame * 2]
    }
    Swag.require(cross / Math.sqrt(sourcePower * outputPower) > 0.99)
}

// A stereo float output mix averages to mono without clipping or channel ordering changes.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 10_000_000, slots: 8)
    var feeder = expect CaptureResampledFeeder.create(&queue, 48_000, 2)
    var source: [1_024 * 2] f32
    for frame in 1_024
    {
        source[frame * 2] = 0.6
        source[frame * 2 + 1] = -0.2
    }
    expect feeder.pushFloat32(Swag.makeSlice(&source[0], source.count), 0, 0)
    expect feeder.finish()
    let output = collectCaptureSamples(&queue)
    Swag.require(output.count == 1_024 and queue.sampleEnd() == 1_024)
    for frame in 200 until 800 do
        Swag.require(Math.abs(cast(s32, output[frame]) - 6_554) <= 64)
}

// The other native sample formats use the same deterministic mono/stereo rules.
#test
{
    var stereo = expect CaptureQueue.create(48_000, 2, 0, 10_000_000, slots: 8)
    var upmix = expect CaptureResampledFeeder.create(&stereo, 48_000, 1)
    var one: [1_024] f32
    for frame in one.count do
        one[frame] = 0.125
    expect upmix.pushFloat32(Swag.makeSlice(&one[0], one.count), 0, 0)
    expect upmix.finish()
    let doubled = collectCaptureSamples(&stereo)
    Swag.require(doubled.count == 2 * 1_024)
    for frame in 200 until 800 do
        Swag.require(doubled[frame * 2] == doubled[frame * 2 + 1] and
                     Math.abs(cast(s32, doubled[frame * 2]) - 4_096) <= 64)

    var mono = expect CaptureQueue.create(48_000, 1, 0, 10_000_000, slots: 8)
    var downmix = expect CaptureResampledFeeder.create(&mono, 48_000, 2)
    var two: [1_024 * 2] s16
    for frame in 1_024
    {
        two[frame * 2] = 10_000
        two[frame * 2 + 1] = -6_000
    }
    expect downmix.pushPcm16(Swag.makeSlice(&two[0], two.count), 0, 0)
    expect downmix.finish()
    let averaged = collectCaptureSamples(&mono)
    Swag.require(averaged.count == 1_024)
    for frame in 200 until 800 do
        Swag.require(Math.abs(cast(s32, averaged[frame]) - 2_000) <= 64)
}

// Unsupported native layouts and incomplete stereo frames fail before advancing the queue.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 10_000_000)
    var rejected: Swag.Error
    discard catch CaptureResampledFeeder.create(&queue, 48_000, 3) as rejected
    Swag.require(rejected.value() is BadParameterError)
    var feeder = expect CaptureResampledFeeder.create(&queue, 48_000, 2)
    const Odd: [3] s16 = [1, 2, 3]
    discard catch feeder.pushPcm16(Swag.makeSlice(&Odd[0], Odd.count), 0, 0) as rejected
    Swag.require(rejected.value() is BadParameterError and queue.sampleEnd() == 0)
}
