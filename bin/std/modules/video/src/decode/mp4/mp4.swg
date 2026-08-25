//! Format: ISO Base Media File Format (MP4/M4V/MOV) decoder component.
//! Supported: Classic sample-table files containing Motion JPEG, H.264, or H.265 video and AAC-LC audio, including composition offsets and sync-sample seeking.
//! Not supported: Fragmented or encrypted media, unsupported sample-entry versions, picture codecs other than Motion JPEG/H.264/H.265, and audio codecs other than AAC-LC.
//! Role: This file owns box parsing, sample tables, track selection, timestamps, and top-level decoding.
//
#global namespace Mp4

using Core, Core.Errors, Pixel, Audio

// Builds the big-endian value an ISO-BMFF box stores for a four-character identifier.
#[Swag.ConstExpr]
func fourCc(a, b, c, d: u32)->u32 => (a << 24) | (b << 16) | (c << 8) | d

const FileTypeId           = fourCc('f'u32, 't'u32, 'y'u32, 'p'u32)
const MovieId              = fourCc('m'u32, 'o'u32, 'o'u32, 'v'u32)
const TrackId              = fourCc('t'u32, 'r'u32, 'a'u32, 'k'u32)
const MediaId              = fourCc('m'u32, 'd'u32, 'i'u32, 'a'u32)
const MediaHeaderId        = fourCc('m'u32, 'd'u32, 'h'u32, 'd'u32)
const HandlerId            = fourCc('h'u32, 'd'u32, 'l'u32, 'r'u32)
const MediaInfoId          = fourCc('m'u32, 'i'u32, 'n'u32, 'f'u32)
const SampleTableId        = fourCc('s'u32, 't'u32, 'b'u32, 'l'u32)
const SampleDescriptionId  = fourCc('s'u32, 't'u32, 's'u32, 'd'u32)
const TimeToSampleId       = fourCc('s'u32, 't'u32, 't'u32, 's'u32)
const SampleToChunkId      = fourCc('s'u32, 't'u32, 's'u32, 'c'u32)
const SampleSizeId         = fourCc('s'u32, 't'u32, 's'u32, 'z'u32)
const ChunkOffsetId        = fourCc('s'u32, 't'u32, 'c'u32, 'o'u32)
const ChunkOffset64Id      = fourCc('c'u32, 'o'u32, '6'u32, '4'u32)
const VideoHandlerId       = fourCc('v'u32, 'i'u32, 'd'u32, 'e'u32)
const AudioHandlerId       = fourCc('s'u32, 'o'u32, 'u'u32, 'n'u32)
const ElementaryStreamId   = fourCc('e'u32, 's'u32, 'd'u32, 's'u32)
const Mpeg4VisualId        = fourCc('m'u32, 'p'u32, '4'u32, 'v'u32)
const Mpeg4AudioId         = fourCc('m'u32, 'p'u32, '4'u32, 'a'u32)
const WaveId               = fourCc('w'u32, 'a'u32, 'v'u32, 'e'u32)
const Mpeg4AudioObjectType = 0x40'u8

const SyncSampleId  = fourCc('s'u32, 't'u32, 's'u32, 's'u32)
const CompositionId = fourCc('c'u32, 't'u32, 't'u32, 's'u32)
const AvcConfigId   = fourCc('a'u32, 'v'u32, 'c'u32, 'C'u32)
const HevcConfigId  = fourCc('h'u32, 'v'u32, 'c'u32, 'C'u32)

const JpegCodecIds: [3] u32 = [
    fourCc('j'u32, 'p'u32, 'e'u32, 'g'u32),
    fourCc('m'u32, 'j'u32, 'p'u32, 'g'u32),
    fourCc('m'u32, 'j'u32, 'p'u32, 'a'u32)]

const AvcCodecIds: [2] u32 = [
    fourCc('a'u32, 'v'u32, 'c'u32, '1'u32),
    fourCc('a'u32, 'v'u32, 'c'u32, '3'u32)]

// `hvc1` keeps its parameter sets in the sample entry alone; `hev1` may repeat them in the access
// units as well. Both are read the same way, because the decoder accepts either source.
const HevcCodecIds: [2] u32 = [
    fourCc('h'u32, 'v'u32, 'c'u32, '1'u32),
    fourCc('h'u32, 'e'u32, 'v'u32, '1'u32)]

const JpegName        = ".jpg"
const JpegObjectType  = 0x6C'u8
const BoxHeaderSize   = 8'u64
const FullBoxSize     = 4'u64
const NoFrameIndex    = Swag.U64.Max
const AacFrameSamples = 1024'u32

// One bounded box in the stream.
struct Box
{
    kind: u32
    data: u64
    end:  u64
}

// One ISO descriptor nested in an `esds` box.
private struct Descriptor
{
    tag: u8
    end: u64
}

