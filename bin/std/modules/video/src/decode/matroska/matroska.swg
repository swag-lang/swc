//! Format: Matroska/EBML container decoder component.
//! Supported: H.264, H.265 and MPEG-4 Part 2 picture tracks, AAC-LC, AC-3, independent E-AC-3, DTS Core, FLAC, Layer III, Vorbis, or Opus audio, and UTF-8 or ASS/SSA subtitle tracks, with cues, timestamps, codec delay, and discard padding.
//! Not supported: Other picture codecs, bitmap subtitles, laced or invisible picture blocks, dependent E-AC-3 substreams, encrypted tracks, and writing Matroska.
//! Role: This file owns tracks, clusters, cues, timestamps, progressive indexing, and media dispatch.
//
#global namespace Matroska

using Core, Core.Errors, Pixel, Audio

private const VideoTrackType    = 1'u64
private const AudioTrackType    = 2'u64
private const SubtitleTrackType = 17'u64

private const AvcCodecId          = "V_MPEG4/ISO/AVC"
private const HevcCodecId         = "V_MPEGH/ISO/HEVC"
private const AacCodecId          = "A_AAC"
private const Ac3CodecId          = "A_AC3"
private const Eac3CodecId         = "A_EAC3"
private const DtsCodecId          = "A_DTS"
private const FlacCodecId         = "A_FLAC"
private const Mp3CodecId          = "A_MPEG/L3"
private const VorbisCodecId       = "A_VORBIS"
private const OpusCodecId         = "A_OPUS"
private const Mpeg4CodecId        = "V_MPEG4/ISO/ASP"
private const VfwCodecId          = "V_MS/VFW/FOURCC"
private const Utf8SubtitleCodecId = "S_TEXT/UTF8"
private const AssSubtitleCodecId  = "S_TEXT/ASS"
private const SsaSubtitleCodecId  = "S_TEXT/SSA"

// An Opus decoder produces 48 kHz whatever rate the track states it was encoded from.
private const OpusOutputRate = 48_000.0

private struct SubtitleSample
{
    offset:       u64
    size:         u64
    startSeconds: f64
    endSeconds:   f64
}

// The one compression a stored frame can carry that this reader undoes, clause 12.3 of the
// Matroska specification: the bytes every frame began with, taken off and stated once.
private const HeaderStrippingAlgorithm = 3'u64
private const DefaultTimestampScale    = 1_000_000'u64
private const NoTrack                  = Swag.U64.Max
private const NoOffset                 = Swag.U64.Max

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

private func dtsPacketBits(bytes: const [..] u8, bitPosition, count: u32, littleEndianWords, packed14: bool)->u32
{
    var result: u32
    for bit in count
    {
        let position = cast(u64) bitPosition + bit
        result <<= 1
        if packed14
        {
            let byte = position / 14 * 2
            let word = littleEndianWords ? cast(u32) bytes[byte] | (cast(u32) bytes[byte + 1] << 8) : (cast(u32) bytes[byte] << 8) | cast(u32) bytes[byte + 1]
            result |= (word >> cast(u32) (13 - position % 14)) & 1
        }
        else
        {
            let byte = (position >> 3) ^ (littleEndianWords ? 1 : 0)
            result |= (cast(u32) bytes[byte] >> cast(u32) (7 - (position & 7))) & 1
        }
    }

    return result
}

internal func dtsSpeakerMask(packet: const [..] u8)->u32 fail
{
    if packet.count < 11 do
        fail InvalidFormatError{"Matroska DTS packet header is truncated"}

    let bigEndian16    = packet[0] == 0x7F and packet[1] == 0xFE and packet[2] == 0x80 and packet[3] == 0x01
    let littleEndian16 = packet[0] == 0xFE and packet[1] == 0x7F and packet[2] == 0x01 and packet[3] == 0x80
    let bigEndian14    = packet[0] == 0x1F and packet[1] == 0xFF and packet[2] == 0xE8 and packet[3] == 0x00
    let littleEndian14 = packet[0] == 0xFF and packet[1] == 0x1F and packet[2] == 0x00 and packet[3] == 0xE8
    if !bigEndian16 and !littleEndian16 and !bigEndian14 and !littleEndian14 do
        fail InvalidFormatError{"Matroska DTS packet has no core sync word"}

    let packed14 = bigEndian14 or littleEndian14
    if packed14 and packet.count < 16 do
        fail InvalidFormatError{"Matroska DTS packet header is truncated"}

    let littleEndian = littleEndian16 or littleEndian14
    let mode         = dtsPacketBits(packet, 60, 6, littleEndian, packed14)
    let lfe          = dtsPacketBits(packet, 85, 2, littleEndian, packed14)
    const Masks: [10] u32 = [0x0004, 0x0003, 0x0003, 0x0003, 0x0003, 0x0007, 0x0103, 0x0107, 0x0033, 0x0037]
    if mode >= Masks.count or lfe == 3 do
        fail InvalidFormatError{"Matroska DTS packet states an invalid channel arrangement"}
    return Masks[mode] | (lfe ? 0x0008 : 0)
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
    setup:           Array'u8     // Setup headers a legacy track states in its stream, not in the container.
    defaultDuration: u64
    codecDelay:      u64
    seekPreRoll:     u64
    width:           s32
    height:          s32
    displayWidth:    u64     // What the track states it is shown at, in the unit below.
    displayHeight:   u64
    displayUnit:     u64     // 0 is pixels, 3 is a bare ratio; everything else is unusable here.
    sampleRate:      f64  = 8_000
    channels:        u32  = 1
    bitsPerSample:   u32
    isEnabled:       bool = true
    isDefault:       bool = true
    hasEncodings:    bool         // The track states an encoding this reader does not undo.
    headerStrip:     Array'u8     // Bytes a writer took off the front of every frame.
    videoSamples:    Array'SampleEntry
    audioPackets:    Array'SoundPacket
    subtitleSamples: Array'SubtitleSample
    durationProbe:   Audio.PacketDurationProbe     // Measures audio packets once the first arrives.
    hasProbe:        bool
    audioFrameCount: u64
    audioStart:      s64
    hasAudioStart:   bool
}

