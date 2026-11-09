#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Four hours of inactive system output stream as bounded AAC silence without microphone loss.
#[Swag.TestTag("stress")]
#test
{
    var queue = expect CaptureQueue.create(48_000, 2, 0, 48_000,
                                           blockFrames: 1_024, slots: 2, tolerance: 0)
    const FourHours = 4'u64 * 60 * 60 * 48_000
    Swag.require(expect queue.markSilentUntil(FourHours) == FourHours)
    Swag.require(not queue.sourceIsLost() and queue.pendingBlocks() == 0)
    var track = expect CaptureAacTrack.create(&queue)
    var packet: Array'u8
    var info: CaptureAacPacket
    var count = 0'u64
    var bytes = 0'u64
    while expect track.nextPacket(&packet, &info)
    {
        Swag.require(info.startSample == count * 1_024)
        Swag.require(info.syntheticFrames == 1_024 and not info.sourceInterrupted)
        Swag.require(packet.count == 7)
        bytes += packet.count
        count += 1
    }
    Swag.require(count == 675_000 and bytes == 4_725_000)
    Swag.require(track.inputFrameCount() == FourHours)
}
