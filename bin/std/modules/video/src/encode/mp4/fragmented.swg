//! Format: ISO Base Media File Format (MP4) fragmented writer.
//! Supported: H.264 video with up to four AAC-LC audio tracks, bounded packet groups, an optional final video key-frame index, and interruption-safe completed fragments.
//! Not supported: Timed metadata and encryption.
//! Role: This file writes an initialization movie followed by bounded `moof`/`mdat` pairs.
//
#global namespace Mp4
#global export

using Core, Core.Errors

private const MovieExtendsId                    = fourCc('m'u32, 'v'u32, 'e'u32, 'x'u32)
private const TrackExtendsId                    = fourCc('t'u32, 'r'u32, 'e'u32, 'x'u32)
private const MovieFragmentId                   = fourCc('m'u32, 'o'u32, 'o'u32, 'f'u32)
private const MovieFragmentHeaderId             = fourCc('m'u32, 'f'u32, 'h'u32, 'd'u32)
private const TrackFragmentId                   = fourCc('t'u32, 'r'u32, 'a'u32, 'f'u32)
private const TrackFragmentHeaderId             = fourCc('t'u32, 'f'u32, 'h'u32, 'd'u32)
private const DecodeTimeId                      = fourCc('t'u32, 'f'u32, 'd'u32, 't'u32)
private const TrackRunId                        = fourCc('t'u32, 'r'u32, 'u'u32, 'n'u32)
private const AvcSampleEntryId                  = fourCc('a'u32, 'v'u32, 'c'u32, '1'u32)
private const Iso6BrandId                       = fourCc('i'u32, 's'u32, 'o'u32, '6'u32)
private const SoundMediaHeaderId                = fourCc('s'u32, 'm'u32, 'h'u32, 'd'u32)
private const MovieFragmentRandomAccessId       = fourCc('m'u32, 'f'u32, 'r'u32, 'a'u32)
private const TrackFragmentRandomAccessId       = fourCc('t'u32, 'f'u32, 'r'u32, 'a'u32)
private const MovieFragmentRandomAccessOffsetId = fourCc('m'u32, 'f'u32, 'r'u32, 'o'u32)
private const EditContainerId                   = fourCc('e'u32, 'd'u32, 't'u32, 's'u32)
private const EditListId                        = fourCc('e'u32, 'l'u32, 's'u32, 't'u32)
private const FreeBoxId                         = fourCc('f'u32, 'r'u32, 'e'u32, 'e'u32)

private struct BufferedPacket
{
    size:              u32
    decodeTime:        u64
    duration:          u32
    compositionOffset: s32
    isKeyFrame:        bool
}

internal struct RandomAccessEntry
{
    time:         u64
    moofOffset:   u64
    sampleNumber: u64
}

// Controls how encoded packets are grouped into MP4 fragments.
struct FragmentedOptions
{
    public maxPacketsPerFragment:      u32  = 1         // Video packets per fragment, at most 1024.
    public maxBufferedBytes:           u32  = 4 * 1024 * 1024     // Buffered payload limit per track.
    public maxAudioPacketsPerFragment: u32  = 1         // AAC packets per fragment, at most 1024.
    public writeRandomAccessIndex:     bool = false     // Append a video key-frame index at end(); temporary disk space grows with its entries.
}

// Describes one AAC-LC sound track to add when the fragmented MP4 file is created.
//
// `decoderConfig` is a borrowed two-byte MPEG-4 AudioSpecificConfig. Its sample rate and channel
// configuration must match `sampleRate` and `channelCount`; the writer copies it before returning.
struct FragmentedAudioConfig
{
    public sampleRate:    u32     // Sound sample frames per second, matching the AAC configuration.
    public channelCount:  u16     // One or two channels.
    public decoderConfig: const [..] u8 = []     // Borrowed AAC-LC AudioSpecificConfig.
}

// Selects the audible part of one decoded AAC track, in its sample-rate clock.
//
// Encoded packets may retain preceding transform history and a padded final packet. These
// samples remain in the file but are omitted from the track's presentation edit. The end must
// lie within its last encoded packet; extra trailing packets must be removed before publication.
struct AudioPresentationRange
{
    public firstSample: u64     // First decoded sample frame to present, on the track's media clock.
    public sampleCount: u64     // Audible sample frames; zero requires an empty track.
}

private struct FragmentedAudioTrack
{
    config:         Array'u8
    pendingPackets: Array'BufferedPacket
    pendingData:    Array'u8
    packetCount:    u64
    sampleRate:     u32
    channels:       u16
    nextTime:       u64
    hasPackets:     bool
    editOffset:     u64
}

// Writes H.264 and optional AAC-LC access units to a fragmented MP4 file.
//
// The caller supplies an AVC decoder configuration (`avcC`) with four-byte NAL lengths and submits
// access units in decode order through [[Video.Mp4.FragmentedWriter.addPacket]]. By default every
// call writes and flushes one `moof`/`mdat` pair. [[Video.Mp4.FragmentedOptions]] can group video
// and AAC packets per track within fixed byte and count limits. [[Video.Mp4.FragmentedWriter.flush]]
// completes all pending groups. The first video packet must be a key frame. Video timestamps use
// the `timescale` given at creation.
//
// [[Video.Mp4.FragmentedWriter.createWithAudioTracks]] adds up to four AAC-LC tracks. Audio packets
// are submitted separately and may be interleaved with video calls. A final key-frame index can
// be requested in the options; sequential playback and recovery of complete fragments work before
// [[Video.Mp4.FragmentedWriter.end]]. [[Video.Reader]] scans fragment headers and ignores a partial
// final fragment or index after at least one complete video fragment.
#[Swag.NoCopy]
struct FragmentedWriter
{
    private
    {
        sink:            ByteSink
        indexStream:     File.FileStream
        indexPath:       String
        indexCount:      u32
        config:          Array'u8
        audioTracks:     Array'FragmentedAudioTrack
        pendingPackets:  Array'BufferedPacket
        pendingData:     Array'u8
        options:         FragmentedOptions
        width:           u16
        height:          u16
        timescale:       u32
        movieTimescale:  u32
        videoEditOffset: u64
        sequence:        u32
        videoPackets:    u64
        nextDecodeTime:  u64
        hasPackets:      bool
        isEnded:         bool
    }
}

