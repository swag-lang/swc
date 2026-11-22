//! Format: Dolby Digital (AC-3) and Dolby Digital Plus (E-AC-3) elementary streams.
//! Supported: Native `.ac3` and `.eac3` files: a sequence of sync frames, indexed by walking their headers.
//! Not supported: Transport-stream and IEC 61937 wrappers, and writing either format.
//! Role: This file owns native Dolby elementary stream traversal and the streamed packet sound it builds.
//
#global namespace Dolby
#global internal

using Core, Core.Errors

// Bytes the walk peeks at each frame: the sync frame fields both formats state their shape in.
private const HeaderBytes = 8'u64

// Opens a native AC-3 or E-AC-3 elementary stream as a streamed packet sound.
//
// The two formats share a sync word and differ in how the frame states its own length, so which
// one a file is comes from the caller's extension rather than from a guess.
internal func openElementaryStream(path: string, encoding: SoundFileEncoding)->SoundFile fail
{
    var source    = try ByteSource.openFile(path)
    let fileBytes = source.size()

    var packets: Array'SoundPacket
    var byteOffset   = 0'u64
    var totalFrames  = 0'u64
    var sampleRate   = 0'u32
    var channelCount = 0'u32
    var speakerMask  = 0'u32

    for
    {
        if byteOffset > fileBytes do
            fail InvalidFormatError{"Dolby frame offset exceeds the file size"}
        if byteOffset == fileBytes do
            break
        let remainingBytes = fileBytes - byteOffset
        if remainingBytes < HeaderBytes do
            fail InvalidFormatError{"Dolby elementary stream ends with a partial sync header"}
        try source.seek(byteOffset)
        let probe = try source.peek(HeaderBytes)
        let info  = encoding == .Eac3 ? try eac3FrameInfo(probe) : try ac3FrameInfo(probe)
        if not info.frameBytes do
            fail InvalidFormatError{"Dolby sync frame has an invalid size"}
        if info.frameBytes > remainingBytes do
            fail InvalidFormatError{"Dolby elementary stream ends inside a sync frame"}

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
            fail InvalidFormatError{"Dolby elementary stream changes shape between sync frames"}
        }

        if info.frameBytes > Swag.U32.Max do
            fail InvalidFormatError{"Dolby sync frame is larger than a packet may be"}
        packets.add(SoundPacket{byteOffset, cast(u32, info.frameBytes), info.frames})
        let frameCount = cast(u64, info.frames)
        if totalFrames > Swag.U64.Max - frameCount do
            fail OverflowError{"Dolby stream sample count overflows"}
        totalFrames += frameCount
        byteOffset  += info.frameBytes
    }

    if not packets.count do
        fail InvalidFormatError{"file carries no Dolby sync frame"}

    source.close()
    var config: Array'u8
    return try SoundFile.openPacketStream(path,
                                          encoding,
                                          sampleRate,
                                          channelCount,
                                          totalFrames,
                                          packets.toSlice(),
                                          config.toSlice(),
                                          {speakerMask: speakerMask})
}
