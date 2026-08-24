#global namespace Matroska

using Core, Core.Errors, Pixel, Audio

private const VideoTrackType = 1'u64
private const AudioTrackType = 2'u64
private const AvcCodecId = "V_MPEG4/ISO/AVC"
private const AacCodecId = "A_AAC"
private const DefaultTimestampScale = 1_000_000'u64
private const AacFrameSamples = 1024'u32
private const NoTrack = Swag.U64.Max
private const NoOffset = Swag.U64.Max

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
    codecId:         String
    codecPrivate:    Array'u8
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
    videoSamples:    Array'H264.SampleEntry
    audioPackets:    Array'SoundPacket
}

private impl Track
{
    mtd const isPlayableVideo()->bool => .isEnabled and !.hasEncodings and .kind == VideoTrackType and .codecId == AvcCodecId and .codecPrivate.count != 0
    mtd const isPlayableAudio()->bool => .isEnabled and !.hasEncodings and .kind == AudioTrackType and .codecId == AacCodecId and .codecPrivate.count != 0 and .sampleRate > 0 and .sampleRate <= cast(f64) Swag.U32.Max and .channels != 0 and .channels <= 2 and !.codecDelay
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
    videoChunkEnds: Array'u64
    cues:           Array'CueEntry
}

private impl Layout
{
    // Parses the EBML hierarchy and indexes block payloads without reading them.
    mtd parse(bytes: const [..] u8, cancelled: #null *u32 = null)->bool fail
    {
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
        if !video.videoSamples.count do
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
    mtd indexUntil(bytes: const [..] u8, sampleCount: u64, cancelled: #null *u32 = null)->bool fail
    {
        if .indexComplete do
            return true

        var cursor = Cursor.open(bytes)
        cursor.seek(.scanPosition)
        while cursor.position < .segment.end and .tracks[.selectedVideo].videoSamples.count < sampleCount
        {
            if cancelled and Atomic.get(cancelled!) do
                return false
            let element = cursor.readElement(.segment.end)
            if element.id == ClusterId and !.parseCluster(&cursor, element, cancelled) do
                return false
            .scanPosition = element.end
            cursor.seek(element.end)
        }

        if .scanPosition >= .segment.end
        {
            .indexComplete = true
            if !.tracks[.selectedVideo].videoSamples.count do
                fail InvalidFormatError{"Matroska video track has no blocks"}
        }

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

    // Chooses one default H.264 picture track and every playable AAC sound track.
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

    // Finds the cluster timestamp, then indexes every selected block in that cluster.
    mtd parseCluster(cursor: *Cursor, cluster: Element, cancelled: #null *u32 = null)->bool fail
    {
        let firstVideoSample = .tracks[.selectedVideo].videoSamples.count
        var clusterTimestamp = 0'u64
        cursor.seek(cluster.data)
        while cursor.position < cluster.end
        {
            if cancelled and Atomic.get(cancelled!) do
                return false
            let element = cursor.readElement(cluster.end)
            if element.id == ClusterTimestampId do
                clusterTimestamp = cursor.readUnsigned(element)
            cursor.seek(element.end)
        }

        cursor.seek(cluster.data)
        while cursor.position < cluster.end
        {
            if cancelled and Atomic.get(cancelled!) do
                return false
            let element = cursor.readElement(cluster.end)
            switch element.id
            {
            case SimpleBlockId: .indexBlock(cursor, element, clusterTimestamp, true)
            case BlockGroupId:  .parseBlockGroup(cursor, element, clusterTimestamp)
            }

            cursor.seek(element.end)
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
            return
        }

        var offset = payload
        for size in .laceSizes
        {
            if size > Swag.U32.Max do
                fail InvalidFormatError{"Matroska audio packet exceeds the supported size"}
            track.audioPackets.add({offset, cast(u32) size, AacFrameSamples})
            offset += size
        }
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

#[Swag.NoCopy]
private struct FileIndex
{
    progressive: #null *Layout
    region:      File.MappedRegion
    path:        String
    soundTracks: Array'SoundFile
    soundReady:  bool
    cancel:      u32
}

private impl FileIndex
{
    mtd opDrop()
    {
        Atomic.exchange(&.cancel, 1)
        if .progressive do
            Memory.delete(.progressive!)
    }
}

// Reads Matroska files carrying H.264 pictures and AAC-LC mono/stereo sound tracks.
//
// Opening reads only seek, track, and cue metadata. Decoding advances one demux cursor through
// complete clusters on demand; random access restarts that cursor at a cue cluster. Compressed
// payloads remain in the file throughout and no second scanner competes with playback.
struct Decoder
{
    internal
    {
        info:               StreamInfo
        avc:                H264.AvcStream
        fileIndex:          #null *FileIndex
        presentationOrigin: s64
        durationSeconds:    f64
        avcSampleCount:     u64
        windowBaseRank:     u64
        avcOpen:            bool
        memoryComplete:     bool
    }
}

private impl Decoder
{
    mtd configureMetadata(layout: *Layout) fail
    {
        let video = &layout.tracks[layout.selectedVideo]
        var probe: H264.Decoder
        probe.configure(video.codecPrivate.toSlice())
        let sps = probe.firstSps()
        if !sps do
            fail InvalidFormatError{"H.264 decoder configuration has no sequence parameter set"}
        .info.width  = sps!.width()
        .info.height = sps!.height()
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
        .avc.open(video.codecPrivate.toSlice(), #move video.videoSamples)
        .avcOpen            = true
        .avcSampleCount     = .info.frameCount
        .presentationOrigin = .avc.presentationTimeAtRank(0)
        let lastTimestamp = .avc.presentationTimeAtRank(.info.frameCount - 1)
        let timestampSpan = cast(u64) (lastTimestamp - .presentationOrigin)
        var frameDuration = video.defaultDuration
        if !frameDuration and .info.frameCount > 1 do
            frameDuration = Math.max(timestampSpan / (.info.frameCount - 1), 1)
        .info.frameRate  = frameRateFromDuration(frameDuration)
        .durationSeconds = cast(f64) .info.frameCount * cast(f64) .info.frameRate.denominator() / cast(f64) .info.frameRate.numerator()
        .memoryComplete  = true
    }

    mtd appendAvailableFrames(samples: const [..] H264.SampleEntry, codecPrivate: const [..] u8) fail
    {
        if @countof(samples) <= .avcSampleCount do
            return
        let added = samples[.avcSampleCount until @countof(samples)]
        if !.avcOpen
        {
            var initial: Array'H264.SampleEntry
            initial.add(added)
            .avc.open(codecPrivate, #move initial)
            .avcOpen            = true
            .presentationOrigin = .avc.presentationTimeAtRank(0)
        }
        else do
            .avc.appendFrames(added)
        .avcSampleCount = @countof(samples)
    }

    mtd replaceAvailableFrames(samples: const [..] H264.SampleEntry, codecPrivate: const [..] u8) fail
    {
        var replacement: Array'H264.SampleEntry
        replacement.add(samples)
        if !.avcOpen
        {
            .avc.open(codecPrivate, #move replacement)
            .avcOpen = true
        }
        else do
            .avc.replaceFrames(#move replacement)
        .avcSampleCount = @countof(samples)
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

    // Publishes sound only after the one foreground cursor naturally reaches end of stream.
    mtd completeSoundTracks() fail
    {
        let fileIndex = .fileIndex!
        if fileIndex.soundReady or .windowBaseRank do
            return
        let layout = fileIndex.progressive!
        if !layout.indexComplete do
            return

        fileIndex.soundTracks.reserve(layout.audioTracks.count)
        for trackIndex in layout.audioTracks
        {
            let track = &layout.tracks[trackIndex]
            if !track.audioPackets.count do
                continue
            if track.audioPackets.count > Swag.U64.Max / AacFrameSamples do
                fail OverflowError{"Matroska audio packet table is too large"}
            let frameCount = track.audioPackets.count * AacFrameSamples
            let sound      = SoundFile.openPacketStream(fileIndex.path.toString(), .AacLc, cast(u32) Math.round(track.sampleRate), track.channels, frameCount, track.audioPackets.toSlice(), track.codecPrivate.toSlice())
            fileIndex.soundTracks.add(#move sound)
        }

        fileIndex.soundReady = true
    }

    // Restarts the single demux cursor on the key cluster advertised by Cues.
    mtd seekWindow(index: u64) fail
    {
        let fileIndex = .fileIndex!
        let layout    = fileIndex.progressive!
        let bytes     = fileIndex.region.bytes()
        let target    = .targetTimestamp(index)
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

        .replaceAvailableFrames(video.videoSamples.toSlice(), video.codecPrivate.toSlice())
        var localRank = 0'u64
        while localRank < .avcSampleCount and .avc.presentationTimeAtRank(localRank) < target do
            localRank += 1
        if localRank >= .avcSampleCount do
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
        if !.avcOpen
        {
            if !layout.indexWindow(bytes, 0, &fileIndex.cancel) do
                fail BadParameterError{"video reader operation was cancelled"}
            let video = &layout.tracks[layout.selectedVideo]
            .appendAvailableFrames(video.videoSamples.toSlice(), video.codecPrivate.toSlice())
            .presentationOrigin = .avc.presentationTimeAtRank(0)
        }

        if index < .windowBaseRank or index - .windowBaseRank > .avcSampleCount
        {
            .seekWindow(index)
        }
        else
        {
            let localIndex = index - .windowBaseRank
            if !layout.indexWindow(bytes, localIndex, &fileIndex.cancel) do
                fail BadParameterError{"video reader operation was cancelled"}
            let video = &layout.tracks[layout.selectedVideo]
            .appendAvailableFrames(video.videoSamples.toSlice(), video.codecPrivate.toSlice())
        }

        if index < .windowBaseRank or index - .windowBaseRank >= .avcSampleCount do
            fail BadParameterError{"Matroska frame index exceeds the stream frame count"}
        if layout.indexComplete and !.windowBaseRank
        {
            .info.frameCount = .avcSampleCount
            .completeSoundTracks()
        }
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

    mtd opDrop()
    {
        if .fileIndex
        {
            Memory.delete(.fileIndex!)
            .fileIndex = null
        }
    }
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
        if index < .windowBaseRank or index - .windowBaseRank >= .avcSampleCount do
            return index
        return .windowBaseRank + .avc.syncRankAt(index - .windowBaseRank)
    }

    mtd impl seekFrame(source: *Source, index: u64) fail
    {
        discard source
        .ensureFrames(index)
        .avc.seekTo(index - .windowBaseRank)
    }

    mtd impl decodeFrame(source: *Source, target: *Image) fail
    {
        // The demuxer already owns a mapped view. Serving payloads from it avoids turning every
        // video packet separated by another track into a small seek on the original file handle.
        if .fileIndex
        {
            var media = Source.openMemory(.fileIndex!.region.bytes())
            .avc.decodeNext(&media, target)
            return
        }

        .avc.decodeNext(source, target)
    }
}

impl IPlanarDecoder for Decoder
{
    mtd impl hasPlanarFrames()->bool => true

    mtd impl decodeFramePlanes(source: *Source, target: *PlanarFrame) fail
    {
        if .fileIndex
        {
            var media = Source.openMemory(.fileIndex!.region.bytes())
            .avc.decodeNextPlanes(&media, target)
            return
        }

        .avc.decodeNextPlanes(source, target)
    }
}

impl IAudioDecoder for Decoder
{
    mtd impl audioTrackCount()->u32
    {
        let fileIndex = .fileIndex
        return fileIndex and fileIndex!.soundReady ? cast(u32) fileIndex!.soundTracks.count : 0
    }

    mtd impl audioTrack(index: u32)->#null const *SoundFile
    {
        let fileIndex = .fileIndex
        if !fileIndex or !fileIndex!.soundReady or index >= fileIndex!.soundTracks.count do
            return null
        return &fileIndex!.soundTracks[index]
    }
}

impl ITimedDecoder for Decoder
{
    mtd impl frameTimestamp(index: u64)->f64
    {
        if index >= .windowBaseRank and index - .windowBaseRank < .avcSampleCount do
            return cast(f64) (.avc.presentationTimeAtRank(index - .windowBaseRank) - .presentationOrigin) / 1_000_000_000.0
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