// One compressed frame in the media-data boxes.
struct FrameEntry
{
    offset: u64
    size:   u64
}

// One run of samples sharing a duration.
private struct TimeEntry
{
    sampleCount: u32
    sampleDelta: u32
}

// One change in the mapping from samples to chunks.
private struct ChunkEntry
{
    firstChunk:       u32
    samplesPerChunk:  u32
    descriptionIndex: u32
}

// Tables describing one media track.
struct Track
{
    codec:          u32
    width:          s32
    height:         s32
    timescale:      u32
    handler:        u32
    times:          Array'TimeEntry
    chunks:         Array'ChunkEntry
    sizes:          Array'u32
    offsets:        Array'u64
    syncSamples:    Array'u32          // Zero-based sync sample indices; empty means every sample.
    ctsEntries:     Array'CtsEntry     // Composition offset runs, empty for decode-order streams.
    videoConfig:    Array'u8           // The `avcC` or `hvcC` decoder configuration of a coded track.
    aacConfig:      Array'u8           // MPEG-4 AudioSpecificConfig of an AAC track.
    channelCount:   u32
    sampleRate:     u32
    sampleBits:     u32
    hasDescription: bool
    isJpeg:         bool
    isAvc:          bool
    isHevc:         bool
    isAac:          bool
}

private impl Track
{
    // Whether the track carries a coded picture stream this module decodes across access units,
    // as opposed to the still images a Motion JPEG track stores.
    mtd const isCodedVideo()->bool => .isAvc or .isHevc
}

// One run of samples sharing a composition-time offset.
private struct CtsEntry
{
    sampleCount: u32
    offset:      s32
}

// What walking the movie metadata found.
private struct Layout
{
    track:            Track
    audioTracks:      Array'Track
    hasMovie:         bool
    hasVideo:         bool
    unsupportedCodec: u32
}

// Reads a big-endian 16-bit integer.
func readU16(source: *Source)->u16 fail
{
    var bytes: [2] u8 = undefined
    source.readExact(bytes)
    return (cast(u16) bytes[0] << 8) | cast(u16) bytes[1]
}

// Reads a big-endian 32-bit integer.
func readU32(source: *Source)->u32 fail
{
    var bytes: [4] u8 = undefined
    source.readExact(bytes)
    return (cast(u32) bytes[0] << 24) | (cast(u32) bytes[1] << 16) | (cast(u32) bytes[2] << 8) | cast(u32) bytes[3]
}

// Reads a big-endian 64-bit integer.
func readU64(source: *Source)->u64 fail
{
    let high = cast(u64) readU32(source)
    let low  = cast(u64) readU32(source)
    return (high << 32) | low
}

// Skips the version and flags shared by every full box and returns the version.
private func readFullBox(source: *Source)->u8 fail
{
    let version = source.readByte()
    source.skip(3)
    return version
}

// Reads an ISO descriptor tag and its base-128 length.
private func readDescriptor(source: *Source, parentEnd: u64)->Descriptor fail
{
    if source.position() >= parentEnd do
        fail InvalidFormatError{"MP4 descriptor header runs past its parent descriptor"}
    let tag  = source.readByte()
    var size = 0'u64
    var complete: bool
    for 4
    {
        if source.position() >= parentEnd do
            fail InvalidFormatError{"MP4 descriptor length runs past its parent descriptor"}
        let value = source.readByte()
        size = (size << 7) | cast(u64) (value & 0x7F)
        if !(value & 0x80)
        {
            complete = true
            break
        }
    }

    if !complete do
        fail InvalidFormatError{"MP4 descriptor length exceeds four bytes"}
    if size > parentEnd - source.position() do
        fail InvalidFormatError{"MP4 descriptor runs past its parent descriptor"}
    return {tag, source.position() + size}
}

// Reads a box header within `parentEnd`.
func readBox(source: *Source, parentEnd: u64)->Box fail
{
    let start = source.position()
    if start > parentEnd or BoxHeaderSize > parentEnd - start do
        fail InvalidFormatError{"MP4 box header runs past its parent box"}

    let compactSize = readU32(source)
    let kind        = readU32(source)
    var size        = cast(u64) compactSize
    if compactSize == 1
    {
        if 8 > parentEnd - source.position() do
            fail InvalidFormatError{"MP4 extended box size runs past its parent box"}
        size = readU64(source)
        if size < 16 do
            fail InvalidFormatError{"MP4 extended box size is smaller than its header"}
    }
    elif !compactSize
    {
        size = parentEnd - start
    }
    elif compactSize < BoxHeaderSize
    {
        fail InvalidFormatError{"MP4 box size is smaller than its header"}
    }

    if size > parentEnd - start do
        fail InvalidFormatError{"MP4 box runs past its parent box"}
    return {kind, source.position(), start + size}
}

