//! Format: DTS Coherent Acoustics Core elementary streams.
//! Supported: Native `.dts` files containing consecutive 16-bit big- or little-endian core frames.
//! Not supported: 14-bit transport packing, DTS extension substreams, transport wrappers, and writing.
//! Role: This file walks native DTS Core frames and builds the packet index used for streamed decoding.
//
#global namespace Dts
#global internal

using Core, Core.Errors

private const ScanWindow = 64 * 1024'u64

internal func openElementaryStream(path: string)->SoundFile fail
{
    var stream = File.openRead(path)
    let size   = try stream.size()

    var window:  Array'u8
    var packets: Array'SoundPacket
    var at       = 0'u64
    var frames   = 0'u64
    var rate     = 0'u32
    var channels = 0'u32
    var speakers = 0'u32

    while at + 13 <= size
    {
        let want = Math.min(ScanWindow, size - at)
        window.resize(want)
        if !try stream.readExactAt(at, window.toSlice()) do
            break

        let info = try frameInfo(window.toSlice())
        if !info.frameBytes or at + info.frameBytes > size do
            break

        if !packets.count
        {
            rate     = info.sampleRate
            channels = info.channels
            speakers = info.speakerMask
        }
        elif info.sampleRate != rate or info.channels != channels or info.speakerMask != speakers
        {
            break
        }

        if info.frameBytes > Swag.U32.Max do
            fail InvalidFormatError{"DTS core frame is larger than a packet may be"}
        packets.add({at, cast(u32) info.frameBytes, info.frames})
        frames += cast(u64) info.frames
        at     += info.frameBytes
    }

    if !packets.count do
        fail InvalidFormatError{"file carries no DTS core frame"}
    if at != size do
        fail InvalidFormatError{"DTS elementary stream ends between core frames"}

    stream.close()
    var config: Array'u8
    return try SoundFile.openPacketStream(path, .Dts, rate, channels, frames, packets.toSlice(), config.toSlice(), {speakerMask: speakers})
}
