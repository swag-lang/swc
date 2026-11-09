#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Run the real filter and queue for one minute of 10 ms stereo capture at either clock edge.
// The four-hour phase-only test covers arithmetic beyond this PCM throughput window.
func checkCaptureFilterEndurance(sourceRate: u32, driftPpm: s32)
{
    const OutputRate = 48_000'u32
    const TickRate = 10_000_000'u64
    const PacketCount = 6_000'u64
    var queue = expect CaptureQueue.create(OutputRate, 2, 0, TickRate,
                                           blockFrames: 1_024, slots: 8, tolerance: 1)
    var feeder = expect CaptureResampledFeeder.create(&queue, sourceRate)
    let framesPerPacket = sourceRate / 100
    var copied: Array's16
    var info: CaptureBlock
    var deliveredEnd = 0'u64
    for packet in PacketCount
    {
        let firstFrame = packet * framesPerPacket
        let tick = cast(u64, Math.round(cast(f64, firstFrame) * TickRate /
                                        (sourceRate * (1.0 + driftPpm / 1_000_000.0))))
        expect feeder.pushSilence(framesPerPacket, tick, firstFrame)
        while queue.pop(&copied, &info)
        {
            Swag.require(info.startSample == deliveredEnd and info.gapFrames == 0 and
                         not info.sourceInterrupted)
            deliveredEnd += info.frameCount
        }
        Swag.require(queue.pendingBlocks() == 0 and queue.droppedBlockCount() == 0)
    }
    expect feeder.finish()
    while queue.pop(&copied, &info)
    {
        Swag.require(info.startSample == deliveredEnd and info.gapFrames == 0)
        deliveredEnd += info.frameCount
    }
    let expectedFrames = cast(s64, Math.round(60.0 * OutputRate /
                                              (1.0 + driftPpm / 1_000_000.0)))
    Swag.require(feeder.clockEstimateIsReady() and
                 Math.abs(feeder.inputClockDriftPpm() - driftPpm) <= 1)
    Swag.require(Math.abs(cast(s64, deliveredEnd) - expectedFrames) < 48 and
                 queue.sampleEnd() == deliveredEnd and queue.droppedBlockCount() == 0)
}

#[Swag.TestTag("stress")]
#test
{
    for sourceRate in [96_000'u32, 44_100]
    {
        checkCaptureFilterEndurance(sourceRate, 100)
        checkCaptureFilterEndurance(sourceRate, -100)
    }
}
