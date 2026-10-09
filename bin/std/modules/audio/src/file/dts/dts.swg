//! Format: DTS Coherent Acoustics Core elementary streams.
//! Supported: Native `.dts` files containing consecutive 14- or 16-bit big- or little-endian core frames.
//! Not supported: DTS extension substreams, transport wrappers, and writing.
//! Role: This file walks native DTS Core frames and builds the packet index used for streamed decoding.
//
#global namespace Dts
#global internal

using Core, Core.Errors

// Bytes the core frame header spans in its widest packing, fourteen bits per word, which is
// what the walk peeks at each frame.
private const HeaderBytes = 18'u64

internal func openElementaryStream(path: string)->SoundFile fail
{
    var source    = try ByteSource.openFile(path)
    let fileBytes = source.size()

    var packets: Array'SoundPacket
    var byteOffset   = 0'u64
    var totalFrames  = 0'u64
    var sampleRate   = 0'u32
    var channelCount = 0'u32
    var speakerMask  = 0'u32

    while byteOffset + 16 <= fileBytes
    {
        try source.seek(byteOffset)
        let probe = try source.peek(Math.min(HeaderBytes, fileBytes - byteOffset))
        let info  = try frameInfo(probe)
        if not info.frameBytes or byteOffset + info.frameBytes > fileBytes do
            break

        if not packets.count
        {
            sampleRate   = info.sampleRate
            channelCount = info.channels
            speakerMask  = info.speakerMask
        }
        elif info.sampleRate != sampleRate or
             info.channels != channelCount or
             info.speakerMask != speakerMask
        {
            break
        }

        if info.frameBytes > Swag.U32.Max do
            fail InvalidFormatError{"DTS core frame is larger than a packet may be"}
        packets.add({byteOffset, cast(u32, info.frameBytes), info.frames})
        totalFrames += cast(u64, info.frames)
        byteOffset  += info.frameBytes
    }

    if not packets.count do
        fail InvalidFormatError{"file carries no DTS core frame"}
    if byteOffset != fileBytes do
        fail InvalidFormatError{"DTS elementary stream ends between core frames"}

    source.close()
    var config: Array'u8
    return try SoundFile.openPacketStream(path,
                                          .Dts,
                                          sampleRate,
                                          channelCount,
                                          totalFrames,
                                          packets.toSlice(),
                                          config.toSlice(),
                                          {speakerMask: speakerMask})
}
