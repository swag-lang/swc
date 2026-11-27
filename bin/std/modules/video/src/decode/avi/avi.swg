//! Format: Audio Video Interleave (AVI/RIFF) decoder component.
//! Supported: Motion JPEG, MPEG-4 Part 2, uncompressed RGB555 16-bit or RGB 24-/32-bit video, integer PCM, and MPEG Layer III audio with complete frames in each AVI chunk. Reads classic idx1 and OpenDML frame indexes across RIFF AVIX continuations.
//! Not supported: OpenDML field-level indexes and video codecs other than Motion JPEG, MPEG-4 Part 2, or uncompressed RGB.
//! Role: This file owns RIFF chunks, stream indexes, frame/audio packet lookup, and top-level decode.
//
#global namespace Avi

using Core, Core.Errors, Pixel, Audio

// Builds the 32-bit value a RIFF file stores for a four-character identifier.
//
// Identifiers are compared as little-endian words rather than as text, so walking a container
// costs one integer comparison per chunk.
#[Swag.ConstExpr]
func fourCc(a, b, c, d: u32) => a | (b << 8) | (c << 16) | (d << 24)

// Identifiers of the container itself.
const RiffId         = fourCc('R'_u32, 'I'_u32, 'F'_u32, 'F'_u32)
const AviId          = fourCc('A'_u32, 'V'_u32, 'I'_u32, ' '_u32)
const ListId         = fourCc('L'_u32, 'I'_u32, 'S'_u32, 'T'_u32)
const HeaderListId   = fourCc('h'_u32, 'd'_u32, 'r'_u32, 'l'_u32)
const StreamListId   = fourCc('s'_u32, 't'_u32, 'r'_u32, 'l'_u32)
const FrameListId    = fourCc('m'_u32, 'o'_u32, 'v'_u32, 'i'_u32)
const MainHeaderId   = fourCc('a'_u32, 'v'_u32, 'i'_u32, 'h'_u32)
const StreamHeaderId = fourCc('s'_u32, 't'_u32, 'r'_u32, 'h'_u32)
const StreamFormatId = fourCc('s'_u32, 't'_u32, 'r'_u32, 'f'_u32)
const IndexId        = fourCc('i'_u32, 'd'_u32, 'x'_u32, '1'_u32)
const VideoStreamId  = fourCc('v'_u32, 'i'_u32, 'd'_u32, 's'_u32)
const AudioStreamId  = fourCc('a'_u32, 'u'_u32, 'd'_u32, 's'_u32)

const AvixId          = fourCc('A'_u32, 'V'_u32, 'I'_u32, 'X'_u32)
const OpenDmlListId   = fourCc('o'_u32, 'd'_u32, 'm'_u32, 'l'_u32)
const OpenDmlHeaderId = fourCc('d'_u32, 'm'_u32, 'l'_u32, 'h'_u32)
const OpenDmlIndexId  = fourCc('i'_u32, 'n'_u32, 'd'_u32, 'x'_u32)
const IndexOfIndexes  = 0_u8
const IndexOfChunks   = 1_u8
private const OpenDmlNonKeyFlag = 0x8000_0000_u32

// WAVE format tag used by uncompressed integer PCM streams.
private const PcmFormatTag = 1_u16
private const Mp3FormatTag = 0x55_u16

// Identifier of the list an OpenDML file groups its frames into.
private const RecordListId = fourCc('r'_u32, 'e'_u32, 'c'_u32, ' '_u32)

// Codec identifiers whose frames are complete JPEG images.
//
// The four spellings all mean Motion JPEG; which one a file carries says who wrote it, not what
// its frames contain. The first one is what an encoded stream declares.
const MotionJpegIds: [4] u32 = [
    fourCc('M'_u32, 'J'_u32, 'P'_u32, 'G'_u32),
    fourCc('m'_u32, 'j'_u32, 'p'_u32, 'g'_u32),
    fourCc('J'_u32, 'P'_u32, 'E'_u32, 'G'_u32),
    fourCc('j'_u32, 'p'_u32, 'e'_u32, 'g'_u32)]

// Codec identifiers whose frames are uncompressed bitmap rows.
//
// `BI_RGB` is the value the bitmap header itself defines, and is what ffmpeg writes; the three
// tags are what other writers put there instead when they want the field to read as a name.
private const UncompressedIds: [4] u32 = [
    cast(u32, Bmp.BI_RGB),
    fourCc('D'_u32, 'I'_u32, 'B'_u32, ' '_u32),
    fourCc('R'_u32, 'A'_u32, 'W'_u32, ' '_u32),
    fourCc('R'_u32, 'G'_u32, 'B'_u32, ' '_u32)]

// Identifier and size of a chunk header, and of one entry of the index.
const FourCcSize      = 4_u64
const ChunkHeaderSize = 8_u64
const IndexEntrySize  = 16_u64

// Extension the frames are handed to the image codecs under.
//
// A Motion JPEG frame is a complete JPEG image, so the picture codec is the Pixel one, selected
// the way every other caller selects it.

const JpegName = ".jpg"

// Highest stream ordinal a frame chunk identifier can name, since it spells it with two digits.
private const MaxStreamIndex = 99_u32

// Frame index meaning that the decoder sits nowhere in particular.
//
// A read that fails part way through a frame leaves the position meaningless, so it is what the
// decoder holds until a seek reestablishes where it is.
private const NoFrameIndex = Swag.U64.Max

// Layout of the `avih` chunk, which describes the file rather than one of its streams.
#[Swag.Pack(1)]
struct MainHeader
{
    microSecPerFrame:    u32     // Nominal frame duration, in microseconds.
    maxBytesPerSec:      u32     // Average data rate of the whole file.
    paddingGranularity:  u32     // Alignment the writer padded chunks to, or zero.
    flags:               u32     // Container flags, such as `MainHasIndex`.
    totalFrames:         u32     // Number of frames in the first stream.
    initialFrames:       u32     // Frames of lead-in before the interleaved streams start.
    streams:             u32     // Number of streams the file declares.
    suggestedBufferSize: u32     // Size of the largest chunk, in bytes.
    width:               u32     // Frame width, in pixels.
    height:              u32     // Frame height, in pixels.
    reserved:            [4] u32
}

#assert(#sizeof(MainHeader) == 56)

// Layout of a `strh` chunk, which describes one stream of the file.
#[Swag.Pack(1)]
struct StreamHeader
{
    kind:                u32     // What the stream carries, `vids` for a picture stream.
    handler:             u32     // Codec identifier suggested by the writer.
    flags:               u32
    priority:            u16
    language:            u16
    initialFrames:       u32
    scale:               u32     // Denominator of the stream rate.
    rate:                u32     // Numerator of the stream rate, in `scale` units per second.
    start:               u32
    length:              u32     // Number of samples, which is the number of frames here.
    suggestedBufferSize: u32     // Size of the largest chunk of this stream, in bytes.
    quality:             u32
    sampleSize:          u32     // Fixed sample size, or zero when samples vary in length.
    frameLeft:           s16
    frameTop:            s16
    frameRight:          s16
    frameBottom:         s16
}

#assert(#sizeof(StreamHeader) == 56)

