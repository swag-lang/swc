//! Format: MPEG-4 AAC in an Audio Data Transport Stream.
//! Supported: Native `.aac` files: ADTS frames of Low Complexity audio, with or without the frame checksum, indexed by walking their headers.
//! Not supported: Audio Data Interchange Format, profiles other than Low Complexity, and writing ADTS.
//! Role: This file owns ADTS traversal, the decoder configuration it implies, and the streamed packet sound it builds.
//
#global namespace Aac
#global internal

using Core, Core.Errors

// How much of a file the frame walk holds at once.
private const ScanWindow = 64 * 1024'u64

// The sampling frequencies an ADTS header names by index, clause 1.6.2.4.
private const AdtsRates: [13] u32 = [
    96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]

// What one ADTS header says about the frame that follows it.
private struct AdtsHeader
{
    frameBytes:   u64
    headerBytes:  u64
    rateIndex:    u32
    channelIndex: u32
    sampleRate:   u32
    channels:     u32
    blocks:       u32     // Raw data blocks the frame carries, each 1024 sample frames.
}

// Reads one ADTS header, clause 1.A.3.2.1.
private func readAdtsHeader(bytes: const [..] u8)->AdtsHeader fail
{
    if @countof(bytes) < 7 do
        fail InvalidFormatError{"ADTS header is truncated"}
    if bytes[0] != 0xFF or (bytes[1] & 0xF0) != 0xF0 do
        fail InvalidFormatError{"ADTS frame has no sync word"}

    let layer = cast(u32) (bytes[1] >> 1) & 3
    if layer do
        fail InvalidFormatError{"ADTS frame states a layer, which the format reserves"}

    var result: retval
    result.headerBytes = (bytes[1] & 1) != 0 ? 7 : 9

    let profile = cast(u32) (bytes[2] >> 6) & 3
    if profile != 1 do
        fail UnsupportedFormatError{"audio decoder reads AAC Low Complexity only"}

    result.rateIndex = cast(u32) (bytes[2] >> 2) & 15
    if result.rateIndex >= 13 do
        fail InvalidFormatError{"ADTS frame states a reserved sampling frequency"}
    result.sampleRate = AdtsRates[cast(u64) result.rateIndex]

    result.channelIndex = (cast(u32) (bytes[2] & 1) << 2) | (cast(u32) (bytes[3] >> 6) & 3)
    if !result.channelIndex or result.channelIndex > 7 do
        fail UnsupportedFormatError{"ADTS frame states a channel configuration this reader does not carry"}

    // Configuration seven is 7.1, whose eighth channel is the low frequency effects one.
    result.channels = result.channelIndex == 7 ? 8 : result.channelIndex

    result.frameBytes = (cast(u64) (bytes[3] & 3) << 11) | (cast(u64) bytes[4] << 3) | (cast(u64) bytes[5] >> 5)
    result.blocks     = (cast(u32) bytes[6] & 3) + 1
    if result.frameBytes < result.headerBytes do
        fail InvalidFormatError{"ADTS frame is shorter than its own header"}
    return result
}

// Builds the decoder configuration an ADTS stream implies.
//
// A transport frame states the profile, the sampling frequency, and the channel configuration in
// every header; a packet codec expects them once, in the two bytes an `AudioSpecificConfig` holds.
private func audioSpecificConfig(header: const *AdtsHeader)->Array'u8
{
    var result: retval
    let first  = cast(u8) ((2 << 3) | ((header.rateIndex >> 1) & 7))
    let second = cast(u8) (((header.rateIndex & 1) << 7) | ((header.channelIndex & 15) << 3))
    result.add(first)
    result.add(second)
    return result
}

// Opens a native ADTS file as a streamed packet sound.
//
// The audio stays in the file: opening walks the frame headers to build the packet index every
// voice then reads through. Each packet starts past the transport header, which is what the
// codec expects and what a container would have stripped for it.
internal func openFile(path: string)->SoundFile fail
{
    var stream = File.openRead(path)
    let size   = try stream.size()

    var window:  Array'u8
    var packets: Array'SoundPacket
    var config:  Array'u8
    var at       = 0'u64
    var frames   = 0'u64
    var rate     = 0'u32
    var channels = 0'u32

    while at + 7 <= size
    {
        let want = Math.min(ScanWindow, size - at)
        window.resize(want)
        if !try stream.readExactAt(at, window.toSlice()) do
            break

        let header = try readAdtsHeader(window.toSlice())
        if at + header.frameBytes > size do
            break

        if !packets.count
        {
            rate     = header.sampleRate
            channels = header.channels
            config   = audioSpecificConfig(&header)
        }
        elif header.sampleRate != rate or header.channels != channels
        {
            break
        }

        if header.frameBytes > Swag.U32.Max do
            fail InvalidFormatError{"ADTS frame is larger than a packet may be"}

        // The transport header belongs to the file, not to the access unit: the codec is handed
        // the raw audio the same way a container hands it over.
        let payload = header.frameBytes - header.headerBytes
        if !payload do
            fail InvalidFormatError{"ADTS frame carries no audio"}
        packets.add({at + header.headerBytes, cast(u32) payload, header.blocks * 1024})
        frames += cast(u64) header.blocks * 1024
        at     += header.frameBytes
    }

    if !packets.count do
        fail InvalidFormatError{"file carries no ADTS frame"}

    stream.close()
    return try SoundFile.openPacketStream(path, .AacLc, rate, channels, frames, packets.toSlice(), config.toSlice())
}