private impl Track
{
    // Returns the size the pictures of this track are shown at, or nothing when it is their own.
    //
    // A track states the two sizes separately, and their ratio is what matters: a display size
    // equal to the stored one, or missing, means square samples. Unit 0 states pixels and unit 3
    // states a bare ratio; the physical units are not something a window can act on.
    mtd const displaySize(width, height: s32)->{ width, height: s32 }
    {
        if .displayUnit != 0 and .displayUnit != 3 do
            return {0, 0}
        if !.displayWidth or !.displayHeight or width <= 0 or height <= 0 do
            return {0, 0}
        if .displayWidth * cast(u64) height == .displayHeight * cast(u64) width do
            return {0, 0}

        // The taller of the two axes keeps its stored resolution, so a picture is only ever
        // stretched: shrinking one instead would throw away samples the stream carries.
        if .displayWidth * cast(u64) height > .displayHeight * cast(u64) width do
            return {cast(s32) ((cast(u64) height * .displayWidth + .displayHeight / 2) / .displayHeight), height}
        return {width, cast(s32) ((cast(u64) width * .displayHeight + .displayWidth / 2) / .displayWidth)}
    }

    mtd const isPlayableVideo()->bool
    {
        if !.isEnabled or .hasEncodings or .kind != VideoTrackType do
            return false
        if .codecId == AvcCodecId or .codecId == HevcCodecId or .codecId == Mpeg4CodecId do
            return .codecPrivate.count != 0
        return .isVfwMpeg4()
    }

    mtd const isHevcVideo()->bool => .codecId == HevcCodecId

    mtd const isPlayableSubtitle()->bool
    {
        return .isEnabled and !.hasEncodings and .kind == SubtitleTrackType and (.codecId == Utf8SubtitleCodecId or .codecId == AssSubtitleCodecId or .codecId == SsaSubtitleCodecId)
    }

    mtd const subtitleFormat()->Subtitle.Format
    {
        return .codecId == AssSubtitleCodecId or .codecId == SsaSubtitleCodecId ? .SubStationAlpha : .MatroskaText
    }

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
        if .codecId == DtsCodecId do
            return .Dts
        if .codecId == FlacCodecId do
            return .Flac
        if .codecId == Mp3CodecId do
            return .Mp3
        if .codecId == VorbisCodecId do
            return .Vorbis
        if .codecId == OpusCodecId do
            return .Opus
        return .Unknown
    }

    // The rate the decoded samples come out at, which for Opus is not the one the track states.
    mtd const decodedSampleRate()->f64 => .soundEncoding() == .Opus ? OpusOutputRate : .sampleRate

    mtd const isPlayableAudio()->bool
    {
        let encoding = .soundEncoding()
        if !.isEnabled or .hasEncodings or .kind != AudioTrackType or encoding == .Unknown do
            return false
        if .sampleRate <= 0 or .sampleRate > cast(f64) Swag.U32.Max or !.channels or .channels > 8 do
            return false
        return !Audio.packetEncodingNeedsConfig(encoding) or .codecPrivate.count != 0
    }

    mtd const leadingTrimFrames()->u64 fail
    {
        if !.codecDelay do
            return 0
        let frames = cast(f64) .codecDelay * .decodedSampleRate() / 1_000_000_000.0
        if frames > cast(f64) Swag.U32.Max do
            fail UnsupportedFormatError{"Matroska audio codec delay exceeds the supported range"}
        return cast(u64) Math.round(frames)
    }

    // Converts the discard padding a block declares to the sample frames it removes from the
    // end of that block's packets; a padding that runs the other way is not something to remove.
    mtd const discardPaddingFrames(nanoseconds: s64)->u64
    {
        if nanoseconds <= 0 do
            return 0
        return cast(u64) Math.round(cast(f64) nanoseconds * .decodedSampleRate() / 1_000_000_000.0)
    }

    mtd const speakerMask(bytes: const [..] u8)->u32 fail
    {
        let encoding = .soundEncoding()

        // AAC states its channel configuration in the decoder setup, and FLAC in its stream
        // information; Dolby and DTS hide it in the first packet.
        if encoding == .Dts
        {
            let packet = .audioPackets[0]
            if packet.sourceOffset > bytes.count or packet.byteSize > bytes.count - packet.sourceOffset do
                fail InvalidFormatError{"Matroska DTS audio packet is truncated"}
            return try dtsSpeakerMask(bytes[packet.sourceOffset until packet.sourceOffset + packet.byteSize])
        }

        if encoding != .Ac3 and encoding != .Eac3 do
            return 0
        let packet = .audioPackets[0]
        if packet.sourceOffset > bytes.count or packet.byteSize > bytes.count - packet.sourceOffset do
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
    timestampScale:       u64  = DefaultTimestampScale
    durationTicks:        f64
    tracks:               Array'Track
    clusters:             Array'Element
    audioTracks:          Array'u64
    subtitleTracks:       Array'u64
    selectedVideo:        u64  = NoTrack
    laceSizes:            Array'u64
    segment:              Element
    scanPosition:         u64
    indexComplete:        bool
    indexPictures:        bool = true
    lastClusterTimestamp: s64
    hasClusterTimestamp:  bool
    videoChunkEnds:       Array'u64
    cues:                 Array'CueEntry
    releasedThrough:      u64     // File offset below which the walk has handed its pages back.
}