impl FragmentedWriter
{
    // Returns bytes accepted by the output sink so far.
    //
    // This includes the initialization movie, completed fragments, an optional final index, and
    // existing bytes when a recording was resumed.
    // Pending video and AAC groups are excluded. Call `flush` first to include every submitted
    // packet and obtain the current complete file size.
    mtd const writtenByteCount()->u64 => .sink.position()

    // Returns the decode-time end of the last submitted video packet in video timescale ticks.
    //
    // The value is zero before the first video packet. It advances even when that packet is still
    // in a pending group, so a recorder can check its time threshold before flushing or splitting.
    mtd const videoEndTime()->u64 => .nextDecodeTime

    // Returns the number of video packets successfully submitted, including pending packets.
    mtd const videoPacketCount()->u64 => .videoPackets

    // Returns the number of packets submitted to an AAC track, including pending packets.
    mtd const audioPacketCount(trackIndex: u32)->u64 fail
    {
        if trackIndex >= .audioTracks.count do
            fail BadParameterError{"fragmented MP4 has no audio track at this index"}
        return .audioTracks[trackIndex].packetCount
    }

    // Returns the decode-time end of an AAC track in its own sample-rate ticks.
    //
    // An empty track returns zero. This includes submitted packets still in a pending group.
    mtd const audioEndTime(trackIndex: u32)->u64 fail
    {
        if trackIndex >= .audioTracks.count do
            fail BadParameterError{"fragmented MP4 has no audio track at this index"}
        return .audioTracks[trackIndex].nextTime
    }

    // Creates a fragmented H.264 MP4 file and writes its initialization movie.
    //
    // `avcConfig` is a complete AVCDecoderConfigurationRecord with four-byte NAL lengths and is
    // copied. `timescale` is positive ticks per second. Width and height must fit a visual sample
    // entry. `options` limits a group to at most 1024 packets and bounds buffered payload bytes.
    // A packet above the byte bound is written alone. An indexed file uses temporary disk storage
    // for key-frame entries until `end` and keeps writer memory bounded. Failure may leave a partial
    // destination file.
    func create(fileName: string, width, height: s32, timescale: u32, avcConfig: const [..] u8, options: FragmentedOptions = {})->FragmentedWriter fail
        => try createConfigured(fileName, width, height, timescale, avcConfig, [], options)

    // Creates a fragmented MP4 file with H.264 video and one AAC-LC sound track.
    //
    // Audio packets use `audio.sampleRate` ticks per second and carry 1024 samples each. The
    // `avcConfig` and `audio.decoderConfig` slices are copied. Submit sound through
    // [[Video.Mp4.FragmentedWriter.addAudioPacket]] after creation.
    func createWithAudio(fileName: string, width, height: s32, timescale: u32, avcConfig: const [..] u8, audio: FragmentedAudioConfig, options: FragmentedOptions = {})->FragmentedWriter fail
    {
        if not audio.decoderConfig.count do
            fail BadParameterError{"fragmented MP4 AAC configuration is empty"}
        let tracks: [1] FragmentedAudioConfig = [audio]
        return try createWithAudioTracks(fileName, width, height, timescale, avcConfig, Swag.makeSlice(&tracks[0], 1), options)
    }

    // Creates a fragmented H.264 MP4 file with up to four independent AAC-LC sound tracks.
    //
    // Each track has its own sample-rate timescale and packet sequence. The configurations are
    // copied before returning. Use the zero-based `trackIndex` in
    // [[Video.Mp4.FragmentedWriter.addAudioPacket]] to select the destination track.
    func createWithAudioTracks(fileName: string, width, height: s32, timescale: u32, avcConfig: const [..] u8, audioTracks: const [..] FragmentedAudioConfig, options: FragmentedOptions = {})->FragmentedWriter fail
    {
        if not audioTracks.count or audioTracks.count > 4 do
            fail BadParameterError{"fragmented MP4 needs one to four AAC tracks"}
        return try createConfigured(fileName, width, height, timescale, avcConfig, audioTracks, options)
    }

