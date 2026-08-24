#global namespace Matroska

using Core, Core.Errors, Pixel, Audio

private const VideoTrackType = 1'u64
private const AudioTrackType = 2'u64
private const AvcCodecId = "V_MPEG4/ISO/AVC"
private const AacCodecId = "A_AAC"
private const DefaultTimestampScale = 1_000_000'u64
private const AacFrameSamples = 1024'u32
private const NoTrack = Swag.U64.Max

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
}

private impl Layout
{
    // Parses the EBML hierarchy and indexes block payloads without reading them.
    mtd parse(bytes: const [..] u8) fail
    {
        var cursor = Cursor.open(bytes)
        if !@countof(bytes) do
            fail InvalidFormatError{"Matroska stream is empty"}

        let header = cursor.readElement(@countof(bytes))
        if header.id != EbmlId do
            fail InvalidFormatError{"Matroska stream has no EBML header"}
        .parseHeader(&cursor, header)
        cursor.seek(header.end)

        var segment:    Element
        var hasSegment: bool
        while cursor.position < @countof(bytes)
        {
            let element = cursor.readElement(@countof(bytes))
            if element.id == SegmentId
            {
                segment    = element
                hasSegment = true
                break
            }

            cursor.seek(element.end)
        }

        if !hasSegment do
            fail InvalidFormatError{"Matroska stream has no segment"}

        .parseSegment(&cursor, segment)
        for cluster in .clusters do
            .parseCluster(&cursor, cluster)

        let video = &.tracks[.selectedVideo]
        if !video.videoSamples.count do
            fail InvalidFormatError{"Matroska video track has no blocks"}
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
    mtd parseSegment(cursor: *Cursor, segment: Element) fail
    {
        cursor.seek(segment.data)
        while cursor.position < segment.end
        {
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
    mtd parseCluster(cursor: *Cursor, cluster: Element) fail
    {
        var clusterTimestamp = 0'u64
        cursor.seek(cluster.data)
        while cursor.position < cluster.end
        {
            let element = cursor.readElement(cluster.end)
            if element.id == ClusterTimestampId do
                clusterTimestamp = cursor.readUnsigned(element)
            cursor.seek(element.end)
        }

        cursor.seek(cluster.data)
        while cursor.position < cluster.end
        {
            let element = cursor.readElement(cluster.end)
            switch element.id
            {
            case SimpleBlockId: .indexBlock(cursor, element, clusterTimestamp, true)
            case BlockGroupId:  .parseBlockGroup(cursor, element, clusterTimestamp)
            }

            cursor.seek(element.end)
        }
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

// Reads Matroska files carrying H.264 pictures and AAC-LC mono/stereo sound tracks.
//
// Opening maps the stream read-only and touches only EBML and block headers. The mapping is
// released after compact offset tables have been built; compressed payloads remain in the file
// and video plus every selected sound track read them through independent cursors.
struct Decoder
{
    internal
    {
        info:               StreamInfo
        avc:                H264.AvcStream
        soundTracks:        Array'SoundFile
        presentationOrigin: s64
        durationSeconds:    f64
    }
}

impl IDecoder for Decoder
{
    mtd impl format()->StreamFormat => {"Matroska multimedia container", ".mkv"}

    mtd impl open(source: *Source)->StreamInfo fail
    {
        var layout: Layout
        let path = source.sourcePath()
        if @countof(path)
        {
            var mapped = File.MappedFile.open(path)
            var region = mapped.mapAll()
            layout.parse(region.bytes())
        }
        else
        {
            if !source.memory do
                fail InvalidFormatError{"Matroska memory source has no bytes"}
            layout.parse(source.memory!)
        }

        let video = &layout.tracks[layout.selectedVideo]
        if video.videoSamples.count > Swag.U32.Max do
            fail OverflowError{"Matroska video sample table is too large"}

        .info.frameCount = video.videoSamples.count
        .avc.open(video.codecPrivate.toSlice(), #move video.videoSamples)
        .info.width  = .avc.width
        .info.height = .avc.height

        .presentationOrigin = .avc.presentationTimeAtRank(0)
        let lastTimestamp = .avc.presentationTimeAtRank(.info.frameCount - 1)
        if .presentationOrigin < 0 and lastTimestamp > Swag.S64.Max + .presentationOrigin do
            fail InvalidFormatError{"Matroska presentation timestamp span exceeds the supported range"}
        let timestampSpan = cast(u64) (lastTimestamp - .presentationOrigin)

        var frameDuration = video.defaultDuration
        if !frameDuration and .info.frameCount > 1 do
            frameDuration = Math.max(timestampSpan / (.info.frameCount - 1), 1)

        .info.frameRate = frameRateFromDuration(frameDuration)

        .durationSeconds = cast(f64) .info.frameCount * cast(f64) .info.frameRate.denominator() / cast(f64) .info.frameRate.numerator()
        if layout.durationTicks > 0
        {
            let declared = layout.durationTicks * cast(f64) layout.timestampScale / 1_000_000_000.0
            if declared > .durationSeconds do
                .durationSeconds = declared
        }

        if @countof(path)
        {
            .soundTracks.reserve(layout.audioTracks.count)
            for trackIndex in layout.audioTracks
            {
                let track = &layout.tracks[trackIndex]
                if !track.audioPackets.count do
                    continue
                if track.audioPackets.count > Swag.U64.Max / AacFrameSamples do
                    fail OverflowError{"Matroska audio packet table is too large"}
                let frameCount = track.audioPackets.count * AacFrameSamples
                let sound      = SoundFile.openPacketStream(path, .AacLc, cast(u32) Math.round(track.sampleRate), track.channels, frameCount, track.audioPackets.toSlice(), track.codecPrivate.toSlice())
                .soundTracks.add(#move sound)
            }
        }

        return .info
    }

    mtd impl syncFrameAt(index: u64)->u64 => .avc.syncRankAt(index)

    mtd impl seekFrame(source: *Source, index: u64) fail
    {
        discard source
        if index >= .info.frameCount do
            fail BadParameterError{"Matroska frame index exceeds the stream frame count"}
        .avc.seekTo(index)
    }

    mtd impl decodeFrame(source: *Source, target: *Image) fail
    {
        .avc.decodeNext(source, target)
    }
}

impl IPlanarDecoder for Decoder
{
    mtd impl hasPlanarFrames()->bool => true

    mtd impl decodeFramePlanes(source: *Source, target: *PlanarFrame) fail
    {
        .avc.decodeNextPlanes(source, target)
    }
}

impl IAudioDecoder for Decoder
{
    mtd impl audioTrackCount()->u32 => cast(u32) .soundTracks.count

    mtd impl audioTrack(index: u32)->#null const *SoundFile
    {
        if index >= .soundTracks.count do
            return null
        return &.soundTracks[index]
    }
}

impl ITimedDecoder for Decoder
{
    mtd impl frameTimestamp(index: u64)->f64
    {
        if index >= .info.frameCount do
            return .durationSeconds
        return cast(f64) (.avc.presentationTimeAtRank(index) - .presentationOrigin) / 1_000_000_000.0
    }

    mtd impl frameAtTime(seconds: f64)->u64
    {
        if seconds < 0 do
            return 0
        if seconds >= .durationSeconds do
            return .info.frameCount

        let nanoseconds = cast(s64) (seconds * 1_000_000_000.0)
        var low         = 0'u64
        var high        = .info.frameCount
        while low < high
        {
            let middle = low + (high - low) / 2
            if .avc.presentationTimeAtRank(middle) - .presentationOrigin <= nanoseconds do
                low = middle + 1
            else do
                high = middle
        }

        return low ? low - 1 : 0
    }
}