// How far behind the walk the mapped pages are handed back, and in what steps.
//
// A walk reads the whole film, and every page it touches stays charged to the process until it
// is released. The decoder reads its payloads from the clusters just behind the index, so those
// stay; everything further back is only the memory the process would otherwise seem to hold.
private const ScanReleaseKeepBytes = 64 * 1024 * 1024'u64
private const ScanReleaseStepBytes = 16 * 1024 * 1024'u64

private impl Layout
{
    // Parses the EBML hierarchy and indexes block payloads without reading them.
    mtd parse(bytes: const [..] u8, cancelled: *u32? = null, indexPictures: bool = true)->bool fail
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
        while !cursor.atEnd(segment.end) and !hasTracks
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

                // The cue table is an index, not content. A file whose tail never made it to disk
                // still holds every picture it wrote, and is played by reading through it rather
                // than by seeking, so a cue table that is not there is not a reason to refuse it.
                if hasTracks and targets.cues != NoOffset
                {
                    let mark = cursor.position
                    catch .parseMetadataElement(cursor, targets.cues, CuesId, segment) as cuesError
                    if cuesError != null
                    {
                        .cues.clear()
                        cursor.seek(mark)
                    }
                }

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

    // Hands back the pages the walk has left far enough behind; see [[ScanReleaseKeepBytes]].
    mtd releaseScanned(bytes: const [..] u8)
    {
        if .releasedThrough > .scanPosition do
            .releasedThrough = .scanPosition
        if .scanPosition < .releasedThrough + ScanReleaseKeepBytes + ScanReleaseStepBytes do
            return
        let end = Math.min(.scanPosition - ScanReleaseKeepBytes, bytes.count)
        File.MappedRegion.releasePages(bytes[.releasedThrough until end])
        .releasedThrough = end
    }

    // Extends the block index by complete clusters until `sampleCount` pictures are available.
    mtd indexUntil(bytes: const [..] u8, sampleCount: u64, cancelled: *u32? = null, paused: *u32? = null)->bool fail
    {
        if .indexComplete do
            return true

        var cursor = Cursor.open(bytes)
        cursor.seek(.scanPosition)
        while !cursor.atEnd(.segment.end) and .tracks[.selectedVideo].videoSamples.count < sampleCount
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
            .releaseScanned(bytes)
            cursor.seek(element.end)
        }

        // The walk is done when there is nothing left to read, which is not always where the
        // segment says it ends: a file whose tail never made it to disk stops earlier, and a
        // reader that waits for the declared end waits forever.
        if cursor.atEnd(.segment.end)
        {
            .scanPosition  = .segment.end
            .indexComplete = true
            if .indexPictures and !.tracks[.selectedVideo].videoSamples.count do
                fail InvalidFormatError{"Matroska video track has no blocks"}
        }