// Returns a four-character identifier as printable text.
private func describeId(id: u32)->String
{
    var result: retval
    for shift in 4
    {
        let value = cast(u8) ((id >> cast(u32) ((3 - shift) * 8)) & 0xFF)
        result.append(value >= 0x20 and value < 0x7F ? cast(rune) value : '?'rune)
    }

    return result
}

private impl Layout
{
    // Walks the top-level boxes and keeps the first supported video track plus playable audio.
    mtd parse(source: *Source) fail
    {
        while source.position() + BoxHeaderSize <= source.size()
        {
            let box = readBox(source, source.size())
            if box.kind == MovieId
            {
                .hasMovie = true
                .parseMovie(source, box.end)
            }

            source.seek(box.end)
        }

        if source.position() != source.size() do
            fail InvalidFormatError{"MP4 stream has trailing bytes outside a box"}
        if !.hasMovie do
            fail InvalidFormatError{"MP4 stream has no movie box"}
        if !.hasVideo do
            fail UnsupportedFormatError{"MP4 file has no video track"}
        if !.track.hasDescription
        {
            if .unsupportedCodec do
                fail UnsupportedFormatError{Errors.mkString(Format.toString("video decoder does not support the MP4 '%' video codec", describeId(.unsupportedCodec)))}
            fail InvalidFormatError{"MP4 video track has no sample description"}
        }
    }

    // Walks every track in a movie box.
    mtd parseMovie(source: *Source, end: u64) fail
    {
        while source.position() + BoxHeaderSize <= end
        {
            let box = readBox(source, end)
            if box.kind == TrackId
            {
                var candidate: Track
                candidate.parse(source, box.end)
                if candidate.handler == VideoHandlerId
                {
                    .hasVideo = true
                    if candidate.hasDescription and (candidate.isJpeg or candidate.isCodedVideo()) and !.track.hasDescription do
                        .track = #move candidate
                    elif !.unsupportedCodec do
                        .unsupportedCodec = candidate.codec
                }
                elif candidate.handler == AudioHandlerId and candidate.hasDescription and candidate.isAac do
                    .audioTracks.add(#move candidate)
            }

            source.seek(box.end)
        }
    }
}

impl Track
{
    // Reads the media hierarchy of one track.
    mtd parse(source: *Source, end: u64) fail
    {
        while source.position() + BoxHeaderSize <= end
        {
            let box = readBox(source, end)
            if box.kind == MediaId do
                .parseMedia(source, box.end)
            source.seek(box.end)
        }
    }

    mtd parseMedia(source: *Source, end: u64) fail
    {
        while source.position() + BoxHeaderSize <= end
        {
            let box = readBox(source, end)
            switch box.kind
            {
            case MediaHeaderId:
                .parseMediaHeader(source, box.end)

            case HandlerId:
                .parseHandler(source, box.end)

            case MediaInfoId:
                if .handler == VideoHandlerId or .handler == AudioHandlerId do
                    .parseMediaInfo(source, box.end)
            }

            source.seek(box.end)
        }
    }

    mtd parseMediaHeader(source: *Source, end: u64) fail
    {
        if FullBoxSize > end - source.position() do
            fail InvalidFormatError{"MP4 media header is truncated"}
        let version = readFullBox(source)
        switch version
        {
        case 0:
            if 16 > end - source.position() do
                fail InvalidFormatError{"MP4 media header is truncated"}
            source.skip(8)
            .timescale = readU32(source)
            source.skip(4)

        case 1:
            if 28 > end - source.position() do
                fail InvalidFormatError{"MP4 media header is truncated"}
            source.skip(16)
            .timescale = readU32(source)
            source.skip(8)

        default:
            fail UnsupportedFormatError{"video decoder does not support this MP4 media-header version"}
        }

        if !.timescale do
            fail InvalidFormatError{"MP4 video track has a zero timescale"}
    }

    mtd parseHandler(source: *Source, end: u64) fail
    {
        if 12 > end - source.position() do
            fail InvalidFormatError{"MP4 handler box is truncated"}
        discard readFullBox(source)
        source.skip(4)
        .handler = readU32(source)
    }

    mtd parseMediaInfo(source: *Source, end: u64) fail
    {
        while source.position() + BoxHeaderSize <= end
        {
            let box = readBox(source, end)
            if box.kind == SampleTableId do
                .parseSampleTable(source, box.end)
            source.seek(box.end)
        }
    }

