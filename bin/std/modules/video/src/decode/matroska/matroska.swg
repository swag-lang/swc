//! Format: Matroska/EBML container decoder component.
//! Supported: H.264, H.265 and MPEG-4 Part 2 picture tracks, the last also through a Video for Windows header, and AAC-LC, AC-3, independent E-AC-3, FLAC, or Layer III audio tracks, with cues, timestamps, codec delay, and common block lacing for audio.
//! Not supported: Picture codecs other than those three, laced or invisible picture blocks, dependent E-AC-3 substreams, encrypted tracks, and writing Matroska.
//! Role: This file owns tracks, clusters, cues, timestamps, progressive indexing, and media dispatch.
//
#global namespace Matroska

using Core, Core.Errors, Pixel, Audio

private const VideoTrackType = 1'u64
private const AudioTrackType = 2'u64
private const AvcCodecId = "V_MPEG4/ISO/AVC"
private const HevcCodecId = "V_MPEGH/ISO/HEVC"
private const AacCodecId = "A_AAC"
private const Ac3CodecId = "A_AC3"
private const Eac3CodecId = "A_EAC3"
private const FlacCodecId = "A_FLAC"
private const Mp3CodecId = "A_MPEG/L3"
private const Mpeg4CodecId = "V_MPEG4/ISO/ASP"
private const VfwCodecId = "V_MS/VFW/FOURCC"
private const DefaultTimestampScale = 1_000_000'u64
private const NoTrack = Swag.U64.Max
private const NoOffset = Swag.U64.Max

private func packetBits(bytes: const [..] u8, offset: u64, bitPosition, count: u32)->u32
{
    var result: u32
    for bit in count
    {
        let position = cast(u64) bitPosition + bit
        result = (result << 1) | ((cast(u32) bytes[offset + (position >> 3)] >> cast(u32) (7 - (position & 7))) & 1)
    }

    return result
}

private func dolbySpeakerMask(acmod: u32, lfeon: bool)->u32
{
    const Masks: [8] u32 = [0x0003, 0x0004, 0x0003, 0x0007, 0x0103, 0x0107, 0x0033, 0x0037]
    return Masks[acmod] | (lfeon ? 0x0008 : 0)
}

// Container root resolved once from the EBML header.
private struct Container
{
    cursor:  Cursor
    segment: Element
}

// Absolute locations advertised by the segment seek head.
private struct MetadataTargets
{
    info:   u64 = NoOffset
    tracks: u64 = NoOffset
    cues:   u64 = NoOffset
}

// One random-access point from the compact Matroska Cues element.
private struct CueEntry
{
    timestamp:     u64
    clusterOffset: u64
}

// One Matroska track and the compact packet index collected for it.
private struct Track
{
    number:          u64
    kind:            u64
    name:            String
    language:        String
    codecId:         String
    codecPrivate:    Array'u8
    setup:           Array'u8       // Setup headers a legacy track states in its stream, not in the container.
    defaultDuration: u64
    codecDelay:      u64
    seekPreRoll:     u64
    width:           s32
    height:          s32
    sampleRate:      f64  = 8_000
    channels:        u32  = 1
    bitsPerSample:   u32
    isEnabled:       bool = true
    isDefault:       bool = true
    hasEncodings:    bool
    videoSamples:    Array'SampleEntry
    audioPackets:    Array'SoundPacket
    audioFrameCount: u64
    audioStart:      s64
    hasAudioStart:   bool
}

private impl Track
{
    mtd const isPlayableVideo()->bool
    {
        if !.isEnabled or .hasEncodings or .kind != VideoTrackType do
            return false
        if .codecId == AvcCodecId or .codecId == HevcCodecId or .codecId == Mpeg4CodecId do
            return .codecPrivate.count != 0
        return .isVfwMpeg4()
    }

    mtd const isHevcVideo()->bool => .codecId == HevcCodecId

    // Whether a Video for Windows header names a codec this decoder reads.
    mtd const isVfwMpeg4()->bool
    {
        if .codecId != VfwCodecId or .codecPrivate.count < Video.BitmapInfoHeaderSize do
            return false
        return Video.isMpeg4FourCc(Video.bitmapCompression(.codecPrivate.toSlice()))
    }

    // The setup headers of a picture track, wherever the file states them.
    mtd const videoConfiguration()->const [..] u8
    {
        if .codecId != VfwCodecId do
            return .codecPrivate.toSlice()
        if .codecPrivate.count > Video.BitmapInfoHeaderSize do
            return .codecPrivate.toSlice()[Video.BitmapInfoHeaderSize until .codecPrivate.count]

        // A bitmap header that names the codec and nothing more leaves the layer to the stream.
        return .setup.toSlice()
    }

    // Whether the setup headers have to be taken from the first sample.
    mtd const needsInlineSetup()->bool => .codecId == VfwCodecId and .codecPrivate.count <= Video.BitmapInfoHeaderSize

    // Which coded picture format this track names.
    mtd const pictureKind()->u32
    {
        if .codecId == HevcCodecId do
            return PictureHevc
        if .codecId == Mpeg4CodecId or .codecId == VfwCodecId do
            return PictureMpeg4
        return PictureAvc
    }

    mtd const soundEncoding()->SoundFileEncoding
    {
        if .codecId == AacCodecId do
            return .AacLc
        if .codecId == Ac3CodecId do
            return .Ac3
        if .codecId == Eac3CodecId do
            return .Eac3
        if .codecId == FlacCodecId do
            return .Flac
        if .codecId == Mp3CodecId do
            return .Mp3
        return .Unknown
    }

    mtd const isPlayableAudio()->bool
    {
        let encoding = .soundEncoding()
        if !.isEnabled or .hasEncodings or .kind != AudioTrackType or encoding == .Unknown do
            return false
        if .sampleRate <= 0 or .sampleRate > cast(f64) Swag.U32.Max or !.channels or .channels > 8 do
            return false
        return (encoding != .AacLc and encoding != .Flac) or .codecPrivate.count != 0
    }

    mtd const leadingTrimFrames()->u64 fail
    {
        if !.codecDelay do
            return 0
        let frames = cast(f64) .codecDelay * .sampleRate / 1_000_000_000.0
        if frames > cast(f64) Swag.U32.Max do
            fail UnsupportedFormatError{"Matroska audio codec delay exceeds the supported range"}
        return cast(u64) Math.round(frames)
    }

    mtd const speakerMask(bytes: const [..] u8)->u32 fail
    {
        let encoding = .soundEncoding()

        // AAC states its channel configuration in the decoder setup, and FLAC in its stream
        // information; only Dolby hides it in the first packet.
        if encoding != .Ac3 and encoding != .Eac3 do
            return 0
        let packet = .audioPackets[0]
        if packet.sourceOffset > @countof(bytes) or packet.byteSize > @countof(bytes) - packet.sourceOffset do
            fail InvalidFormatError{"Matroska Dolby audio packet is truncated"}
        if encoding == .Eac3
        {
            if packet.byteSize < 5 do
                fail InvalidFormatError{"Matroska E-AC-3 packet header is truncated"}
            let acmod = packetBits(bytes, packet.sourceOffset, 36, 3)
            let lfeon = packetBits(bytes, packet.sourceOffset, 39, 1) != 0
            return dolbySpeakerMask(acmod, lfeon)
        }

        if packet.byteSize < 7 do
            fail InvalidFormatError{"Matroska AC-3 packet header is truncated"}
        let acmod       = packetBits(bytes, packet.sourceOffset, 48, 3)
        var lfePosition = 51'u32
        if acmod & 1 and acmod != 1 do
            lfePosition += 2
        if acmod & 4 do
            lfePosition += 2
        if acmod == 2 do
            lfePosition += 2
        let lfeon = packetBits(bytes, packet.sourceOffset, lfePosition, 1) != 0
        return dolbySpeakerMask(acmod, lfeon)
    }
}