        return true
    }

    // Reports whether every playable sound track is indexed through `timestampNanoseconds`.
    //
    // A file whose sound this module cannot read has nothing to index and nothing to wait for, so
    // the answer is yes. Answering no there made the window scan walk the whole file looking for
    // packets that were never going to appear: a seek in a fourteen-gigabyte film whose only
    // tracks are unsupported never returned.
    mtd const hasAudioThrough(timestampNanoseconds: s64)->bool
    {
        if !.audioTracks.count do
            return true
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

    mtd const hasMediaThrough(timestampNanoseconds: s64)->bool
    {
        if !.hasAudioThrough(timestampNanoseconds) do
            return false
        if !.subtitleTracks.count do
            return true
        return .hasClusterTimestamp and .lastClusterTimestamp >= timestampNanoseconds
    }

    // Extends a sound and timed-text window until every playable track reaches the timestamp.
    mtd indexAudioThrough(bytes: const [..] u8, timestampNanoseconds: s64, cancelled: *u32? = null, paused: *u32? = null)->bool fail
    {
        if .indexComplete or .hasMediaThrough(timestampNanoseconds) do
            return true

        var cursor = Cursor.open(bytes)
        cursor.seek(.scanPosition)
        while !cursor.atEnd(.segment.end) and !.hasMediaThrough(timestampNanoseconds)
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
            .releaseScanned(bytes)
            cursor.seek(element.end)
        }

        if cursor.atEnd(.segment.end)
        {
            .scanPosition  = .segment.end
            .indexComplete = true
        }

        return true
    }

    // Keeps the requested picture plus one complete following cluster indexed.
    //
    // The following cluster is the H.264 reorder queue: pictures stored just beyond a cluster
    // boundary may still be presented before its tail. Its size comes from the container rather
    // than from a time or frame-count heuristic.
    mtd indexWindow(bytes: const [..] u8, sampleIndex: u64, cancelled: *u32? = null)->bool fail
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
            track.subtitleSamples.clear()
            track.audioFrameCount = 0
            track.audioStart      = 0
            track.hasAudioStart   = false
        }

        .videoChunkEnds.clear()
        .scanPosition         = clusterOffset
        .indexComplete        = false
        .lastClusterTimestamp = 0
        .hasClusterTimestamp  = false
    }

    // Finds the last cue not later than `timestampNanoseconds`.
    mtd const cueAtOrBefore(timestampNanoseconds: u64)->const *CueEntry?
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
    mtd const cueAtOrAfter(timestampNanoseconds: u64)->const *CueEntry?
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
        if !bytes.count do
            fail InvalidFormatError{"Matroska stream is empty"}

        let header = result.cursor.readElement(bytes.count)
        if header.id != EbmlId do
            fail InvalidFormatError{"Matroska stream has no EBML header"}
        .parseHeader(&result.cursor, header)
        result.cursor.seek(header.end)

        var hasSegment: bool
        while result.cursor.position < bytes.count
        {
            let element = result.cursor.readElement(bytes.count)
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
    mtd parseSegment(cursor: *Cursor, segment: Element, cancelled: *u32? = null)->bool fail
    {
        cursor.seek(segment.data)
        while !cursor.atEnd(segment.end)
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
            case TrackNumberId:              track.number = cursor.readUnsigned(element)
            case TrackTypeId:                track.kind = cursor.readUnsigned(element)
            case FlagEnabledId:              track.isEnabled = cursor.readUnsigned(element) != 0
            case FlagDefaultId:              track.isDefault = cursor.readUnsigned(element) != 0
            case DefaultDurationId:          track.defaultDuration = cursor.readUnsigned(element)
            case NameId:                     track.name = cursor.readString(element)
            case LanguageId, LanguageIetfId: track.language = cursor.readString(element)
            case CodecIdId:                  track.codecId = cursor.readString(element)
            case CodecPrivateId:             track.codecPrivate = cursor.readBytes(element)
            case CodecDelayId:               track.codecDelay = cursor.readUnsigned(element)
            case SeekPreRollId:              track.seekPreRoll = cursor.readUnsigned(element)
            case ContentEncodingsId:         .parseContentEncodings(cursor, element, track)
            case VideoId:                    .parseVideo(cursor, element, track)
            case AudioId:                    .parseAudio(cursor, element, track)
            }

            cursor.seek(element.end)
        }

        if !track.number do
            fail InvalidFormatError{"Matroska track has no positive track number"}
        if track.codecId.isEmpty() do
            fail InvalidFormatError{"Matroska track has no codec identifier"}
    }

    // Reads what was done to the frames of a track before they were stored.
    //
    // The one thing done to them that this reader undoes is header stripping: a writer that knows
    // every frame of a track begins with the same bytes stores them once and takes them off, which
    // is what mkvmerge does by default to several codecs. Anything else — a compressed or an
    // encrypted track — is recorded as an encoding this reader cannot undo, and the track is not
    // offered rather than offered wrong.
    mtd parseContentEncodings(cursor: *Cursor, encodings: Element, track: *Track) fail
    {
        var count = 0'u32
        while !cursor.atEnd(encodings.end)
        {
            let element = cursor.readElement(encodings.end)
            if element.id == ContentEncodingId
            {
                count += 1
                if count > 1 or !try .parseContentEncoding(cursor, element, track) do
                    track.hasEncodings = true
            }

            cursor.seek(element.end)
        }

        if !count do
            track.hasEncodings = true
    }

    // Reads one encoding and answers whether it is one this reader undoes.
    mtd parseContentEncoding(cursor: *Cursor, encoding: Element, track: *Track)->bool fail
    {
        var scope     = 1'u64
        var kind      = 0'u64
        var algorithm = Swag.U64.Max
        var stripped: Array'u8
        while !cursor.atEnd(encoding.end)
        {
            let element = cursor.readElement(encoding.end)
            switch element.id
            {
            case ContentEncodingScopeId:
                scope = cursor.readUnsigned(element)

            case ContentEncodingTypeId:
                kind = cursor.readUnsigned(element)

            case ContentCompressionId:
                while !cursor.atEnd(element.end)
                {
                    let field = cursor.readElement(element.end)
                    switch field.id
                    {
                    case ContentCompAlgoId:     algorithm = cursor.readUnsigned(field)
                    case ContentCompSettingsId: stripped = cursor.readBytes(field)
                    }

                    cursor.seek(field.end)
                }
            }

            cursor.seek(element.end)
        }

        // Scope one is the frames themselves; the other scopes describe what was done to the
        // private data or to a later encoding, and neither is a thing this reader undoes.
        if scope != 1 or kind != 0 or algorithm != HeaderStrippingAlgorithm do
            return false

        track.headerStrip = #move stripped
        return true
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

            case DisplayWidthId:
                track.displayWidth = cursor.readUnsigned(element)

            case DisplayHeightId:
                track.displayHeight = cursor.readUnsigned(element)

            case DisplayUnitId:
                track.displayUnit = cursor.readUnsigned(element)
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

    // Chooses one default picture track and every playable sound and subtitle track.
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
            for track, index in .tracks where track.isPlayableSubtitle() and track.isDefault == wantDefault do
                .subtitleTracks.add(index)
        }
    }

    // Indexes a cluster in one forward pass.
    //
    // Muxers normally put Timestamp before the first block, so packets are indexed as their
    // headers are encountered. Matroska does not require that order: blocks seen first are kept
    // as tiny element descriptors until Timestamp arrives. This avoids the old full preliminary
    // pass over every block header and the repeated cursor jumps it imposed on a mapped file.
    mtd parseCluster(cursor: *Cursor, cluster: Element, cancelled: *u32? = null, paused: *u32? = null)->bool fail
    {
        let firstVideoSample = .tracks[.selectedVideo].videoSamples.count
        var clusterTimestamp = 0'u64
        var hasTimestamp: bool
        var pending:      Array'Element
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
                        .indexBlock(cursor, queued, clusterTimestamp, true, 0)
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
                    .indexBlock(cursor, element, clusterTimestamp, true, 0)
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
                .indexBlock(cursor, queued, clusterTimestamp, true, 0)
            else do
                .parseBlockGroup(cursor, queued, clusterTimestamp)
        }

        let videoSampleCount = .tracks[.selectedVideo].videoSamples.count
        if videoSampleCount > firstVideoSample do
            .videoChunkEnds.add(videoSampleCount)
        .lastClusterTimestamp = .timestampNanoseconds(clusterTimestamp, 0)
        .hasClusterTimestamp  = true
        return true
    }

    mtd parseBlockGroup(cursor: *Cursor, group: Element, clusterTimestamp: u64) fail
    {
        var block: Element
        var blockDuration  = 0'u64
        var discardPadding = 0's64
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

            case BlockDurationId:
                blockDuration = cursor.readUnsigned(element)

            case DiscardPaddingId:
                discardPadding = cursor.readSigned(element)
            }

            cursor.seek(element.end)
        }

        if hasBlock do
            .indexBlock(cursor, block, clusterTimestamp, !hasReference, blockDuration, discardPadding)
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

    // Indexes one block belonging to the selected picture, sound, or subtitle tracks.
    mtd indexBlock(cursor: *Cursor, block: Element, clusterTimestamp: u64, keyFromContainer: bool, blockDurationTicks: u64, discardPadding: s64 = 0) fail
    {
        cursor.seek(block.data)
        let trackNumber = cursor.readVintValue(block.end).value
        if block.end - cursor.position < 3 do
            fail InvalidFormatError{"Matroska block header is truncated"}
        let timeBits = (cast(u16) cursor.readByte(block.end) << 8) | cursor.readByte(block.end)
        let relative = cast #bit (s16) timeBits
        let flags    = cursor.readByte(block.end)

        var trackIndex = NoTrack
        var isVideo, isSubtitle: bool
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

            if trackIndex == NoTrack
            {
                for index in .subtitleTracks where .tracks[index].number == trackNumber
                {
                    trackIndex = index
                    isSubtitle = true
                    break
                }
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
                let end = Math.min(payload + .laceSizes[0], cursor.bytes.count)
                track.setup.add(Video.inlineSetupHeaders(cursor.bytes[payload until end]))
            }

            return
        }

        if isSubtitle
        {
            let timestamp = .timestampNanoseconds(clusterTimestamp, relative)
            let declared  = blockDurationTicks ? cast(f64) blockDurationTicks * cast(f64) .timestampScale : cast(f64) track.defaultDuration
            let duration  = declared > 0 ? declared / 1_000_000_000.0 : 5.0
            let part      = duration / cast(f64) .laceSizes.count
            var offset    = payload
            for size, index in .laceSizes
            {
                let start = cast(f64) timestamp / 1_000_000_000.0 + cast(f64) index * part
                track.subtitleSamples.add({offset, size, start, start + part})
                offset += size
            }

            return
        }

        let timestamp = .timestampNanoseconds(clusterTimestamp, relative)
        if !track.hasAudioStart
        {
            track.audioStart    = timestamp
            track.hasAudioStart = true
        }

        if !track.hasProbe
        {
            try track.durationProbe.initialize(track.soundEncoding(), track.codecPrivate.toSlice())
            track.hasProbe = true
        }

        var offset = payload
        for size, laceIndex in .laceSizes
        {
            if size > Swag.U32.Max do
                fail InvalidFormatError{"Matroska audio packet exceeds the supported size"}
            var frameCount = .audioPacketFrames(cursor.bytes, offset, size, track)
            if laceIndex + 1 == .laceSizes.count
            {
                // The padding trims the end of the block, which is the end of its last packet.
                let discarded = track.discardPaddingFrames(discardPadding)
                frameCount = discarded < frameCount ? frameCount - cast(u32) discarded : 0
            }

            track.audioPackets.add({offset, cast(u32) size, frameCount})
            if track.audioFrameCount > Swag.U64.Max - frameCount do
                fail OverflowError{"Matroska audio packet table is too large"}
            track.audioFrameCount += frameCount
            offset                += size
        }
    }

    mtd audioPacketFrames(bytes: const [..] u8, offset, size: u64, track: *Track)->u32 fail
    {
        if offset > bytes.count or size > bytes.count - offset do
            fail InvalidFormatError{"Matroska audio packet is truncated"}
        return try track.durationProbe.frames(bytes[offset until offset + size])
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

private const SoundIndexIdle    = 0'u32
private const SoundIndexRunning = 1'u32
private const SoundIndexReady   = 2'u32
private const SoundIndexFailed  = 3'u32

// How much sound one bounded window carries, and how close the picture may come to its end.
//
// The complete packet tables are built by a background walk of the whole file, which on a large
// film held on a network share takes minutes. Until they arrive the sound is whatever window the
// last seek published, so a window that ends while the picture is still playing is silence. These
// two decide how long a window lasts and how early the next one is built.
private const SoundSeekRunAheadNanoseconds  = 60_000_000_000's64
private const SoundWindowRefreshNanoseconds = 20_000_000_000's64
private const SoundWindowRetryNanoseconds   = 5_000_000_000's64

// How far ahead of the indexed window a picture can be asked for and still be reached by
// walking the index rather than by restarting the reader at a cue. Two thousand pictures is
// about eighty seconds of film, which covers every skip playback makes to catch up and
// leaves a real seek to what a reader asks for by hand.
private const ForwardWalkSamples          = 2000'u64
private const SoundSeekPreRollNanoseconds = 1_000_000_000'u64
private const SoundSeekPreRollSeconds     = 1.0

#[Swag.NoCopy]
private struct PublishedSound
{
    tracks:    Array'SoundFile
    subtitles: Array'Subtitle.Track
}

#[Swag.NoCopy]
private struct FileIndex
{
    progressive:      *Layout?
    region:           File.MappedRegion
    path:             String
    soundTracks:      Array'SoundFile
    subtitleTracks:   Array'Subtitle.Track
    soundThread:      Threading.Thread
    windowThread:     Threading.Thread
    windowWake:       Sync.Event
    windowTarget:     u64     // Timestamp the window being built must cover.
    windowBuilding:   u32     // Whether a window build is in flight.
    seekSounds:       Array'*PublishedSound
    soundLock:        Sync.Mutex
    cancel:           u32
    soundPause:       u32
    soundStatus:      u32
    soundStage:       u32
    currentSeekSound: u64
    seekSoundEnd:     s64     // Where the published window stops carrying sound.
}

private func publishFullSound(index: *FileIndex, tracks: *Array'SoundFile, subtitles: *Array'Subtitle.Track)
{
    Sync.scopedLock(&index.soundLock)
    index.soundTracks    = #move tracks[]
    index.subtitleTracks = #move subtitles[]
    Atomic.exchange(&index.soundStage, 1)
    if !Atomic.get(&index.soundPause) do
        Atomic.exchange(&index.currentSeekSound, 0)
}

private func publishSeekSound(index: *FileIndex, tracks: *Array'SoundFile, subtitles: *Array'Subtitle.Track, coverEndHint: s64)
{
    // The window ends where its shortest sound track does, or at the text scan horizon when it
    // carries subtitles alone.
    var coverEnd = coverEndHint
    for sound in tracks
    {
        let end = cast(s64) Math.round((sound.timelineStartSeconds() + sound.durationInSeconds()) * 1_000_000_000.0)
        coverEnd = Math.min(coverEnd, end)
    }

    let published = Memory.new'PublishedSound()
    published.tracks    = #move tracks[]
    published.subtitles = #move subtitles[]

    Sync.scopedLock(&index.soundLock)
    index.seekSounds.add(published)
    Atomic.exchange(&index.seekSoundEnd, coverEnd)
    Atomic.exchange(&index.currentSeekSound, cast(u64) published)
}

private impl FileIndex
{
    mtd opDrop()
    {
        Atomic.exchange(&.cancel, 1)
        if .windowThread.isValid()
        {
            .windowThread.safeForceEnd()
            .windowWake.signal()
            .windowThread.wait()
        }

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
        let sound         = SoundFile.openPacketStream(path, track.soundEncoding(), cast(u32) Math.round(track.decodedSampleRate()), track.channels, track.audioFrameCount, track.audioPackets.toSlice(), track.codecPrivate.toSlice(), options)
        result.add(#move sound)
    }
}

private func buildSubtitleTracks(bytes: const [..] u8, layout: *Layout, result: *Array'Subtitle.Track) fail
{
    result.reserve(layout.subtitleTracks.count)
    for trackIndex in layout.subtitleTracks
    {
        let source = &layout.tracks[trackIndex]
        var track  = Subtitle.Track.create(source.name.toString(), source.language.toString(), source.subtitleFormat())
        for sample in source.subtitleSamples
        {
            if sample.offset > bytes.count or sample.size > bytes.count - sample.offset do
                fail InvalidFormatError{"Matroska subtitle packet is truncated"}
            var payload: String
            if source.headerStrip.count do
                payload += cast(string) source.headerStrip.toSlice()
            payload += cast(string) bytes[sample.offset until sample.offset + sample.size]
            track.addEncodedCue(sample.startSeconds, sample.endSeconds, payload.toString())
        }

        track.sortCues()
        result.add(#move track)
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

    // The run-ahead applies at the start of the file too: a window built without it holds only
    // whatever one cluster happened to carry, which is about two seconds of sound.
    let requestedEnd = timestampNanoseconds > cast(u64) Swag.S64.Max - cast(u64) SoundSeekRunAheadNanoseconds ? Swag.S64.Max : cast(s64) timestampNanoseconds + SoundSeekRunAheadNanoseconds
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

    var subtitles: Array'Subtitle.Track
    try buildSubtitleTracks(bytes, &layout, &subtitles)
    publishSeekSound(index, &tracks, &subtitles, requestedEnd)
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
    var subtitles: Array'Subtitle.Track
    try buildSubtitleTracks(bytes, &layout, &subtitles)
    publishFullSound(index, &tracks, &subtitles)
}

// Reads Matroska files carrying supported picture tracks and AAC-LC, AC-3, E-AC-3, DTS Core,
// FLAC, or MPEG Layer III sound tracks.
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
        info:                        StreamInfo
        video:                       PictureStream
        fileIndex:                   *FileIndex?
        presentationOrigin:          s64
        durationSeconds:             f64
        streamSampleCount:           u64
        windowBaseRank:              u64
        streamOpen:                  bool
        memoryComplete:              bool
        resumeSoundIndexAfterDecode: bool
        soundWindowAttempt:          s64     // Earliest picture time the next window extension may be built at.
        memorySubtitleTracks:        Array'Subtitle.Track
        sawVideoSync:                bool     // A sample the container marks as a clean decode point was seen.
        syncScanAt:                  u64      // How far the search for one has read.
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

        let display = video.displaySize(.info.width, .info.height)
        .info.displayWidth  = display.width
        .info.displayHeight = display.height
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
        try .video.open(video.pictureKind(), video.videoConfiguration(), video.videoSamples.toSlice(), video.headerStrip.toSlice())
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
        if samples.count <= .streamSampleCount do
            return
        let added = samples[.streamSampleCount until samples.count]
        if !.streamOpen
        {
            try .video.open(track.pictureKind(), track.videoConfiguration(), added, track.headerStrip.toSlice())
            .streamOpen         = true
            .presentationOrigin = .video.presentationTimeAtRank(0)
        }
        else do
            try .video.appendFrames(added)
        .streamSampleCount = samples.count
    }

    mtd replaceAvailableFrames(track: const *Track) fail
    {
        let samples = track.videoSamples.toSlice()
        if !.streamOpen
        {
            try .video.open(track.pictureKind(), track.videoConfiguration(), samples, track.headerStrip.toSlice())
            .streamOpen = true
        }
        else do
            try .video.replaceFrames(samples)
        .streamSampleCount = samples.count
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
        if !fileIndex!.progressive!.audioTracks.count and !fileIndex!.progressive!.subtitleTracks.count
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
        let layout = fileIndex.progressive!
        let bytes  = fileIndex.region.bytes()
        let target = .targetTimestamp(index)
        .soundWindowAttempt = 0

        // A container whose sound this module cannot read has no window to build; asking for one
        // walked the whole file looking for packets that were never going to appear.
        if target >= 0 and (layout.audioTracks.count or layout.subtitleTracks.count) do
            discard catch buildSoundWindow(fileIndex, cast(u64) target) as soundWindowError
        let cue = target >= 0 ? layout.cueAtOrBefore(cast(u64) target) : null
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
            .refineFrameRate()
        }

        // A picture ahead of the window is reached by walking the index forward, which is
        // what the walk is already positioned for: restarting the reader at a cue instead
        // rebuilds the sound window, forgets every packet location the window holds, and
        // indexes the same clusters again. That restart costs between a quarter of a second
        // and two on a film read across a network share, and playback asks for it every time
        // it skips ahead to recover, which is precisely when it has no time to spare.
        // A jump longer than what the walk would cover, and every jump backwards, still
        // restarts at the nearest cue.
        let ahead = index >= .windowBaseRank ? index - .windowBaseRank : Swag.U64.Max
        if ahead == Swag.U64.Max or ahead > .streamSampleCount + ForwardWalkSamples
        {
            .seekWindow(index)
        }
        else
        {
            let localIndex = ahead
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

    // Replaces a declared frame duration the pictures themselves contradict.
    //
    // `DefaultDuration` is what a track states about itself, and a muxer can state anything: one
    // film of a real library declares one millisecond, which reads as a thousand pictures a
    // second and puts the playback clock a thousand times past where the picture is. The times
    // the pictures actually carry are the answer, and by here the first window of them is
    // indexed. They are believed only when they disagree with the declaration by half again,
    // which no rounding of a real rate ever does.
    mtd refineFrameRate()
    {
        if .streamSampleCount < 2 do
            return

        let span = cast(u64) (.video.presentationTimeAtRank(.streamSampleCount - 1) - .presentationOrigin)
        if !span do
            return

        let observed = Math.max(span / (.streamSampleCount - 1), 1)
        let declared = .info.frameRate.isValid() ? cast(u64) Math.round(1_000_000_000.0 * cast(f64) .info.frameRate.denominator() / cast(f64) .info.frameRate.numerator()) : 0
        if declared and observed * 2 < declared * 3 and declared * 2 < observed * 3 do
            return

        .info.frameRate = catch frameRateFromDuration(observed)
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

    // Keeps the bounded sound window ahead of the picture being decoded.
    //
    // A window covers a fixed run of sound from where it was built. Playing past its end is
    // silence until the background walk publishes the complete tables, which is minutes on a
    // large file; building the next window as the picture approaches the end of this one is what
    // keeps the sound running in between.
    mtd extendSoundWindow(index: u64)
    {
        let fileIndex = .fileIndex
        if !fileIndex or (!fileIndex!.progressive!.audioTracks.count and !fileIndex!.progressive!.subtitleTracks.count) do
            return
        if !Atomic.get(&fileIndex!.currentSeekSound) do
            return

        let target = .targetTimestamp(index)
        if target < 0 or target < .soundWindowAttempt do
            return
        if target + SoundWindowRefreshNanoseconds < Atomic.get(&fileIndex!.seekSoundEnd) do
            return

        // A window that cannot be built is not retried on the next picture: the walk that would
        // fix it is already running, and asking again every frame would stall every one of them.
        .soundWindowAttempt = target + SoundWindowRetryNanoseconds
        .requestSoundWindow(fileIndex!, cast(u64) target)
    }

    // Asks the worker for a window covering `target`, and returns without waiting for it.
    //
    // One build at a time: a second request while one is in flight is dropped, and the picture
    // that wanted it asks again once its retry delay has passed.
    mtd requestSoundWindow(index: *FileIndex, target: u64)
    {
        if Atomic.get(&index.windowBuilding) do
            return

        Atomic.exchange(&index.windowTarget, target)
        Atomic.exchange(&index.windowBuilding, 1)
        if !index.windowThread.isValid()
        {
            index.windowWake.init()
            catch index.windowThread.init(&runMatroskaSoundWindow, index, priority: .Normal) as startError
            if startError == null do
                discard catch index.windowThread.start()
            if !index.windowThread.isValid()
            {
                // No worker means no window, and a silent film is worse than a late one.
                Atomic.exchange(&index.windowBuilding, 0)
                discard catch buildSoundWindow(index, target) as windowError
                return
            }
        }

        index.windowWake.signal()
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

// Builds the bounded sound window a playing picture asked for.
//
// The walk reads every cluster between the last cue and the position asked for, which is one to
// two seconds on a large film read across a network share. Done on the thread that decodes, that
// is the run-ahead queue emptied and a picture skipped; the player already knows how to show a
// picture whose sound has not arrived yet, so the walk waits here instead.
private func runMatroskaSoundWindow(thread: Threading.Thread)
{
    let index = cast(*FileIndex) thread.userParam!
    while !thread.requestEnd
    {
        index.windowWake.wait()
        if thread.requestEnd do
            break

        discard catch buildSoundWindow(index, Atomic.get(&index.windowTarget)) as windowError
        Atomic.exchange(&index.windowBuilding, 0)
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
        if path.count
        {
            var mapped = File.MappedFile.open(path)
            .fileIndex              = Memory.new'FileIndex()
            .fileIndex!.region      = mapped.mapAll()
            .fileIndex!.progressive = Memory.new'Layout()
            .fileIndex!.progressive!.parseMetadata(.fileIndex!.region.bytes())
            .fileIndex!.path = path
            .configureMetadata(.fileIndex!.progressive!)

            // The opening sound window is built beside the picture rather than before it. It
            // reads a minute of interleaved clusters, which is a second on a film read across a
            // network share, and a player has nothing to show for that second: it can present
            // its first picture as soon as the video is ready and let the sound join it, which
            // is what it already does after every seek.
            if .fileIndex!.progressive!.audioTracks.count or .fileIndex!.progressive!.subtitleTracks.count do
                .requestSoundWindow(.fileIndex!, 0)
            .startSoundIndex()
            return .info
        }

        if !source.memory do
            fail InvalidFormatError{"Matroska memory source has no bytes"}
        var layout: Layout
        discard try layout.parse(source.memory!)
        try buildSubtitleTracks(source.memory!, &layout, &.memorySubtitleTracks)
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

    // Makes sure the window reaches a sample the container marks as a clean decode point.
    //
    // A container that marks nothing leaves the first sample as the only place a decode can start.
    // A window that stops short of the first mark looks exactly the same, so it is widened until
    // one shows up or the file runs out; only then is the absence of a mark a fact rather than a
    // consequence of how little has been read. A stream clipped in the middle of a group has no
    // clean start before its first mark, and starting anyway decodes slices whose references were
    // cut away with the file they came from.
    mtd ensureDecodablePoint() fail
    {
        if .memoryComplete or .sawVideoSync do
            return

        let fileIndex = .fileIndex!
        let layout    = fileIndex.progressive!
        let bytes     = fileIndex.region.bytes()
        var reach     = .streamSampleCount
        while true
        {
            let samples = layout.tracks[layout.selectedVideo].videoSamples.toSlice()
            while .syncScanAt < samples.count
            {
                if samples[.syncScanAt].isSync
                {
                    .sawVideoSync = true
                    return
                }

                .syncScanAt += 1
            }

            if layout.indexComplete do
                return

            reach += 64
            if !layout.indexWindow(bytes, reach, &fileIndex.cancel) do
                fail BadParameterError{"video reader operation was cancelled"}
            try .appendAvailableFrames(&layout.tracks[layout.selectedVideo])
        }
    }

    mtd impl seekFrame(source: *Source, index: u64) fail
    {
        discard source
        if .fileIndex and Atomic.get(&.fileIndex!.soundStatus) == SoundIndexRunning
        {
            // Video reconstruction has the foreground deadline. The complete audio packet scan
            // can use every idle gap, but must not compete for a core or mapped pages while one
            // picture is being sought and decoded; the bounded sound window remains available.
            Atomic.exchange(&.fileIndex!.soundPause, 1)
            .resumeSoundIndexAfterDecode = true
        }

        defer #fail .resumeSoundIndex()
        .extendSoundWindow(index)
        .ensureFrames(index)
        try .ensureDecodablePoint()
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

    mtd impl audioTrack(index: u32)->const *SoundFile?
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

impl ISubtitleDecoder for Decoder
{
    mtd const impl subtitleTrackCount()->u32
    {
        let fileIndex = .fileIndex
        if !fileIndex do
            return cast(u32) .memorySubtitleTracks.count
        let seekSound = Atomic.get(&fileIndex!.currentSeekSound)
        if seekSound do
            return cast(u32) (cast(*PublishedSound) seekSound).subtitles.count
        return Atomic.get(&fileIndex!.soundStage) ? cast(u32) fileIndex!.subtitleTracks.count : 0
    }

    mtd const impl subtitleTrack(index: u32)->const *Subtitle.Track?
    {
        let fileIndex = .fileIndex
        if !fileIndex do
            return index < .memorySubtitleTracks.count ? &.memorySubtitleTracks[index] : null
        let seekSound = Atomic.get(&fileIndex!.currentSeekSound)
        if seekSound
        {
            let tracks = &(cast(*PublishedSound) seekSound).subtitles
            return index < tracks.count ? &tracks[index] : null
        }

        if !Atomic.get(&fileIndex!.soundStage) do
            return null
        return index < fileIndex!.subtitleTracks.count ? &fileIndex!.subtitleTracks[index] : null
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