    mtd parseSampleTable(source: *Source, end: u64) fail
    {
        while source.position() + BoxHeaderSize <= end
        {
            let box = readBox(source, end)
            switch box.kind
            {
            case SampleDescriptionId: .parseSampleDescription(source, box.end)
            case TimeToSampleId:      .parseTimeToSample(source, box.end)
            case SampleToChunkId:     .parseSampleToChunk(source, box.end)
            case SampleSizeId:        .parseSampleSizes(source, box.end)
            case ChunkOffsetId:       .parseChunkOffsets(source, box.end, false)
            case ChunkOffset64Id:     .parseChunkOffsets(source, box.end, true)
            case SyncSampleId:        .parseSyncSamples(source, box.end)
            case CompositionId:       .parseCompositionOffsets(source, box.end)
            }

            source.seek(box.end)
        }
    }

    mtd parseSampleDescription(source: *Source, end: u64) fail
    {
        if 8 > end - source.position() do
            fail InvalidFormatError{"MP4 sample-description box is truncated"}
        discard readFullBox(source)
        let count = readU32(source)
        if !count do
            fail InvalidFormatError{"MP4 video track has no sample description"}

        let entry = readBox(source, end)
        if .handler == AudioHandlerId
        {
            .parseAudioDescription(source, entry)
            return
        }

        if 28 > entry.end - entry.data do
            fail InvalidFormatError{"MP4 visual sample entry is truncated"}
        .codec = entry.kind
        source.seek(entry.data + 24)
        .width          = cast(s32) readU16(source)
        .height         = cast(s32) readU16(source)
        .hasDescription = true
        if .width <= 0 or .height <= 0 do
            fail InvalidFormatError{"MP4 video track needs positive frame dimensions"}

        .isJpeg = Slice.contains(JpegCodecIds, .codec)
        if .codec == Mpeg4VisualId do
            .isJpeg = .parseMpeg4VisualDescription(source, entry)
        if Slice.contains(AvcCodecIds, .codec) do
            .isAvc = .parseCodecConfiguration(source, entry, AvcConfigId)
        if Slice.contains(HevcCodecIds, .codec) do
            .isHevc = .parseCodecConfiguration(source, entry, HevcConfigId)
    }

    // Reads an MPEG-4 audio sample entry and locates its AudioSpecificConfig.
    mtd parseAudioDescription(source: *Source, entry: Box) fail
    {
        const AudioSampleEntrySize = 28'u64
        if AudioSampleEntrySize > entry.end - entry.data do
            fail InvalidFormatError{"MP4 audio sample entry is truncated"}
        .codec = entry.kind
        source.seek(entry.data + 8)
        let version = readU16(source)
        source.skip(6)
        .channelCount = readU16(source)
        .sampleBits   = readU16(source)
        source.skip(4)
        .sampleRate     = readU32(source) >> 16
        .hasDescription = true
        if !.channelCount or !.sampleRate do
            fail InvalidFormatError{"MP4 audio track needs channels and a sample rate"}
        if version > 1 do
            fail UnsupportedFormatError{"video decoder does not support this MP4 audio sample-entry version"}

        let childStart = entry.data + AudioSampleEntrySize + (version == 1 ? 16 : 0)
        if childStart > entry.end do
            fail InvalidFormatError{"MP4 audio sample entry is truncated"}
        if .codec == Mpeg4AudioId do
            .isAac = .parseAudioChildren(source, childStart, entry.end)
    }

    // Recursively searches the sample entry and its QuickTime `wave` wrapper for `esds`.
    mtd parseAudioChildren(source: *Source, start, end: u64)->bool fail
    {
        var position = start
        while position + BoxHeaderSize <= end
        {
            source.seek(position)
            let child = readBox(source, end)
            if child.kind == ElementaryStreamId do
                return .parseAacElementaryStreamDescriptor(source, child.end)
            if child.kind == WaveId and .parseAudioChildren(source, child.data, child.end) do
                return true
            position = child.end
        }

        return false
    }

    // Reads an MPEG-4 systems descriptor and retains an AAC AudioSpecificConfig.
    mtd parseAacElementaryStreamDescriptor(source: *Source, end: u64)->bool fail
    {
        if FullBoxSize > end - source.position() do
            fail InvalidFormatError{"MP4 elementary-stream box is truncated"}
        discard readFullBox(source)
        let es = readDescriptor(source, end)
        if es.tag != 3 or 3 > es.end - source.position() do
            fail InvalidFormatError{"MP4 elementary-stream descriptor is truncated"}
        source.skip(2)
        let flags = source.readByte()
        if flags & 0x80 do
            .skipDescriptorBytes(source, es.end, 2)
        if flags & 0x40
        {
            if source.position() >= es.end do
                fail InvalidFormatError{"MP4 elementary-stream URL length is truncated"}
            .skipDescriptorBytes(source, es.end, source.readByte())
        }

        if flags & 0x20 do
            .skipDescriptorBytes(source, es.end, 2)

        let decoder = readDescriptor(source, es.end)
        if decoder.tag != 4 or 13 > decoder.end - source.position() do
            fail InvalidFormatError{"MP4 decoder-configuration descriptor is truncated"}
        if source.readByte() != Mpeg4AudioObjectType do
            return false
        source.skip(12)
        let specific = readDescriptor(source, decoder.end)
        if specific.tag != 5 or specific.end <= source.position() do
            fail InvalidFormatError{"MP4 AAC track has no AudioSpecificConfig"}
        .aacConfig.resize(specific.end - source.position())
        source.readExact(.aacConfig.toSlice())
        return true
    }