// Layout of the base WAVE format structure carried by an audio `strf` chunk.
#[Swag.Pack(1)]
private struct AudioFormat
{
    formatTag:     u16
    channels:      u16
    sampleRate:    u32
    averageBytes:  u32
    blockAlign:    u16
    bitsPerSample: u16
}

#assert(#sizeof(AudioFormat) == 16)

// One chunk header: what it identifies, where its payload lies, and where the next one starts.
private struct Chunk
{
    id:   u32
    size: u64
    data: u64
    next: u64
}

// The range of chunk headers and payloads in one `movi` list.
private struct MovieList
{
    start, end: u64
}

// Standard indexes and superindexes both start with these 24 bytes.
#[Swag.Pack(1)]
struct OpenDmlIndexHeader
{
    entryWords: u16
    subtype:    u8
    kind:       u8
    count:      u32
    chunkId:    u32
    base:       u64
    reserved:   u32
}

#assert(#sizeof(OpenDmlIndexHeader) == 24)

#[Swag.Pack(1)]
struct OpenDmlIndexReference
{
    offset:   u64
    size:     u32
    duration: u32
}

#assert(#sizeof(OpenDmlIndexReference) == 16)

// Indexed movie chunks advance in file order across the RIFF continuations.
private struct OpenDmlIndexCursor
{
    movie: u64
    next:  u64
}

// One video slot and the payload used to decode it.
private struct FrameEntry
{
    offset: u64      // Offset of the payload in the stream, in bytes.
    size:   u32      // RIFF chunk length; zero when a coded slot repeats or starts with no picture.
    isSync: bool     // Whether the frame starts a decode that depends on nothing before it.
}

#assert(#sizeof(FrameEntry) == 16)

// One on-disk record of the idx1 table. RIFF only aligns chunks to two bytes.
#[Swag.Pack(1)]
struct IndexRecord
{
    id:     u32
    flags:  u32
    offset: u32
    size:   u32
}

#assert(#sizeof(IndexRecord) == IndexEntrySize)

// Index flag a frame carries when it depends on nothing before it.
const IndexKeyFrameFlag = 0x0000_0010_u32

// One playable audio stream found in the AVI header.
private struct AudioTrack
{
    format:      AudioFormat
    streamIndex: u32
}

// Packet locations for a playable audio stream, gathered in movie-chunk order.
private struct AudioPackets
{
    format:  AudioFormat
    packets: Array!{SoundPacket}
}

// What walking the container found, before it is turned into a stream description.
private struct Layout
{
    main:              MainHeader             // Contents of the `avih` chunk.
    stream:            StreamHeader           // Stream header of the first video stream.
    format:            Bmp.Header             // Bitmap header describing the frames of that stream.
    movieLists:        Array!{MovieList}      // Every `movi` list in file order.
    openDmlIndex:      Chunk                  // The video stream's `indx` chunk, if any.
    openDmlFrameCount: u32                    // Total video frames in the OpenDML header.
    indexStart:        u64                    // Offset of the `idx1` payload, or zero when the file has none.
    indexSize:         u64                    // Length of the `idx1` payload, in bytes.
    streamIndex:       u32                    // Ordinal of the video stream among the streams of the file.
    audioTracks:       Array!{AudioTrack}     // Playable sound streams, in declaration order.
    hasMain:           bool
    hasStream:         bool
}

// Returns the identifier a frame chunk of stream `index` carries.
//
// The first two characters spell the stream ordinal and the last two say what the chunk holds:
// `db` for uncompressed bits and `dc` for compressed ones. Writers disagree on which one an
// uncompressed stream deserves, so a decoder accepts both.
#[Swag.ConstExpr]
func frameChunkId(index: u32, a, b: u32)->u32 => fourCc('0'_u32 + index / 10, '0'_u32 + index % 10, a, b)

// Reads one chunk header and reports where its payload and its successor start.
private func readChunk(source: *ByteSource, end: u64)->Chunk fail
{
    if source.position() > end or ChunkHeaderSize > end - source.position()
    {
        fail InvalidFormatError{"AVI chunk header runs past the end of its list"}
    }

    let header = try source.readNative!{[2] u32}()
    var result: #returntype
    result.id   = Math.littleEndianToNative(header[0])
    result.size = cast(u64, Math.littleEndianToNative(header[1]))
    result.data = source.position()
    if result.data > end or result.size > end - result.data
    {
        fail InvalidFormatError{"AVI chunk runs past the end of the stream"}
    }

    // RIFF pads an odd payload with one byte that belongs to neither chunk.
    let payloadEnd = result.data + result.size
    result.next = payloadEnd + (payloadEnd < end ? result.size & 1 : 0)
    return result
}

// Returns `id` as the four characters a file stores, for an error message.
//
// A byte that is not printable becomes a question mark: the identifier of a stream this decoder
// refuses is exactly the field most likely to hold something that is not text at all.
private func describeId(id: u32)->String
{
    var result: #returntype
    for shift in 4
    {
        let value = cast(u8, ((id >> cast(u32, (shift * 8))) & 0xFF))
        result.append(value >= 0x20 and value < 0x7F ? cast(rune, value) : '?'_rune)
    }

    return result
}

private impl Layout
{
    // Collects the movie lists of the initial AVI RIFF and any OpenDML AVIX continuations.
    mtd parse(source: *ByteSource) fail
    {
        let tag = try source.readLittleEndian!{u32}()
        if tag != RiffId
        {
            fail InvalidFormatError{"AVI stream is not a RIFF file"}
        }

        // An interrupted classic capture can leave the RIFF length unset or overstated.
        let fileEnd  = source.size()
        let declared = cast(u64, (try source.readLittleEndian!{u32}()))
        let end      = declared < FourCcSize ? fileEnd : Math.min(fileEnd, source.position() + declared)
        let form     = try source.readLittleEndian!{u32}()
        if form != AviId
        {
            fail InvalidFormatError{"RIFF stream does not hold an AVI file"}
        }

        // The file bounds a chunk in the first RIFF because classic writers sometimes leave
        // the form length a few bytes short even though the final chunk is complete.
        try .parseRiff(source, end, fileEnd, initial: true)
        let next = end + (end < fileEnd ? declared & 1 : 0)
        if source.position() > next
        {
            return
        }

        try source.seek(next)
        while source.remaining() >= ChunkHeaderSize + FourCcSize
        {
            let continuation = try source.readLittleEndian!{u32}()
            if continuation != RiffId
            {
                return
            }

            let size = cast(u64, (try source.readLittleEndian!{u32}()))
            let kind = try source.readLittleEndian!{u32}()
            if kind != AvixId
            {
                return
            }

            if size < FourCcSize or size - FourCcSize > source.remaining()
            {
                fail InvalidFormatError{"AVI continuation runs past the end of the stream"}
            }

            let segmentEnd = source.position() + (size - FourCcSize)
            try .parseRiff(source, segmentEnd, segmentEnd, initial: false)
            try source.seek(segmentEnd + (segmentEnd < fileEnd ? size & 1 : 0))
        }
    }

