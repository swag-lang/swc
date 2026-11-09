#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Independent microphone and system-output queues share one monotonic AAC recording clock.
#test
{
    var microphone = expect CaptureQueue.create(48_000, 2, 0, 10_000_000,
                                                blockFrames: 1_024, tolerance: 0)
    var systemOutput = expect CaptureQueue.create(48_000, 2, 0, 10_000_000,
                                                  blockFrames: 1_024, tolerance: 0)
    var microphonePackets = CapturePcmFeeder.create(&microphone)
    var systemPackets = CapturePcmFeeder.create(&systemOutput)
    var voice: [2 * 1_024] f32
    var desktop: [2 * 1_024] f32
    for frame in 1_024
    {
        voice[frame * 2] = cast(f32, 0.4 * Math.sin(Math.ConstF64.TwoPi * 1_000.0 * frame / 48_000.0))
        voice[frame * 2 + 1] = voice[frame * 2]
        desktop[frame * 2] = cast(f32, 0.3 * Math.sin(Math.ConstF64.TwoPi * 8_000.0 * frame / 48_000.0))
        desktop[frame * 2 + 1] = -desktop[frame * 2]
    }
    expect microphonePackets.pushFloat32(Swag.makeSlice(&voice[0], voice.count), 0)
    for index in 4
    {
        let tick = cast(u64, Math.round(cast(f64, index) * 1_024 * 10_000_000.0 / 48_000.0))
        if index == 2 do
            expect systemPackets.pushSilence(1_024, tick)
        else do
            expect systemPackets.pushFloat32(Swag.makeSlice(&desktop[0], desktop.count), tick)
    }
    expect microphone.markLost(213_333)
    let resumedTick = cast(u64, Math.round(3.0'f64 * 1_024 * 10_000_000.0 / 48_000.0))
    expect microphonePackets.pushFloat32(Swag.makeSlice(&voice[0], voice.count), resumedTick)

    var microphoneTrack = expect CaptureAacTrack.create(&microphone)
    var systemTrack = expect CaptureAacTrack.create(&systemOutput)
    var microphoneAac: Array'u8
    var systemAac: Array'u8
    var microphoneInfo: CaptureAacPacket
    var systemInfo: CaptureAacPacket
    for index in 4
    {
        Swag.require(expect microphoneTrack.nextPacket(&microphoneAac, &microphoneInfo))
        Swag.require(expect systemTrack.nextPacket(&systemAac, &systemInfo))
        Swag.require(microphoneInfo.startSample == index * 1_024 and
                     systemInfo.startSample == microphoneInfo.startSample)
        Swag.require(microphoneInfo.syntheticFrames == (index == 1 or index == 2 ? 1_024 : 0))
        Swag.require(systemInfo.syntheticFrames == 0)
        Swag.require(microphoneInfo.sourceInterrupted == (index == 3))
        Swag.require(not systemInfo.sourceInterrupted)
        Swag.require(microphoneAac.count > 0 and systemAac.count > 0)
    }
    Swag.require(not expect microphoneTrack.nextPacket(&microphoneAac, &microphoneInfo))
    Swag.require(not expect systemTrack.nextPacket(&systemAac, &systemInfo))
    Swag.require(expect microphoneTrack.finish(&microphoneAac, &microphoneInfo))
    Swag.require(expect systemTrack.finish(&systemAac, &systemInfo))
    Swag.require(microphoneInfo.startSample == 4 * 1_024 and
                 systemInfo.startSample == microphoneInfo.startSample)
}

// Render silence advances the live AAC track; a delayed render packet only replaces future time.
#test
{
    var output = expect CaptureQueue.create(48_000, 1, 0, 48_000,
                                            blockFrames: 1_024, tolerance: 0)
    var feeder = CapturePcmFeeder.create(&output)
    var signal: [1_024] s16
    for index in signal.count do
        signal[index] = cast(s16, index % 200)
    expect feeder.pushPcm16(Swag.makeSlice(&signal[0], signal.count), 0)
    Swag.require(expect output.markSilentUntil(3 * 1_024) == 2 * 1_024)
    Swag.require(output.silentGapEnd() == 0)
    var track = expect CaptureAacTrack.create(&output)
    var packet: Array'u8
    var info: CaptureAacPacket
    for index in 3
    {
        Swag.require(expect track.nextPacket(&packet, &info))
        Swag.require(info.startSample == index * 1_024)
        Swag.require(info.syntheticFrames == (index == 0 ? 0 : 1_024))
        Swag.require(not info.sourceInterrupted)
    }
    Swag.require(not expect track.nextPacket(&packet, &info))

    let placement = expect output.push(Swag.makeSlice(&signal[0], signal.count),
                                       2 * 1_024 + 512)
    Swag.require(placement.discardedFrames == 512 and placement.acceptedFrames == 512)
    Swag.require(not expect track.nextPacket(&packet, &info))
    Swag.require(expect output.markSilentUntil(4 * 1_024) == 512)
    Swag.require(expect track.nextPacket(&packet, &info))
    Swag.require(info.startSample == 3 * 1_024 and info.syntheticFrames == 512)
    Swag.require(not info.sourceInterrupted and track.inputFrameCount() == 4 * 1_024)
    let stale = expect output.push(Swag.makeSlice(&signal[0], signal.count), 0)
    Swag.require(stale.discardedFrames == 1_024 and stale.acceptedFrames == 0)
    Swag.require(output.pendingBlocks() == 0 and output.sampleEnd() == 4 * 1_024)
    Swag.require(expect output.markSilentUntil(3 * 1_024) == 0)
}

// A discontinuity flag on a late render packet survives the silence cutoff and resumes safely.
#test
{
    var queue = expect CaptureQueue.create(1_000, 1, 0, 1_000,
                                           blockFrames: 4, tolerance: 0)
    var feeder = CapturePcmFeeder.create(&queue)
    Swag.require(expect queue.markSilentUntil(10) == 10)
    const Late: [4] s16 = [11, 22, 33, 44]
    expect feeder.pushPcm16(Swag.makeSlice(&Late[0], Late.count), 8, true)
    var copied: Array's16
    var info: CaptureBlock
    Swag.require(queue.pop(&copied, &info))
    Swag.require(info.startSample == 10 and info.frameCount == 2 and info.sourceInterrupted)
    Swag.require(Slice.equals(copied.toSlice(), [33's16, 44]))
    Swag.require(not queue.pop(&copied, &info) and queue.sampleEnd() == 12)
}
