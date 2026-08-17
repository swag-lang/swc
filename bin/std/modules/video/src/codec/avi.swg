#global namespace Avi

using Core, Core.Errors, Pixel

// Builds the 32-bit value a RIFF file stores for a four-character identifier.
//
// Identifiers are compared as little-endian words rather than as text, so walking a container
// costs one integer comparison per chunk.
#[Swag.ConstExpr]
private func fourCc(a, b, c, d: u32) => a | (b << 8) | (c << 16) | (d << 24)

// Identifiers of the container itself.
private const RiffId = fourCc('R'u32, 'I'u32, 'F'u32, 'F'u32)
private const AviId = fourCc('A'u32, 'V'u32, 'I'u32, ' 'u32)
private const ListId = fourCc('L'u32, 'I'u32, 'S'u32, 'T'u32)
private const HeaderListId = fourCc('h'u32, 'd'u32, 'r'u32, 'l'u32)
private const StreamListId = fourCc('s'u32, 't'u32, 'r'u32, 'l'u32)
private const FrameListId = fourCc('m'u32, 'o'u32, 'v'u32, 'i'u32)
private const RecordListId = fourCc('r'u32, 'e'u32, 'c'u32, ' 'u32)
private const MainHeaderId = fourCc('a'u32, 'v'u32, 'i'u32, 'h'u32)
private const StreamHeaderId = fourCc('s'u32, 't'u32, 'r'u32, 'h'u32)
private const StreamFormatId = fourCc('s'u32, 't'u32, 'r'u32, 'f'u32)
private const IndexId = fourCc('i'u32, 'd'u32, 'x'u32, '1'u32)
private const VideoStreamId = fourCc('v'u32, 'i'u32, 'd'u32, 's'u32)

// Codec identifiers whose frames are complete JPEG images.
//
// The four spellings all mean Motion JPEG; which one a file carries says who wrote it, not what
// its frames contain.
private const MotionJpegIds: [4] u32 = [
    fourCc('M'u32, 'J'u32, 'P'u32, 'G'u32),
    fourCc('m'u32, 'j'u32, 'p'u32, 'g'u32),
    fourCc('J'u32, 'P'u32, 'E'u32, 'G'u32),
    fourCc('j'u32, 'p'u32, 'e'u32, 'g'u32)]

// Codec identifiers whose frames are uncompressed bitmap rows.
//
// `BI_RGB` is the value the bitmap header itself defines; the three tags are what writers put
// there instead when they want the field to read as a name.
private const UncompressedIds: [4] u32 = [
    cast(u32) Bmp.BI_RGB,
    fourCc('D'u32, 'I'u32, 'B'u32, ' 'u32),
    fourCc('R'u32, 'A'u32, 'W'u32, ' 'u32),
    fourCc('R'u32, 'G'u32, 'B'u32, ' 'u32)]

// Identifier and size of a frame chunk, and of one entry of the index.
private const FourCcSize = 4'u64
private const ChunkHeaderSize = 8'u64
private const IndexEntrySize = 16'u64

// Extension the frames are handed to the image codecs under.
//
// A Motion JPEG frame is a complete JPEG image, so the picture codec is the Pixel one, selected
// the way every other caller selects it.
private const JpegName = ".jpg"

// Highest stream ordinal a frame chunk identifier can name, since it spells it with two digits.
private const MaxStreamIndex = 99'u32

// Largest frame side an encoded stream can describe, bounded by the 16-bit frame rectangle of
// the stream header.
private const MaxFrameSide = 32_767's32

// Quality the JPEG frames of an encoded stream are compressed with.
//
// A video is a long sequence of similar pictures, so the last few percent of detail costs
// proportionally far more here than it does on a single photograph.
private const FrameQuality = 90'u8

// `AVIF_HASINDEX`: the file ends with the `idx1` table, which is what makes seeking free.
private const MainHasIndex = 0x0000_0010'u32

