//! Format: ISO Base Media File Format (MP4) progressive fragment cursor.
//! Supported: Bounded H.264 and AAC-LC fragments, partial final-fragment recovery, and indexed seek offsets.
//! Not supported: Classic sample tables, multi-track movie fragments, and files changing while open.
//! Role: This file walks compressed MP4 packets with memory independent of recording duration.
//
#global namespace Mp4
#global export

using Core, Core.Errors

private const CursorMovieExtendsId = fourCc('m'u32, 'v'u32, 'e'u32, 'x'u32)

// One compressed sample found while walking MP4 fragments in file order.
//
// `trackIndex` is zero for video; for audio it is the zero-based index returned by
// [[Video.Mp4.FragmentedPacketCursor.audioTrack]]. `info.sourceOffset` can be passed to
// [[Video.Mp4.FragmentedPacketCursor.readPayload]].
struct FragmentedCursorPacket
{
    public info:       FragmentedPacketInfo     // Sample timing and payload location.
    public isVideo:    bool     // Whether this packet belongs to the video track.
    public trackIndex: u32      // Zero for video or the zero-based AAC track index.
}

// Walks a fragmented H.264 MP4 without retaining a table for the whole recording.
//
// Opening reads only the initialization movie. Each call to `nextPacket` parses at most one
// `moof`/`mdat` pair and keeps at most 1024 sample descriptions. Payload bytes are read only on
// request. A completed [[Video.Mp4.FragmentedIndex]] can supply a key-frame fragment offset for
// `seekFragment`. The file must remain unchanged while the cursor is open.
#[Swag.NoCopy]
struct FragmentedPacketCursor
{
    private
    {
        source:              ByteSource
        layout:              Layout
        current:             Array'FragmentSample
        nextBoxOffset:       u64
        firstFragmentOffset: u64
        currentIndex:        u64
        currentTrackIndex:   u32
        currentIsVideo:      bool
        nextVideoTime:       u64
        audioNextTimes:      Array'u64
        audioSeen:           Array'bool
        hasVideo:            bool
        isEnded:             bool
    }
}

impl FragmentedPacketCursor
{
    // Opens the initialization movie of a fragmented H.264 MP4 without scanning its media.
    func open(fileName: string)->FragmentedPacketCursor fail
    {
        var result: #returntype
        result.source = try ByteSource.openFile(fileName)
        while result.source.position() < result.source.size()
        {
            let box = try readBox(&result.source, result.source.size())
            if box.kind == MovieId
            {
                var hasMovieExtends = false
                while result.source.position() < box.end
                {
                    let child = try readBox(&result.source, box.end)
                    if child.kind == CursorMovieExtendsId do
                        hasMovieExtends = true
                    try result.source.seek(child.end)
                }

                if not hasMovieExtends do
                    fail UnsupportedFormatError{"MP4 packet cursor needs a fragmented movie"}
                try result.source.seek(box.data)
                try result.layout.parseMovie(&result.source, box.end)
                if not result.layout.hasVideo or
                   not result.layout.track.isAvc or
                   result.layout.audioTracks.count > 4 do
                    fail UnsupportedFormatError{"MP4 packet cursor needs H.264 and up to four AAC tracks"}
                result.firstFragmentOffset = box.end
                result.nextBoxOffset       = box.end
                result.audioNextTimes.resize(result.layout.audioTracks.count)
                result.audioSeen.resize(result.layout.audioTracks.count)
                return result
            }

            try result.source.seek(box.end)
        }

        fail InvalidFormatError{"fragmented MP4 has no initialization movie"}
    }

    // Releases the source file; repeated calls do nothing.
    mtd close() => .source.close()

    // Returns the video width in pixels.
    mtd const width()->s32 => .layout.track.width

    // Returns the video height in pixels.
    mtd const height()->s32 => .layout.track.height

    // Returns the video track's decode-time ticks per second.
    mtd const timescale()->u32 => .layout.track.timescale

    // Borrows the AVC decoder configuration until the cursor closes.
    mtd const avcConfig()->const [..] u8 => .layout.track.videoConfig.toSlice()

    // Returns the number of AAC-LC tracks, including empty tracks.
    mtd const audioTrackCount()->u64 => .layout.audioTracks.count

    // Borrows one AAC-LC track configuration until the cursor closes.
    mtd const audioTrack(index: u64)->FragmentedAudioConfig fail
    {
        if index >= .layout.audioTracks.count do
            fail BadParameterError{"fragmented MP4 cursor audio track index is outside the movie"}
        let track = &.layout.audioTracks[index]
        return {track.sampleRate, cast(u16, track.channelCount), track.aacConfig.toSlice()}
    }

    // Advances to the next complete video or AAC sample in file order.
    //
    // Returns false at the end, or when an incomplete final fragment follows completed video.
    // `packet` receives metadata only; call `readPayload` for its encoded bytes.
    mtd nextPacket(packet: *FragmentedCursorPacket)->bool fail
    {
        while .currentIndex == .current.count
        {
            if not try .nextFragment() do
                return false
        }

        let sample = .current[.currentIndex]
        .currentIndex += 1
        packet[]      = {FragmentedPacketInfo{sample.offset, sample.size, sample.decodeTime,
                                              sample.presentationTime, sample.duration, sample.isKeyFrame},
                         .currentIsVideo, .currentTrackIndex}
        return true
    }

