//! Format: ISO Base Media File Format (MP4) fragmented writer.
//! Supported: H.264 video with optional AAC-LC audio, bounded packet groups per fragment, and interruption-safe completed fragments.
//! Not supported: Multiple audio tracks, timed metadata, encryption, and a final random-access index.
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
private const SoundMediaHeaderId    = fourCc('s'u32, 'm'u32, 'h'u32, 'd'u32)

private struct BufferedPacket
{
    size:              u32
    decodeTime:        u64
    duration:          u32
    compositionOffset: s32
    isKeyFrame:        bool
}

// Controls how H.264 packets are grouped into MP4 fragments.
struct FragmentedOptions
{
    public maxPacketsPerFragment: u32 = 1     // One packet per fragment by default; at most 1024.
    public maxBufferedBytes:      u32 = 4 * 1024 * 1024     // Buffered payload limit when grouping packets.
}

// Describes one AAC-LC sound track to add when the fragmented MP4 file is created.
//
// `decoderConfig` is a borrowed two-byte MPEG-4 AudioSpecificConfig. Its sample rate and channel
// configuration must match `sampleRate` and `channelCount`; the writer copies it before returning.
struct FragmentedAudioConfig
{
    public sampleRate:    u32              // Sound sample frames per second, matching the AAC configuration.
    public channelCount:  u16              // One or two channels.
    public decoderConfig: const [..] u8 = [] // Borrowed AAC-LC AudioSpecificConfig.
}

// Writes H.264 and optional AAC-LC access units to a fragmented MP4 file.
//
// The caller supplies an AVC decoder configuration (`avcC`) with four-byte NAL lengths and submits
// access units in decode order through [[Video.Mp4.FragmentedWriter.addPacket]]. By default every
// call writes and flushes one `moof`/`mdat` pair. [[Video.Mp4.FragmentedOptions]] can group packets
// within fixed byte and count limits; [[Video.Mp4.FragmentedWriter.flush]] completes a pending
// group. The first packet must be a key frame. Timestamps use the `timescale` given at creation.
//
// [[Video.Mp4.FragmentedWriter.createWithAudio]] adds one AAC-LC track. Audio packets are submitted
// separately and may be interleaved with video calls. The file has no final index; sequential
// playback and recovery of complete fragments work before
// [[Video.Mp4.FragmentedWriter.end]]. [[Video.Reader]] scans their headers and ignores a partial
// final fragment after at least one complete video fragment.
#[Swag.NoCopy]
struct FragmentedWriter
{
    private
    {
        sink:            ByteSink
        config:          Array'u8
        audioConfig:     Array'u8
        pendingPackets:  Array'BufferedPacket
        pendingData:     Array'u8
        options:         FragmentedOptions
        width:           u16
        height:          u16
        timescale:       u32
        audioSampleRate: u32
        audioChannels:   u16
        sequence:        u32
        nextDecodeTime:  u64
        nextAudioTime:   u64
        hasPackets:      bool
        hasAudioPackets: bool
        isEnded:         bool
    }
}

impl FragmentedWriter
{
    // Creates a fragmented H.264 MP4 file and writes its initialization movie.
    //
    // `avcConfig` is a complete AVCDecoderConfigurationRecord with four-byte NAL lengths and is
    // copied. `timescale` is positive ticks per second. Width and height must fit a visual sample
    // entry. `options` limits a group to at most 1024 packets and bounds buffered payload bytes.
    // A packet above the byte bound is written alone. Failure may leave a partial destination file.
    func create(fileName: string, width, height: s32, timescale: u32, avcConfig: const [..] u8, options: FragmentedOptions = {})->FragmentedWriter fail
        => try createConfigured(fileName, width, height, timescale, avcConfig, {}, options)

    // Creates a fragmented MP4 file with H.264 video and one AAC-LC sound track.
    //
    // Audio packets use `audio.sampleRate` ticks per second and carry 1024 samples each. The
    // `avcConfig` and `audio.decoderConfig` slices are copied. Submit sound through
    // [[Video.Mp4.FragmentedWriter.addAudioPacket]] after creation.
    func createWithAudio(fileName: string, width, height: s32, timescale: u32, avcConfig: const [..] u8, audio: FragmentedAudioConfig, options: FragmentedOptions = {})->FragmentedWriter fail
    {
        if not audio.decoderConfig.count do
            fail BadParameterError{"fragmented MP4 AAC configuration is empty"}
        return try createConfigured(fileName, width, height, timescale, avcConfig, audio, options)
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
            try .flush()

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
                try .flush()
        }