    // Resumes a stopped file produced by this writer after its last complete fragment.
    //
    // Complete video and AAC packets remain in place. An incomplete final box or an existing
    // `mfra` index is removed; completed presentation edits are reverted to reserved `free`
    // boxes so newly appended packets cannot inherit a stale end time. A new index is written
    // at `end` when requested in `options`.
    // The scan and optional key-frame spool use bounded memory. The file must stay unchanged
    // during the scan. At least one complete video fragment is required. Validation happens
    // before truncation; an I/O failure after truncation may leave a playable media prefix.
    func resume(fileName: string, options: FragmentedOptions = {})->FragmentedWriter fail
    {
        try validateOptions(options)
        let originalSize = (try File.info(fileName)).size
        var cursor       = try FragmentedPacketCursor.open(fileName)
        defer cursor.close()
        try validateAvcConfig(cursor.avcConfig())

        with var result: #returntype
        {
            .width           = cast(u16, cursor.width())
            .height          = cast(u16, cursor.height())
            .timescale       = cursor.timescale()
            .movieTimescale  = cursor.movieTimescale()
            .videoEditOffset = cursor.videoEditOffset()
            .options         = options
            .config.add(cursor.avcConfig())
            .audioTracks.reserve(cursor.audioTrackCount())
            for index in cursor.audioTrackCount()
            {
                let audio = try cursor.audioTrack(index)
                try validateAudioConfig(audio)
                var track: FragmentedAudioTrack
                track.sampleRate = audio.sampleRate
                track.channels   = audio.channelCount
                track.editOffset = cursor.audioEditOffset(index)
                track.config.add(audio.decoderConfig)
                .audioTracks.add(#move track)
            }

            if options.writeRandomAccessIndex
            {
                .indexPath = Path.combine(Env.getSpecialDirectory(.Temp),
                                          Format.toString("swag-mp4-index-%.tmp", Guid128.random()))
                .indexStream = try File.open(.indexPath.toString(), .CreateNew, .ReadWrite, .Zero)
            }
        }

        var packet: FragmentedCursorPacket
        var lastFragment = Swag.U64.Max
        while try cursor.nextPacket(&packet)
        {
            if packet.fragmentOffset != lastFragment
            {
                if result.sequence == Swag.U32.Max do
                    fail OverflowError{"fragmented MP4 sequence number is exhausted"}
                result.sequence += 1
                lastFragment    = packet.fragmentOffset
            }

            if packet.isVideo
            {
                result.hasPackets     = true
                result.videoPackets   += 1
                result.nextDecodeTime = packet.info.decodeTime + packet.info.duration
                if options.writeRandomAccessIndex and packet.info.isKeyFrame
                {
                    if result.indexCount >= (Swag.U32.Max - 48) / 20 do
                        fail OverflowError{"fragmented MP4 random-access index exceeds a compact box"}
                    let entry = RandomAccessEntry{packet.info.decodeTime, packet.fragmentOffset,
                                                  packet.sampleNumber}
                    try result.indexStream.writeAll(Swag.makeSlice(cast(const [*] u8, &entry), #sizeof(RandomAccessEntry)))
                    result.indexCount += 1
                }
            }
            else
            {
                let track = &result.audioTracks[packet.trackIndex]
                track.hasPackets  = true
                track.packetCount += 1
                track.nextTime    = packet.info.decodeTime + packet.info.duration
            }
        }

        let mediaEnd = cursor.completeMediaByteCount()
        cursor.close()
        if not result.hasPackets or not mediaEnd do
            fail InvalidFormatError{"fragmented MP4 resume found no complete video fragment"}
        scope
        {
            var file = try File.open(fileName, .Open, .ReadWrite, .Zero)
            if try file.size() != originalSize or mediaEnd > originalSize do
                fail InvalidFormatError{"fragmented MP4 changed during resume"}
            try file.resize(mediaEnd)
            file.close()
        }

        result.sink = try ByteSink.openAppendFile(fileName, .Read)
        if result.videoEditOffset do
            try patchU32(&result.sink, result.videoEditOffset + 4, FreeBoxId)
        for &track in result.audioTracks where track.editOffset do
            try patchU32(&result.sink, track.editOffset + 4, FreeBoxId)
        return result
    }

    // Appends one H.264 access unit, flushing a complete fragment when its limits are reached.
    //
    // `packet.bytes` contains four-byte-length-prefixed NAL units, not Annex B start codes.
    // Decode times must not overlap. The signed composition offset must fit 32 bits, and one
    // packet plus its media-data header must fit a compact MP4 box. A grouped packet is copied
    // until its fragment is flushed; a packet larger than `maxBufferedBytes` is written alone.
    mtd addPacket(packet: EncodedPacket) fail
    {
        if .isEnded do
            fail BadParameterError{"cannot append to an ended fragmented MP4"}
        if not packet.bytes.count or packet.bytes.count > Swag.U32.Max - 8 do
            fail BadParameterError{"fragmented MP4 packet size is outside the supported range"}
        if not packet.duration do
            fail BadParameterError{"fragmented MP4 packet duration must be positive"}
        if .hasPackets and packet.decodeTime < .nextDecodeTime do
            fail BadParameterError{"fragmented MP4 decode times overlap"}
        if not .hasPackets and not packet.isKeyFrame do
            fail BadParameterError{"fragmented MP4 must start with a key frame"}
        if .sequence == Swag.U32.Max do
            fail OverflowError{"fragmented MP4 sequence number is exhausted"}
        if packet.decodeTime > cast(u64, Swag.S64.Max) or packet.presentationTime > cast(u64, Swag.S64.Max) do
            fail OverflowError{"fragmented MP4 timestamp exceeds the signed composition range"}
        if packet.duration > Swag.U64.Max - packet.decodeTime do
            fail OverflowError{"fragmented MP4 decode time overflows"}

        let compositionOffset = cast(s64, packet.presentationTime) - cast(s64, packet.decodeTime)
        if compositionOffset < Swag.S32.Min or compositionOffset > Swag.S32.Max do
            fail UnsupportedFormatError{"fragmented MP4 composition offset exceeds 32 bits"}

        try validateAvcPacket(packet.bytes)

        if .pendingPackets.count and
           (packet.isKeyFrame or packet.decodeTime != .nextDecodeTime or .pendingPackets.count >= .options.maxPacketsPerFragment or packet.bytes.count > .options.maxBufferedBytes - .pendingData.count) do
            try .flushVideo()

        let sample = BufferedPacket{cast(u32, packet.bytes.count), packet.decodeTime, packet.duration,
                                    cast(s32, compositionOffset), packet.isKeyFrame}
        if .options.maxPacketsPerFragment == 1 or packet.bytes.count > .options.maxBufferedBytes
        {
            let one: [1] BufferedPacket = [sample]
            try .writeFragment(Swag.makeSlice(&one[0], 1), packet.bytes)
            try .sink.flush()
            .sequence += 1
        }
        else
        {
            .pendingPackets.add(sample)
            .pendingData.add(packet.bytes)
            if .pendingPackets.count == .options.maxPacketsPerFragment or
               .pendingData.count == .options.maxBufferedBytes do
                try .flushVideo()
        }

        .nextDecodeTime = packet.decodeTime + packet.duration
        .videoPackets   += 1
        .hasPackets     = true
    }

    // Appends one 1024-sample AAC-LC access unit to sound track `trackIndex`.
    //
    // `packet.bytes` is raw AAC payload without an ADTS header. Index zero is the default. Decode
    // and presentation times are equal and use the audio sample rate as their timescale. Audio
    // packets must be continuous; the caller can interleave them with video in recording order.
    // The key-frame flag is ignored because every AAC-LC access unit is independently decodable.
    // Grouped payload is copied until the count or byte limit, or an explicit flush. An oversized
    // packet is written alone.
    mtd addAudioPacket(packet: EncodedPacket, trackIndex: u32 = 0) fail
    {
        if .isEnded or trackIndex >= .audioTracks.count do
            fail BadParameterError{"fragmented MP4 has no open audio track at this index"}
        if not packet.bytes.count or
           packet.bytes.count > Swag.U32.Max - 8 or
           packet.duration != 1_024 or
           packet.presentationTime != packet.decodeTime or
           (.audioTracks[trackIndex].hasPackets and packet.decodeTime != .audioTracks[trackIndex].nextTime) do
            fail BadParameterError{"fragmented MP4 AAC packet size or timing is invalid"}
        if .sequence == Swag.U32.Max do
            fail OverflowError{"fragmented MP4 sequence number is exhausted"}
        if packet.decodeTime > cast(u64, Swag.S64.Max) - 1_024 do
            fail OverflowError{"fragmented MP4 AAC timestamp exceeds the supported range"}

        let sample = BufferedPacket{cast(u32, packet.bytes.count), packet.decodeTime,
                                    packet.duration, 0, true}
        if .audioTracks[trackIndex].pendingPackets.count and
           packet.bytes.count > .options.maxBufferedBytes - .audioTracks[trackIndex].pendingData.count do
            try .flushAudioTrack(trackIndex)

        if .options.maxAudioPacketsPerFragment == 1 or packet.bytes.count > .options.maxBufferedBytes
        {
            try .flush()
            let one: [1] BufferedPacket = [sample]
            try .writeFragment(Swag.makeSlice(&one[0], 1), packet.bytes, 2 + trackIndex)
            try .sink.flush()
            .sequence += 1
        }
        else
        {
            .audioTracks[trackIndex].pendingPackets.add(sample)
            .audioTracks[trackIndex].pendingData.add(packet.bytes)
            if .audioTracks[trackIndex].pendingPackets.count == .options.maxAudioPacketsPerFragment or
               .audioTracks[trackIndex].pendingData.count == .options.maxBufferedBytes
            {
                try .flushAudioTrack(trackIndex)
            }
        }

        .audioTracks[trackIndex].nextTime    = packet.decodeTime + packet.duration
        .audioTracks[trackIndex].packetCount += 1
        .audioTracks[trackIndex].hasPackets  = true
    }

    // Writes and flushes pending video and audio groups, making their packets recoverable.
    mtd flush() fail
    {
        if .isEnded do
            fail BadParameterError{"cannot flush an ended fragmented MP4"}
        try .flushVideo()

        for index in .audioTracks.count do
            try .flushAudioTrack(cast(u32, index))

        try .sink.flush()
    }

    // Publishes sample-accurate presentation ranges for the video and AAC tracks.
    //
    // `videoMediaStart` is in video track ticks. `audioFrameCounts` gives the audible sample
    // frames of each AAC track in track order; pass zero for an empty track. This flushes
    // pending fragments and patches edit lists in place before [[Video.Mp4.FragmentedWriter.end]].
    // Invalid counts fail without changing the presentation ranges.
    mtd setPresentationEdits(videoMediaStart: u64, audioFrameCounts: const [..] u64) fail
    {
        if .isEnded or
           not .movieTimescale or
           not .videoEditOffset or
           audioFrameCounts.count != .audioTracks.count or
           videoMediaStart >= .nextDecodeTime do
            fail BadParameterError{"fragmented MP4 presentation edits do not match its tracks"}
        for index in audioFrameCounts.count
        {
            let track  = &.audioTracks[index]
            let frames = audioFrameCounts[index]
            if frames > Swag.U64.Max / .movieTimescale or
               (not frames and track.hasPackets) do
                fail BadParameterError{"fragmented MP4 audio edit exceeds its decoded packets"}
            if frames
            {
                if not track.hasPackets or track.nextTime < 2_048 do
                    fail BadParameterError{"fragmented MP4 audio edit needs a priming and a drain packet"}
                let audibleCapacity = track.nextTime - 1_024
                if frames > audibleCapacity or audibleCapacity - frames >= 1_024 do
                    fail BadParameterError{"fragmented MP4 audio edit needs one priming packet and less than one padding packet"}
            }
        }

        var ranges: Array'AudioPresentationRange
        for count in audioFrameCounts do
            ranges.add({1_024, count})
        try .setPresentationEdits(videoMediaStart, ranges.toSlice())
    }

    // Publishes audio trims with caller-selected decode preroll and exact audible lengths.
    //
    // `videoMediaStart` is in video ticks. Each range uses its audio track's sample-rate clock
    // and must fit submitted packets with less than one packet of trailing padding. This flushes
    // and patches edits before `end`; packet bytes
    // stay unchanged. Use this overload for packet-copy cuts that retain AAC transform history.
    mtd setPresentationEdits(videoMediaStart: u64, audioRanges: const [..] AudioPresentationRange) fail
    {
        if .isEnded or
           not .movieTimescale or
           not .videoEditOffset or
           audioRanges.count != .audioTracks.count or
           videoMediaStart >= .nextDecodeTime do
            fail BadParameterError{"fragmented MP4 presentation edits do not match its tracks"}
        for range, index in audioRanges
        {
            let track = &.audioTracks[index]
            if range.firstSample > cast(u64, Swag.S64.Max) or
               range.sampleCount > Swag.U64.Max / .movieTimescale or
               (not range.sampleCount and track.hasPackets) or
               (range.sampleCount and (not track.hasPackets or range.firstSample >= track.nextTime or range.sampleCount > track.nextTime - range.firstSample or track.nextTime - range.firstSample - range.sampleCount >= 1_024)) do
                fail BadParameterError{"fragmented MP4 audio presentation range exceeds its decoded packets"}
        }

        if .nextDecodeTime - videoMediaStart > Swag.U64.Max / .movieTimescale do
            fail OverflowError{"fragmented MP4 video presentation duration overflows"}

        try .flush()
        let videoDuration = (.nextDecodeTime - videoMediaStart) * .movieTimescale / .timescale
        try .publishEdit(.videoEditOffset, videoDuration, videoMediaStart)
        for range, index in audioRanges
        {
            if not range.sampleCount do
                continue
            let track = &.audioTracks[index]

            // The movie clock is at least as fine as this sample clock. Flooring here and
            // ceiling the inverse in Reader recovers `frames` exactly, including 44.1 kHz.
            let duration = range.sampleCount * .movieTimescale / track.sampleRate
            try .publishEdit(track.editOffset, duration, range.firstSample)
        }

        try .sink.flush()
    }

    // Flushes, optionally appends the random-access index, and closes the stream; repeated calls do nothing.
    mtd end() fail
    {
        if .isEnded do
            return
        try .flush()
        if .options.writeRandomAccessIndex do
            try .writeRandomAccessIndex()
        .isEnded = true
        try .sink.close()
        .closeIndex()
    }

    // Removes the temporary key-frame entries if a writer is discarded before `end`.
    mtd opDrop()
    {
        .closeIndex()
    }
}

// Emits the same bounded-memory final index for a live writer or a recovered recording.
#[Swag.Propagate]
internal func writeFragmentRandomAccessIndex(sink: *ByteSink, entries: *File.FileStream, count: u32) fail
{
    if not count do
        return
    if count > (Swag.U32.Max - 48) / 20 do
        fail OverflowError{"fragmented MP4 random-access index exceeds a compact box"}
    entries.seek(.Begin, 0)
    let randomAccess = beginBox(sink, MovieFragmentRandomAccessId)
    let trackAccess  = beginBox(sink, TrackFragmentRandomAccessId)
    writeFullBox(sink, 1, 0)
    writeU32(sink, 1)
    writeU32(sink, 1)     // One-byte traf/trun numbers and a two-byte sample number.
    writeU32(sink, count)
    for count
    {
        var entry: RandomAccessEntry
        let bytes = Swag.makeSlice(cast([*] u8, &entry), #sizeof(RandomAccessEntry))
        if not entries.readExact(bytes) do
            fail InvalidFormatError{"fragmented MP4 random-access entries are truncated"}
        writeU64(sink, entry.time)
        writeU64(sink, entry.moofOffset)
        writeU8(sink, 1)
        writeU8(sink, 1)
        writeU16(sink, cast(u16, entry.sampleNumber))
    }

    endBox(sink, trackAccess)
    let offset = beginBox(sink, MovieFragmentRandomAccessOffsetId)
    writeFullBox(sink, 0, 0)
    writeU32(sink, cast(u32, sink.position() - randomAccess + 4))
    endBox(sink, offset)
    endBox(sink, randomAccess)
}

private impl FragmentedWriter
{
    mtd closeIndex()
    {
        .indexStream.close()
        if not .indexPath.isEmpty()
        {
            discard catch File.delete(.indexPath.toString())
            .indexPath.clear()
        }
    }

    #[Swag.Propagate]
    mtd writeRandomAccessIndex() fail
    {
        writeFragmentRandomAccessIndex(&.sink, &.indexStream, .indexCount)
    }

    mtd flushVideo() fail
    {
        if not .pendingPackets.count do
            return
        if .sequence == Swag.U32.Max do
            fail OverflowError{"fragmented MP4 sequence number is exhausted"}
        try .writeFragment(.pendingPackets.toSlice(), .pendingData.toSlice())
        .pendingPackets.clear()
        .pendingData.clear()
        .sequence += 1
        try .sink.flush()
    }

    mtd flushAudioTrack(index: u32) fail
    {
        if not .audioTracks[index].pendingPackets.count do
            return
        try .writeFragment(.audioTracks[index].pendingPackets.toSlice(),
                           .audioTracks[index].pendingData.toSlice(),
                           2 + index)
        .audioTracks[index].pendingPackets.clear()
        .audioTracks[index].pendingData.clear()
        .sequence += 1
        try .sink.flush()
    }

    func createConfigured(fileName: string, width, height: s32, timescale: u32, avcConfig: const [..] u8, audioTracks: const [..] FragmentedAudioConfig, options: FragmentedOptions)->FragmentedWriter fail
    {
        if width <= 0 or width > Swag.U16.Max or height <= 0 or height > Swag.U16.Max do
            fail BadParameterError{"fragmented MP4 needs dimensions in the range 1 to 65535"}
        if not timescale do
            fail BadParameterError{"fragmented MP4 needs a positive timescale"}
        try validateOptions(options)
        try validateAvcConfig(avcConfig)
        for audio in audioTracks do
            try validateAudioConfig(audio)

        with var result: #returntype
        {
            .sink = try ByteSink.createFile(fileName, .Read)
            if options.writeRandomAccessIndex
            {
                .indexPath = Path.combine(Env.getSpecialDirectory(.Temp),
                                          Format.toString("swag-mp4-index-%.tmp", Guid128.random()))
                .indexStream = try File.open(.indexPath.toString(), .CreateNew, .ReadWrite, .Zero)
            }

            .width          = cast(u16, width)
            .height         = cast(u16, height)
            .timescale      = timescale
            .movieTimescale = timescale
            .options        = options
            .config.add(avcConfig)
            .audioTracks.reserve(audioTracks.count)
            for audio in audioTracks
            {
                var track: FragmentedAudioTrack
                track.sampleRate = audio.sampleRate
                track.channels   = audio.channelCount
                track.config.add(audio.decoderConfig)
                .audioTracks.add(#move track)
                result.movieTimescale = Math.max(result.movieTimescale, audio.sampleRate)
            }
        }

        try result.writeInitialization()
        try result.sink.flush()
        return result
    }

    func validateOptions(options: FragmentedOptions) fail
    {
        if not options.maxPacketsPerFragment or
           options.maxPacketsPerFragment > 1_024 or
           not options.maxAudioPacketsPerFragment or
           options.maxAudioPacketsPerFragment > 1_024 or
           not options.maxBufferedBytes or
           options.maxBufferedBytes > Swag.U32.Max - 8 do
            fail BadParameterError{"fragmented MP4 grouping limits are outside the supported range"}
    }

    func validateAudioConfig(audio: FragmentedAudioConfig) fail
    {
        const Rates: [13] u32 = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000,
                                 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]
        let config = audio.decoderConfig
        if config.count != 2 or config[0] >> 3 != 2 do
            fail UnsupportedFormatError{"fragmented MP4 needs a two-byte AAC-LC AudioSpecificConfig"}
        let rateIndex = cast(u32, ((config[0] & 7) << 1) | (config[1] >> 7))
        let channels  = (config[1] >> 3) & 15
        if rateIndex >= Rates.count or
           Rates[rateIndex] != audio.sampleRate or
           audio.sampleRate > Swag.U16.Max or
           channels != audio.channelCount or
           (channels != 1 and channels != 2) or
           (config[1] & 7) != 0 do
            fail BadParameterError{"fragmented MP4 AAC configuration does not match its sample rate or channels"}
    }

    // Reject incomplete parameter sets before opening the destination file.
    func validateAvcConfig(bytes: const [..] u8) fail
    {
        if bytes.count < 7 or bytes.count > Swag.U32.Max - 8 or bytes[0] != 1 or (bytes[4] & 3) != 3 do
            fail InvalidFormatError{"fragmented MP4 needs AVC configuration with four-byte NAL lengths"}

        let sequenceCount = bytes[5] & 31
        if not sequenceCount do
            fail InvalidFormatError{"AVC configuration has no sequence parameter set"}
        var offset = 6'u64
        for sequenceCount
        {
            if bytes.count - offset < 2 do
                fail InvalidFormatError{"AVC sequence parameter set length is missing"}
            let size = Math.make16(bytes[offset], bytes[offset + 1])
            offset += 2
            if not size or size > bytes.count - offset do
                fail InvalidFormatError{"AVC sequence parameter set is truncated"}
            offset += size
        }

        if offset == bytes.count or not bytes[offset] do
            fail InvalidFormatError{"AVC configuration has no picture parameter set"}
        let pictureCount = bytes[offset]
        offset += 1
        for pictureCount
        {
            if bytes.count - offset < 2 do
                fail InvalidFormatError{"AVC picture parameter set length is missing"}
            let size = Math.make16(bytes[offset], bytes[offset + 1])
            offset += 2
            if not size or size > bytes.count - offset do
                fail InvalidFormatError{"AVC picture parameter set is truncated"}
            offset += size
        }
    }

    // Checks the complete length-prefixed access unit before writing any part of its fragment.
    func validateAvcPacket(bytes: const [..] u8) fail
    {
        var offset = 0'u64
        while offset < bytes.count
        {
            if bytes.count - offset < 5 do
                fail InvalidFormatError{"AVC packet ends before a complete NAL unit"}
            let size = Math.make32(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
            offset += 4
            if not size or size > bytes.count - offset do
                fail InvalidFormatError{"AVC NAL unit length exceeds the packet"}
            offset += size
        }
    }

    #[Swag.Propagate]
    mtd writeInitialization() fail
    {
        let fileType = beginBox(&.sink, FileTypeId)
        writeU32(&.sink, IsomBrandId)
        writeU32(&.sink, 0x0000_0200)
        writeU32(&.sink, IsomBrandId)
        writeU32(&.sink, Iso6BrandId)
        writeU32(&.sink, AvcSampleEntryId)
        endBox(&.sink, fileType)

        let movie = beginBox(&.sink, MovieId)
        .writeMovieHeader()
        .writeTrack()
        for index in .audioTracks.count do
            .writeAudioTrack(cast(u32, index))
        .writeMovieExtends()
        endBox(&.sink, movie)
    }

    // A 44-byte edit list sits inside an ignored `free` box until the completed stream
    // publishes it. The box type is patched last, so a partly finalized file remains readable.
    #[Swag.Propagate]
    mtd writeEditPlaceholder()->u64 fail
    {
        let start = beginBox(&.sink, FreeBoxId)
        let list  = beginBox(&.sink, EditListId)
        writeFullBox(&.sink, 1, 0)
        writeU32(&.sink, 1)
        writeU64(&.sink, 0)
        writeU64(&.sink, 0)
        writeU16(&.sink, 1)
        writeU16(&.sink, 0)
        endBox(&.sink, list)
        endBox(&.sink, start)
        return start
    }

    mtd publishEdit(offset, duration, mediaTime: u64) fail
    {
        try patchU64(&.sink, offset + 24, duration)
        try patchU64(&.sink, offset + 32, mediaTime)
        try patchU32(&.sink, offset + 4, EditContainerId)
    }

    #[Swag.Propagate]
    mtd writeMovieHeader() fail
    {
        let box = beginBox(&.sink, MovieHeaderId)
        writeFullBox(&.sink, 1, 0)
        writeU64(&.sink, 0)
        writeU64(&.sink, 0)
        writeU32(&.sink, .movieTimescale)
        writeU64(&.sink, 0)
        writeU32(&.sink, 0x0001_0000)
        writeU16(&.sink, 0x0100)
        writeU16(&.sink, 0)
        writeU32(&.sink, 0)
        writeU32(&.sink, 0)
        writeIdentityMatrix(&.sink)
        for 6 do
            writeU32(&.sink, 0)
        writeU32(&.sink, cast(u32, .audioTracks.count + 2))
        endBox(&.sink, box)
    }

    #[Swag.Propagate]
    mtd writeTrack() fail
    {
        let track  = beginBox(&.sink, TrackId)
        let header = beginBox(&.sink, TrackHeaderId)
        writeFullBox(&.sink, 1, 7)
        writeU64(&.sink, 0)
        writeU64(&.sink, 0)
        writeU32(&.sink, 1)
        writeU32(&.sink, 0)
        writeU64(&.sink, 0)
        writeU32(&.sink, 0)
        writeU32(&.sink, 0)
        for 4 do
            writeU16(&.sink, 0)
        writeIdentityMatrix(&.sink)
        writeU32(&.sink, cast(u32, .width) << 16)
        writeU32(&.sink, cast(u32, .height) << 16)
        endBox(&.sink, header)

        .videoEditOffset = .writeEditPlaceholder()

        let media = beginBox(&.sink, MediaId)
        .writeMediaHeader()
        .writeHandler()
        .writeMediaInfo()
        endBox(&.sink, media)
        endBox(&.sink, track)
    }

    #[Swag.Propagate]
    mtd writeMediaHeader() fail
    {
        let box = beginBox(&.sink, MediaHeaderId)
        writeFullBox(&.sink, 1, 0)
        writeU64(&.sink, 0)
        writeU64(&.sink, 0)
        writeU32(&.sink, .timescale)
        writeU64(&.sink, 0)
        writeU16(&.sink, UndLanguage)
        writeU16(&.sink, 0)
        endBox(&.sink, box)
    }

    #[Swag.Propagate]
    mtd writeHandler() fail
    {
        let box = beginBox(&.sink, HandlerId)
        writeFullBox(&.sink, 0, 0)
        writeU32(&.sink, 0)
        writeU32(&.sink, VideoHandlerId)
        for 3 do
            writeU32(&.sink, 0)
        .sink.writeText("Swag H.264\x00")
        endBox(&.sink, box)
    }

    #[Swag.Propagate]
    mtd writeMediaInfo() fail
    {
        let mediaInfo   = beginBox(&.sink, MediaInfoId)
        let videoHeader = beginBox(&.sink, VideoMediaHeaderId)
        writeFullBox(&.sink, 0, 1)
        for 4 do
            writeU16(&.sink, 0)
        endBox(&.sink, videoHeader)

        .writeDataInfo()
        .writeSampleTable()
        endBox(&.sink, mediaInfo)
    }

    #[Swag.Propagate]
    mtd writeDataInfo() fail
    {
        let dataInfo  = beginBox(&.sink, DataInfoId)
        let reference = beginBox(&.sink, DataReferenceId)
        writeFullBox(&.sink, 0, 0)
        writeU32(&.sink, 1)
        let url = beginBox(&.sink, DataEntryUrlId)
        writeFullBox(&.sink, 0, 1)
        endBox(&.sink, url)
        endBox(&.sink, reference)
        endBox(&.sink, dataInfo)
    }

    #[Swag.Propagate]
    mtd writeSampleTable() fail
    {
        let table        = beginBox(&.sink, SampleTableId)
        let descriptions = beginBox(&.sink, SampleDescriptionId)
        writeFullBox(&.sink, 0, 0)
        writeU32(&.sink, 1)
        .writeAvcSampleEntry()
        endBox(&.sink, descriptions)
        .writeEmptySampleTables()
        endBox(&.sink, table)
    }

    #[Swag.Propagate]
    mtd writeEmptySampleTables() fail
    {
        const EmptyTables: [3] u32 = [TimeToSampleId, SampleToChunkId, ChunkOffsetId]
        for kind in EmptyTables
        {
            let box = beginBox(&.sink, kind)
            writeFullBox(&.sink, 0, 0)
            writeU32(&.sink, 0)
            endBox(&.sink, box)
        }

        let sizes = beginBox(&.sink, SampleSizeId)
        writeFullBox(&.sink, 0, 0)
        writeU32(&.sink, 0)
        writeU32(&.sink, 0)
        endBox(&.sink, sizes)
    }

    #[Swag.Propagate]
    mtd writeAvcSampleEntry() fail
    {
        let entry = beginBox(&.sink, AvcSampleEntryId)
        writeU32(&.sink, 0)
        writeU16(&.sink, 0)
        writeU16(&.sink, 1)
        for 4 do
            writeU32(&.sink, 0)
        writeU16(&.sink, .width)
        writeU16(&.sink, .height)
        writeU32(&.sink, 72 << 16)
        writeU32(&.sink, 72 << 16)
        writeU32(&.sink, 0)
        writeU16(&.sink, 1)
        for 32 do
            writeU8(&.sink, 0)
        writeU16(&.sink, 24)
        writeU16(&.sink, 0xFFFF)

        let configBox = beginBox(&.sink, AvcConfigId)
        .sink.write(.config.toSlice())
        endBox(&.sink, configBox)
        endBox(&.sink, entry)
    }

    #[Swag.Propagate]
    mtd writeAudioTrack(index: u32) fail
    {
        let track  = beginBox(&.sink, TrackId)
        let header = beginBox(&.sink, TrackHeaderId)
        writeFullBox(&.sink, 1, 7)
        writeU64(&.sink, 0)
        writeU64(&.sink, 0)
        writeU32(&.sink, 2 + index)
        writeU32(&.sink, 0)
        writeU64(&.sink, 0)
        writeU32(&.sink, 0)
        writeU32(&.sink, 0)
        writeU16(&.sink, 0)
        writeU16(&.sink, 0)
        writeU16(&.sink, 0x0100)
        writeU16(&.sink, 0)
        writeIdentityMatrix(&.sink)
        writeU32(&.sink, 0)
        writeU32(&.sink, 0)
        endBox(&.sink, header)

        .audioTracks[index].editOffset = .writeEditPlaceholder()

        let media  = beginBox(&.sink, MediaId)
        let timing = beginBox(&.sink, MediaHeaderId)
        writeFullBox(&.sink, 1, 0)
        writeU64(&.sink, 0)
        writeU64(&.sink, 0)
        writeU32(&.sink, .audioTracks[index].sampleRate)
        writeU64(&.sink, 0)
        writeU16(&.sink, UndLanguage)
        writeU16(&.sink, 0)
        endBox(&.sink, timing)

        let handler = beginBox(&.sink, HandlerId)
        writeFullBox(&.sink, 0, 0)
        writeU32(&.sink, 0)
        writeU32(&.sink, AudioHandlerId)
        for 3 do
            writeU32(&.sink, 0)
        .sink.writeText("Swag AAC-LC\x00")
        endBox(&.sink, handler)

        let mediaInfo   = beginBox(&.sink, MediaInfoId)
        let soundHeader = beginBox(&.sink, SoundMediaHeaderId)
        writeFullBox(&.sink, 0, 0)
        writeU16(&.sink, 0)
        writeU16(&.sink, 0)
        endBox(&.sink, soundHeader)
        .writeDataInfo()
        .writeAudioSampleTable(index)
        endBox(&.sink, mediaInfo)
        endBox(&.sink, media)
        endBox(&.sink, track)
    }

    #[Swag.Propagate]
    mtd writeAudioSampleTable(index: u32) fail
    {
        let table        = beginBox(&.sink, SampleTableId)
        let descriptions = beginBox(&.sink, SampleDescriptionId)
        writeFullBox(&.sink, 0, 0)
        writeU32(&.sink, 1)
        .writeAudioSampleEntry(index)
        endBox(&.sink, descriptions)
        .writeEmptySampleTables()
        endBox(&.sink, table)
    }

    #[Swag.Propagate]
    mtd writeAudioSampleEntry(index: u32) fail
    {
        let entry = beginBox(&.sink, Mpeg4AudioId)
        for 6 do
            writeU8(&.sink, 0)
        writeU16(&.sink, 1)
        writeU16(&.sink, 0)
        writeU16(&.sink, 0)
        writeU32(&.sink, 0)
        writeU16(&.sink, .audioTracks[index].channels)
        writeU16(&.sink, 16)
        writeU16(&.sink, 0)
        writeU16(&.sink, 0)
        writeU32(&.sink, .audioTracks[index].sampleRate << 16)

        let descriptor = beginBox(&.sink, ElementaryStreamId)
        writeFullBox(&.sink, 0, 0)

        // ES_ID matches this track, followed by the MPEG-4 Audio decoder and its ASC.
        writeU8(&.sink, 0x03)
        writeU8(&.sink, 0x19)
        writeU16(&.sink, cast(u16, 2 + index))
        const Decoder: [18] u8 = [0, 0x04, 0x11, 0x40, 0x15, 0, 0, 0,
                                  0, 0, 0, 0, 0, 0, 0, 0, 0x05, 0x02]
        .sink.write(Swag.makeSlice(&Decoder[0], Decoder.count))
        .sink.write(.audioTracks[index].config.toSlice())
        const Suffix: [3] u8 = [0x06, 0x01, 0x02]
        .sink.write(Swag.makeSlice(&Suffix[0], Suffix.count))
        endBox(&.sink, descriptor)
        endBox(&.sink, entry)
    }

    #[Swag.Propagate]
    mtd writeMovieExtends() fail
    {
        let extends = beginBox(&.sink, MovieExtendsId)
        let track   = beginBox(&.sink, TrackExtendsId)
        writeFullBox(&.sink, 0, 0)
        writeU32(&.sink, 1)
        writeU32(&.sink, 1)
        for 3 do
            writeU32(&.sink, 0)
        endBox(&.sink, track)
        for index in .audioTracks.count
        {
            let audio = beginBox(&.sink, TrackExtendsId)
            writeFullBox(&.sink, 0, 0)
            writeU32(&.sink, cast(u32, 2 + index))
            writeU32(&.sink, 1)
            for 3 do
                writeU32(&.sink, 0)
            endBox(&.sink, audio)
        }

        endBox(&.sink, extends)
    }

    #[Swag.Propagate]
    mtd writeFragment(samples: const [..] BufferedPacket, bytes: const [..] u8, trackId: u32 = 1) fail
    {
        if .sequence == Swag.U32.Max do
            fail OverflowError{"fragmented MP4 sequence number is exhausted"}
        let fragment = beginBox(&.sink, MovieFragmentId)
        let header   = beginBox(&.sink, MovieFragmentHeaderId)
        writeFullBox(&.sink, 0, 0)
        writeU32(&.sink, .sequence + 1)
        endBox(&.sink, header)

        let track       = beginBox(&.sink, TrackFragmentId)
        let trackHeader = beginBox(&.sink, TrackFragmentHeaderId)
        writeFullBox(&.sink, 0, 0x020000)
        writeU32(&.sink, trackId)
        endBox(&.sink, trackHeader)

        let decodeTime = beginBox(&.sink, DecodeTimeId)
        writeFullBox(&.sink, 1, 0)
        writeU64(&.sink, samples[0].decodeTime)
        endBox(&.sink, decodeTime)

        let run = beginBox(&.sink, TrackRunId)
        writeFullBox(&.sink, 1, 0x000F01)
        writeU32(&.sink, cast(u32, samples.count))
        let dataOffset = .sink.position()
        writeU32(&.sink, 0)
        var described = 0'u64
        for sample in samples
        {
            writeU32(&.sink, sample.duration)
            writeU32(&.sink, sample.size)
            writeU32(&.sink, sample.isKeyFrame ? 0x02000000 : 0x01010000)
            writeU32(&.sink, cast #bit(u32, sample.compositionOffset))
            described += sample.size
        }

        endBox(&.sink, run)
        endBox(&.sink, track)
        endBox(&.sink, fragment)

        Swag.assert(described == bytes.count)
        patchU32(&.sink, dataOffset, cast(u32, .sink.position() - fragment + 8))
        writeU32(&.sink, cast(u32, bytes.count + 8))
        writeU32(&.sink, MediaDataId)
        .sink.write(bytes)
        if trackId == 1 and .options.writeRandomAccessIndex
        {
            for index in samples.count where samples[index].isKeyFrame
            {
                if .indexCount == Swag.U32.Max do
                    fail OverflowError{"fragmented MP4 random-access index has too many entries"}
                let entry = RandomAccessEntry{samples[index].decodeTime, fragment, index + 1}
                .indexStream.writeAll(Swag.makeSlice(cast(const [*] u8, &entry), #sizeof(RandomAccessEntry)))
                .indexCount += 1
            }
        }
    }
}
