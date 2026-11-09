#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

// A 96 kHz stereo float device produces a 48 kHz PCM queue at the same wall-clock duration.
#test
{
    var queue = expect CaptureQueue.create(48_000, 2, 0, 10_000_000,
                                           blockFrames: 1_024, slots: 8, tolerance: 1)
    var feeder = expect CaptureResampledFeeder.create(&queue, 96_000)
    var input: [960 * 2] f32
    for packetIndex in 5
    {
        for frame in 960
        {
            let sourceFrame = packetIndex * 960 + frame
            let tone = cast(f32, 0.5 * Math.sin(Math.ConstF64.TwoPi * 1_000.0 * sourceFrame / 96_000.0))
            input[frame * 2] = tone
            input[frame * 2 + 1] = -tone
        }
        expect feeder.pushFloat32(Swag.makeSlice(&input[0], input.count),
                                  packetIndex * 100_000, packetIndex * 960)
    }
    expect feeder.finish()
    var all: Array's16
    var block: Array's16
    var info: CaptureBlock
    var expected = 0'u64
    while queue.pop(&block, &info)
    {
        Swag.require(info.startSample == expected and info.gapFrames == 0)
        expected += info.frameCount
        all.add(block.toSlice())
    }
    Swag.require(expected == 2_400 and all.count == 4_800)
    var sourcePower = 0.0'f64
    var decodedPower = 0.0'f64
    var cross = 0.0'f64
    for frame in 200 until 2_200
    {
        let original = 16_384.0 * Math.sin(Math.ConstF64.TwoPi * 1_000.0 * frame / 48_000.0)
        let actual = cast(f64, all[frame * 2])
        sourcePower += original * original
        decodedPower += actual * actual
        cross += original * actual
        Swag.require(all[frame * 2 + 1] == -all[frame * 2] or
                     Math.abs(cast(s32, all[frame * 2 + 1]) + all[frame * 2]) <= 1)
    }
    Swag.require(cross / Math.sqrt(sourcePower * decodedPower) > 0.99)
}

// A 100 ppm device clock controls the live resampler and remains within one millisecond.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 10_000_000,
                                           blockFrames: 1_024, slots: 8, tolerance: 1)
    var feeder = expect CaptureResampledFeeder.create(&queue, 48_000)
    var input: [1_024] s16
    var copied: Array's16
    var info: CaptureBlock
    for block in 120
    {
        let firstFrame = cast(u64, block) * 1_024
        let tick = cast(u64, Math.round(cast(f64, firstFrame) * 10_000_000.0 /
                                          (48_000.0 * 1.0001)))
        expect feeder.pushPcm16(Swag.makeSlice(&input[0], input.count), tick, firstFrame)
        while queue.pop(&copied, &info) {}
    }
    expect feeder.finish()
    while queue.pop(&copied, &info) {}
    Swag.require(feeder.clockEstimateIsReady() and Math.abs(feeder.inputClockDriftPpm() - 100) <= 1)
    let trueEnd = 120.0 * 1_024 / 1.0001
    Swag.require(Math.abs(cast(f64, queue.sampleEnd()) - trueEnd) < 48.0)
}

// A new device resets clock estimation and filter phase while preserving a visible timeline gap.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 10_000_000,
                                           blockFrames: 1_024, slots: 8, tolerance: 0)
    var feeder = expect CaptureResampledFeeder.create(&queue, 96_000)
    var input: [960] f32
    input[0] = 0.25
    expect feeder.pushFloat32(Swag.makeSlice(&input[0], input.count), 0, 0)
    input[0] = 0.5
    expect feeder.pushFloat32(Swag.makeSlice(&input[0], input.count), 20_000_000, 0, true)
    expect feeder.finish()
    var samples: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&samples, &info) and info.startSample == 0)
    var lastEnd = info.startSample + info.frameCount
    var foundRestoration = false
    while queue.pop(&samples, &info)
    {
        if info.sourceInterrupted
        {
            Swag.require(info.startSample == 96_000 and info.gapFrames == 96_000 - lastEnd)
            foundRestoration = true
        }
        lastEnd = info.startSample + info.frameCount
    }
    Swag.require(foundRestoration and queue.sampleEnd() == 96_480)
    Swag.require(not feeder.clockEstimateIsReady() and feeder.inputClockDriftPpm() == 0)
}

