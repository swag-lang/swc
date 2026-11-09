#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A four-hour lost microphone advances one small AAC packet at a time.
#[Swag.TestTag("stress")]
#test
{
    var queue = expect CaptureQueue.create(48_000, 1, 0, 48_000,
                                           blockFrames: 1_024, slots: 2, tolerance: 0)
    expect queue.markLost(0)
    const FourHours = 4'u64 * 60 * 60 * 48_000
    expect queue.markLost(FourHours)
    var track = expect CaptureAacTrack.create(&queue)
    var packet: Array'u8
    var info: CaptureAacPacket
    var count = 0'u64
    var bytes = 0'u64
    while expect track.nextPacket(&packet, &info)
    {
        Swag.require(info.startSample == count * 1_024)
        Swag.require(info.validFrames == 1_024 and info.syntheticFrames == 1_024)
        Swag.require(packet.count == 4)
        bytes += packet.count
        count += 1
    }
    Swag.require(count == 675_000 and bytes == 2_700_000)
    Swag.require(queue.pendingBlocks() == 0 and track.inputFrameCount() == FourHours)
    Swag.require(expect track.finish(&packet, &info))
    Swag.require(info.startSample == FourHours and info.validFrames == 0)
    Swag.require(not expect track.finish(&packet, &info))
}