    // Reads top-level chunks without consuming frame data.
    mtd parseRiff(source: *ByteSource, end, chunkBound: u64, initial: bool) fail
    {
        while source.position() <= end and ChunkHeaderSize <= end - source.position()
        {
            let chunk = try readChunk(source, chunkBound)
            if initial and chunk.id == IndexId
            {
                .indexStart = chunk.data
                .indexSize  = chunk.size
            }
            else if chunk.id == ListId and chunk.size >= FourCcSize
            {
                switch try source.readLittleEndian!{u32}()
                {
                case HeaderListId where initial: try .parseHeaderList(source, chunk.data + chunk.size)
                case FrameListId: .movieLists.add(MovieList{chunk.data + FourCcSize, chunk.data + chunk.size})
                }
            }

            try source.seek(chunk.next)
        }
    }

    // Reads the `hdrl` list: the header of the file, and the streams it declares.
    mtd parseHeaderList(source: *ByteSource, end: u64) fail
    {
        var index = 0_u32
        while source.position() + ChunkHeaderSize <= end
        {
            let chunk = try readChunk(source, end)
            if chunk.id == MainHeaderId and chunk.size >= #sizeof(MainHeader)
            {
                .main    = try source.readNative!{MainHeader}()
                .hasMain = true
            }
            else if chunk.id == ListId and chunk.size >= FourCcSize
            {
                switch try source.readLittleEndian!{u32}()
                {
                case StreamListId:
                    try .parseStreamList(source, chunk.data + chunk.size, index)
                    index += 1

                case OpenDmlListId:
                    try .parseOpenDmlHeader(source, chunk.data + chunk.size)
                }
            }

            try source.seek(chunk.next)
        }
    }

    // Reads the total frame count from the OpenDML header, including continuations.
    mtd parseOpenDmlHeader(source: *ByteSource, end: u64) fail
    {
        while source.position() <= end and ChunkHeaderSize <= end - source.position()
        {
            let chunk = try readChunk(source, end)
            if chunk.id == OpenDmlHeaderId and chunk.size >= 4
            {
                .openDmlFrameCount = try source.readLittleEndian!{u32}()
            }

            try source.seek(chunk.next)
        }
    }

    // Reads one `strl` list, keeping the first video stream and every playable audio stream.
    mtd parseStreamList(source: *ByteSource, end: u64, index: u32) fail
    {
        var header:     StreamHeader
        var indexChunk: Chunk
        var hasHeader:  bool
        var hasAudio:   bool

        while source.position() + ChunkHeaderSize <= end
        {
            let chunk = try readChunk(source, end)
            if chunk.id == StreamHeaderId and chunk.size >= #sizeof(StreamHeader)
            {
                header    = try source.readNative!{StreamHeader}()
                hasHeader = true
            }
            else if chunk.id == OpenDmlIndexId
            {
                indexChunk = chunk
            }
            else if chunk.id == StreamFormatId and
                    hasHeader and
                    not .hasStream and
                    header.kind == VideoStreamId
            {
                if chunk.size < #sizeof(Bmp.Header)
                {
                    fail UnsupportedFormatError{"AVI video stream is not described by a bitmap header"}
                }

                .format      = try source.readNative!{Bmp.Header}()
                .stream      = header
                .streamIndex = index
                .hasStream   = true
            }
            else if chunk.id == StreamFormatId and
                    hasHeader and
                    not hasAudio and
                    header.kind == AudioStreamId and
                    chunk.size >= #sizeof(AudioFormat)
            {
                let format = try source.readNative!{AudioFormat}()
                if format.isPlayable()
                {
                    .audioTracks.add(AudioTrack{format, index})
                    hasAudio = true
                }
            }

            try source.seek(chunk.next)
        }

        if .hasStream and .streamIndex == index
        {
            .openDmlIndex = indexChunk
        }
    }

    // Returns the exact rate of the video stream.
    //
    // The stream header states it as a ratio and is the accurate answer; the header of the file
    // rounds it to whole microseconds, and is what a file without a stream rate leaves.
    mtd const frameRate()->FrameRate fail
    {
        if .stream.scale and .stream.rate
        {
            return try FrameRate.create(.stream.rate, .stream.scale)
        }

        if .main.microSecPerFrame
        {
            return try FrameRate.create(1_000_000, .main.microSecPerFrame)
        }

        fail InvalidFormatError{"AVI stream declares no frame rate"}
    }
}

private impl AudioFormat
{
    // Reports whether std/audio can stream this interleaved AVI format without conversion.
    mtd const isPlayable()->bool
    {
        if not .channels or not .sampleRate
        {
            return false
        }

        if .formatTag == Mp3FormatTag
        {
            return .channels <= 2
        }

        if .formatTag != PcmFormatTag
        {
            return false
        }

        if .bitsPerSample != 8 and
           .bitsPerSample != 16 and
           .bitsPerSample != 24 and
           .bitsPerSample != 32
        {
            return false
        }

        let bytesPerFrame = cast(u32, .channels) * cast(u32, (.bitsPerSample / 8))
        return bytesPerFrame <= Swag.U16.Max and .blockAlign == bytesPerFrame
    }

    // Returns the std/audio encoding matching this validated PCM format.
    mtd const encoding()->SoundFileEncoding
    {
        switch .bitsPerSample
        {
        case 8:  return .Pcm8
        case 16: return .Pcm16
        case 24: return .Pcm24
        case 32: return .Pcm32
        }

        return .Unknown
    }
}

// Reads AVI files one frame at a time.
//
// The container says where every frame lies, either in its own index or in the list holding the
// frames, so opening a stream reads its headers and its frame table and never a picture. That
// table is what makes a seek free, and it is the only part of the file the decoder holds: sixteen
// bytes per frame, whatever a frame itself weighs.
//
// Frames are Motion JPEG, planes of a coded picture stream, or uncompressed bitmap rows. A Motion
// JPEG frame is a complete JPEG image and is decoded by the Pixel image codec, so both modules read
// the same pictures. A coded stream is driven by the same picture decoders the other containers
// use. PCM sound chunks remain in file order and stream through their own std/audio cursor.
struct Decoder
{
    internal
    {
        info:          StreamInfo             // What the container headers described.
        frames:        Array!{FrameEntry}     // Where every frame of the video stream lies.
        payload:       Array!{u8}             // Scratch storage of one encoded frame.
        soundTracks:   Array!{SoundFile}      // Tracks streamed from the AVI file.
        bytesPerPixel: u64                    // Source bytes of one pixel of an uncompressed frame.
        rowBytes:      u64                    // Padded length of one row of an uncompressed frame.
        nextIndex:     u64                    // Index of the frame the decoder is positioned on.
        pictures:      Mpeg4.Mpeg4Stream      // Coded pictures, when frames are a coded stream.
        isTopDown:     bool                   // Whether uncompressed rows start with the top one.
        isJpeg:        bool                   // Whether frames are complete JPEG images.
        isCoded:       bool                   // Whether frames are planes of a coded picture stream.
        pictureOnly:   bool                   // Whether the reader opens without sound tracks.
    }
}

impl IDecoder for Decoder
{
    mtd impl format()->StreamFormat => {"AVI - Audio Video Interleave", ".avi"}

