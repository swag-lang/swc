//! Format: ISO Base Media File Format (MP4) fragmented writer.
//! Supported: One H.264 video track, one packet per fragment, and interruption-safe completed fragments.
//! Not supported: Audio or metadata tracks, encryption, and a final random-access index.
//! Role: This file writes an initialization movie followed by bounded `moof`/`mdat` pairs.
//
#global namespace Mp4
#global export

using Core, Core.Errors

private const MovieExtendsId        = fourCc('m'u32, 'v'u32, 'e'u32, 'x'u32)
private const TrackExtendsId        = fourCc('t'u32, 'r'u32, 'e'u32, 'x'u32)
private const MovieFragmentId       = fourCc('m'u32, 'o'u32, 'o'u32, 'f'u32)
private const MovieFragmentHeaderId = fourCc('m'u32, 'f'u32, 'h'u32, 'd'u32)
private const TrackFragmentId       = fourCc('t'u32, 'r'u32, 'a'u32, 'f'u32)
private const TrackFragmentHeaderId = fourCc('t'u32, 'f'u32, 'h'u32, 'd'u32)
private const DecodeTimeId          = fourCc('t'u32, 'f'u32, 'd'u32, 't'u32)
private const TrackRunId            = fourCc('t'u32, 'r'u32, 'u'u32, 'n'u32)
private const AvcSampleEntryId      = fourCc('a'u32, 'v'u32, 'c'u32, '1'u32)
private const Iso6BrandId           = fourCc('i'u32, 's'u32, 'o'u32, '6'u32)

// Writes H.264 access units to an MP4 file that stays playable through its last complete fragment.
//
// The caller supplies an AVC decoder configuration (`avcC`) with four-byte NAL lengths and submits
// access units in decode order through [[Video.Mp4.FragmentedWriter.addPacket]]. Each call writes
// one `moof`/`mdat` pair and flushes it before returning, so memory does not grow with duration.
// The first packet must be a key frame. Timestamps use the `timescale` given at creation.
//
// The file has no final index; sequential playback and recovery of complete fragments work before
// [[Video.Mp4.FragmentedWriter.end]]. The current [[Video.Reader]] does not yet read fragmented
// MP4, so readers that understand ISO-BMFF movie fragments are needed for playback.
#[Swag.NoCopy]
struct FragmentedWriter
{
    private
    {
        sink:           ByteSink
        config:         Array'u8
        width:          u16
        height:         u16
        timescale:      u32
        sequence:       u32
        nextDecodeTime: u64
        hasPackets:     bool
        isEnded:        bool
    }
}

impl FragmentedWriter
{
    // Creates a fragmented H.264 MP4 file and writes its initialization movie.
    //
    // `avcConfig` is a complete AVCDecoderConfigurationRecord with four-byte NAL lengths and is
    // copied. `timescale` is positive ticks per second. Width and height must fit a visual sample
    // entry. Failure may leave a partial destination file.
    func create(fileName: string, width, height: s32, timescale: u32, avcConfig: const [..] u8)->FragmentedWriter fail
    {
        if width <= 0 or width > Swag.U16.Max or height <= 0 or height > Swag.U16.Max do
            fail BadParameterError{"fragmented MP4 needs dimensions in the range 1 to 65535"}
        if not timescale do
            fail BadParameterError{"fragmented MP4 needs a positive timescale"}
        try validateAvcConfig(avcConfig)

        with var result: #returntype
        {
            .sink      = try ByteSink.createFile(fileName)
            .width     = cast(u16, width)
            .height    = cast(u16, height)
            .timescale = timescale
            .config.resize(avcConfig.count)
            Memory.copy(.config.storage(), avcConfig.buffer, avcConfig.count)
        }

        try result.writeInitialization()
        try result.sink.flush()
        return result
    }

    // Appends and flushes one H.264 access unit as a complete fragment.
    //
    // `packet.bytes` contains four-byte-length-prefixed NAL units, not Annex B start codes.
    // Decode times must not overlap. The signed composition offset must fit 32 bits, and one
    // packet plus its media-data header must fit a compact MP4 box.
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
        try .writeFragment(packet, cast(s32, compositionOffset))
        try .sink.flush()
        .nextDecodeTime = packet.decodeTime + packet.duration
        .hasPackets     = true
        .sequence       += 1
    }

    // Flushes and closes the stream; repeated calls do nothing.
    mtd end() fail
    {
        if .isEnded do
            return
        .isEnded = true
        try .sink.close()
    }
}

private impl FragmentedWriter
{
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
        .writeMovieExtends()
        endBox(&.sink, movie)
    }

    #[Swag.Propagate]
    mtd writeMovieHeader() fail
    {
        let box = beginBox(&.sink, MovieHeaderId)
        writeFullBox(&.sink, 1, 0)
        writeU64(&.sink, 0)
        writeU64(&.sink, 0)
        writeU32(&.sink, .timescale)
        writeU64(&.sink, 0)
        writeU32(&.sink, 0x0001_0000)
        writeU16(&.sink, 0x0100)
        writeU16(&.sink, 0)
        writeU32(&.sink, 0)
        writeU32(&.sink, 0)
        writeIdentityMatrix(&.sink)
        for 6 do
            writeU32(&.sink, 0)
        writeU32(&.sink, 2)
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

        let dataInfo  = beginBox(&.sink, DataInfoId)
        let reference = beginBox(&.sink, DataReferenceId)
        writeFullBox(&.sink, 0, 0)
        writeU32(&.sink, 1)
        let url = beginBox(&.sink, DataEntryUrlId)
        writeFullBox(&.sink, 0, 1)
        endBox(&.sink, url)
        endBox(&.sink, reference)
        endBox(&.sink, dataInfo)

        .writeSampleTable()
        endBox(&.sink, mediaInfo)
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
        endBox(&.sink, table)
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
        endBox(&.sink, extends)
    }

    #[Swag.Propagate]
    mtd writeFragment(packet: EncodedPacket, compositionOffset: s32) fail
    {
        let fragment = beginBox(&.sink, MovieFragmentId)
        let header   = beginBox(&.sink, MovieFragmentHeaderId)
        writeFullBox(&.sink, 0, 0)
        writeU32(&.sink, .sequence + 1)
        endBox(&.sink, header)

        let track       = beginBox(&.sink, TrackFragmentId)
        let trackHeader = beginBox(&.sink, TrackFragmentHeaderId)
        writeFullBox(&.sink, 0, 0x020000)
        writeU32(&.sink, 1)
        endBox(&.sink, trackHeader)

        let decodeTime = beginBox(&.sink, DecodeTimeId)
        writeFullBox(&.sink, 1, 0)
        writeU64(&.sink, packet.decodeTime)
        endBox(&.sink, decodeTime)

        let run = beginBox(&.sink, TrackRunId)
        writeFullBox(&.sink, 1, 0x000F01)
        writeU32(&.sink, 1)
        let dataOffset = .sink.position()
        writeU32(&.sink, 0)
        writeU32(&.sink, packet.duration)
        writeU32(&.sink, cast(u32, packet.bytes.count))
        writeU32(&.sink, packet.isKeyFrame ? 0x02000000 : 0x01010000)
        writeU32(&.sink, cast #bit(u32, compositionOffset))
        endBox(&.sink, run)
        endBox(&.sink, track)
        endBox(&.sink, fragment)

        patchU32(&.sink, dataOffset, cast(u32, .sink.position() - fragment + 8))
        writeU32(&.sink, cast(u32, packet.bytes.count + 8))
        writeU32(&.sink, MediaDataId)
        .sink.write(packet.bytes)
    }
}