    // Locates and keeps the decoder configuration record of a coded visual sample entry.
    mtd parseCodecConfiguration(source: *Source, entry: Box, kind: u32)->bool fail
    {
        const VisualSampleEntrySize = 78'u64
        var position = entry.data + VisualSampleEntrySize
        while position + BoxHeaderSize <= entry.end
        {
            source.seek(position)
            let child = readBox(source, entry.end)
            if child.kind == kind
            {
                let size = child.end - child.data
                .videoConfig.resize(size)
                source.readExact(.videoConfig.toSlice())
                return true
            }

            position = child.end
        }

        return false
    }

    // Reads the sync sample table, converting indices to zero-based sample numbers.
    mtd parseSyncSamples(source: *Source, end: u64) fail
    {
        if 8 > end - source.position() do
            fail InvalidFormatError{"MP4 sync-sample box is truncated"}
        discard readFullBox(source)
        let count = readU32(source)
        if cast(u64) count * 4 > end - source.position() do
            fail InvalidFormatError{"MP4 sync-sample table is truncated"}
        .syncSamples.reserve(count)
        for count
        {
            let number = readU32(source)
            if !number do
                fail InvalidFormatError{"MP4 sync-sample table holds a zero sample number"}
            .syncSamples.add(number - 1)
        }
    }

    // Reads the composition offset table.
    mtd parseCompositionOffsets(source: *Source, end: u64) fail
    {
        if 8 > end - source.position() do
            fail InvalidFormatError{"MP4 composition-offset box is truncated"}
        let version = readFullBox(source)
        let count   = readU32(source)
        if cast(u64) count * 8 > end - source.position() do
            fail InvalidFormatError{"MP4 composition-offset table is truncated"}
        if version > 1 do
            fail UnsupportedFormatError{"video decoder does not support this MP4 composition-offset version"}
        .ctsEntries.reserve(count)
        for count
        {
            let sampleCount = readU32(source)
            let rawOffset   = readU32(source)
            let offset      = version == 0 ? cast(s32) Math.min(rawOffset, cast(u32) Swag.S32.Max) : cast(s32) rawOffset
            .ctsEntries.add({sampleCount, offset})
        }
    }

    // Reports whether an `mp4v` sample entry identifies ISO/IEC 10918-1 JPEG samples.
    //
    // FFmpeg uses the generic MPEG-4 visual sample entry for Motion JPEG and carries the real
    // codec as object type `0x6c` in its elementary-stream descriptor.
    mtd parseMpeg4VisualDescription(source: *Source, entry: Box)->bool fail
    {
        const VisualSampleEntrySize = 78'u64
        var position = entry.data + VisualSampleEntrySize
        while position + BoxHeaderSize <= entry.end
        {
            source.seek(position)
            let child = readBox(source, entry.end)
            if child.kind == ElementaryStreamId do
                return .parseElementaryStreamDescriptor(source, child.end)
            position = child.end
        }

        return false
    }

    // Reads enough of `esds` to identify its decoder object type.
    mtd parseElementaryStreamDescriptor(source: *Source, end: u64)->bool fail
    {
        if FullBoxSize > end - source.position() do
            fail InvalidFormatError{"MP4 elementary-stream box is truncated"}
        discard readFullBox(source)
        let es = readDescriptor(source, end)
        if es.tag != 3 or 3 > es.end - source.position() do
            fail InvalidFormatError{"MP4 elementary-stream descriptor is truncated"}

        source.skip(2)
        let flags = source.readByte()
        if flags & 0x80 do
            .skipDescriptorBytes(source, es.end, 2)
        if flags & 0x40
        {
            if source.position() >= es.end do
                fail InvalidFormatError{"MP4 elementary-stream URL length is truncated"}
            let urlSize = source.readByte()
            .skipDescriptorBytes(source, es.end, urlSize)
        }

        if flags & 0x20 do
            .skipDescriptorBytes(source, es.end, 2)

        let decoder = readDescriptor(source, es.end)
        if decoder.tag != 4 or source.position() >= decoder.end do
            fail InvalidFormatError{"MP4 decoder-configuration descriptor is truncated"}
        return source.readByte() == JpegObjectType
    }

    // Skips bytes without leaving their descriptor.
    mtd skipDescriptorBytes(source: *Source, end: u64, count: u64) fail
    {
        if source.position() > end or count > end - source.position() do
            fail InvalidFormatError{"MP4 elementary-stream descriptor is truncated"}
        source.skip(count)
    }