// `AVIIF_KEYFRAME`: every frame of a Motion JPEG stream stands on its own.
private const IndexKeyFrame = 0x0000_0010'u32

// Quality the stream header reports when the writer does not measure one.
private const UnknownQuality = 0xFFFF_FFFF'u32

// Largest stream an encoder accepts, in bytes.
//
// Every size in the container is a 32-bit field, so the margin below four gigabytes leaves room
// for the index and the trailing chunk headers a stream still owes when its last frame lands.
private const MaxStreamSize = 0xFFF0_0000'u64

// Frame index meaning that the decoder sits nowhere in particular.
//
// A read that fails part way through a frame leaves the position meaningless, so it is what the
// decoder holds until a seek reestablishes where it is.
private const NoFrameIndex = Swag.U64.Max

// Layout of the `avih` chunk, which describes the file rather than one of its streams.
#[Swag.Pack(1)]
private struct MainHeader
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
private struct StreamHeader
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

// Total size of the `hdrl` list an encoder writes, counting its own identifier.
private const StreamListSize = FourCcSize + ChunkHeaderSize + #sizeof(StreamHeader) + ChunkHeaderSize + #sizeof(Bmp.Header)
private const HeaderListSize = FourCcSize + ChunkHeaderSize + #sizeof(MainHeader) + ChunkHeaderSize + StreamListSize

// One chunk header: what it identifies, where its payload lies, and where the next one starts.
private struct Chunk
{
    id:   u32
    size: u64
    data: u64
    next: u64
}

// One frame of the video stream, as the container places it.
private struct FrameEntry
{
    offset: u64     // Offset of the payload in the stream, in bytes.
    size:   u64     // Length of the payload, in bytes; zero for a frame that repeats the previous one.
}

// One entry of the index an encoder builds while it writes.
private struct IndexEntry
{
    offset: u32     // Offset of the frame chunk, relative to the frame-list identifier.
    size:   u32     // Length of the frame payload, in bytes.
}

// What walking the container found, before it is turned into a stream description.
private struct Layout
{
    main:        MainHeader       // Contents of the `avih` chunk.
    stream:      StreamHeader     // Stream header of the first video stream.
    format:      Bmp.Header       // Bitmap header describing the frames of that stream.
    frameList:   u64              // Offset of the `movi` identifier.
    frameEnd:    u64              // Offset just past the frames of the `movi` list.
    indexStart:  u64              // Offset of the `idx1` payload, or zero when the file has none.
    indexSize:   u64              // Length of the `idx1` payload, in bytes.
    streamIndex: u32              // Ordinal of the video stream among the streams of the file.
    hasMain:     bool
    hasStream:   bool
}