// Restarting the filter reproduces a fresh instance without a new coefficient table.
#test
{
    var resampler = expect Resampler.create(96_000, 48_000, 1)
    var fresh = expect Resampler.create(96_000, 48_000, 1)
    var input: [500] f32
    for frame in input.count do
        input[frame] = cast(f32, Math.sin(Math.ConstF64.TwoPi * 500.0 * frame / 96_000.0))
    var previous: Array'f32
    expect resampler.setInputClockDriftPpm(1_000)
    expect resampler.addFrames(Swag.makeSlice(&input[0], input.count), &previous)
    expect resampler.end(&previous)
    resampler.restart()
    var restarted: Array'f32
    var expected: Array'f32
    expect resampler.addFrames(Swag.makeSlice(&input[0], input.count), &restarted)
    expect resampler.end(&restarted)
    expect fresh.addFrames(Swag.makeSlice(&input[0], input.count), &expected)
    expect fresh.end(&expected)
    Swag.require(Slice.equals(restarted.toSlice(), expected.toSlice()))
}

// Idle loopback drains the delayed filter tail before committing silence, then resumes cleanly.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 10_000_000,
                                           blockFrames: 1_024, slots: 8, tolerance: 0)
    var feeder = expect CaptureResampledFeeder.create(&queue, 96_000)
    var signal: [960] f32
    signal[0] = 0.5
    expect feeder.pushFloat32(Swag.makeSlice(&signal[0], signal.count), 0, 0)
    Swag.require(queue.sampleEnd() < 480)
    expect feeder.suspendForIdle()
    Swag.require(queue.sampleEnd() == 480)
    Swag.require(expect queue.markSilentUntil(1_000_000) == 4_320)
    expect feeder.pushFloat32(Swag.makeSlice(&signal[0], signal.count), 1_000_000, 0)
    expect feeder.finish()
    var output: Array's16
    var info: CaptureBlock
    var foundResume = false
    while queue.pop(&output, &info)
    {
        if info.startSample == 4_800
        {
            Swag.require(not info.sourceInterrupted and info.gapFrames == 4_320)
            foundResume = true
        }
    }
    Swag.require(foundResume and queue.sampleEnd() == 5_280)
}

// Device replacement after a clock estimate clears that estimate and reports the elapsed gap.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 10_000_000,
                                           blockFrames: 1_024, slots: 8, tolerance: 0)
    var feeder = expect CaptureResampledFeeder.create(&queue, 96_000)
    var samples: Array's16
    var info: CaptureBlock
    var lastEnd = 0'u64
    for packet in 120
    {
        expect feeder.pushSilence(960, packet * 100_000, packet * 960)
        while queue.pop(&samples, &info) do
            lastEnd = info.startSample + info.frameCount
    }
    Swag.require(feeder.clockEstimateIsReady() and feeder.inputClockDriftPpm() == 0)
    var resumed: [960] f32
    resumed[0] = 0.25
    expect feeder.pushFloat32(Swag.makeSlice(&resumed[0], resumed.count), 20_000_000, 0, true)
    expect feeder.finish()
    Swag.require(not feeder.clockEstimateIsReady() and feeder.inputClockDriftPpm() == 0)
    var found = false
    while queue.pop(&samples, &info)
    {
        if info.sourceInterrupted
        {
            Swag.require(info.startSample == 96_000 and info.gapFrames == 96_000 - lastEnd)
            found = true
        }
        lastEnd = info.startSample + info.frameCount
    }
    Swag.require(found and lastEnd == 96_480)
}

// Unsupported queue formats and invalid packets fail without advancing the timeline.
#test
{
    var unsupported = expect CaptureQueue.create(32_000, 1, 0, 10_000_000)
    var rejected: Swag.Error
    discard catch CaptureResampledFeeder.create(&unsupported, 96_000) as rejected
    Swag.require(rejected.value() is BadParameterError)
    var queue = expect CaptureQueue.create(48_000, 2, 0, 10_000_000)
    var feeder = expect CaptureResampledFeeder.create(&queue, 96_000)
    const Odd: [3] s16 = [1, 2, 3]
    discard catch feeder.pushPcm16(Swag.makeSlice(&Odd[0], Odd.count), 0, 0) as rejected
    Swag.require(rejected.value() is BadParameterError and queue.sampleEnd() == 0)
}