    mtd parseTimeToSample(source: *Source, end: u64) fail
    {
        if 8 > end - source.position() do
            fail InvalidFormatError{"MP4 time-to-sample box is truncated"}
        discard readFullBox(source)
        let count = readU32(source)
        if cast(u64) count * 8 > end - source.position() do
            fail InvalidFormatError{"MP4 time-to-sample table is truncated"}
        .times.reserve(count)
        for count do
            .times.add({readU32(source), readU32(source)})
    }

    mtd parseSampleToChunk(source: *Source, end: u64) fail
    {
        if 8 > end - source.position() do
            fail InvalidFormatError{"MP4 sample-to-chunk box is truncated"}
        discard readFullBox(source)
        let count = readU32(source)
        if cast(u64) count * 12 > end - source.position() do
            fail InvalidFormatError{"MP4 sample-to-chunk table is truncated"}
        .chunks.reserve(count)
        var previous = 0'u32
        for count
        {
            let entry = ChunkEntry{readU32(source), readU32(source), readU32(source)}
            if entry.firstChunk <= previous do
                fail InvalidFormatError{"MP4 sample-to-chunk entries are not in ascending chunk order"}
            previous = entry.firstChunk
            .chunks.add(entry)
        }
    }

    mtd parseSampleSizes(source: *Source, end: u64) fail
    {
        if 12 > end - source.position() do
            fail InvalidFormatError{"MP4 sample-size box is truncated"}
        discard readFullBox(source)
        let fixedSize = readU32(source)
        let count     = readU32(source)
        if !fixedSize and cast(u64) count * 4 > end - source.position() do
            fail InvalidFormatError{"MP4 sample-size table is truncated"}
        .sizes.resize(count)
        for &size in .sizes do
            size[] = fixedSize ? fixedSize : readU32(source)
    }

    mtd parseChunkOffsets(source: *Source, end: u64, wide: bool) fail
    {
        if 8 > end - source.position() do
            fail InvalidFormatError{"MP4 chunk-offset box is truncated"}
        discard readFullBox(source)
        let count     = readU32(source)
        let entrySize = wide ? 8'u64 : 4'u64
        if cast(u64) count * entrySize > end - source.position() do
            fail InvalidFormatError{"MP4 chunk-offset table is truncated"}
        .offsets.reserve(count)
        for count do
            .offsets.add(wide ? readU64(source) : cast(u64) readU32(source))
    }

    // Returns the exact frame rate of a constant-duration track, and the exact average rate
    // of a variable one, which is what a caller pacing playback can best use.
    mtd const frameRate()->FrameRate fail
    {
        if !.times.count do
            fail InvalidFormatError{"MP4 video track has no time-to-sample table"}
        if !.timescale do
            fail InvalidFormatError{"MP4 video track has no media timescale"}

        let delta    = .times[0].sampleDelta
        var constant = true
        var samples  = 0'u64
        var ticks    = 0'u64
        for entry in .times
        {
            if entry.sampleDelta != delta do
                constant = false
            samples += entry.sampleCount
            ticks   += cast(u64) entry.sampleCount * cast(u64) entry.sampleDelta
        }

        if samples != .sizes.count do
            fail InvalidFormatError{"MP4 timing and sample-size tables describe different frame counts"}
        if constant
        {
            if !delta do
                fail InvalidFormatError{"MP4 video samples have a zero duration"}
            return FrameRate.create(.timescale, delta)
        }

        if !ticks do
            fail InvalidFormatError{"MP4 video samples have a zero duration"}

        // The average `timescale * samples / ticks`, reduced so it fits the rate's parts.
        var numerator   = cast(u64) .timescale * samples
        var denominator = ticks
        var a           = numerator
        var b           = denominator
        while b != 0
        {
            let remainder = a % b
            a = b
            b = remainder
        }

        numerator   /= a
        denominator /= a
        if numerator <= Swag.U32.Max and denominator <= Swag.U32.Max do
            return FrameRate.create(cast(u32) numerator, cast(u32) denominator)
        return FrameRate.create(.timescale, cast(u32) Math.max(ticks / samples, 1))
    }

    // Expands the composition offsets into the display time of every sample.
    mtd const sampleTimes()->Array's64 fail
    {
        var result: retval
        result.reserve(.sizes.count)

        // Decode times first.
        var time = 0's64
        for entry in .times
        {
            for entry.sampleCount
            {
                if result.count >= .sizes.count do
                    break
                result.add(time)
                time += cast(s64) entry.sampleDelta
            }
        }

        while result.count < .sizes.count
        {
            result.add(time)
            time += cast(s64) (.times.count ? .times.back().sampleDelta : 1)
        }

        var index = 0'u64
        for entry in .ctsEntries
        {
            for entry.sampleCount
            {
                if index >= result.count do
                    break
                result[index] += cast(s64) entry.offset
                index         += 1
            }
        }

        return result
    }