    mtd impl open(source: *ByteSource)->StreamInfo fail
    {
        var layout: Layout
        try layout.parse(source)
        if not layout.hasMain
        {
            fail InvalidFormatError{"AVI file has no main header"}
        }

        if not layout.hasStream
        {
            fail UnsupportedFormatError{"AVI file has no video stream"}
        }

        if layout.movieLists.isEmpty()
        {
            fail InvalidFormatError{"AVI file has no frame list"}
        }

        try .describeFrames(&layout)
        try .buildFrameTable(source, &layout)
        if .frames.isEmpty()
        {
            fail InvalidFormatError{"AVI video stream has no frame"}
        }

        .info.frameCount = .frames.count
        .nextIndex       = 0
        if .isCoded
        {
            try .openPictures(source)
            .frames.reserve(0)
        }

        if not .pictureOnly
        {
            try .buildSoundTracks(source, &layout)
        }

        return .info
    }

    mtd impl syncFrameAt(index: u64)->u64 => .isCoded ? .pictures.syncRankAt(index) : index

    mtd impl seekFrame(_: *ByteSource, index: u64) fail
    {
        // The container gave every frame position away when the stream was opened, so seeking is
        // arithmetic on the frame table and never touches the source.
        if index >= .info.frameCount
        {
            fail BadParameterError{"AVI frame index exceeds the stream frame count"}
        }

        .nextIndex = index
    }

    mtd impl decodeFrame(source: *ByteSource, target: *Image) fail
    {
        let current = .nextIndex
        if current >= .info.frameCount
        {
            fail InvalidFormatError{"AVI stream has no frame at this position"}
        }

        if .isCoded
        {
            .nextIndex = NoFrameIndex
            .pictures.seekTo(current)
            try .pictures.decodeNext(source, target)
            .nextIndex = current + 1
            return
        }

        .nextIndex = NoFrameIndex
        let entry = .frames[current]
        let size  = cast(u64, entry.size)
        if not size
        {
            fail InvalidFormatError{"AVI stream starts with a frame that carries no picture"}
        }

        if entry.offset > source.size() or size > source.size() - entry.offset
        {
            fail InvalidFormatError{"AVI frame payload is truncated"}
        }

        try source.seek(entry.offset)
        if .isJpeg
        {
            // The input buffer already contains the complete encoded sample.
            let borrowed = not source.path().count
            var payload: const [..] u8
            if borrowed
            {
                payload = (try source.peek(size))[until size]
            }
            else
            {
                if .payload.count != size
                {
                    .payload.resize(size)
                }

                try source.readExact(.payload.toSlice())
                payload = .payload.toSlice()
            }

            try .decodeJpegFrame(payload, target)
            if borrowed
            {
                try source.skip(size)
            }
        }
        else
        {
            try .decodeBitmapFrame(source, size, target)
        }

        .nextIndex = current + 1
    }
}

impl ISyncPictureDecoder for Decoder
{
    mtd impl decodeSyncPicture(source: *ByteSource, rank: u64, target: *Image)->bool fail
    {
        if not .isCoded
        {
            return false
        }

        return try .pictures.decodeSyncPicture(source, rank, target)
    }
}

impl IPlanarDecoder for Decoder
{
    mtd impl hasPlanarFrames()->bool => .isCoded

    mtd impl decodeFramePlanes(source: *ByteSource, target: *PlanarFrame) fail
    {
        if not .isCoded
        {
            fail UnsupportedFormatError{"AVI frames of this codec are not coded planes"}
        }

        let current = .nextIndex
        if current >= .info.frameCount
        {
            fail InvalidFormatError{"AVI stream has no frame at this position"}
        }

        .nextIndex = NoFrameIndex
        .pictures.seekTo(current)
        try .pictures.decodeNextPlanes(source, target)
        .nextIndex = current + 1
    }
}

impl IPictureOnlyDecoder for Decoder
{
    mtd impl skipOtherTracks()
    {
        .pictureOnly = true
    }
}

impl IAudioDecoder for Decoder
{
    mtd impl audioTrackCount()->u32 => cast(u32, .soundTracks.count)

    mtd impl audioTrack(index: u32)->const *SoundFile?
    {
        if index >= .soundTracks.count
        {
            return null
        }

        return &.soundTracks[index]
    }
}

