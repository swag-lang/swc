//! Format: ISO Base Media File Format (MP4) fragmented packet reader.
//! Supported: Encoded H.264 samples and AAC-LC samples with their original track timestamps.
//! Not supported: Classic MP4 sample tables, other codecs, and remuxing negative composition times.
//! Role: This file exposes compressed packets for copying and cutting without video decoding.
//
#global namespace Mp4
#global export

using Core, Core.Errors

// Describes one compressed sample without reading its payload.
//
// Times use the containing track's timescale. The signed presentation time retains negative
// composition offsets that [[Video.EncodedPacket]] cannot represent.
struct FragmentedPacketInfo
{
    public sourceOffset:     u64      // Absolute byte offset of the encoded payload.
    public byteSize:         u32      // Number of payload bytes.
    public decodeTime:       u64      // Decode-time ticks on the track.
    public presentationTime: s64      // Presentation-time ticks, possibly negative.
    public duration:         u32      // Positive duration in track ticks.
    public isKeyFrame:       bool     // Sample can start decoding without prior video samples.
}

// Describes one AAC-LC track of a fragmented MP4 file.
//
// `decoderConfig` is borrowed from the reader and remains valid until it closes.
struct FragmentedAudioInfo
{
    public sampleRate:    u32     // Track ticks and sound sample frames per second.
    public channelCount:  u16     // One or two channels.
    public decoderConfig: const [..] u8     // Borrowed MPEG-4 AudioSpecificConfig.
    public packetCount:   u64     // Number of complete AAC-LC access units.
}

// Reads encoded H.264 and AAC-LC packets from a fragmented MP4 without decoding them.
//
// Opening scans fragment headers and retains packet offsets and timestamps, while payloads remain
// in the file. The file must stay unchanged until the reader closes. Use
// [[Video.Mp4.FragmentedIndex]] to locate key-frame fragments in a long completed file without a
// full header scan.
#[Swag.NoCopy]
struct FragmentedPacketReader
{
    private
    {
        source: ByteSource
        layout: Layout
    }
}

impl FragmentedPacketReader
{
    // Opens a fragmented H.264 MP4 file, including its available AAC-LC tracks.
    //
    // A partial final fragment is ignored when earlier video fragments are complete. A classic
    // sample-table MP4 or a file without H.264 fragments is rejected.
    func open(fileName: string)->FragmentedPacketReader fail
    {
        var result: #returntype
        result.source = try ByteSource.openFile(fileName)
        try result.layout.parse(&result.source)
        if not result.layout.hasFragments or not result.layout.track.isAvc do
            fail UnsupportedFormatError{"MP4 packet reader needs fragmented H.264 video"}
        return result
    }

    // Releases the source file; repeated calls do nothing.
    mtd close() => .source.close()

    // Returns the video width in pixels.
    mtd const width()->s32 => .layout.track.width

    // Returns the video height in pixels.
    mtd const height()->s32 => .layout.track.height

    // Returns the video track's decode-time ticks per second.
    mtd const timescale()->u32 => .layout.track.timescale

    // Borrows the video AVCDecoderConfigurationRecord until the reader closes.
    mtd const avcConfig()->const [..] u8 => .layout.track.videoConfig.toSlice()

    // Returns the number of complete video access units.
    mtd const packetCount()->u64 => .layout.fragments.count

    // Returns one video packet's timing and location without reading its payload.
    mtd const packetInfo(index: u64)->FragmentedPacketInfo fail
    {
        if index >= .layout.fragments.count do
            fail BadParameterError{"fragmented MP4 video packet index is outside its track"}
        return describeSample(.layout.fragments[index])
    }

    // Reads one video access unit into `bytes` and returns its original track timestamps.
    //
    // The returned payload borrows `bytes` until it is changed. The caller can pass it directly
    // to [[Video.Mp4.FragmentedWriter.addPacket]]. A negative composition time cannot be
    // represented by [[Video.EncodedPacket]] and produces an unsupported-format error.
    mtd readPacket(index: u64, bytes: *Array'u8)->EncodedPacket fail
    {
        if index >= .layout.fragments.count do
            fail BadParameterError{"fragmented MP4 video packet index is outside its track"}
        let sample = .layout.fragments[index]
        if sample.presentationTime < 0 do
            fail UnsupportedFormatError{"fragmented MP4 packet has a negative presentation time"}
        try .readPayload(sample, bytes)
        return EncodedPacket{bytes.toSlice(), sample.decodeTime, cast(u64, sample.presentationTime),
                             sample.duration, sample.isKeyFrame}
    }

    // Returns the number of AAC-LC tracks in the movie, including empty tracks.
    mtd const audioTrackCount()->u64 => .layout.audioTracks.count

    // Returns one AAC-LC track's configuration and packet count.
    //
    // `trackIndex` is zero based. The returned decoder configuration borrows the reader's storage.
    mtd const audioTrack(trackIndex: u64)->FragmentedAudioInfo fail
    {
        if trackIndex >= .layout.audioTracks.count do
            fail BadParameterError{"fragmented MP4 audio track index is outside the movie"}
        let track = &.layout.audioTracks[trackIndex]
        return FragmentedAudioInfo{track.sampleRate, cast(u16, track.channelCount),
                                   track.aacConfig.toSlice(), .layout.audioFragments[trackIndex].samples.count}
    }

    // Returns one AAC-LC packet's timing and location without reading its payload.
    mtd const audioPacketInfo(trackIndex, packetIndex: u64)->FragmentedPacketInfo fail
    {
        if trackIndex >= .layout.audioFragments.count or
           packetIndex >= .layout.audioFragments[trackIndex].samples.count do
            fail BadParameterError{"fragmented MP4 AAC packet index is outside its track"}
        return describeSample(.layout.audioFragments[trackIndex].samples[packetIndex])
    }

    // Reads one raw AAC-LC access unit into `bytes` with its original track timestamps.
    //
    // The returned payload borrows `bytes` until it is changed. It contains no ADTS header and
    // can be passed to [[Video.Mp4.FragmentedWriter.addAudioPacket]].
    mtd readAudioPacket(trackIndex, packetIndex: u64, bytes: *Array'u8)->EncodedPacket fail
    {
        if trackIndex >= .layout.audioFragments.count or
           packetIndex >= .layout.audioFragments[trackIndex].samples.count do
            fail BadParameterError{"fragmented MP4 AAC packet index is outside its track"}
        let sample = .layout.audioFragments[trackIndex].samples[packetIndex]
        try .readPayload(sample, bytes)
        return EncodedPacket{bytes.toSlice(), sample.decodeTime, sample.decodeTime,
                             sample.duration, true}
    }
}

private impl FragmentedPacketReader
{
    mtd readPayload(sample: FragmentSample, bytes: *Array'u8) fail
    {
        bytes.resize(sample.size)
        try .source.seek(sample.offset)
        try .source.readExact(bytes.toSlice())
    }
}

private func describeSample(sample: FragmentSample)->FragmentedPacketInfo
    =>
{sample.offset, sample.size, sample.decodeTime, sample.presentationTime,
 sample.duration, sample.isKeyFrame}