    // Expands the chunk tables into one direct frame table.
    mtd buildFrames(sourceSize: u64)->Array'FrameEntry fail
    {
        if !.sizes.count do
            fail InvalidFormatError{"MP4 video track has no samples"}
        if !.offsets.count do
            fail InvalidFormatError{"MP4 video track has no chunk offsets"}
        if !.chunks.count or .chunks[0].firstChunk != 1 do
            fail InvalidFormatError{"MP4 sample-to-chunk table does not start at the first chunk"}

        var result: retval
        result.reserve(.sizes.count)
        var tableIndex  = 0'u64
        var sampleIndex = 0'u64
        for chunkIndex in .offsets.count
        {
            let chunkNumber = cast(u64) chunkIndex + 1
            while tableIndex + 1 < .chunks.count and cast(u64) .chunks[tableIndex + 1].firstChunk <= chunkNumber do
                tableIndex += 1
            let mapping = .chunks[tableIndex]
            if !mapping.samplesPerChunk or mapping.descriptionIndex != 1 do
                fail UnsupportedFormatError{"video decoder does not support this MP4 sample-to-chunk mapping"}

            var offset = .offsets[chunkIndex]
            for mapping.samplesPerChunk
            {
                if sampleIndex >= .sizes.count do
                    fail InvalidFormatError{"MP4 chunk table describes more samples than the sample-size table"}
                let size = cast(u64) .sizes[sampleIndex]
                if !size do
                    fail InvalidFormatError{"MP4 video sample has no payload"}
                if offset > sourceSize or size > sourceSize - offset do
                    fail InvalidFormatError{"MP4 sample runs past the end of the stream"}
                result.add({offset, size})
                offset      += size
                sampleIndex += 1
            }
        }

        if sampleIndex != .sizes.count do
            fail InvalidFormatError{"MP4 chunk table does not describe every video sample"}
        return result
    }

    // Expands this AAC track into the packet index consumed by std/audio.
    //
    // The duration a sample table states is a presentation time, and a writer is free to spread it
    // across packets so that a track's total lands on a clock it cares about: durations of 1023 and
    // 1025 either side of 1024 are common, and so are runs of 1008 and 1032. What a packet decodes
    // to is the codec's business, not the container's, and an AAC-LC access unit decodes to a fixed
    // number of frames whatever the table says. The table is still required to describe every
    // packet, because a table that does not is a broken one.
    mtd buildSoundPackets(sourceSize: u64)->{ packets: Array'SoundPacket, frameCount: u64 } fail
    {
        let frames = .buildFrames(sourceSize)
        var result: retval
        result.packets.reserve(frames.count)

        var timed = 0'u64
        for timing in .times do
            timed += timing.sampleCount
        if timed != frames.count do
            fail InvalidFormatError{"MP4 audio timing does not describe every packet"}

        for frame in frames
        {
            result.packets.add({frame.offset, cast(u32) frame.size, AacFrameSamples})
            result.frameCount += AacFrameSamples
        }

        return result
    }
}

// Reads ISO-BMFF files carrying Motion JPEG, H.264, or H.265 video samples.
//
// Opening walks only the movie metadata and expands its compact sample tables into one direct
// offset-and-size entry per frame. Frame payloads remain in the source and are read only when
// requested. A Motion JPEG sample is a key frame, so seeking costs one table lookup; a coded
// stream seeks by decoding forward from the nearest sync sample, and its frames are returned
// in display order whatever order the file stores them in.
//
// AAC-LC mono/stereo tracks are exposed as packetized std/audio streams. Their payload remains
// in the MP4 file and each voice opens its own cursor, so sound and picture can stream in parallel.
struct Decoder
{
    internal
    {
        info:                  StreamInfo
        frames:                Array'FrameEntry
        payload:               Array'u8
        nextIndex:             u64
        isCoded:               bool
        video:                 PictureStream
        soundTracks:           Array'SoundFile
        presentationTimes:     Array's64
        presentationTimescale: u32
    }
}

impl IDecoder for Decoder
{
    mtd impl format()->StreamFormat => {"MP4 - ISO Base Media File Format", ".mp4;.m4v;.mov"}

