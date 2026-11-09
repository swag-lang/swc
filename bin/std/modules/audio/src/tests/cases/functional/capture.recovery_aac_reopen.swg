#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Models the recorder-side sequence used after either WASAPI source stops delivering packets.
func checkNativeReopen(channels: u16, sourceRate: u32)
{
    const TickRate = 10_000_000'u64
    var queue = expect CaptureQueue.create(48_000, channels, 0, TickRate,
                                           blockFrames: 1_024, slots: 8, tolerance: 1)
    var recovery = expect CaptureRecovery.create(&queue, 200_000)
    var oldSource = expect CaptureResampledFeeder.create(&queue, sourceRate)
    var track = expect CaptureAacTrack.create(&queue, .Voice)
    let nativeFrames = sourceRate / 100
    var microphone: [960] s16
    var outputMix: [960 * 2] f32
    for index in nativeFrames
    {
        microphone[index] = 8_000
        outputMix[index * 2] = 0.25
        outputMix[index * 2 + 1] = -0.25
    }
    if channels == 1 do
        expect oldSource.pushPcm16(Swag.makeSlice(&microphone[0], nativeFrames), 0, 0)
    else do
        expect oldSource.pushFloat32(Swag.makeSlice(&outputMix[0], nativeFrames * 2), 0, 0)

    // The first failure marks the queue unavailable before the native owner closes. A filter
    // tail may no longer enter the lost queue; AAC fills those few frames from its sample clock.
    expect recovery.deviceLost(100_000)
    discard catch oldSource.finish()
    Swag.require(recovery.isLost() and queue.sourceIsLost() and queue.sampleEnd() == 480)
    var encoded: Array'u8
    var info: CaptureAacPacket
    Swag.require(not expect track.nextPacket(&encoded, &info))
    Swag.require(not recovery.retryDue(299_999) and recovery.retryDue(300_000))
    expect recovery.retryFailed(300_000)
    Swag.require(queue.sampleEnd() == 1_440 and recovery.nextRetryTick() == 500_000)
    Swag.require(expect track.nextPacket(&encoded, &info))
    var packetCount = 1'u64
    var synthetic = cast(u64, info.syntheticFrames)
    var interrupted = info.sourceInterrupted

    // A fresh native adapter after reopen may have reset its raw frame counter to zero.
    expect recovery.deviceRestored(500_000)
    var reopened = expect CaptureResampledFeeder.create(&queue, sourceRate)
    Swag.require(not reopened.clockEstimateIsReady() and reopened.inputClockDriftPpm() == 0)
    for packet in 2
    {
        let tick = 500_000'u64 + packet * 100_000
        let firstFrame = packet * nativeFrames
        if channels == 1 do
            expect reopened.pushPcm16(Swag.makeSlice(&microphone[0], nativeFrames),
                                      tick, firstFrame)
        else do
            expect reopened.pushFloat32(Swag.makeSlice(&outputMix[0], nativeFrames * 2),
                                        tick, firstFrame)
        while expect track.nextPacket(&encoded, &info)
        {
            Swag.require(info.startSample == packetCount * 1_024)
            packetCount += 1
            synthetic += info.syntheticFrames
            interrupted = interrupted or info.sourceInterrupted
        }
    }
    expect reopened.finish()
    while expect track.finish(&encoded, &info)
    {
        Swag.require(info.startSample == packetCount * 1_024)
        packetCount += 1
        synthetic += info.syntheticFrames
        interrupted = interrupted or info.sourceInterrupted
    }
    Swag.require(not recovery.isLost() and not queue.sourceIsLost() and
                 interrupted and synthetic >= 1_900 and synthetic < 2_100 and
                 queue.sampleEnd() >= 3_360 and queue.sampleEnd() <= 3_361 and
                 track.inputFrameCount() == queue.sampleEnd() and
                 queue.droppedBlockCount() == 0)
}

// A mono microphone and a stereo system-output source both resume on their original timeline.
#test
{
    checkNativeReopen(1, 44_100)
    checkNativeReopen(2, 96_000)
}