// Reads one value of the container's binary layout.
private func(T) readValue(source: *Source)->T fail
{
    var result: T = undefined
    source.readExact(@mkslice(cast([*] u8) &result, #sizeof(T)))
    return result
}

// Appends one value of the container's binary layout.
private func(T) writeValue(sink: *Sink, value: T) fail
{
    var stored = value
    sink.write(@mkslice(cast(const [*] u8) &stored, #sizeof(T)))
}

// Rewrites one value of a header the sink already accepted.
private func(T) patchValue(sink: *Sink, offset: u64, value: T) fail
{
    var stored = value
    sink.patch(offset, @mkslice(cast(const [*] u8) &stored, #sizeof(T)))
}

// Reads one chunk header and reports where its payload and its successor start.
private func readChunk(source: *Source, end: u64)->Chunk fail
{
    var result: retval
    result.id   = readValue'u32(source)
    result.size = cast(u64) readValue'u32(source)
    result.data = source.position()
    if result.data > end or result.size > end - result.data do
        fail InvalidFormatError{"AVI chunk runs past the end of the stream"}

    // RIFF pads an odd payload with one byte that belongs to neither chunk.
    result.next = Math.min(result.data + result.size + (result.size & 1), end)
    return result
}

// Returns the identifier a frame chunk of stream `index` carries.
//
// The first two characters spell the stream ordinal and the last two say what the chunk holds:
// `db` for uncompressed bits and `dc` for compressed ones.
#[Swag.ConstExpr]
private func frameChunkId(index: u32, a, b: u32)->u32
{
    return fourCc('0'u32 + index / 10, '0'u32 + index % 10, a, b)
}

// Identifier the frames of an encoded stream carry: compressed pictures of the first stream.
private const FrameChunkId = frameChunkId(0, 'd'u32, 'c'u32)

// Returns `id` as the four characters a file stores, for an error message.
//
// A byte that is not printable becomes a question mark: the identifier of a stream this decoder
// refuses is exactly the field most likely to hold something that is not text at all.
private func describeId(id: u32)->String
{
    var result: retval
    for shift in 4
    {
        let value = cast(u8) ((id >> cast(u32) (shift * 8)) & 0xFF)
        result.append(value >= 0x20 and value < 0x7F ? cast(rune) value : '?'rune)
    }

    return result
}

private impl Layout
{
    // Walks the top-level chunks of the file, keeping the ones a picture stream needs.
    mtd parse(source: *Source) fail
    {
        if readValue'u32(source) != RiffId do
            fail InvalidFormatError{"AVI stream is not a RIFF file"}

        // A capture interrupted before its header was patched leaves a size of zero behind, and a
        // size larger than the file means the same thing: the file itself is the bound.
        let declared = cast(u64) readValue'u32(source)
        let end      = declared < FourCcSize ? source.size() : Math.min(source.size(), source.position() + declared)
        if readValue'u32(source) != AviId do
            fail InvalidFormatError{"RIFF stream does not hold an AVI file"}

        while source.position() + ChunkHeaderSize <= end
        {
            let chunk = readChunk(source, end)
            if chunk.id == IndexId
            {
                .indexStart = chunk.data
                .indexSize  = chunk.size
            }
            elif chunk.id == ListId and chunk.size >= FourCcSize
            {
                switch readValue'u32(source)
                {
                case HeaderListId:
                    .parseHeaderList(source, chunk.next)

                case FrameListId:
                    .frameList = chunk.data
                    .frameEnd  = chunk.next
                }
            }

            source.seek(chunk.next)
        }
    }

    // Reads the `hdrl` list: the header of the file, and the streams it declares.
    private mtd parseHeaderList(source: *Source, end: u64) fail
    {
        var index = 0'u32
        while source.position() + ChunkHeaderSize <= end
        {
            let chunk = readChunk(source, end)
            if chunk.id == MainHeaderId and chunk.size >= #sizeof(MainHeader)
            {
                .main    = readValue'MainHeader(source)
                .hasMain = true
            }
            elif chunk.id == ListId and chunk.size >= FourCcSize and readValue'u32(source) == StreamListId
            {
                .parseStreamList(source, chunk.next, index)
                index += 1
            }

            source.seek(chunk.next)
        }
    }

    // Reads one `strl` list, keeping the first video stream the file declares.
    private mtd parseStreamList(source: *Source, end: u64, index: u32) fail
    {
        var header:    StreamHeader
        var hasHeader: bool

        while source.position() + ChunkHeaderSize <= end
        {
            let chunk = readChunk(source, end)
            if chunk.id == StreamHeaderId and chunk.size >= #sizeof(StreamHeader)
            {
                header    = readValue'StreamHeader(source)
                hasHeader = true
            }
            elif chunk.id == StreamFormatId and hasHeader and !.hasStream and header.kind == VideoStreamId
            {
                if chunk.size < #sizeof(Bmp.Header) do
                    fail UnsupportedFormatError{"AVI video stream is not described by a bitmap header"}

                .format      = readValue'(Bmp.Header)(source)
                .stream      = header
                .streamIndex = index
                .hasStream   = true
            }

            source.seek(chunk.next)
        }
    }

    // Returns the exact rate of the video stream.
    //
    // The stream header states it as a ratio and is the accurate answer; the header of the file
    // rounds it to whole microseconds, and is what a file without a stream rate leaves.
    mtd const frameRate()->FrameRate fail
    {
        if .stream.scale and .stream.rate do
            return FrameRate.create(.stream.rate, .stream.scale)
        if .main.microSecPerFrame do
            return FrameRate.create(1_000_000, .main.microSecPerFrame)
        fail InvalidFormatError{"AVI stream declares no frame rate"}
    }
}

// Reads AVI files one frame at a time.
//
// The container says where every frame lies, either in its own index or in the list holding the
// frames, so opening a stream reads its headers and its frame table and never a picture. That
// table is what makes a seek free, and it is the only part of the file the decoder holds: sixteen
// bytes per frame, whatever a frame itself weighs.
//
// Frames are Motion JPEG or uncompressed bitmap rows. A Motion JPEG frame is a complete JPEG
// image and is decoded by the Pixel image codec, so both modules read the same pictures.
struct Decoder
{
    internal
    {
        info:          StreamInfo           // What the container headers described.
        frames:        Array'FrameEntry     // Where every frame of the video stream lies.
        payload:       Array'u8             // Scratch storage of one encoded frame.
        bytesPerPixel: u64                  // Source bytes of one pixel of an uncompressed frame.
        rowBytes:      u64                  // Padded length of one row of an uncompressed frame.
        nextIndex:     u64                  // Index of the frame the decoder is positioned on.
        isTopDown:     bool                 // Whether uncompressed rows start with the top one.
        isJpeg:        bool                 // Whether frames are complete JPEG images.
    }
}

impl IDecoder for Decoder
{
    mtd impl format()->StreamFormat => {"AVI - Audio Video Interleave", ".avi"}

    mtd impl open(source: *Source)->StreamInfo fail
    {
        var layout: Layout
        layout.parse(source)
        if !layout.hasMain do
            fail InvalidFormatError{"AVI file has no main header"}
        if !layout.hasStream do
            fail UnsupportedFormatError{"AVI file has no video stream"}
        if !layout.frameList do
            fail InvalidFormatError{"AVI file has no frame list"}

        .describeFrames(&layout)
        .buildFrameTable(source, &layout)
        if !.frames.count do
            fail InvalidFormatError{"AVI video stream has no frame"}

        .info.frameCount = .frames.count
        .nextIndex       = 0
        return .info
    }

    mtd impl seekFrame(source: *Source, index: u64) fail
    {
        // The container gave every frame position away when the stream was opened, so seeking is
        // arithmetic on the frame table and never touches the source.
        discard source
        if index >= .frames.count do
            fail BadParameterError{"AVI frame index exceeds the stream frame count"}

        .nextIndex = index
    }

    mtd impl decodeFrame(source: *Source, target: *Image) fail
    {
        let current = .nextIndex
        if current >= .frames.count do
            fail InvalidFormatError{"AVI stream has no frame at this position"}

        .nextIndex = NoFrameIndex
        let entry = .frames[.resolveFrame(current)]
        if entry.offset > source.size() or entry.size > source.size() - entry.offset do
            fail InvalidFormatError{"AVI frame payload is truncated"}

        if .payload.count != entry.size do
            .payload.resize(entry.size)
        source.seek(entry.offset)
        source.readExact(.payload.toSlice())

        if .isJpeg do
            .decodeJpegFrame(target)
        else do
            .decodeBitmapFrame(target)
        .nextIndex = current + 1
    }
}

impl Decoder
{
    // Turns the bitmap header of the video stream into everything decoding a frame needs.
    private mtd describeFrames(layout: const *Layout) fail
    {
        let width  = layout.format.biWidth
        let height = Math.abs(layout.format.biHeight)
        if width <= 0 or height <= 0 do
            fail InvalidFormatError{"AVI frame dimensions need positive values"}
        if width > Swag.S32.Max / 4 or height > Swag.S32.Max / 4 do
            fail UnsupportedFormatError{"AVI frame dimensions exceed Pixel image storage"}

        .info.width     = width
        .info.height    = height
        .info.frameRate = layout.frameRate()

        let compression = layout.format.biCompression
        if Slice.contains(MotionJpegIds, compression)
        {
            .isJpeg = true
            return
        }

        if !Slice.contains(UncompressedIds, compression) do
            fail UnsupportedFormatError{Errors.mkString(Format.toString("video decoder does not support the AVI '%' video codec", describeId(compression)))}

        let bitCount = layout.format.biBitCount
        if bitCount != 24 and bitCount != 32 do
            fail UnsupportedFormatError{Errors.mkString(Format.toString("video decoder does not support uncompressed AVI frames of % bits per pixel", bitCount))}

        // Uncompressed frames follow the bitmap rules: rows are padded to a multiple of four
        // bytes, and only a negative height stores the top row first.
        .bytesPerPixel = cast(u64) bitCount / 8
        .rowBytes      = (cast(u64) width * cast(u64) bitCount + 31) / 32 * 4
        .isTopDown     = layout.format.biHeight < 0
    }

    // Records where every frame of the video stream lies.
    private mtd buildFrameTable(source: *Source, layout: const *Layout) fail
    {
        if layout.streamIndex > MaxStreamIndex do
            fail UnsupportedFormatError{"AVI file declares more streams than the container can name"}

        let dataId       = frameChunkId(layout.streamIndex, 'd'u32, 'b'u32)
        let compressedId = frameChunkId(layout.streamIndex, 'd'u32, 'c'u32)
        if .readIndex(source, layout, dataId, compressedId) do
            return

        .walkFrames(source, layout, dataId, compressedId)
    }

    // Builds the frame table from the `idx1` chunk, and reports whether it produced one.
    //
    // An index that does not describe the frames it claims to is not a reason to refuse the file:
    // the frame list itself always holds the answer, so a rejected index falls back to a walk.
    private mtd readIndex(source: *Source, layout: const *Layout, dataId, compressedId: u32)->bool
    {
        if !layout.indexSize do
            return false

        catch .readIndexEntries(source, layout, dataId, compressedId) as indexError
        if indexError == null and .frames.count do
            return true

        .frames.clear()
        return false
    }

    // Reads the entries of the `idx1` chunk that belong to the video stream.
    private mtd readIndexEntries(source: *Source, layout: const *Layout, dataId, compressedId: u32) fail
    {
        var base = Swag.U64.Max
        for entry in layout.indexSize / IndexEntrySize
        {
            source.seek(layout.indexStart + entry * IndexEntrySize)
            let id = readValue'u32(source)
            if id != dataId and id != compressedId
            {
                // Interleaved audio, and the lists an OpenDML file wraps its frames in, are
                // indexed beside the pictures and say nothing about them.
                continue
            }

            source.skip(FourCcSize)
            let offset = cast(u64) readValue'u32(source)
            let size   = cast(u64) readValue'u32(source)
            if base == Swag.U64.Max do
                base = probeIndexBase(source, layout, id, offset)

            let start = base + offset + ChunkHeaderSize
            if start > source.size() or size > source.size() - start do
                fail InvalidFormatError{"AVI index points past the end of the stream"}

            .frames.add({start, size})
        }
    }

    // Walks the frame list, which is what a file without a usable index leaves.
    //
    // Only chunk headers are read, so the cost is one small read per chunk rather than a pass
    // over the frames themselves, and no picture is decoded to reach the end of the list.
    private mtd walkFrames(source: *Source, layout: const *Layout, dataId, compressedId: u32) fail
    {
        var position = layout.frameList + FourCcSize
        while position + ChunkHeaderSize <= layout.frameEnd
        {
            source.seek(position)
            let chunk = readChunk(source, layout.frameEnd)
            if chunk.id == dataId or chunk.id == compressedId
            {
                .frames.add({chunk.data, chunk.size})
                position = chunk.next
                continue
            }

            // An OpenDML file groups its frames into `rec ` lists, one level below the frame
            // list; descending into one reaches the frames it holds without a second walk. Any
            // other list is skipped rather than entered, since its content is not chunks.
            let isGroup = chunk.id == ListId and chunk.size >= FourCcSize and readValue'u32(source) == RecordListId
            position = isGroup ? chunk.data + FourCcSize : chunk.next
        }
    }

    // Returns the frame that really holds the picture of frame `index`.
    //
    // A frame repeating the picture before it is recorded as an empty chunk, which is how the
    // container carries a stream that pauses at a constant frame rate. Walking back to the last
    // frame that has a payload answers such a frame without holding a decoded picture between
    // two calls, and without depending on the order frames are asked for.
    private mtd const resolveFrame(index: u64)->u64 fail
    {
        var found = index
        while !.frames[found].size
        {
            if !found do
                fail InvalidFormatError{"AVI stream starts with a frame that carries no picture"}
            found -= 1
        }

        return found
    }

    // Decodes one Motion JPEG frame, which is a complete JPEG image.
    private mtd decodeJpegFrame(target: *Image) fail
    {
        var decoded = Image.decode(JpegName, .payload.toSlice())
        if decoded.width != .info.width or decoded.height != .info.height do
            fail InvalidFormatError{"AVI frame does not have the dimensions its stream declares"}

        decoded.convertTo(.RGB8)
        .prepareTarget(target)
        Memory.copy(target.pixels.buffer!, decoded.pixels.buffer!, target.byteCount)
    }

    // Decodes one uncompressed frame, whose rows are bitmap rows.
    private mtd decodeBitmapFrame(target: *Image) fail
    {
        if .rowBytes * cast(u64) .info.height > .payload.count do
            fail InvalidFormatError{"AVI frame payload is smaller than the picture it declares"}

        .prepareTarget(target)
        let payload = .payload.buffer!
        for y in .info.height
        {
            // Pixel storage is bottom-up and so is a bitmap frame of positive height, so only a
            // top-down frame is turned over here.
            let sourceRow = cast(u64) (.isTopDown ? .info.height - y - 1 : y) * .rowBytes
            let targetRow = cast(u64) y * cast(u64) target.rowStride
            for x in .info.width
            {
                let source      = payload + sourceRow + cast(u64) x * .bytesPerPixel
                let destination = target.pixels.buffer! + targetRow + cast(u64) x * 3
                destination[0] = source[2]
                destination[1] = source[1]
                destination[2] = source[0]
            }
        }
    }

    // Reuses the frame the caller already has, and creates one only when it cannot hold this one.
    //
    // This is what keeps decoding a whole stream at the memory cost of a single frame.
    private mtd const prepareTarget(target: *Image)
    {
        if target.width != .info.width or target.height != .info.height or target.pixelFormat != .RGB8 do
            target[] = Image.create(.info.width, .info.height, .RGB8)
    }
}

// Returns the base the offsets of an index are counted from.
//
// Most writers count them from the frame-list identifier and some store absolute stream offsets,
// and nothing in the file says which. The first entry decides: whichever base puts the chunk the
// entry names where the entry claims it is, is the base the file used.
private func probeIndexBase(source: *Source, layout: const *Layout, id: u32, offset: u64)->u64 fail
{
    if matchesChunkId(source, layout.frameList + offset, id) do
        return layout.frameList
    if matchesChunkId(source, offset, id) do
        return 0
    fail InvalidFormatError{"AVI index does not point at the frames it describes"}
}

// Reports whether the chunk header at `offset` carries `id`.
//
// A probe past the end of the stream is an answer, not a failure: it says the index counts its
// offsets from somewhere else.
private func matchesChunkId(source: *Source, offset: u64, id: u32)->bool
{
    let found = catch readChunkIdAt(source, offset) as probeError
    return probeError == null and found == id
}

// Returns the identifier of the chunk header at `offset`.
private func readChunkIdAt(source: *Source, offset: u64)->u32 fail
{
    source.seek(offset)
    return readValue'u32(source)
}

// Writes AVI files one frame at a time, compressing each of them as a JPEG image.
//
// Motion JPEG codes every frame on its own, so an encoded stream seeks anywhere at the cost of
// one frame and survives losing any part of itself, which is what a container written while it
// is being recorded needs. The totals the header carries — the size of the file, the size of the
// frame list, the number of frames — are reserved when the header is written and rewritten once
// the last frame lands, so encoding never holds more than one frame.
struct Encoder
{
    internal
    {
        info:          StreamInfo           // Geometry and rate the stream was opened with.
        index:         Array'IndexEntry     // One entry per written frame, written as `idx1`.
        mainHeader:    u64                  // Offset of the `avih` payload.
        streamHeader:  u64                  // Offset of the `strh` payload.
        frameList:     u64                  // Offset of the `movi` identifier.
        frameListSize: u64                  // Offset of the size field of the `movi` list.
        largestFrame:  u64                  // Size of the largest frame written, in bytes.
    }
}

impl IEncoder for Encoder
{
    mtd impl format()->StreamFormat => {"AVI - Audio Video Interleave", ".avi"}

    mtd impl begin(sink: *Sink, info: StreamInfo) fail
    {
        if info.width > MaxFrameSide or info.height > MaxFrameSide do
            fail UnsupportedFormatError{"AVI frame dimensions exceed what the container can describe"}

        .info = info
        writeValue(sink, RiffId)
        writeValue(sink, 0'u32)
        writeValue(sink, AviId)

        writeValue(sink, ListId)
        writeValue(sink, cast(u32) HeaderListSize)
        writeValue(sink, HeaderListId)

        writeValue(sink, MainHeaderId)
        writeValue(sink, cast(u32) #sizeof(MainHeader))
        .mainHeader = sink.position()
        writeValue(sink, .createMainHeader())

        writeValue(sink, ListId)
        writeValue(sink, cast(u32) StreamListSize)
        writeValue(sink, StreamListId)

        writeValue(sink, StreamHeaderId)
        writeValue(sink, cast(u32) #sizeof(StreamHeader))
        .streamHeader = sink.position()
        writeValue(sink, .createStreamHeader())

        writeValue(sink, StreamFormatId)
        writeValue(sink, cast(u32) #sizeof(Bmp.Header))
        writeValue(sink, .createFormatHeader())

        writeValue(sink, ListId)
        .frameListSize = sink.position()
        writeValue(sink, 0'u32)
        .frameList = sink.position()
        writeValue(sink, FrameListId)
    }

    mtd impl addFrame(sink: *Sink, image: Image) fail
    {
        var options: Jpg.EncodeOptions
        options.quality = FrameQuality

        var encoded = image.encode(JpegName, options)
        encoded.makeLinear()

        let payload = encoded.toSlice()!
        let size    = @countof(payload)
        .reserve(sink, size)

        .index.add({cast(u32) (sink.position() - .frameList), cast(u32) size})
        writeValue(sink, FrameChunkId)
        writeValue(sink, cast(u32) size)
        sink.write(payload)

        // RIFF pads an odd payload so the next chunk starts on an even offset.
        if size & 1 do
            writeValue(sink, 0'u8)
        .largestFrame = Math.max(.largestFrame, size)
    }

    mtd impl end(sink: *Sink) fail
    {
        let frameEnd = sink.position()
        writeValue(sink, IndexId)
        writeValue(sink, cast(u32) (.index.count * IndexEntrySize))
        for entry in .index
        {
            writeValue(sink, FrameChunkId)
            writeValue(sink, IndexKeyFrame)
            writeValue(sink, entry.offset)
            writeValue(sink, entry.size)
        }

        .patchTotals(sink, frameEnd)
    }
}

impl Encoder
{
    // Offset of the size field of the file, which is the first total to be rewritten.
    private const RiffSizeOffset = 4'u64

    // Fails unless a frame of `size` bytes still fits in what the container can address.
    //
    // Every size in the container is a 32-bit field, so a stream that would run past four
    // gigabytes is refused while it is still correct rather than written with a size that wraps.
    private mtd const reserve(sink: *Sink, size: u64) fail
    {
        let projected = sink.position() + ChunkHeaderSize + size + 1 + ChunkHeaderSize + (.index.count + 1) * IndexEntrySize
        if projected > MaxStreamSize do
            fail UnsupportedFormatError{"AVI stream exceeds the four gigabytes the container can address"}
    }

    // Returns the header of the file, with the totals it cannot know yet left at zero.
    private mtd const createMainHeader()->MainHeader
    {
        var result: retval
        result.microSecPerFrame = cast(u32) (1_000_000'u64 * cast(u64) .info.frameRate.denominator() / cast(u64) .info.frameRate.numerator())
        result.flags            = MainHasIndex
        result.streams          = 1
        result.width            = cast(u32) .info.width
        result.height           = cast(u32) .info.height
        return result
    }

    // Returns the header of the video stream, with its length left at zero.
    private mtd const createStreamHeader()->StreamHeader
    {
        var result: retval
        result.kind        = VideoStreamId
        result.handler     = MotionJpegIds[0]
        result.scale       = .info.frameRate.denominator()
        result.rate        = .info.frameRate.numerator()
        result.quality     = UnknownQuality
        result.frameRight  = cast(s16) .info.width
        result.frameBottom = cast(s16) .info.height
        return result
    }

    // Returns the bitmap header describing the frames of the video stream.
    private mtd const createFormatHeader()->Bmp.Header
    {
        var result: retval
        result.biSize        = cast(u32) #sizeof(Bmp.Header)
        result.biWidth       = .info.width
        result.biHeight      = .info.height
        result.biPlanes      = 1
        result.biBitCount    = 24
        result.biCompression = MotionJpegIds[0]
        result.biSizeImage   = cast(u32) (cast(u64) .info.width * cast(u64) .info.height * 3)
        return result
    }

    // Rewrites the header fields only the finished stream knows.
    private mtd const patchTotals(sink: *Sink, frameEnd: u64) fail
    {
        let frames = cast(u32) .index.count

        var main = .createMainHeader()
        main.totalFrames         = frames
        main.suggestedBufferSize = cast(u32) .largestFrame
        main.maxBytesPerSec      = .bytesPerSecond(frameEnd)
        patchValue(sink, .mainHeader, main)

        var stream = .createStreamHeader()
        stream.length              = frames
        stream.suggestedBufferSize = cast(u32) .largestFrame
        patchValue(sink, .streamHeader, stream)

        patchValue(sink, RiffSizeOffset, cast(u32) (sink.position() - ChunkHeaderSize))
        patchValue(sink, .frameListSize, cast(u32) (frameEnd - .frameList))
    }

    // Returns the average data rate of the finished stream, in bytes per second.
    private mtd const bytesPerSecond(frameEnd: u64)->u32
    {
        let seconds = cast(f64) .index.count * cast(f64) .info.frameRate.denominator() / cast(f64) .info.frameRate.numerator()
        if seconds <= 0 do
            return 0
        return cast(u32) Math.min(cast(f64) (frameEnd - .frameList) / seconds, cast(f64) Swag.U32.Max)
    }
}