    mtd impl open(source: *Source)->StreamInfo fail
    {
        var layout: Layout
        layout.parse(source)
        var frames = layout.track.buildFrames(source.size())

        let times = layout.track.sampleTimes()
        .presentationTimescale = layout.track.timescale
        .presentationTimes.reserve(times.count)
        if layout.track.isCodedVideo()
        {
            var order: Array'u32
            order.reserve(times.count)
            for index in times.count
            {
                var position = order.count
                while position > 0 and times[cast(u64) order[position - 1]] > times[index] do
                    position -= 1
                order.insertAt(position, cast(u32) index)
            }

            for sample in order do
                .presentationTimes.add(times[sample])
        }
        else do
            .presentationTimes = #move times

        if .presentationTimes.count
        {
            let origin = .presentationTimes[0]
            for &time in .presentationTimes do
                time[] -= origin
        }

        let path = source.sourcePath()
        if @countof(path)
        {
            .soundTracks.reserve(layout.audioTracks.count)
            for &audioTrack in layout.audioTracks
            {
                let packetLayout = audioTrack.buildSoundPackets(source.size())
                let sound        = SoundFile.openPacketStream(path, .AacLc, audioTrack.sampleRate, audioTrack.channelCount, packetLayout.frameCount, packetLayout.packets.toSlice(), audioTrack.aacConfig.toSlice())
                .soundTracks.add(#move sound)
            }
        }

        .info.frameRate  = layout.track.frameRate()
        .info.frameCount = frames.count
        .nextIndex       = 0

        if layout.track.isCodedVideo()
        {
            var syncFlags: Array'u8
            syncFlags.resize(frames.count)
            if layout.track.syncSamples.count
            {
                for sample in layout.track.syncSamples where cast(u64) sample < syncFlags.count do
                    syncFlags[cast(u64) sample] = 1
            }
            else
            {
                for &flag in syncFlags do
                    flag[] = 1
            }

            if syncFlags.count do
                syncFlags[0] = 1

            var samples: Array'SampleEntry
            samples.reserve(frames.count)
            for frame, index in frames do
                samples.add({frame.offset, frame.size, times[index], syncFlags[index] != 0})

            .isCoded = true
            try .video.open(layout.track.isHevc ? PictureHevc : PictureAvc, layout.track.videoConfig.toSlice(), samples.toSlice())
            .info.width  = .video.width()
            .info.height = .video.height()
        }
        else
        {
            .frames      = #move frames
            .info.width  = layout.track.width
            .info.height = layout.track.height
        }

        return .info
    }

    mtd impl syncFrameAt(index: u64)->u64
    {
        if !.isCoded do
            return index
        return .video.syncRankAt(index)
    }

    mtd impl seekFrame(source: *Source, index: u64) fail
    {
        discard source
        if index >= .info.frameCount do
            fail BadParameterError{"MP4 frame index exceeds the stream frame count"}
        if .isCoded do
            .video.seekTo(index)
        else do
            .nextIndex = index
    }

    mtd impl decodeFrame(source: *Source, target: *Image) fail
    {
        if .isCoded
        {
            try .video.decodeNext(source, target)
            return
        }

        let current = .nextIndex
        if current >= .frames.count do
            fail InvalidFormatError{"MP4 stream has no frame at this position"}
        .nextIndex = NoFrameIndex

        let frame = .frames[current]
        if .payload.count != frame.size do
            .payload.resize(frame.size)
        source.seek(frame.offset)
        source.readExact(.payload.toSlice())

        var decoded = Image.decode(JpegName, .payload.toSlice())
        if decoded.width != .info.width or decoded.height != .info.height do
            fail InvalidFormatError{"MP4 frame does not have the dimensions its track declares"}
        decoded.convertTo(.RGB8)
        if target.width != .info.width or target.height != .info.height or target.pixelFormat != .RGB8 do
            target[] = Image.create(.info.width, .info.height, .RGB8)
        Memory.copy(target.pixels.buffer!, decoded.pixels.buffer!, target.byteCount)
        .nextIndex = current + 1
    }
}

impl IPlanarDecoder for Decoder
{
    mtd impl hasPlanarFrames()->bool => .isCoded

    mtd impl decodeFramePlanes(source: *Source, target: *PlanarFrame) fail
    {
        if !.isCoded do
            fail UnsupportedFormatError{"MP4 track does not decode to planar pictures"}
        try .video.decodeNextPlanes(source, target)
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
        if index >= .presentationTimes.count or !.presentationTimescale do
            return 0
        return cast(f64) .presentationTimes[index] / cast(f64) .presentationTimescale
    }

    mtd impl frameAtTime(seconds: f64)->u64
    {
        if !.presentationTimes.count or !.presentationTimescale do
            return 0
        if seconds < 0 do
            return 0
        if seconds >= cast(f64) .info.frameCount * cast(f64) .info.frameRate.denominator() / cast(f64) .info.frameRate.numerator() do
            return .info.frameCount

        let ticks = cast(s64) (seconds * cast(f64) .presentationTimescale)
        var low   = 0'u64
        var high  = .presentationTimes.count
        while low < high
        {
            let middle = low + (high - low) / 2
            if .presentationTimes[middle] <= ticks do
                low = middle + 1
            else do
                high = middle
        }

        return low ? low - 1 : 0
    }
}
