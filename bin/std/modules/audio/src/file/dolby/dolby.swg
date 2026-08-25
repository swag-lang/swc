//! Format: Dolby Digital (AC-3) and Dolby Digital Plus (E-AC-3) elementary streams.
//! Supported: Native `.ac3` and `.eac3` files: a sequence of sync frames, indexed by walking their headers.
//! Not supported: Transport-stream and IEC 61937 wrappers, and writing either format.
//! Role: This file owns native Dolby elementary stream traversal and the streamed packet sound it builds.
//
#global namespace Dolby
#global internal

using Core, Core.Errors

// How much of a file the frame walk holds at once.
private const ScanWindow = 64 * 1024'u64

// Opens a native AC-3 or E-AC-3 elementary stream as a streamed packet sound.
//
// The two formats share a sync word and differ in how the frame states its own length, so which
// one a file is comes from the caller's extension rather than from a guess.
internal func openElementaryStream(path: string, encoding: SoundFileEncoding)->SoundFile fail
{
    var stream = File.openRead(path)
    let size   = try stream.size()

    var window:  Array'u8
    var packets: Array'SoundPacket
    var at       = 0'u64
    var frames   = 0'u64
    var rate     = 0'u32
    var channels = 0'u32

    while at + 8 <= size
    {
        let want = Math.min(ScanWindow, size - at)
        window.resize(want)
        if !try stream.readExactAt(at, window.toSlice()) do
            break

        let info = encoding == .Eac3 ? try eac3FrameInfo(window.toSlice()) : try ac3FrameInfo(window.toSlice())
        if !info.frameBytes or at + info.frameBytes > size do
            break

        if !packets.count
        {
            rate     = info.sampleRate
            channels = info.channels
        }
        elif info.sampleRate != rate or info.channels != channels
        {
            // A stream that changes shape mid-file is not one this reader indexes.
            break
        }

        if info.frameBytes > Swag.U32.Max do
            fail InvalidFormatError{"Dolby sync frame is larger than a packet may be"}
        packets.add({at, cast(u32) info.frameBytes, info.frames})
        frames += cast(u64) info.frames
        at     += info.frameBytes
    }

    if !packets.count do
        fail InvalidFormatError{"file carries no Dolby sync frame"}

    stream.close()
    var config: Array'u8
    return try SoundFile.openPacketStream(path, encoding, rate, channels, frames, packets.toSlice(), config.toSlice())
}