private impl Decoder
{
    // Exposes each supported stream as a sparse, file-backed audio source.
    mtd buildSoundTracks(source: *ByteSource, layout: const *Layout) fail
    {
        let path = source.path()
        if not path.count or layout.audioTracks.isEmpty()
        {
            return
        }

        // A zero slot means the file did not declare a supported stream at this ordinal.
        var trackForStream: [MaxStreamIndex + 1] u8
        var tracks:         Array!{AudioPackets}
        for track in layout.audioTracks where track.streamIndex <= MaxStreamIndex
        {
            tracks.add(AudioPackets{format: track.format})
            trackForStream[track.streamIndex] = cast(u8, tracks.count)
        }

        if tracks.isEmpty()
        {
            return
        }

        try .walkSoundPackets(source, layout, trackForStream, &tracks)
        .soundTracks.reserve(tracks.count)
        for &track in tracks where not track.packets.isEmpty()
        {
            let packets = track.packets.toSlice()
            if track.format.formatTag == Mp3FormatTag
            {
                var frames = 0_u64
                for packet in packets
                {
                    frames += packet.sampleFrameCount
                }

                let sound = try SoundFile.openPacketStream(path, .Mp3, track.format.sampleRate, track.format.channels, frames, packets, [])
                .soundTracks.add(#move sound)
            }
            else
            {
                let sound = try SoundFile.openPcmPacketStream(path, track.format.encoding(), track.format.sampleRate, track.format.channels, packets)
                .soundTracks.add(#move sound)
            }

            track.packets.free()
        }
    }

    // Walks each movie list once and routes each packet to its declared audio stream.
    mtd walkSoundPackets(source: *ByteSource, layout: const *Layout, trackForStream: const [..] u8, tracks: *Array!{AudioPackets}) fail
    {
        #[Swag.Inline]
        func trackIndex(id: u32, trackForStream: const [..] u8)->u8
        {
            if id >> 16 != ('w'_u32 | ('b'_u32 << 8))
            {
                return 0
            }

            let tens = id & 0xFF
            let ones = (id >> 8) & 0xFF
            if tens < '0' or tens > '9' or ones < '0' or ones > '9'
            {
                return 0
            }

            return trackForStream[(tens - '0'_u32) * 10 + (ones - '0'_u32)]
        }

        func addChunk(source: *ByteSource, chunk: const *Chunk, format: const *AudioFormat, packets: *Array!{SoundPacket}) fail
        {
            if not chunk.size
            {
                return
            }

            if format.formatTag == PcmFormatTag
            {
                if chunk.size % format.blockAlign
                {
                    fail InvalidFormatError{"AVI PCM chunk does not hold complete sample frames"}
                }

                packets.add(SoundPacket{chunk.data, cast(u32, chunk.size), cast(u32, chunk.size / format.blockAlign)})
                return
            }

            var position = chunk.data
            let end      = chunk.data + chunk.size
            while position < end
            {
                if end - position < 4
                {
                    fail InvalidFormatError{"AVI Layer III chunk ends inside a frame header"}
                }

                try source.seek(position)
                let frame = try Audio.mp3FrameInfo(try source.peek(4))
                if frame.byteSize > end - position
                {
                    fail InvalidFormatError{"AVI Layer III chunk ends inside a frame"}
                }

                if frame.sampleRate != format.sampleRate or frame.channels != format.channels
                {
                    fail InvalidFormatError{"AVI Layer III frame differs from the track sample rate or channel count"}
                }

                packets.add(SoundPacket{position, frame.byteSize, frame.sampleFrames})
                position += frame.byteSize
            }
        }

        for movie in layout.movieLists
        {
            var position = movie.start
            while position <= movie.end and ChunkHeaderSize <= movie.end - position
            {
                try source.seek(position)
                let chunk = try readChunk(source, movie.end)
                let index = trackIndex(chunk.id, trackForStream)
                if index
                {
                    let track = &tracks[index - 1]
                    try addChunk(source, &chunk, &track.format, &track.packets)
                }
                else if chunk.id == ListId and
                        chunk.size >= FourCcSize and
                        (try source.readLittleEndian!{u32}()) == RecordListId
                {
                    let groupEnd       = chunk.data + chunk.size
                    var nestedPosition = chunk.data + FourCcSize
                    while nestedPosition <= groupEnd and ChunkHeaderSize <= groupEnd - nestedPosition
                    {
                        try source.seek(nestedPosition)
                        let nested      = try readChunk(source, groupEnd)
                        let nestedIndex = trackIndex(nested.id, trackForStream)
                        if nestedIndex
                        {
                            let track = &tracks[nestedIndex - 1]
                            try addChunk(source, &nested, &track.format, &track.packets)
                        }

                        nestedPosition = nested.next
                    }

                    if nestedPosition != groupEnd
                    {
                        fail InvalidFormatError{"AVI record list ends with a partial chunk"}
                    }
                }

                position = chunk.next
            }
        }
    }

    // Turns the bitmap header of the video stream into everything decoding a frame needs.
    mtd describeFrames(layout: const *Layout) fail
    {
        let width  = layout.format.biWidth
        let height = Math.abs(layout.format.biHeight)
        if width <= 0 or height <= 0
        {
            fail InvalidFormatError{"AVI frame dimensions need positive values"}
        }

        if width > Swag.S32.Max / 4 or height > Swag.S32.Max / 4
        {
            fail UnsupportedFormatError{"AVI frame dimensions exceed Pixel image storage"}
        }

        .info.width     = width
        .info.height    = height
        .info.frameRate = try layout.frameRate()

        let compression = layout.format.biCompression
        if Slice.contains(MotionJpegIds, compression)
        {
            .isJpeg         = true
            .info.codecName = "Motion JPEG"
            return
        }

        if Video.isMpeg4FourCc(compression)
        {
            .isCoded        = true
            .info.codecName = "MPEG-4 Part 2"
            return
        }

        if not Slice.contains(UncompressedIds, compression)
        {
            fail UnsupportedFormatError{Errors.mkString(Format.toString("video decoder does not support the AVI '%' video codec", describeId(compression)))}
        }

        let bitCount = layout.format.biBitCount
        let isRgb555 = bitCount == 16 and compression == Bmp.BI_RGB
        .info.codecName = "Uncompressed RGB"
        if bitCount != 24 and bitCount != 32 and not isRgb555
        {
            fail UnsupportedFormatError{Errors.mkString(Format.toString("video decoder does not support uncompressed AVI frames of % bits per pixel", bitCount))}
        }

        // Uncompressed frames follow the bitmap rules: rows are padded to a multiple of four
        // bytes, and only a negative height stores the top row first.
        .bytesPerPixel = cast(u64, bitCount) / 8
        .rowBytes      = (cast(u64, width) * cast(u64, bitCount) + 31) / 32 * 4
        .isTopDown     = layout.format.biHeight < 0
    }

    // Records where every frame of the video stream lies.
    mtd buildFrameTable(source: *ByteSource, layout: const *Layout) fail
    {
        if layout.streamIndex > MaxStreamIndex
        {
            fail UnsupportedFormatError{"AVI file declares more streams than the container can name"}
        }

        let dataId       = frameChunkId(layout.streamIndex, 'd'_u32, 'b'_u32)
        let compressedId = frameChunkId(layout.streamIndex, 'd'_u32, 'c'_u32)
        if .readOpenDmlIndex(source, layout, dataId, compressedId) or
           (layout.movieLists.count == 1 and .readIndex(source, layout, dataId, compressedId))
        {
            return
        }

        try .walkFrames(source, layout, dataId, compressedId)
    }

    // Intra-only formats can reuse the previous payload directly when a slot is empty.
    // Inter-coded streams keep empty slots so the picture stream can apply presentation order.
    #[Swag.Inline]
    mtd appendFrame(offset, size: u64, isSync: bool)
    {
        if size or .isCoded or .frames.isEmpty()
        {
            .frames.add(FrameEntry{offset, cast(u32, size), isSync})
            return
        }

        let previous = .frames.back()
        .frames.add(FrameEntry{previous.offset, previous.size, isSync})
    }

    // Tries the OpenDML frame index before scanning movie lists.
    mtd readOpenDmlIndex(source: *ByteSource, layout: const *Layout, dataId, compressedId: u32)->bool
    {
        let declared = layout.openDmlFrameCount ? layout.openDmlFrameCount : layout.stream.length
        if not layout.openDmlIndex.size or not declared
        {
            return false
        }

        var indexError: Swag.Error
        catch .readOpenDmlIndexEntries(source, layout, dataId, compressedId) as indexError
        if indexError.value() == null and .frames.count == declared
        {
            return true
        }

        .frames.clear()
        return false
    }

    mtd readOpenDmlIndexEntries(source: *ByteSource, layout: const *Layout, dataId, compressedId: u32) fail
    {
        let root   = layout.openDmlIndex
        let header = try readOpenDmlIndexHeader(source, root, dataId, compressedId)
        var cursor: OpenDmlIndexCursor
        if header.kind == IndexOfChunks
        {
            try .readOpenDmlFrameEntries(source, layout, header, &cursor)
        }
        else
        {
            let indexId = fourCc('i'_u32, 'x'_u32, '0'_u32 + layout.streamIndex / 10, '0'_u32 + layout.streamIndex % 10)
            let end     = source.size()
            for header.count
            {
                let reference = try source.readNative!{OpenDmlIndexReference}()
                let resume    = source.position()
                let offset    = Math.littleEndianToNative(reference.offset)
                let size      = cast(u64, Math.littleEndianToNative(reference.size))
                if offset > end or size > end - offset
                {
                    fail InvalidFormatError{"AVI OpenDML index points past the end of the stream"}
                }

                try source.seek(offset)
                let child = try readChunk(source, offset + size)
                if child.id != indexId or child.size + ChunkHeaderSize != size
                {
                    fail InvalidFormatError{"AVI OpenDML index points at the wrong chunk"}
                }

                let table = try readOpenDmlIndexHeader(source, child, dataId, compressedId)
                if table.kind != IndexOfChunks
                {
                    fail InvalidFormatError{"AVI OpenDML index does not point at a frame table"}
                }

                try .readOpenDmlFrameEntries(source, layout, table, &cursor)
                try source.seek(resume)
            }
        }

        if not cursor.next
        {
            fail InvalidFormatError{"AVI OpenDML index contains no frame payload"}
        }
    }

    mtd readOpenDmlFrameEntries(source: *ByteSource, layout: const *Layout, table: OpenDmlIndexHeader, cursor: *OpenDmlIndexCursor) fail
    {
        var probed: bool
        for entry in table.count
        {
            let record = try source.readNative!{[2] u32}()
            let offset = cast(u64, Math.littleEndianToNative(record[0]))
            let flags  = Math.littleEndianToNative(record[1])
            let size   = cast(u64, flags & ~OpenDmlNonKeyFlag)
            if not size
            {
                .appendFrame(0, 0, isSync: false)
                continue
            }

            // Standard index offsets address the payload eight bytes after its chunk header.
            // Compare before adding the relative offset to the unsigned 64-bit base.
            if offset > Swag.U64.Max - table.base or table.base + offset < ChunkHeaderSize
            {
                fail InvalidFormatError{"AVI OpenDML frame offset exceeds the stream"}
            }

            let start  = table.base + offset
            let header = start - ChunkHeaderSize
            while cursor.movie < layout.movieLists.count and header >= layout.movieLists[cursor.movie].end
            {
                cursor.movie += 1
            }

            if cursor.movie >= layout.movieLists.count
            {
                fail InvalidFormatError{"AVI OpenDML frame lies outside a movie list"}
            }

            let movie = layout.movieLists[cursor.movie]
            if header < movie.start or
               header < cursor.next or
               start > movie.end or
               size > movie.end - start
            {
                fail InvalidFormatError{"AVI OpenDML frame lies outside a movie list or overlaps an earlier frame"}
            }

            // Sample both ends of the index so a bad base or offset convention triggers the
            // fallback without reading the headers of every picture in a large recording.
            if not probed or entry + 1 == table.count
            {
                let resume = source.position()
                try source.seek(header)
                let chunk = try readChunk(source, movie.end)
                if chunk.id != table.chunkId or chunk.size != size
                {
                    fail InvalidFormatError{"AVI OpenDML index does not identify the frame chunk"}
                }

                try source.seek(resume)
                probed = true
            }

            let payloadEnd = start + size
            cursor.next = payloadEnd + (payloadEnd < movie.end ? size & 1 : 0)
            .appendFrame(start, size, (flags & OpenDmlNonKeyFlag) == 0)
        }
    }

    // Builds the frame table from the `idx1` chunk, and reports whether it produced one.
    //
    // An index that does not describe the frames it claims to is not a reason to refuse the file:
    // the frame list itself always holds the answer, so a rejected index falls back to a walk.
    mtd readIndex(source: *ByteSource, layout: const *Layout, dataId, compressedId: u32)->bool
    {
        if not layout.indexSize
        {
            return false
        }

        var indexErrorOutcome: Swag.Error
        catch .readIndexEntries(source, layout, dataId, compressedId) as indexErrorOutcome
        let indexError = indexErrorOutcome.value()
        if indexError == null and not .frames.isEmpty()
        {
            return true
        }

        .frames.clear()
        return false
    }

    // Reads the entries of the `idx1` chunk that belong to the video stream.
    mtd readIndexEntries(source: *ByteSource, layout: const *Layout, dataId, compressedId: u32) fail
    {
        if layout.indexSize % IndexEntrySize
        {
            fail InvalidFormatError{"AVI index ends with a partial entry"}
        }

        let indexEnd   = layout.indexStart + layout.indexSize
        let sourceSize = source.size()
        var position   = layout.indexStart
        var base       = Swag.U64.Max
        while position < indexEnd
        {
            try source.seek(position)
            let bytes   = try source.peek(IndexEntrySize)
            let records = cast(const [*] IndexRecord, bytes.buffer)
            let count   = Math.min(indexEnd - position, bytes.count) / IndexEntrySize
            for index in count
            {
                let record = records[index]
                let id     = Math.littleEndianToNative(record.id)
                position += IndexEntrySize
                if id != dataId and id != compressedId
                {
                    continue
                }

                let flags      = Math.littleEndianToNative(record.flags)
                let offset     = cast(u64, Math.littleEndianToNative(record.offset))
                let size       = cast(u64, Math.littleEndianToNative(record.size))
                let needsProbe = base == Swag.U64.Max
                if needsProbe
                {
                    base = try probeIndexBase(source, layout, id, offset)
                }

                let start = base + offset + ChunkHeaderSize
                if start > sourceSize or size > sourceSize - start
                {
                    fail InvalidFormatError{"AVI index points past the end of the stream"}
                }

                .appendFrame(start, size, (flags & IndexKeyFrameFlag) != 0)

                // The probe moves the cursor and can replace the borrowed window.
                if needsProbe
                {
                    break
                }
            }
        }

        if layout.stream.length and .frames.count != cast(u64, layout.stream.length)
        {
            fail InvalidFormatError{"AVI index does not describe every video frame"}
        }
    }

    // Walks the frame list, which is what a file without a usable index leaves.
    //
    // Chunk headers are read once, and MPEG-4 samples are scanned only through their first plane
    // header to recover clean points when the AVI index is absent or unusable.
    mtd walkFrames(source: *ByteSource, layout: const *Layout, dataId, compressedId: u32) fail
    {
        func isCodedIntra(source: *ByteSource, end, plane, layerBody: u64, layer: *Mpeg4.Layer)->bool fail
        {
            if layerBody
            {
                // A supported video object layer, including both quantiser matrices, fits here.
                const LayerHeaderBytes = 256_u64
                let count = Math.min(LayerHeaderBytes, plane - FourCcSize - layerBody)
                try source.seek(layerBody)
                var bits    = Mpeg4.BitReader.create((try source.peek(count))[until count])
                var updated = layer[]
                var layerError: Swag.Error
                catch updated.readVideoObjectLayer(&bits) as layerError
                if layerError.value() != null
                {
                    return false
                }

                layer[] = updated
            }

            if not layer.configured or plane >= end
            {
                return false
            }

            // The plane parser bounds the time base to 64 bits. The whole intra header fits in
            // sixteen bytes, so a padding VOP can be recognized without reading a picture body.
            const IntraHeaderBytes = 16_u64
            let count = Math.min(IntraHeaderBytes, end - plane)
            try source.seek(plane)
            let bytes = (try source.peek(count))[until count]
            if (cast(u32, bytes[0]) >> 6) != Mpeg4.VopIntra
            {
                return false
            }

            var bits = Mpeg4.BitReader.create(bytes)
            var header:      Mpeg4.PlaneHeader
            var headerError: Swag.Error
            catch Mpeg4.readPlaneHeader(layer, &bits, &header) as headerError
            return headerError.value() == null and header.coded
        }

        func isMpeg4SyncFrame(source: *ByteSource, offset, size: u64, layer: *Mpeg4.Layer)->bool fail
        {
            try source.seek(offset)
            var startCode = Swag.U32.Max
            var layerBody = 0_u64
            var scanned   = 0_u64
            while scanned < size
            {
                let bytes = try source.peek(1)
                let count = Math.min(bytes.count, size - scanned)
                for byte, index in bytes[until count]
                {
                    startCode = (startCode << 8) | cast(u32, byte)
                    if startCode >> 8 != 1
                    {
                        continue
                    }

                    let code = startCode & 0xFF
                    let next = index + 1
                    let body = offset + scanned + next
                    if code >= 0x20 and code <= 0x2F
                    {
                        layerBody = body
                    }
                    else if code == Mpeg4.CodeVop
                    {
                        // Most packets start with a predicted plane and carry no layer header.
                        if not layerBody and
                           next < count and
                           (cast(u32, bytes[next]) >> 6) != Mpeg4.VopIntra
                        {
                            return false
                        }

                        return try isCodedIntra(source, offset + size, body, layerBody, layer)
                    }
                }

                try source.skip(count)
                scanned += count
            }

            return false
        }

        var layer: Mpeg4.Layer
        for movie in layout.movieLists
        {
            var position = movie.start
            while position <= movie.end and ChunkHeaderSize <= movie.end - position
            {
                try source.seek(position)
                let chunk = try readChunk(source, movie.end)
                if chunk.id == dataId or chunk.id == compressedId
                {
                    var isSync = .frames.isEmpty()
                    if .isCoded
                    {
                        isSync = try isMpeg4SyncFrame(source, chunk.data, chunk.size, &layer)
                    }

                    .appendFrame(chunk.data, chunk.size, isSync)
                    position = chunk.next
                    continue
                }

                // An OpenDML file groups its frames into `rec ` lists, one level below the frame
                // list; descending into one reaches the frames it holds without a second walk. Any
                // other list is skipped rather than entered, since its content is not chunks.
                let isGroup = chunk.id == ListId and
                              chunk.size >= FourCcSize and
                              (try source.readLittleEndian!{u32}()) == RecordListId
                if isGroup
                {
                    let groupEnd       = chunk.data + chunk.size
                    var nestedPosition = chunk.data + FourCcSize
                    while nestedPosition <= groupEnd and ChunkHeaderSize <= groupEnd - nestedPosition
                    {
                        try source.seek(nestedPosition)
                        let nested = try readChunk(source, groupEnd)
                        if nested.id == dataId or nested.id == compressedId
                        {
                            var isSync = .frames.isEmpty()
                            if .isCoded
                            {
                                isSync = try isMpeg4SyncFrame(source, nested.data, nested.size, &layer)
                            }

                            .appendFrame(nested.data, nested.size, isSync)
                        }

                        nestedPosition = nested.next
                    }

                    if nestedPosition != groupEnd
                    {
                        fail InvalidFormatError{"AVI record list ends with a partial chunk"}
                    }

                    position = chunk.next
                }
                else
                {
                    position = chunk.next
                }
            }
        }
    }

    // Hands the frame table to the picture decoder the stream header named.
    //
    // AVI numbers slots at the declared frame rate, including empty slots that hold a picture.
    // When the codec reorders pictures it supplies their display order independently.
    mtd openPictures(source: *ByteSource) fail
    {
        var samples: Array!{SampleEntry}
        samples.reserve(.frames.count)

        // AVI supplies slot order here. Reader derives presentation times from the frame rate.
        for index in .frames.count
        {
            let entry = .frames[index]
            samples.add(SampleEntry{
                offset: entry.offset,
                size: cast(u64, entry.size),
                presentationTime: cast(s64, index),
                isSync: entry.isSync and entry.size != 0,
                repeatPrevious: entry.size == 0})
        }

        // The setup headers of such a file live at the front of its first frame, never in the
        // container, so that is where the layer is read from.
        let first = .frames[0]
        let size  = cast(u64, first.size)
        if size > source.size() or first.offset > source.size() - size
        {
            fail InvalidFormatError{"AVI frame payload is truncated"}
        }

        try source.seek(first.offset)
        let available = try source.peek(Math.min(size, FourCcSize))
        let head      = available[until Math.min(available.count, size)]
        var setup     = Video.inlineSetupHeaders(head)

        // The usual layer header and first VOP marker both fit in the existing window.
        // When user data stretches beyond it, read the complete sample to find the boundary.
        var full: Array!{u8}
        if setup.count == head.count and head.count < size
        {
            full.grow(size)
            full.count = size
            try source.readExact(full.toSlice())
            setup = Video.inlineSetupHeaders(full.toSlice())
        }

        try .pictures.open(setup, #move samples, slotTimestamps: true)
        .info.width  = .pictures.width
        .info.height = .pictures.height
    }

    // Decodes one Motion JPEG frame, which is a complete JPEG image.
    mtd decodeJpegFrame(payload: const [..] u8, target: *Image) fail
    {
        try Jpg.decodeRgbInto(target, payload, .info.width, .info.height)
    }

    // Decodes one uncompressed frame, whose rows are bitmap rows.
    mtd decodeBitmapFrame(source: *ByteSource, payloadSize: u64, target: *Image) fail
    {
        let height = cast(u64, .info.height)
        let size   = .rowBytes * height
        if size > payloadSize
        {
            fail InvalidFormatError{"AVI frame payload is smaller than the picture it declares"}
        }

        .prepareTarget(target)
        if not source.path().count
        {
            // Memory-backed bitmap rows can be converted directly from the borrowed payload.
            .copyRows((try source.peek(size)).buffer, target, 0, height)
            try source.skip(payloadSize)
            return
        }

        // Convert file-backed rows while the bytes just read are still in cache.
        const ReadSize = 256 * 1024_u64
        let rowsPerRead = Math.min(height, Math.max(1_u64, ReadSize / .rowBytes))
        let capacity    = rowsPerRead * .rowBytes
        if .payload.count != capacity
        {
            .payload.resize(capacity)
        }

        var readRows = 0_u64
        while readRows < height
        {
            let count = Math.min(rowsPerRead, height - readRows)
            try source.readExact(.payload.toSlice()[until count * .rowBytes])
            let destRow = .isTopDown ? height - readRows - count : readRows
            .copyRows(.payload.storage(), target, destRow, count)
            readRows += count
        }

        try source.skip(payloadSize - size)
    }

    mtd const copyRows(pixels: const [*] u8, target: *Image, firstRow, count: u64)
    {
        switch .bytesPerPixel
        {
        case 2: copyBitmapRows!{2}(pixels, target, .rowBytes, .isTopDown, firstRow, count)
        case 3: copyBitmapRows!{3}(pixels, target, .rowBytes, .isTopDown, firstRow, count)
        case 4: copyBitmapRows!{4}(pixels, target, .rowBytes, .isTopDown, firstRow, count)
        }
    }

    // Reuses the frame the caller already has, and creates one only when it cannot hold this one.
    //
    // This is what keeps decoding a whole stream at the memory cost of a single frame.
    mtd const prepareTarget(target: *Image)
    {
        if target.width != .info.width or target.height != .info.height or target.pixelFormat != .RGB8
        {
            target[] = Image.create(.info.width, .info.height, .RGB8)
        }
    }
}

// Selects the RGB channels of four BGR or BGRA pixels in output order.
private const Bgr24ToRgb  = cast(Math.Simd.U8x16, [2_u8, 1, 0, 5, 4, 3, 8, 7, 6, 11, 10, 9, 128, 128, 128, 128])
private const Bgra32ToRgb = cast(Math.Simd.U8x16, [2_u8, 1, 0, 6, 5, 4, 10, 9, 8, 14, 13, 12, 128, 128, 128, 128])

#[Swag.Inline]
private func storeRgb5558(target: [*] u8, pixels: Math.Simd.U16x8)
{
    using Math.Simd
    const LowRg  = cast(U8x16, [0_u8, 8, 128, 1, 9, 128, 2, 10, 128, 3, 11, 128, 4, 12, 128, 5])
    const LowB   = cast(U8x16, [128_u8, 128, 0, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 4, 128])
    const HighRg = cast(U8x16, [13_u8, 128, 6, 14, 128, 7, 15, 128, 128, 128, 128, 128, 128, 128, 128, 128])
    const HighB  = cast(U8x16, [128_u8, 5, 128, 128, 6, 128, 128, 7, 128, 128, 128, 128, 128, 128, 128, 128])
    let red   = ((pixels >> 7) & 248) | ((pixels >> 12) & 7)
    let green = ((pixels >> 2) & 248) | ((pixels >> 7) & 7)
    let blue  = ((pixels << 3) & 248) | ((pixels >> 2) & 7)
    let rg    = packUnsigned(cast #bit(S16x8, red), cast #bit(S16x8, green))
    let b     = packUnsigned(cast #bit(S16x8, blue), cast #bit(S16x8, blue))
    store(target, shuffle(rg, LowRg) | shuffle(b, LowB))
    storeLow8(target + 16, shuffle(rg, HighRg) | shuffle(b, HighB))
}

private func(PIXEL_BYTES: u64) copyBitmapRows(pixels: const [*] u8, target: *Image, sourceStride: u64, topDown: bool, firstRow, rows: u64)
{
    let output = target.pixels.storage() + firstRow * target.rowStride
    for y in rows
    {
        // Pixel storage is bottom-up, so a top-down bitmap is turned over here.
        let sourceY     = topDown ? rows - y - 1 : y
        var source      = pixels + sourceY * sourceStride
        var destination = output + y * target.rowStride
        var count       = target.width

        #static if PIXEL_BYTES == 2
        {
            while count >= 8
            {
                let packed = Math.Simd.load(cast(const [*] u16, source))
                storeRgb5558(destination, packed)
                source      += 16
                destination += 24
                count       -= 8
            }
        }
        else
        {
            let shuffle = PIXEL_BYTES == 3 ? Bgr24ToRgb : Bgra32ToRgb

            // Two remaining pixels cover the overlap of the second load and store.
            while count >= 10
            {
                let low  = Math.Simd.load(source)
                let high = Math.Simd.load(source + 4 * PIXEL_BYTES)
                Math.Simd.store(destination, Math.Simd.shuffle(low, shuffle))
                Math.Simd.store(destination + 12, Math.Simd.shuffle(high, shuffle))
                source      += 8 * PIXEL_BYTES
                destination += 24
                count       -= 8
            }

            if count >= 6
            {
                let packed = Math.Simd.load(source)
                Math.Simd.store(destination, Math.Simd.shuffle(packed, shuffle))
                source      += 4 * PIXEL_BYTES
                destination += 12
                count       -= 4
            }
        }

        for count
        {
            #static if PIXEL_BYTES == 2
            {
                let pixel = cast(u32, source[0]) | (cast(u32, source[1]) << 8)
                let blue  = pixel & 0x1F
                let green = (pixel >> 5) & 0x1F
                let red   = (pixel >> 10) & 0x1F
                destination[0] = cast(u8, (red << 3) | (red >> 2))
                destination[1] = cast(u8, (green << 3) | (green >> 2))
                destination[2] = cast(u8, (blue << 3) | (blue >> 2))
            }
            else
            {
                destination[0] = source[2]
                destination[1] = source[1]
                destination[2] = source[0]
            }

            source      += PIXEL_BYTES
            destination += 3
        }
    }
}

// Reads one index header and bounds its records before a caller consumes them.
private func readOpenDmlIndexHeader(source: *ByteSource, chunk: Chunk, dataId, compressedId: u32)->OpenDmlIndexHeader fail
{
    if chunk.size < #sizeof(OpenDmlIndexHeader)
    {
        fail InvalidFormatError{"AVI OpenDML index header is truncated"}
    }

    try source.seek(chunk.data)
    var table = try source.readNative!{OpenDmlIndexHeader}()
    table.entryWords = Math.littleEndianToNative(table.entryWords)
    table.count      = Math.littleEndianToNative(table.count)
    table.chunkId    = Math.littleEndianToNative(table.chunkId)
    table.base       = Math.littleEndianToNative(table.base)
    if table.subtype or
       (table.kind != IndexOfIndexes and table.kind != IndexOfChunks) or
       table.entryWords != (table.kind == IndexOfIndexes ? 4 : 2) or
       (table.chunkId != dataId and table.chunkId != compressedId)
    {
        fail InvalidFormatError{"AVI OpenDML index has an unsupported layout"}
    }

    let bytes = cast(u64, table.entryWords) * 4
    if table.count > (chunk.size - #sizeof(OpenDmlIndexHeader)) / bytes
    {
        fail InvalidFormatError{"AVI OpenDML index ends inside a frame entry"}
    }

    return table
}

// Returns the base the offsets of an index are counted from.
//
// Most writers count them from the frame-list identifier and some store absolute stream offsets,
// and nothing in the file says which. The first entry decides: whichever base puts the chunk the
// entry names where the entry claims it is, is the base the file used.
private func probeIndexBase(source: *ByteSource, layout: const *Layout, id: u32, offset: u64)->u64 fail
{
    let movieType = layout.movieLists[0].start - FourCcSize
    if matchesChunkId(source, movieType + offset, id)
    {
        return movieType
    }

    if matchesChunkId(source, offset, id)
    {
        return 0
    }

    fail InvalidFormatError{"AVI index does not point at the frames it describes"}
}

// Reports whether the chunk header at `offset` carries `id`.
//
// A probe past the end of the stream is an answer, not a failure: it says the index counts its
// offsets from somewhere else.
private func matchesChunkId(source: *ByteSource, offset: u64, id: u32)->bool
{
    var probeErrorOutcome: Swag.Error
    var found: #decltype(expect readChunkIdAt(source, offset))
    catch { found = try readChunkIdAt(source, offset) } as probeErrorOutcome
    let probeError = probeErrorOutcome.value()
    return probeError == null and found == id
}

// Returns the identifier of the chunk header at `offset`.
private func readChunkIdAt(source: *ByteSource, offset: u64)->u32 fail
{
    try source.seek(offset)
    return try source.readLittleEndian!{u32}()
}
