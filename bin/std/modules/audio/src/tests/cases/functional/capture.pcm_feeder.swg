#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

// Float capture clips safely, zeroes invalid samples, and splits at the queue's fixed block size.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 10_000_000,
                                           blockFrames: 3, tolerance: 0)
    var feeder = CapturePcmFeeder.create(&queue)
    const Input: [8] f32 = [-1.5, -1.0, -0.5, 0, 0.5, 1.0,
                            cast #bit (f32, 0x7FC0_0000'u32),
                            cast #bit (f32, 0x7F80_0000'u32)]
    expect feeder.pushFloat32(Swag.makeSlice(&Input[0], Input.count), 0)
    var output: Array's16
    var info: CaptureBlock
    var all: Array's16
    var expectedStart = 0'u64
    while queue.pop(&output, &info)
    {
        Swag.require(info.startSample == expectedStart and info.gapFrames == 0)
        expectedStart += info.frameCount
        all.add(output.toSlice())
    }
    Swag.require(expectedStart == 8)
    Swag.require(Slice.equals(all.toSlice(), [-32_768's16, -32_768, -16_384, 0,
                                               16_384, 32_767, 0, 0]))
}

// Packet splitting preserves frame positions and a discontinuity after a missing interval.
#test
{
    var queue = expect CaptureQueue.create(1_000, 2, 0, 10_000_000,
                                           blockFrames: 2, tolerance: 0)
    var feeder = CapturePcmFeeder.create(&queue)
    const First: [6] s16 = [1, 2, 3, 4, 5, 6]
    const Second: [4] s16 = [7, 8, 9, 10]
    expect feeder.pushPcm16(Swag.makeSlice(&First[0], First.count), 0)
    expect feeder.pushPcm16(Swag.makeSlice(&Second[0], Second.count), 50_000, true)
    var output: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&output, &info) and info.startSample == 0 and info.frameCount == 2)
    Swag.require(Slice.equals(output.toSlice(), [1's16, 2, 3, 4]))
    Swag.require(queue.pop(&output, &info) and info.startSample == 2 and info.frameCount == 1)
    Swag.require(Slice.equals(output.toSlice(), [5's16, 6]))
    Swag.require(queue.pop(&output, &info) and info.startSample == 5 and info.gapFrames == 2)
    Swag.require(info.sourceInterrupted and Slice.equals(output.toSlice(), [7's16, 8, 9, 10]))
}

// Split packet timestamps round offsets once on a fractional sample clock.
#test
{
    var queue = expect CaptureQueue.create(44_100, 1, 12_345, 10_000_000,
                                           blockFrames: 3, slots: 3, tolerance: 0)
    var feeder = CapturePcmFeeder.create(&queue)
    const Input: [8] s16 = [1, 2, 3, 4, 5, 6, 7, 8]
    expect feeder.pushPcm16(Swag.makeSlice(&Input[0], Input.count), 12_345)

    const ExpectedTicks: [3] u64 = [12_345, 13_025, 13_706]
    var samples: Array's16
    var info: CaptureBlock
    for index in ExpectedTicks.count
    {
        Swag.require(queue.pop(&samples, &info))
        Swag.require(info.startSample == index * 3 and
                     info.frameCount == (index == 2 ? 2 : 3) and
                     info.firstTick == ExpectedTicks[index])
    }
    Swag.require(not queue.pop(&samples, &info))
}

// A native silent packet stays zero and restores a lost source at its own timestamp.
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 48_000,
                                           blockFrames: 4, tolerance: 0)
    var feeder = CapturePcmFeeder.create(&queue)
    expect queue.markLost(0)
    expect feeder.pushSilence(7, 4)
    var output: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&output, &info) and info.startSample == 4)
    Swag.require(info.sourceInterrupted and info.frameCount == 4 and info.gapFrames == 4)
    for sample in output do
        Swag.require(sample == 0)
    Swag.require(queue.pop(&output, &info) and info.startSample == 8 and info.frameCount == 3)
    for sample in output do
        Swag.require(sample == 0)
}

// Invalid packet lengths leave a source queue untouched.
#test
{
    var queue = expect CaptureQueue.create(48_000, 2, 0, 10_000_000)
    var feeder = CapturePcmFeeder.create(&queue)
    const Odd: [3] s16 = [1, 2, 3]
    var rejected: Swag.Error
    discard catch feeder.pushPcm16(Swag.makeSlice(&Odd[0], Odd.count), 0) as rejected
    Swag.require(rejected.value() is BadParameterError and queue.pendingBlocks() == 0)
    discard catch feeder.pushSilence(0, 0) as rejected
    Swag.require(rejected.value() is BadParameterError and queue.sampleEnd() == 0)
}

// Simulated float microphone packets reach AAC with exact 44.1 kHz stereo gap metadata.
#test
{
    var queue = expect CaptureQueue.create(44_100, 2, 0, 10_000_000,
                                           blockFrames: 1_024, tolerance: 0)
    var feeder = CapturePcmFeeder.create(&queue)
    var source: [2 * 1_024] f32
    for frame in 1_024
    {
        let tone = cast(f32, 0.5 * Math.sin(Math.ConstF64.TwoPi * 880.0 * frame / 44_100.0))
        source[frame * 2] = tone
        source[frame * 2 + 1] = -tone
    }
    expect feeder.pushFloat32(Swag.makeSlice(&source[0], source.count), 0)
    let resumedTick = cast(u64, Math.round(2.0'f64 * 1_024 * 10_000_000.0 / 44_100.0))
    expect feeder.pushFloat32(Swag.makeSlice(&source[0], source.count), resumedTick, true)
    var track = expect CaptureAacTrack.create(&queue)
    var packet: Array'u8
    var info: CaptureAacPacket
    for index in 3
    {
        Swag.require(expect track.nextPacket(&packet, &info))
        Swag.require(info.startSample == index * 1_024)
        Swag.require(info.syntheticFrames == (index == 1 ? 1_024 : 0))
        Swag.require(info.sourceInterrupted == (index == 2))
    }
    Swag.require(not expect track.nextPacket(&packet, &info))
    Swag.require(expect track.finish(&packet, &info))
    Swag.require(info.startSample == 3 * 1_024 and info.validFrames == 0)
}