    // Reads a packet's encoded payload into caller-owned storage.
    //
    // `packet` must have been returned by this cursor while its source file was unchanged.
    mtd readPayload(packet: FragmentedCursorPacket, bytes: *Array'u8) fail
    {
        bytes.resize(packet.info.byteSize)
        try .source.seek(packet.info.sourceOffset)
        try .source.readExact(bytes.toSlice())
    }

    // Restarts the scan at a complete movie-fragment offset.
    //
    // A [[Video.Mp4.FragmentedSeekPoint.moofOffset]] is suitable. The fragment must start with
    // a key video sample if the caller intends to decode from it. This resets continuity checks
    // for the tracks because preceding fragments are skipped.
    mtd seekFragment(offset: u64) fail
    {
        if offset < .firstFragmentOffset or
           offset > .source.size() or
           .source.size() - offset < BoxHeaderSize do
            fail BadParameterError{"fragmented MP4 cursor offset is outside its fragments"}
        try .source.seek(offset)
        let boxSize = try .source.readBigEndian'u32()
        let boxKind = try .source.readBigEndian'u32()
        if boxKind != FragmentId or boxSize < BoxHeaderSize or boxSize > .source.size() - offset do
            fail BadParameterError{"fragmented MP4 cursor offset does not name a movie fragment"}
        .nextBoxOffset = offset
        .current.clear()
        .currentIndex  = 0
        .hasVideo      = false
        .nextVideoTime = 0
        for &seen in .audioSeen do
            seen[] = false
        .isEnded = false
    }
}

private impl FragmentedPacketCursor
{
    mtd nextFragment()->bool fail
    {
        if .isEnded do
            return false
        while .nextBoxOffset < .source.size()
        {
            let offset    = .nextBoxOffset
            let remaining = .source.size() - offset
            if remaining < BoxHeaderSize
            {
                if .hasVideo
                {
                    .isEnded = true
                    return false
                }

                fail InvalidFormatError{"fragmented MP4 cursor has a partial box header"}
            }

            try .source.seek(offset)
            let declared = try .source.readBigEndian'u32()
            let kind     = try .source.readBigEndian'u32()
            if (kind == FragmentId or kind == MediaDataId or kind == FragmentRandomAccessId) and
               ((kind == FragmentId and not declared) or
                (declared >= BoxHeaderSize and declared > remaining))
            {
                if .hasVideo
                {
                    .isEnded = true
                    return false
                }

                fail InvalidFormatError{"fragmented MP4 cursor has no complete video fragment"}
            }

            try .source.seek(offset)
            let box = try readBox(&.source, .source.size())
            if box.kind == FragmentRandomAccessId
            {
                .isEnded = true
                return false
            }

            if box.kind != FragmentId
            {
                .nextBoxOffset = box.end
                continue
            }

            var fragment = try .layout.parseFragment(&.source, offset, box.end)
            if box.end > .source.size() - BoxHeaderSize
            {
                if .hasVideo
                {
                    .isEnded = true
                    return false
                }

                fail InvalidFormatError{"fragmented MP4 cursor has no media data for its first fragment"}
            }

            try .source.seek(box.end)
            let dataSize = try .source.readBigEndian'u32()
            let dataKind = try .source.readBigEndian'u32()
            if dataKind != MediaDataId do
                fail InvalidFormatError{"fragmented MP4 movie fragment is not followed by media data"}
            if dataSize < BoxHeaderSize or dataSize > .source.size() - box.end
            {
                if .hasVideo
                {
                    .isEnded = true
                    return false
                }

                fail InvalidFormatError{"fragmented MP4 cursor has no complete media data"}
            }

            try .source.seek(box.end)
            let mediaData = try readBox(&.source, .source.size())
            for sample in fragment.samples do
                try .layout.validateFragmentSample(sample, mediaData)

            if fragment.trackId == .layout.track.id
            {
                if not .hasVideo and not fragment.samples[0].isKeyFrame do
                    fail InvalidFormatError{"fragmented MP4 cursor video must start at a key frame"}
                if .hasVideo and fragment.samples[0].decodeTime < .nextVideoTime do
                    fail InvalidFormatError{"fragmented MP4 cursor video decode times overlap"}
                .currentIsVideo    = true
                .currentTrackIndex = 0
                .hasVideo          = true
                let last = fragment.samples.back()
                .nextVideoTime = last.decodeTime + last.duration
            }
            else
            {
                let trackIndex = .layout.findAudioTrack(fragment.trackId)
                if trackIndex == Swag.U64.Max do
                    fail UnsupportedFormatError{"fragmented MP4 cursor refers to an unsupported track"}
                for sample in fragment.samples
                {
                    if sample.duration != 1024 or sample.presentationTime != cast(s64, sample.decodeTime) do
                        fail UnsupportedFormatError{"fragmented MP4 cursor needs 1024-sample AAC access units"}
                }

                if .audioSeen[trackIndex] and
                   fragment.samples[0].decodeTime != .audioNextTimes[trackIndex] do
                    fail InvalidFormatError{"fragmented MP4 cursor AAC packets are not continuous"}
                let last = fragment.samples.back()
                .audioNextTimes[trackIndex] = last.decodeTime + last.duration
                .audioSeen[trackIndex]      = true
                .currentIsVideo             = false
                .currentTrackIndex          = cast(u32, trackIndex)
            }

            .current       = #move fragment.samples
            .currentIndex  = 0
            .nextBoxOffset = mediaData.end
            return true
        }

        .isEnded = true
        return false
    }
}