// Matroska metadata retained while the mapped stream is indexed.
private struct Layout
{
    timestampScale: u64 = DefaultTimestampScale
    durationTicks:  f64
    tracks:         Array'Track
    clusters:       Array'Element
    audioTracks:    Array'u64
    selectedVideo:  u64 = NoTrack
    laceSizes:      Array'u64
    segment:        Element
    scanPosition:   u64
    indexComplete:  bool
    indexPictures:  bool = true
    videoChunkEnds: Array'u64
    cues:           Array'CueEntry
}

private impl Layout
{
    // Parses the EBML hierarchy and indexes block payloads without reading them.
    mtd parse(bytes: const [..] u8, cancelled: #null *u32 = null, indexPictures: bool = true)->bool fail
    {
        .indexPictures = indexPictures
        var container = .openContainer(bytes)
        if !.parseSegment(&container.cursor, container.segment, cancelled) do
            return false
        for cluster in .clusters
        {
            if cancelled and Atomic.get(cancelled!) do
                return false
            if !.parseCluster(&container.cursor, cluster, cancelled) do
                return false
        }

        let video = &.tracks[.selectedVideo]
        if indexPictures and !video.videoSamples.count do
            fail InvalidFormatError{"Matroska video track has no blocks"}
        return true
    }

    // Reads only the bounded metadata needed to choose and configure a decoder.
    mtd parseMetadata(bytes: const [..] u8) fail
    {
        var container = .openContainer(bytes)
        let cursor    = &container.cursor
        let segment   = container.segment
        .segment      = segment
        .scanPosition = segment.data
        var targets:   MetadataTargets
        var hasTracks: bool

        cursor.seek(segment.data)
        while cursor.position < segment.end and !hasTracks
        {
            let element = cursor.readElement(segment.end)
            switch element.id
            {
            case SeekHeadId:
                targets = .parseSeekHead(cursor, element, segment)
                if targets.info != NoOffset do
                    .parseMetadataElement(cursor, targets.info, InfoId, segment)

                if targets.tracks != NoOffset
                {
                    .parseMetadataElement(cursor, targets.tracks, TracksId, segment)
                    .selectTracks()
                    hasTracks = true
                }

                if hasTracks and targets.cues != NoOffset do
                    .parseMetadataElement(cursor, targets.cues, CuesId, segment)

            case InfoId:
                .parseInfo(cursor, element)

            case TracksId:
                .parseTracks(cursor, element)
                .selectTracks()
                hasTracks = true

            case CuesId:
                if hasTracks do
                    .parseCues(cursor, element)

            case ClusterId:
                fail InvalidFormatError{"Matroska metadata is not indexed before media data"}
            }

            cursor.seek(element.end)
        }

        if !hasTracks do
            fail InvalidFormatError{"Matroska segment has no track metadata"}
        if .selectedVideo == NoTrack do
            .selectTracks()
    }

    // Extends the block index by complete clusters until `sampleCount` pictures are available.
    mtd indexUntil(bytes: const [..] u8, sampleCount: u64, cancelled: #null *u32 = null, paused: #null *u32 = null)->bool fail
    {
        if .indexComplete do
            return true

        var cursor = Cursor.open(bytes)
        cursor.seek(.scanPosition)
        while cursor.position < .segment.end and .tracks[.selectedVideo].videoSamples.count < sampleCount
        {
            while paused and Atomic.get(paused!)
            {
                if cancelled and Atomic.get(cancelled!) do
                    return false
                Threading.Thread.sleep(1'ms)
            }
            if cancelled and Atomic.get(cancelled!) do
                return false
            let element = cursor.readElement(.segment.end)
            if element.id == ClusterId and !.parseCluster(&cursor, element, cancelled, paused) do
                return false
            .scanPosition = element.end
            cursor.seek(element.end)
        }

        if .scanPosition >= .segment.end
        {
            .indexComplete = true
            if .indexPictures and !.tracks[.selectedVideo].videoSamples.count do
                fail InvalidFormatError{"Matroska video track has no blocks"}
        }

        return true
    }

    mtd const hasAudioThrough(timestampNanoseconds: s64)->bool
    {
        if !.audioTracks.count do
            return false
        for trackIndex in .audioTracks
        {
            let track = &.tracks[trackIndex]
            if !track.hasAudioStart or !track.audioFrameCount do
                return false
            let duration = cast(f64) track.audioFrameCount * 1_000_000_000.0 / track.sampleRate
            if cast(f64) track.audioStart + duration <= cast(f64) timestampNanoseconds do
                return false
        }

        return true
    }

    // Extends an audio-only window until every playable track reaches the requested timestamp.
    mtd indexAudioThrough(bytes: const [..] u8, timestampNanoseconds: s64, cancelled: #null *u32 = null, paused: #null *u32 = null)->bool fail
    {
        if .indexComplete or .hasAudioThrough(timestampNanoseconds) do
            return true

        var cursor = Cursor.open(bytes)
        cursor.seek(.scanPosition)
        while cursor.position < .segment.end and !.hasAudioThrough(timestampNanoseconds)
        {
            while paused and Atomic.get(paused!)
            {
                if cancelled and Atomic.get(cancelled!) do
                    return false
                Threading.Thread.sleep(1'ms)
            }
            if cancelled and Atomic.get(cancelled!) do
                return false
            let element = cursor.readElement(.segment.end)
            if element.id == ClusterId and !.parseCluster(&cursor, element, cancelled, paused) do
                return false
            .scanPosition = element.end
            cursor.seek(element.end)
        }

        if .scanPosition >= .segment.end do
            .indexComplete = true
        return true
    }

    // Keeps the requested picture plus one complete following cluster indexed.
    //
    // The following cluster is the H.264 reorder queue: pictures stored just beyond a cluster
    // boundary may still be presented before its tail. Its size comes from the container rather
    // than from a time or frame-count heuristic.
    mtd indexWindow(bytes: const [..] u8, sampleIndex: u64, cancelled: #null *u32 = null)->bool fail
    {
        if .tracks[.selectedVideo].videoSamples.count <= sampleIndex
        {
            if sampleIndex == Swag.U64.Max do
                fail OverflowError{"Matroska frame index exceeds the supported range"}
            if !.indexUntil(bytes, sampleIndex + 1, cancelled) do
                return false
        }

        while !.indexComplete
        {
            var followingClusters = 0'u32
            for chunkEnd in .videoChunkEnds where chunkEnd > sampleIndex do
                followingClusters += 1
            if followingClusters >= 2 do
                break

            let count = .tracks[.selectedVideo].videoSamples.count
            if count == Swag.U64.Max do
                fail OverflowError{"Matroska video sample table is too large"}
            if !.indexUntil(bytes, count + 1, cancelled) do
                return false
        }

        return true
    }

    // Discards packet locations from the old playback window and resumes at a cue cluster.
    mtd resetMediaAt(clusterOffset: u64) fail
    {
        if clusterOffset < .segment.data or clusterOffset >= .segment.end do
            fail InvalidFormatError{"Matroska cue position exceeds the segment"}
        for &track in .tracks
        {
            track.videoSamples.clear()
            track.audioPackets.clear()
            track.audioFrameCount = 0
            track.audioStart      = 0
            track.hasAudioStart   = false
        }

        .videoChunkEnds.clear()
        .scanPosition  = clusterOffset
        .indexComplete = false
    }

    // Finds the last cue not later than `timestampNanoseconds`.
    mtd const cueAtOrBefore(timestampNanoseconds: u64)->#null const *CueEntry
    {
        if !.cues.count do
            return null
        let timestamp = timestampNanoseconds / .timestampScale
        var low       = 0'u64
        var high      = .cues.count
        while low + 1 < high
        {
            let middle = low + (high - low) / 2
            if .cues[middle].timestamp <= timestamp do
                low = middle
            else do
                high = middle
        }

        return .cues[low].timestamp <= timestamp ? &.cues[low] : null
    }

    // Finds the first random-access point not earlier than `timestampNanoseconds`.
    mtd const cueAtOrAfter(timestampNanoseconds: u64)->#null const *CueEntry
    {
        if !.cues.count do
            return null
        var timestamp = timestampNanoseconds / .timestampScale
        if timestampNanoseconds % .timestampScale do
            timestamp += 1

        var low  = 0'u64
        var high = .cues.count
        while low < high
        {
            let middle = low + (high - low) / 2
            if .cues[middle].timestamp < timestamp do
                low = middle + 1
            else do
                high = middle
        }

        return low < .cues.count ? &.cues[low] : null
    }

    // Returns the end of the complete cluster containing `sampleCount` pictures.
    mtd const videoWindowEnd(sampleCount: u64)->u64
    {
        for count in .videoChunkEnds where count >= sampleCount do
            return count
        return .tracks[.selectedVideo].videoSamples.count
    }

    mtd openContainer(bytes: const [..] u8)->Container fail
    {
        var result: retval = {Cursor.open(bytes), {}}
        if !@countof(bytes) do
            fail InvalidFormatError{"Matroska stream is empty"}

        let header = result.cursor.readElement(@countof(bytes))
        if header.id != EbmlId do
            fail InvalidFormatError{"Matroska stream has no EBML header"}
        .parseHeader(&result.cursor, header)
        result.cursor.seek(header.end)

        var hasSegment: bool
        while result.cursor.position < @countof(bytes)
        {
            let element = result.cursor.readElement(@countof(bytes))
            if element.id == SegmentId
            {
                result.segment = element
                hasSegment     = true
                break
            }

            result.cursor.seek(element.end)
        }

        if !hasSegment do
            fail InvalidFormatError{"Matroska stream has no segment"}
        return result
    }

    mtd parseSeekHead(cursor: *Cursor, seekHead, segment: Element)->MetadataTargets fail
    {
        var result: retval
        cursor.seek(seekHead.data)
        while cursor.position < seekHead.end
        {
            let element = cursor.readElement(seekHead.end)
            if element.id == SeekId
            {
                var targetId, relative:     u64
                var hasTarget, hasPosition: bool
                cursor.seek(element.data)
                while cursor.position < element.end
                {
                    let field = cursor.readElement(element.end)
                    switch field.id
                    {
                    case SeekTargetId:
                        targetId  = cursor.readUnsigned(field)
                        hasTarget = true

                    case SeekPositionId:
                        relative    = cursor.readUnsigned(field)
                        hasPosition = true
                    }

                    cursor.seek(field.end)
                }

                if hasTarget and hasPosition
                {
                    if relative > segment.end - segment.data do
                        fail InvalidFormatError{"Matroska seek position exceeds the segment"}
                    let absolute = segment.data + relative
                    if targetId == InfoId do
                        result.info = absolute
                    elif targetId == TracksId do
                        result.tracks = absolute
                    elif targetId == CuesId do
                        result.cues = absolute
                }
            }

            cursor.seek(element.end)
        }

        return result
    }

    mtd parseMetadataElement(cursor: *Cursor, offset: u64, expectedId: u32, segment: Element) fail
    {
        cursor.seek(offset)
        let element = cursor.readElement(segment.end)
        if element.id != expectedId do
            fail InvalidFormatError{"Matroska seek entry points to the wrong element"}
        if expectedId == InfoId do
            .parseInfo(cursor, element)
        elif expectedId == TracksId do
            .parseTracks(cursor, element)
        else do
            .parseCues(cursor, element)
    }

    mtd parseHeader(cursor: *Cursor, header: Element) fail
    {
        var docType: String
        cursor.seek(header.data)
        while cursor.position < header.end
        {
            let element = cursor.readElement(header.end)
            if element.id == DocTypeId do
                docType = cursor.readString(element)
            cursor.seek(element.end)
        }

        if docType != "matroska" and docType != "webm" do
            fail InvalidFormatError{"EBML document type is not Matroska or WebM"}
    }

    // Records clusters in the first pass so tracks may legally follow media data.
    mtd parseSegment(cursor: *Cursor, segment: Element, cancelled: #null *u32 = null)->bool fail
    {
        cursor.seek(segment.data)
        while cursor.position < segment.end
        {
            if cancelled and Atomic.get(cancelled!) do
                return false
            let element = cursor.readElement(segment.end)
            switch element.id
            {
            case InfoId:
                .parseInfo(cursor, element)

            case TracksId:
                .parseTracks(cursor, element)
                .selectTracks()

            case ClusterId:
                .clusters.add(element)
            }

            cursor.seek(element.end)
        }

        if .selectedVideo == NoTrack do
            .selectTracks()
        return true
    }

    mtd parseInfo(cursor: *Cursor, info: Element) fail
    {
        cursor.seek(info.data)
        while cursor.position < info.end
        {
            let element = cursor.readElement(info.end)
            switch element.id
            {
            case TimestampScaleId: .timestampScale = cursor.readUnsigned(element)
            case DurationId:       .durationTicks = cursor.readFloat(element)
            }

            cursor.seek(element.end)
        }

        if !.timestampScale or .timestampScale > cast(u64) Swag.S64.Max do
            fail InvalidFormatError{"Matroska timestamp scale exceeds the supported range"}
        if !Math.isFinite(.durationTicks) or .durationTicks < 0 do
            fail InvalidFormatError{"Matroska duration is not finite and non-negative"}
    }

    mtd parseTracks(cursor: *Cursor, tracks: Element) fail
    {
        cursor.seek(tracks.data)
        while cursor.position < tracks.end
        {
            let element = cursor.readElement(tracks.end)
            if element.id == TrackEntryId
            {
                var track: Track
                .parseTrack(cursor, element, &track)
                for existing in .tracks where existing.number == track.number do
                    fail InvalidFormatError{"Matroska track number is already declared"}
                .tracks.add(#move track)
            }

            cursor.seek(element.end)
        }
    }

    // Reads only cue timestamps and cluster offsets for the selected picture track.
    mtd parseCues(cursor: *Cursor, cues: Element) fail
    {
        cursor.seek(cues.data)
        while cursor.position < cues.end
        {
            let element = cursor.readElement(cues.end)
            if element.id == CuePointId do
                .parseCuePoint(cursor, element)
            cursor.seek(element.end)
        }
    }

    mtd parseCuePoint(cursor: *Cursor, point: Element) fail
    {
        var timestamp:    u64
        var hasTimestamp: bool
        var clusterOffset = NoOffset
        cursor.seek(point.data)
        while cursor.position < point.end
        {
            let element = cursor.readElement(point.end)
            switch element.id
            {
            case CueTimeId:
                timestamp    = cursor.readUnsigned(element)
                hasTimestamp = true

            case CueTrackPositionsId:
                let offset = .parseCueTrackPosition(cursor, element)
                if offset != NoOffset do
                    clusterOffset = offset
            }

            cursor.seek(element.end)
        }

        if !hasTimestamp or clusterOffset == NoOffset do
            return
        if .cues.count and timestamp < .cues[.cues.count - 1].timestamp do
            fail InvalidFormatError{"Matroska cue timestamps are not ordered"}
        .cues.add({timestamp, clusterOffset})
    }

    mtd parseCueTrackPosition(cursor: *Cursor, position: Element)->u64 fail
    {
        var track, relative:       u64
        var hasTrack, hasPosition: bool
        cursor.seek(position.data)
        while cursor.position < position.end
        {
            let element = cursor.readElement(position.end)
            switch element.id
            {
            case CueTrackId:
                track    = cursor.readUnsigned(element)
                hasTrack = true

            case CueClusterPositionId:
                relative    = cursor.readUnsigned(element)
                hasPosition = true
            }

            cursor.seek(element.end)
        }

        if !hasTrack or !hasPosition or track != .tracks[.selectedVideo].number do
            return NoOffset
        if relative > .segment.end - .segment.data do
            fail InvalidFormatError{"Matroska cue position exceeds the segment"}
        return .segment.data + relative
    }

    mtd parseTrack(cursor: *Cursor, entry: Element, track: *Track) fail
    {
        cursor.seek(entry.data)
        while cursor.position < entry.end
        {
            let element = cursor.readElement(entry.end)
            switch element.id
            {
            case TrackNumberId:      track.number = cursor.readUnsigned(element)
            case TrackTypeId:        track.kind = cursor.readUnsigned(element)
            case FlagEnabledId:      track.isEnabled = cursor.readUnsigned(element) != 0
            case FlagDefaultId:      track.isDefault = cursor.readUnsigned(element) != 0
            case DefaultDurationId:  track.defaultDuration = cursor.readUnsigned(element)
            case NameId:             track.name = cursor.readString(element)
            case LanguageId:         track.language = cursor.readString(element)
            case CodecIdId:          track.codecId = cursor.readString(element)
            case CodecPrivateId:     track.codecPrivate = cursor.readBytes(element)
            case CodecDelayId:       track.codecDelay = cursor.readUnsigned(element)
            case SeekPreRollId:      track.seekPreRoll = cursor.readUnsigned(element)
            case ContentEncodingsId: track.hasEncodings = true
            case VideoId:            .parseVideo(cursor, element, track)
            case AudioId:            .parseAudio(cursor, element, track)
            }

            cursor.seek(element.end)
        }

        if !track.number do
            fail InvalidFormatError{"Matroska track has no positive track number"}
        if track.codecId.isEmpty() do
            fail InvalidFormatError{"Matroska track has no codec identifier"}
    }

    mtd parseVideo(cursor: *Cursor, video: Element, track: *Track) fail
    {
        cursor.seek(video.data)
        while cursor.position < video.end
        {
            let element = cursor.readElement(video.end)
            switch element.id
            {
            case PixelWidthId:
                let width = cursor.readUnsigned(element)
                if width > cast(u64) Swag.S32.Max do
                    fail InvalidFormatError{"Matroska video width exceeds the supported range"}
                track.width = cast(s32) width

            case PixelHeightId:
                let height = cursor.readUnsigned(element)
                if height > cast(u64) Swag.S32.Max do
                    fail InvalidFormatError{"Matroska video height exceeds the supported range"}
                track.height = cast(s32) height
            }

            cursor.seek(element.end)
        }
    }

    mtd parseAudio(cursor: *Cursor, audio: Element, track: *Track) fail
    {
        cursor.seek(audio.data)
        while cursor.position < audio.end
        {
            let element = cursor.readElement(audio.end)
            switch element.id
            {
            case SamplingFrequencyId, OutputSamplingFreqId:
                track.sampleRate = cursor.readFloat(element)

            case ChannelsId:
                let channels = cursor.readUnsigned(element)
                if channels > Swag.U32.Max do
                    fail InvalidFormatError{"Matroska audio channel count exceeds the supported range"}
                track.channels = cast(u32) channels

            case BitDepthId:
                let bits = cursor.readUnsigned(element)
                if bits > Swag.U32.Max do
                    fail InvalidFormatError{"Matroska audio bit depth exceeds the supported range"}
                track.bitsPerSample = cast(u32) bits
            }

            cursor.seek(element.end)
        }
    }

    // Chooses one default H.264 picture track and every playable sound track.
    mtd selectTracks() fail
    {
        var firstVideoCodec: String
        for track, index in .tracks where track.kind == VideoTrackType and track.isEnabled
        {
            if firstVideoCodec.isEmpty() do
                firstVideoCodec = String.from(track.codecId.toString())
            if !track.isPlayableVideo() do
                continue
            if .selectedVideo == NoTrack or (track.isDefault and !.tracks[.selectedVideo].isDefault) do
                .selectedVideo = index
        }

        if .selectedVideo == NoTrack
        {
            if !firstVideoCodec.isEmpty() do
                fail UnsupportedFormatError{Errors.mkString(Format.toString("video decoder does not support Matroska codec '%'", firstVideoCodec.toString()))}
            fail InvalidFormatError{"Matroska segment has no enabled video track"}
        }

        // Put the default track first so existing callers keep a useful zero index.
        for wantDefault in [true, false]
        {
            for track, index in .tracks where track.isPlayableAudio() and track.isDefault == wantDefault do
                .audioTracks.add(index)
        }
    }

    // Indexes a cluster in one forward pass.
    //
    // Muxers normally put Timestamp before the first block, so packets are indexed as their
    // headers are encountered. Matroska does not require that order: blocks seen first are kept
    // as tiny element descriptors until Timestamp arrives. This avoids the old full preliminary
    // pass over every block header and the repeated cursor jumps it imposed on a mapped file.
    mtd parseCluster(cursor: *Cursor, cluster: Element, cancelled: #null *u32 = null, paused: #null *u32 = null)->bool fail
    {
        let firstVideoSample = .tracks[.selectedVideo].videoSamples.count
        var clusterTimestamp = 0'u64
        var hasTimestamp:       bool
        var pending:            Array'Element
        cursor.seek(cluster.data)
        while cursor.position < cluster.end
        {
            while paused and Atomic.get(paused!)
            {
                if cancelled and Atomic.get(cancelled!) do
                    return false
                Threading.Thread.sleep(1'ms)
            }
            if cancelled and Atomic.get(cancelled!) do
                return false
            let element = cursor.readElement(cluster.end)
            if element.id == ClusterTimestampId
            {
                clusterTimestamp = cursor.readUnsigned(element)
                hasTimestamp     = true
                for queued in pending
                {
                    if cancelled and Atomic.get(cancelled!) do
                        return false
                    if queued.id == SimpleBlockId do
                        .indexBlock(cursor, queued, clusterTimestamp, true)
                    else do
                        .parseBlockGroup(cursor, queued, clusterTimestamp)
                }
                pending.clear()
            }
            elif element.id == SimpleBlockId or element.id == BlockGroupId
            {
                if !hasTimestamp do
                    pending.add(element)
                elif element.id == SimpleBlockId do
                    .indexBlock(cursor, element, clusterTimestamp, true)
                else do
                    .parseBlockGroup(cursor, element, clusterTimestamp)
            }

            cursor.seek(element.end)
        }

        // Preserve the existing zero-timestamp interpretation for a cluster that omits the
        // schema's mandatory Timestamp element.
        for queued in pending
        {
            if cancelled and Atomic.get(cancelled!) do
                return false
            if queued.id == SimpleBlockId do
                .indexBlock(cursor, queued, clusterTimestamp, true)
            else do
                .parseBlockGroup(cursor, queued, clusterTimestamp)
        }

        let videoSampleCount = .tracks[.selectedVideo].videoSamples.count
        if videoSampleCount > firstVideoSample do
            .videoChunkEnds.add(videoSampleCount)
        return true
    }

    mtd parseBlockGroup(cursor: *Cursor, group: Element, clusterTimestamp: u64) fail
    {
        var block: Element
        var hasBlock, hasReference: bool
        cursor.seek(group.data)
        while cursor.position < group.end
        {
            let element = cursor.readElement(group.end)
            switch element.id
            {
            case BlockId:
                block    = element
                hasBlock = true

            case ReferenceBlockId:
                hasReference = true
            }

            cursor.seek(element.end)
        }

        if hasBlock do
            .indexBlock(cursor, block, clusterTimestamp, !hasReference)
    }

    // Converts a cluster-relative timestamp to signed nanoseconds with overflow checks.
    mtd timestampNanoseconds(clusterTimestamp: u64, relative: s16)->s64 fail
    {
        if clusterTimestamp > cast(u64) Swag.S64.Max do
            fail InvalidFormatError{"Matroska cluster timestamp exceeds the supported range"}
        let clusterTicks = cast(s64) clusterTimestamp
        if relative > 0 and clusterTicks > Swag.S64.Max - relative do
            fail InvalidFormatError{"Matroska block timestamp exceeds the supported range"}
        let ticks = clusterTicks + relative
        if ticks > 0 and ticks > Swag.S64.Max / cast(s64) .timestampScale do
            fail InvalidFormatError{"Matroska block timestamp exceeds the supported range"}
        if ticks < 0 and ticks < Swag.S64.Min / cast(s64) .timestampScale do
            fail InvalidFormatError{"Matroska block timestamp exceeds the supported range"}
        return ticks * cast(s64) .timestampScale
    }

    // Reads the lacing header and retains one byte size per payload.
    mtd parseLaces(cursor: *Cursor, end: u64, mode: u8)->u64 fail
    {
        .laceSizes.clear()
        if mode == 0
        {
            if cursor.position >= end do
                fail InvalidFormatError{"Matroska block has no payload"}
            .laceSizes.add(end - cursor.position)
            return cursor.position
        }

        let count = cast(u32) cursor.readByte(end) + 1
        if count < 2 do
            fail InvalidFormatError{"Matroska lacing needs at least two payloads"}
        switch mode
        {
        case 1:
            var known = 0'u64
            for count - 1
            {
                var size = 0'u64
                while true
                {
                    let part = cursor.readByte(end)
                    size += part
                    if part != 255 do
                        break
                }

                .laceSizes.add(size)
                if known > Swag.U64.Max - size do
                    fail InvalidFormatError{"Matroska Xiph lace size exceeds the supported range"}
                known += size
            }

            if known >= end - cursor.position do
                fail InvalidFormatError{"Matroska Xiph lacing exceeds its block payload"}
            .laceSizes.add(end - cursor.position - known)

        case 2:
            let remaining = end - cursor.position
            if remaining % count do
                fail InvalidFormatError{"Matroska fixed lacing does not divide its block payload"}
            let size = remaining / count
            if !size do
                fail InvalidFormatError{"Matroska fixed lace has no payload"}
            for count do
                .laceSizes.add(size)

        case 3:
            let first = cursor.readVintValue(end)
            if !first.value do
                fail InvalidFormatError{"Matroska EBML lace has no payload"}
            .laceSizes.add(first.value)
            var known    = first.value
            var previous = cast(s64) first.value
            for 1 until count - 1
            {
                let delta = cursor.readSignedVint(end)
                if (delta > 0 and previous > Swag.S64.Max - delta) or (delta < 0 and previous < Swag.S64.Min - delta) do
                    fail InvalidFormatError{"Matroska EBML lace size exceeds the supported range"}
                let size = previous + delta
                if size <= 0 do
                    fail InvalidFormatError{"Matroska EBML lace has no payload"}
                .laceSizes.add(cast(u64) size)
                let unsignedSize = cast(u64) size
                if known > Swag.U64.Max - unsignedSize do
                    fail InvalidFormatError{"Matroska EBML lace size exceeds the supported range"}
                known    += unsignedSize
                previous = size
            }

            if known >= end - cursor.position do
                fail InvalidFormatError{"Matroska EBML lacing exceeds its block payload"}
            .laceSizes.add(end - cursor.position - known)

        default:
            fail InvalidFormatError{"Matroska block uses an unknown lacing mode"}
        }

        return cursor.position
    }

    // Indexes one block belonging to the selected picture or sound tracks.
    mtd indexBlock(cursor: *Cursor, block: Element, clusterTimestamp: u64, keyFromContainer: bool) fail
    {
        cursor.seek(block.data)
        let trackNumber = cursor.readVintValue(block.end).value
        if block.end - cursor.position < 3 do
            fail InvalidFormatError{"Matroska block header is truncated"}
        let timeBits = (cast(u16) cursor.readByte(block.end) << 8) | cursor.readByte(block.end)
        let relative = cast #bit (s16) timeBits
        let flags    = cursor.readByte(block.end)

        var trackIndex = NoTrack
        var isVideo: bool
        if .tracks[.selectedVideo].number == trackNumber
        {
            trackIndex = .selectedVideo
            isVideo    = true
        }
        else
        {
            for index in .audioTracks where .tracks[index].number == trackNumber
            {
                trackIndex = index
                break
            }
        }

        if trackIndex == NoTrack do
            return
        if isVideo and !.indexPictures do
            return

        let lacing = (flags >> 1) & 3
        if isVideo and lacing do
            fail UnsupportedFormatError{"video decoder does not support laced Matroska picture blocks"}
        if isVideo and flags & 0x08 do
            fail UnsupportedFormatError{"video decoder does not support invisible Matroska pictures"}

        let payload = .parseLaces(cursor, block.end, lacing)
        let track   = &.tracks[trackIndex]
        if isVideo
        {
            let timestamp = .timestampNanoseconds(clusterTimestamp, relative)
            let isSync    = keyFromContainer and (block.id != SimpleBlockId or flags & 0x80 != 0)
            track.videoSamples.add({payload, .laceSizes[0], timestamp, isSync})
            if track.videoSamples.count == 1 and track.needsInlineSetup()
            {
                let end = Math.min(payload + .laceSizes[0], @countof(cursor.bytes))
                track.setup.add(Video.inlineSetupHeaders(cursor.bytes[payload until end]))
            }
            return
        }

        let timestamp = .timestampNanoseconds(clusterTimestamp, relative)
        if !track.hasAudioStart
        {
            track.audioStart    = timestamp
            track.hasAudioStart = true
        }

        var offset = payload
        for size in .laceSizes
        {
            if size > Swag.U32.Max do
                fail InvalidFormatError{"Matroska audio packet exceeds the supported size"}
            let frameCount = .audioPacketFrames(cursor.bytes, offset, size, track.soundEncoding())
            track.audioPackets.add({offset, cast(u32) size, frameCount})
            if track.audioFrameCount > Swag.U64.Max - frameCount do
                fail OverflowError{"Matroska audio packet table is too large"}
            track.audioFrameCount += frameCount
            offset += size
        }
    }

    mtd const audioPacketFrames(bytes: const [..] u8, offset, size: u64, encoding: SoundFileEncoding)->u32 fail
    {
        if offset > @countof(bytes) or size > @countof(bytes) - offset do
            fail InvalidFormatError{"Matroska audio packet is truncated"}
        return try Audio.packetFrameCount(encoding, bytes[offset until offset + size])
    }
}

// Reduces a nanosecond frame duration into the public 32-bit rate representation.
private func frameRateFromDuration(durationNanoseconds: u64)->FrameRate fail
{
    if !durationNanoseconds do
        fail InvalidFormatError{"Matroska video track has no frame duration"}
    var numerator   = 1_000_000_000'u64
    var denominator = durationNanoseconds
    var a           = numerator
    var b           = denominator
    while b
    {
        let remainder = a % b
        a = b
        b = remainder
    }

    numerator   /= a
    denominator /= a
    if numerator <= Swag.U32.Max and denominator <= Swag.U32.Max do
        return FrameRate.create(cast(u32) numerator, cast(u32) denominator)

    // Sub-quarter-frame-per-second media is represented at whole-second precision.
    return FrameRate.create(1, cast(u32) Math.min(Math.max(durationNanoseconds / 1_000_000_000, 1), cast(u64) Swag.U32.Max))
}

private const SoundIndexIdle = 0'u32
private const SoundIndexRunning = 1'u32
private const SoundIndexReady = 2'u32
private const SoundIndexFailed = 3'u32
private const SoundSeekRunAheadNanoseconds = 10_000_000_000's64
private const SoundSeekPreRollNanoseconds = 1_000_000_000'u64
private const SoundSeekPreRollSeconds = 1.0

#[Swag.NoCopy]
private struct PublishedSound
{
    tracks: Array'SoundFile
}

#[Swag.NoCopy]
private struct FileIndex
{
    progressive:        #null *Layout
    region:             File.MappedRegion
    path:               String
    soundTracks:         Array'SoundFile
    soundThread:         Threading.Thread
    seekSounds:          Array'*PublishedSound
    soundLock:           Sync.Mutex
    cancel:              u32
    soundPause:          u32
    soundStatus:         u32
    soundStage:          u32
    currentSeekSound:    u64
}

private func publishFullSound(index: *FileIndex, tracks: *Array'SoundFile)
{
    Sync.scopedLock(&index.soundLock)
    index.soundTracks = #move tracks[]
    Atomic.exchange(&index.soundStage, 1)
    if !Atomic.get(&index.soundPause) do
        Atomic.exchange(&index.currentSeekSound, 0)
}

private func publishSeekSound(index: *FileIndex, tracks: *Array'SoundFile)
{
    let published = Memory.new'PublishedSound()
    published.tracks = #move tracks[]

    Sync.scopedLock(&index.soundLock)
    index.seekSounds.add(published)
    Atomic.exchange(&index.currentSeekSound, cast(u64) published)
}

private impl FileIndex
{
    mtd opDrop()
    {
        Atomic.exchange(&.cancel, 1)
        if .soundThread.isValid() do
            .soundThread.wait()
        for sound in .seekSounds do
            Memory.delete(sound)
        if .progressive do
            Memory.delete(.progressive!)
    }
}

private func buildSoundTracks(path: string, bytes: const [..] u8, layout: *Layout, result: *Array'SoundFile) fail
{
    result.reserve(layout.audioTracks.count)
    for trackIndex in layout.audioTracks
    {
        let track = &layout.tracks[trackIndex]
        if !track.audioPackets.count do
            continue
        let timelineStart = Math.max(cast(f64) track.audioStart / 1_000_000_000.0, 0)
        let leadingTrim   = timelineStart == 0 ? try track.leadingTrimFrames() : 0
        let options       = PacketStreamOptions{leadingTrimFrames: leadingTrim, speakerMask: try track.speakerMask(bytes), timelineStartSeconds: timelineStart, displayName: track.name.toString(), language: track.language.toString()}
        let sound         = SoundFile.openPacketStream(path, track.soundEncoding(), cast(u32) Math.round(track.sampleRate), track.channels, track.audioFrameCount, track.audioPackets.toSlice(), track.codecPrivate.toSlice(), options)
        result.add(#move sound)
    }
}

// Publishes a bounded packet window around one media-timeline position.
private func buildSoundWindow(index: *FileIndex, timestampNanoseconds: u64) fail
{
    var layout: Layout
    let bytes = index.region.bytes()
    layout.parseMetadata(bytes)
    layout.indexPictures = false

    let cueTimestamp = timestampNanoseconds > SoundSeekPreRollNanoseconds ? timestampNanoseconds - SoundSeekPreRollNanoseconds : 0
    let cue          = layout.cueAtOrBefore(cueTimestamp)
    try layout.resetMediaAt(cue ? cue!.clusterOffset : layout.segment.data)

    var requestedEnd: s64
    if timestampNanoseconds
    {
        requestedEnd = timestampNanoseconds > cast(u64) Swag.S64.Max - cast(u64) SoundSeekRunAheadNanoseconds ? Swag.S64.Max : cast(s64) timestampNanoseconds + SoundSeekRunAheadNanoseconds
    }
    if !layout.indexAudioThrough(bytes, requestedEnd, &index.cancel) do
        fail BadParameterError{"video reader operation was cancelled"}

    var tracks: Array'SoundFile
    try buildSoundTracks(index.path.toString(), bytes, &layout, &tracks)
    if tracks.count != layout.audioTracks.count do
        fail InvalidFormatError{"Matroska audio window has no packets"}
    let seconds = cast(f64) timestampNanoseconds / 1_000_000_000.0
    for sound in tracks
    {
        let local = seconds - sound.timelineStartSeconds()
        if local < -SoundSeekPreRollSeconds or local >= sound.durationInSeconds() do
            fail InvalidFormatError{"Matroska audio window does not cover its requested timestamp"}
    }

    publishSeekSound(index, &tracks)
}

// Builds complete packet tables while the opening and seek windows remain playable.
private func buildSoundIndex(index: *FileIndex) fail
{
    var layout: Layout
    let bytes = index.region.bytes()
    layout.parseMetadata(bytes)
    layout.indexPictures = false
    if !layout.indexUntil(bytes, 1, &index.cancel, &index.soundPause) do
        fail BadParameterError{"video reader operation was cancelled"}
    var tracks: Array'SoundFile
    try buildSoundTracks(index.path.toString(), bytes, &layout, &tracks)
    publishFullSound(index, &tracks)
}

// Reads Matroska files carrying H.264 pictures and supported AAC-LC, AC-3, or E-AC-3 tracks.
//
// Opening reads seek, track, and cue metadata plus the first audio-bearing cluster. Decoding
// advances one demux cursor through complete clusters on demand; random access restarts that
// cursor at a cue cluster and publishes a bounded sound window around the target. A low-priority
// scanner still builds complete sound packet tables in the background. Compressed payloads remain
// in the file throughout.
struct Decoder
{
    internal
    {
        info:               StreamInfo
        video:              PictureStream
        fileIndex:          #null *FileIndex
        presentationOrigin: s64
        durationSeconds:    f64
        streamSampleCount:  u64
        windowBaseRank:     u64
        streamOpen:         bool
        memoryComplete:     bool
        resumeSoundIndexAfterDecode: bool
    }
}

private impl Decoder
{
    mtd configureMetadata(layout: *Layout) fail
    {
        var video = &layout.tracks[layout.selectedVideo]
        if video.needsInlineSetup() and !video.setup.count
        {
            // A track that carries its layer in the stream needs one sample read before it can
            // answer anything about itself.
            discard layout.indexUntil(.fileIndex!.region.bytes(), 1)
            video = &layout.tracks[layout.selectedVideo]
        }

        if video.pictureKind() == PictureMpeg4
        {
            // The setup headers state the geometry outright.
            var probe: Mpeg4.Decoder
            try probe.configure(video.videoConfiguration())
            .info.width  = cast(s32) probe.layer.width
            .info.height = cast(s32) probe.layer.height
        }
        elif video.isHevcVideo()
        {
            // The stream answers its own geometry, so the parameter sets are read once here and
            // once more when the sample table exists.
            var probe: Hevc.HevcStream
            var empty: Array'SampleEntry
            empty.add({0, 0, 0, true})
            try probe.open(video.codecPrivate.toSlice(), #move empty)
            .info.width  = probe.width
            .info.height = probe.height
        }
        else
        {
            var probe: H264.Decoder
            probe.configure(video.codecPrivate.toSlice())
            let sps = probe.firstSps()
            if !sps do
                fail InvalidFormatError{"H.264 decoder configuration has no sequence parameter set"}
            .info.width  = sps!.width()
            .info.height = sps!.height()
        }
        if video.defaultDuration do
            .info.frameRate = frameRateFromDuration(video.defaultDuration)
        if layout.durationTicks > 0 do
            .durationSeconds = layout.durationTicks * cast(f64) layout.timestampScale / 1_000_000_000.0
    }

    mtd openMemory(layout: *Layout) fail
    {
        let video = &layout.tracks[layout.selectedVideo]
        if video.videoSamples.count > Swag.U32.Max do
            fail OverflowError{"Matroska video sample table is too large"}
        .info.frameCount = video.videoSamples.count
        try .video.open(video.pictureKind(), video.videoConfiguration(), video.videoSamples.toSlice())
        .streamOpen         = true
        .streamSampleCount  = .info.frameCount
        .presentationOrigin = .video.presentationTimeAtRank(0)
        let lastTimestamp = .video.presentationTimeAtRank(.info.frameCount - 1)
        let timestampSpan = cast(u64) (lastTimestamp - .presentationOrigin)
        var frameDuration = video.defaultDuration
        if !frameDuration and .info.frameCount > 1 do
            frameDuration = Math.max(timestampSpan / (.info.frameCount - 1), 1)
        .info.frameRate  = frameRateFromDuration(frameDuration)
        .durationSeconds = cast(f64) .info.frameCount * cast(f64) .info.frameRate.denominator() / cast(f64) .info.frameRate.numerator()
        .memoryComplete  = true
    }

    mtd appendAvailableFrames(track: const *Track) fail
    {
        let samples = track.videoSamples.toSlice()
        if @countof(samples) <= .streamSampleCount do
            return
        let added = samples[.streamSampleCount until @countof(samples)]
        if !.streamOpen
        {
            try .video.open(track.pictureKind(), track.videoConfiguration(), added)
            .streamOpen         = true
            .presentationOrigin = .video.presentationTimeAtRank(0)
        }
        else do
            try .video.appendFrames(added)
        .streamSampleCount = @countof(samples)
    }

    mtd replaceAvailableFrames(track: const *Track) fail
    {
        let samples = track.videoSamples.toSlice()
        if !.streamOpen
        {
            try .video.open(track.pictureKind(), track.videoConfiguration(), samples)
            .streamOpen = true
        }
        else do
            try .video.replaceFrames(samples)
        .streamSampleCount = @countof(samples)
    }

    mtd targetTimestamp(index: u64)->s64
    {
        let rate = .currentFrameRate()
        if !rate.isValid() do
            return .presentationOrigin
        let offset = cast(f64) index * cast(f64) rate.denominator() * 1_000_000_000.0 / cast(f64) rate.numerator()
        if offset >= cast(f64) Swag.S64.Max - cast(f64) .presentationOrigin do
            return Swag.S64.Max
        return .presentationOrigin + cast(s64) Math.round(offset)
    }

    mtd startSoundIndex() fail
    {
        let fileIndex = .fileIndex
        if !fileIndex or Atomic.get(&fileIndex!.soundStatus) != SoundIndexIdle do
            return
        if !fileIndex!.progressive!.audioTracks.count
        {
            Atomic.exchange(&fileIndex!.soundStatus, SoundIndexReady)
            return
        }

        Atomic.exchange(&fileIndex!.soundStatus, SoundIndexRunning)
        fileIndex!.soundThread.init(&runMatroskaSoundIndex, fileIndex!, priority: .BelowNormal)
        fileIndex!.soundThread.start()
    }

    // Restarts the single demux cursor on the key cluster advertised by Cues.
    mtd seekWindow(index: u64) fail
    {
        let fileIndex = .fileIndex!
        Atomic.exchange(&fileIndex.soundPause, 1)
        .resumeSoundIndexAfterDecode = true
        let layout    = fileIndex.progressive!
        let bytes     = fileIndex.region.bytes()
        let target    = .targetTimestamp(index)
        if target >= 0 do
            discard catch buildSoundWindow(fileIndex, cast(u64) target) as soundWindowError
        let cue       = target >= 0 ? layout.cueAtOrBefore(cast(u64) target) : null
        if cue do
            layout.resetMediaAt(cue!.clusterOffset)
        else do
            layout.resetMediaAt(layout.segment.data)

        var reachedTarget: bool
        while !layout.indexComplete and !reachedTarget
        {
            let video = &layout.tracks[layout.selectedVideo]
            let count = video.videoSamples.count
            if count == Swag.U64.Max do
                fail OverflowError{"Matroska video sample table is too large"}
            if !layout.indexUntil(bytes, count + 1, &fileIndex.cancel) do
                fail BadParameterError{"video reader operation was cancelled"}
            for sample in video.videoSamples where sample.presentationTime >= target
            {
                reachedTarget = true
                break
            }
        }

        let video = &layout.tracks[layout.selectedVideo]
        if !video.videoSamples.count do
            fail BadParameterError{"Matroska frame index exceeds the stream frame count"}

        // Complete one following cluster before handing packets to H.264 so B-picture reorder
        // across the target cluster boundary is already represented.
        if !layout.indexComplete
        {
            let count = video.videoSamples.count
            if !layout.indexUntil(bytes, count + 1, &fileIndex.cancel) do
                fail BadParameterError{"video reader operation was cancelled"}
        }

        try .replaceAvailableFrames(video)
        var localRank = 0'u64
        while localRank < .streamSampleCount and .video.presentationTimeAtRank(localRank) < target do
            localRank += 1
        if localRank >= .streamSampleCount do
            fail BadParameterError{"Matroska frame index exceeds the stream frame count"}
        .windowBaseRank = index >= localRank ? index - localRank : 0
    }

    mtd ensureFrames(index: u64) fail
    {
        if .memoryComplete
        {
            if index >= .info.frameCount do
                fail BadParameterError{"Matroska frame index exceeds the stream frame count"}
            return
        }

        let fileIndex = .fileIndex!
        if Atomic.get(&fileIndex.cancel) do
            fail BadParameterError{"video reader operation was cancelled"}

        let layout = fileIndex.progressive!
        let bytes  = fileIndex.region.bytes()
        if !.streamOpen
        {
            if !layout.indexWindow(bytes, 0, &fileIndex.cancel) do
                fail BadParameterError{"video reader operation was cancelled"}
            let video = &layout.tracks[layout.selectedVideo]
            try .appendAvailableFrames(video)
            .presentationOrigin = .video.presentationTimeAtRank(0)
        }

        if index < .windowBaseRank or index - .windowBaseRank > .streamSampleCount
        {
            .seekWindow(index)
        }
        else
        {
            let localIndex = index - .windowBaseRank
            if !layout.indexWindow(bytes, localIndex, &fileIndex.cancel) do
                fail BadParameterError{"video reader operation was cancelled"}
            let video = &layout.tracks[layout.selectedVideo]
            try .appendAvailableFrames(video)
        }

        if index < .windowBaseRank or index - .windowBaseRank >= .streamSampleCount do
            fail BadParameterError{"Matroska frame index exceeds the stream frame count"}
        if layout.indexComplete and !.windowBaseRank do
            .info.frameCount = .streamSampleCount
    }

    mtd const currentFrameCount()->u64
    {
        if .memoryComplete do
            return .info.frameCount
        return .info.frameCount
    }

    mtd const currentFrameRate()->FrameRate
    {
        if .memoryComplete do
            return .info.frameRate
        return .info.frameRate
    }

    mtd const currentDuration()->f64
    {
        if .memoryComplete do
            return .durationSeconds
        return .durationSeconds
    }

    // Converts an absolute container timestamp to the first display rank not earlier than it.
    mtd const frameAtTimestamp(timestampNanoseconds: f64)->u64
    {
        let rate = .currentFrameRate()
        if !rate.isValid() do
            return 0
        let seconds = Math.max((timestampNanoseconds - cast(f64) .presentationOrigin) / 1_000_000_000.0, 0)
        return cast(u64) Math.ceil(seconds * cast(f64) rate.numerator() / cast(f64) rate.denominator())
    }

    mtd resumeSoundIndex()
    {
        if !.resumeSoundIndexAfterDecode do
            return
        .resumeSoundIndexAfterDecode = false
        Atomic.exchange(&.fileIndex!.soundPause, 0)
        if Atomic.get(&.fileIndex!.soundStage) do
            Atomic.exchange(&.fileIndex!.currentSeekSound, 0)
    }

    mtd opDrop()
    {
        if .fileIndex
        {
            Memory.delete(.fileIndex!)
            .fileIndex = null
        }
    }
}

private func runMatroskaSoundIndex(thread: Threading.Thread)
{
    let index = cast(*FileIndex) thread.userParam!
    catch buildSoundIndex(index) as indexError
    if indexError != null
    {
        Atomic.exchange(&index.soundStatus, SoundIndexFailed)
        return
    }

    Atomic.exchange(&index.soundStatus, SoundIndexReady)
}

impl IDecoder for Decoder
{
    mtd impl format()->StreamFormat => {"Matroska multimedia container", ".mkv"}

    mtd impl open(source: *Source)->StreamInfo fail
    {
        let path = source.sourcePath()
        if @countof(path)
        {
            var mapped = File.MappedFile.open(path)
            .fileIndex              = Memory.new'FileIndex()
            .fileIndex!.region      = mapped.mapAll()
            .fileIndex!.progressive = Memory.new'Layout()
            .fileIndex!.progressive!.parseMetadata(.fileIndex!.region.bytes())
            .fileIndex!.path = path
            .configureMetadata(.fileIndex!.progressive!)
            if .fileIndex!.progressive!.audioTracks.count do
                discard catch buildSoundWindow(.fileIndex!, 0) as initialSoundError
            .startSoundIndex()
            return .info
        }

        if !source.memory do
            fail InvalidFormatError{"Matroska memory source has no bytes"}
        var layout: Layout
        discard try layout.parse(source.memory!)
        .openMemory(&layout)
        return .info
    }

    mtd impl syncFrameAt(index: u64)->u64
    {
        let fileIndex = .fileIndex
        if index >= .windowBaseRank and index - .windowBaseRank < .streamSampleCount
        {
            let local = .video.syncRankAt(index - .windowBaseRank)
            if local < .streamSampleCount or !fileIndex or fileIndex!.progressive!.indexComplete do
                return .windowBaseRank + local
        }

        if !fileIndex do
            return index
        let timestamp = .targetTimestamp(index)
        if timestamp < 0 do
            return index
        let layout = fileIndex!.progressive!
        let cue    = layout.cueAtOrAfter(cast(u64) timestamp)
        if cue
        {
            let cueNanoseconds = cast(f64) cue!.timestamp * cast(f64) layout.timestampScale
            return Math.max(index, .frameAtTimestamp(cueNanoseconds))
        }

        return .frameAtTimestamp(.currentDuration() * 1_000_000_000.0 + cast(f64) .presentationOrigin)
    }

    mtd impl seekFrame(source: *Source, index: u64) fail
    {
        discard source
        defer #fail .resumeSoundIndex()
        .ensureFrames(index)
        .video.seekTo(index - .windowBaseRank)
    }

    mtd impl decodeFrame(source: *Source, target: *Image) fail
    {
        defer .resumeSoundIndex()
        // The demuxer already owns a mapped view. Serving payloads from it avoids turning every
        // video packet separated by another track into a small seek on the original file handle.
        if .fileIndex
        {
            var media = Source.openMemory(.fileIndex!.region.bytes())
            try .video.decodeNext(&media, target)
            return
        }

        try .video.decodeNext(source, target)
    }
}

impl IPlanarDecoder for Decoder
{
    mtd impl hasPlanarFrames()->bool => true

    mtd impl decodeFramePlanes(source: *Source, target: *PlanarFrame) fail
    {
        defer .resumeSoundIndex()
        if .fileIndex
        {
            var media = Source.openMemory(.fileIndex!.region.bytes())
            try .video.decodeNextPlanes(&media, target)
            return
        }

        try .video.decodeNextPlanes(source, target)
    }
}

impl IAudioDecoder for Decoder
{
    mtd impl audioTrackCount()->u32
    {
        let fileIndex = .fileIndex
        if !fileIndex do
            return 0
        let seekSound = Atomic.get(&fileIndex!.currentSeekSound)
        if seekSound do
            return cast(u32) (cast(*PublishedSound) seekSound).tracks.count
        return Atomic.get(&fileIndex!.soundStage) ? cast(u32) fileIndex!.soundTracks.count : 0
    }

    mtd impl audioTrack(index: u32)->#null const *SoundFile
    {
        let fileIndex = .fileIndex
        if !fileIndex do
            return null
        let seekSound = Atomic.get(&fileIndex!.currentSeekSound)
        if seekSound
        {
            let tracks = &(cast(*PublishedSound) seekSound).tracks
            return index < tracks.count ? &tracks[index] : null
        }
        if !Atomic.get(&fileIndex!.soundStage) do
            return null
        return index < fileIndex!.soundTracks.count ? &fileIndex!.soundTracks[index] : null
    }
}

impl ITimedDecoder for Decoder
{
    mtd impl frameTimestamp(index: u64)->f64
    {
        if index >= .windowBaseRank and index - .windowBaseRank < .streamSampleCount do
            return cast(f64) (.video.presentationTimeAtRank(index - .windowBaseRank) - .presentationOrigin) / 1_000_000_000.0
        let rate = .currentFrameRate()
        return rate.isValid() ? cast(f64) index * cast(f64) rate.denominator() / cast(f64) rate.numerator() : 0
    }

    mtd impl frameAtTime(seconds: f64)->u64
    {
        if seconds < 0 do
            return 0
        let count    = .currentFrameCount()
        let duration = .currentDuration()
        if count and seconds >= duration do
            return count
        let rate = .currentFrameRate()
        if !rate.isValid() do
            return 0
        return Math.min(cast(u64) (seconds * cast(f64) rate.numerator() / cast(f64) rate.denominator()), count ? count : Swag.U64.Max)
    }
}

impl IDeferredDecoder for Decoder
{
    mtd impl frameCount()->u64 => .currentFrameCount()

    mtd impl frameRate()->FrameRate => .currentFrameRate()

    mtd impl durationInSeconds()->f64 => .currentDuration()

    mtd impl requestCancel()
    {
        if .fileIndex do
            Atomic.exchange(&.fileIndex!.cancel, 1)
    }
}