        .nextDecodeTime = packet.decodeTime + packet.duration
        .hasPackets     = true
    }

    // Appends one 1024-sample AAC-LC access unit to the configured sound track.
    //
    // `packet.bytes` is raw AAC payload without an ADTS header. Its decode and presentation times
    // are equal and use the audio sample rate as their timescale. Audio packets must be continuous;
    // the caller can interleave audio and video submissions in recording order. The key-frame flag
    // is ignored because every AAC-LC access unit is independently decodable.
    mtd addAudioPacket(packet: EncodedPacket) fail
    {
        if .isEnded or not .audioSampleRate do
            fail BadParameterError{"fragmented MP4 has no open audio track"}
        if not packet.bytes.count or
           packet.bytes.count > Swag.U32.Max - 8 or
           packet.duration != 1_024 or
           packet.presentationTime != packet.decodeTime or
           (.hasAudioPackets and packet.decodeTime != .nextAudioTime) do
            fail BadParameterError{"fragmented MP4 AAC packet size or timing is invalid"}
        if .sequence == Swag.U32.Max do
            fail OverflowError{"fragmented MP4 sequence number is exhausted"}
        if packet.decodeTime > cast(u64, Swag.S64.Max) - 1_024 do
            fail OverflowError{"fragmented MP4 AAC timestamp exceeds the supported range"}

        try .flush()
        let sample: [1] BufferedPacket = [{cast(u32, packet.bytes.count), packet.decodeTime,
                                           packet.duration, 0, true}]
        try .writeFragment(Swag.makeSlice(&sample[0], 1), packet.bytes, 2)
        try .sink.flush()
        .sequence        += 1
        .nextAudioTime   = packet.decodeTime + packet.duration
        .hasAudioPackets = true
    }

    // Writes and flushes the current group, making every packet in it recoverable.
    mtd flush() fail
    {
        if .isEnded do
            fail BadParameterError{"cannot flush an ended fragmented MP4"}
        if .pendingPackets.count
        {
            if .sequence == Swag.U32.Max do
                fail OverflowError{"fragmented MP4 sequence number is exhausted"}
            try .writeFragment(.pendingPackets.toSlice(), .pendingData.toSlice())
            .pendingPackets.clear()
            .pendingData.clear()
            .sequence += 1
        }

        try .sink.flush()
    }

    // Flushes and closes the stream; repeated calls do nothing.
    mtd end() fail
    {
        if .isEnded do
            return
        try .flush()
        .isEnded = true
        try .sink.close()
    }
}

private impl FragmentedWriter
{
    func createConfigured(fileName: string, width, height: s32, timescale: u32, avcConfig: const [..] u8, audio: FragmentedAudioConfig, options: FragmentedOptions)->FragmentedWriter fail
    {
        if width <= 0 or width > Swag.U16.Max or height <= 0 or height > Swag.U16.Max do
            fail BadParameterError{"fragmented MP4 needs dimensions in the range 1 to 65535"}
        if not timescale do
            fail BadParameterError{"fragmented MP4 needs a positive timescale"}
        if not options.maxPacketsPerFragment or
           options.maxPacketsPerFragment > 1_024 or
           not options.maxBufferedBytes or
           options.maxBufferedBytes > Swag.U32.Max - 8 do
            fail BadParameterError{"fragmented MP4 grouping limits are outside the supported range"}
        try validateAvcConfig(avcConfig)
        if audio.sampleRate or audio.channelCount or audio.decoderConfig.count do
            try validateAudioConfig(audio)

        with var result: #returntype
        {
            .sink            = try ByteSink.createFile(fileName)
            .width           = cast(u16, width)
            .height          = cast(u16, height)
            .timescale       = timescale
            .options         = options
            .audioSampleRate = audio.sampleRate
            .audioChannels   = audio.channelCount
            .config.add(avcConfig)
            .audioConfig.add(audio.decoderConfig)
        }

        try result.writeInitialization()
        try result.sink.flush()
        return result
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
        if .audioSampleRate do
            .writeAudioTrack()
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
        writeU32(&.sink, .audioSampleRate ? 3 : 2)
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
    mtd writeAudioTrack() fail
    {
        let track  = beginBox(&.sink, TrackId)
        let header = beginBox(&.sink, TrackHeaderId)
        writeFullBox(&.sink, 1, 7)
        writeU64(&.sink, 0)
        writeU64(&.sink, 0)
        writeU32(&.sink, 2)
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

        let media  = beginBox(&.sink, MediaId)
        let timing = beginBox(&.sink, MediaHeaderId)
        writeFullBox(&.sink, 1, 0)
        writeU64(&.sink, 0)
        writeU64(&.sink, 0)
        writeU32(&.sink, .audioSampleRate)
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
        .writeAudioSampleTable()
        endBox(&.sink, mediaInfo)
        endBox(&.sink, media)
        endBox(&.sink, track)
    }

    #[Swag.Propagate]
    mtd writeAudioSampleTable() fail
    {
        let table        = beginBox(&.sink, SampleTableId)
        let descriptions = beginBox(&.sink, SampleDescriptionId)
        writeFullBox(&.sink, 0, 0)
        writeU32(&.sink, 1)
        .writeAudioSampleEntry()
        endBox(&.sink, descriptions)
        .writeEmptySampleTables()
        endBox(&.sink, table)
    }

    #[Swag.Propagate]
    mtd writeAudioSampleEntry() fail
    {
        let entry = beginBox(&.sink, Mpeg4AudioId)
        for 6 do
            writeU8(&.sink, 0)
        writeU16(&.sink, 1)
        writeU16(&.sink, 0)
        writeU16(&.sink, 0)
        writeU32(&.sink, 0)
        writeU16(&.sink, .audioChannels)
        writeU16(&.sink, 16)
        writeU16(&.sink, 0)
        writeU16(&.sink, 0)
        writeU32(&.sink, .audioSampleRate << 16)

        let descriptor = beginBox(&.sink, ElementaryStreamId)
        writeFullBox(&.sink, 0, 0)

        // ES_ID 2, MPEG-4 Audio decoder configuration, unspecified bitrates, then the ASC.
        const Prefix: [22] u8 = [0x03, 0x19, 0, 2, 0, 0x04, 0x11, 0x40, 0x15, 0, 0, 0,
                                 0, 0, 0, 0, 0, 0, 0, 0, 0x05, 0x02]
        .sink.write(Swag.makeSlice(&Prefix[0], Prefix.count))
        .sink.write(.audioConfig.toSlice())
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
        if .audioSampleRate
        {
            let audio = beginBox(&.sink, TrackExtendsId)
            writeFullBox(&.sink, 0, 0)
            writeU32(&.sink, 2)
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
    }
}
