//! Format: Audio Video Interleave (AVI/RIFF) encoder component.
//! Supported: Indexed Motion JPEG video with a standard `idx1` index and files up to the 32-bit RIFF size limit.
//! Not supported: OpenDML/AVI 2.0, audio tracks, uncompressed output, and files of 4 GiB or more.
//! Role: This file owns RIFF chunk emission, stream indexes, frame writing, and top-level encoding.
//
#global namespace Avi

using Core, Core.Errors, Pixel

// Largest frame side an encoded stream can describe, bounded by the 16-bit frame rectangle of
// the stream header.
private const MaxFrameSide = 32_767's32

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

// Identifier the frames of an encoded stream carry: compressed pictures of the first stream.
private const FrameChunkId = frameChunkId(0, 'd'u32, 'c'u32)

// Total size of the lists an encoder writes, counting their own identifier.
private const StreamListSize = FourCcSize + ChunkHeaderSize + #sizeof(StreamHeader) + ChunkHeaderSize + #sizeof(Bmp.Header)
private const HeaderListSize = FourCcSize + ChunkHeaderSize + #sizeof(MainHeader) + ChunkHeaderSize + StreamListSize

// One entry of the index an encoder builds while it writes.
private struct IndexEntry
{
    offset: u32     // Offset of the frame chunk, relative to the frame-list identifier.
    size:   u32     // Length of the frame payload, in bytes.
}

// Appends one value of the container's binary layout.
private func(T) writeValue(sink: *Sink, value: T) fail
{
    var stored = value
    sink.write(Swag.makeSlice(cast(const [*] u8) &stored, #sizeof(T)))
}

// Rewrites one value of a header the sink already accepted.
private func(T) patchValue(sink: *Sink, offset: u64, value: T) fail
{
    var stored = value
    sink.patch(offset, Swag.makeSlice(cast(const [*] u8) &stored, #sizeof(T)))
}

// Writes AVI files one frame at a time, compressing each of them as a JPEG image.
//
// Motion JPEG codes every frame on its own, so an encoded stream seeks anywhere at the cost of
// one frame and survives losing any part of itself, which is what a container written while it
// is being recorded needs. The totals the header carries — the size of the file, the size of the
// frame list, the number of frames — are reserved when the header is written and rewritten once
// the last frame lands, so encoding never holds more than one frame.
//
// [[Avi.EncodeOptions]] selects the quality of the frames.
struct Encoder
{
    internal
    {
        info:          StreamInfo           // Geometry and rate the stream was opened with.
        options:       EncodeOptions        // Compression the caller asked for.
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

    mtd impl begin(sink: *Sink, info: StreamInfo, options: #null any) fail
    {
        if info.width > MaxFrameSide or info.height > MaxFrameSide do
            fail UnsupportedFormatError{"AVI frame dimensions exceed what the container can describe"}

        .info = info
        if options.buffer != null
        {
            Debug.assert(Swag.kindOf(options) == EncodeOptions)
            .options = options.buffer![as EncodeOptions]
        }

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
        var frameOptions: Jpg.EncodeOptions
        frameOptions.quality = .options.quality

        var encoded = image.encode(JpegName, frameOptions)
        encoded.makeLinear()

        let payload = encoded.toSlice()!
        let size    = payload.count
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

private impl Encoder
{
    // Offset of the size field of the file, which is the first total to be rewritten.
    const RiffSizeOffset = 4'u64

    // Fails unless a frame of `size` bytes still fits in what the container can address.
    //
    // Every size in the container is a 32-bit field, so a stream that would run past four
    // gigabytes is refused while it is still correct rather than written with a size that wraps.
    mtd const reserve(sink: *Sink, size: u64) fail
    {
        let projected = sink.position() + ChunkHeaderSize + size + 1 + ChunkHeaderSize + (.index.count + 1) * IndexEntrySize
        if projected > MaxStreamSize do
            fail UnsupportedFormatError{"AVI stream exceeds the four gigabytes the container can address"}
    }

    // Returns the header of the file, with the totals it cannot know yet left at zero.
    mtd const createMainHeader()->MainHeader
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
    mtd const createStreamHeader()->StreamHeader
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
    mtd const createFormatHeader()->Bmp.Header
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
    mtd const patchTotals(sink: *Sink, frameEnd: u64) fail
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
    mtd const bytesPerSecond(frameEnd: u64)->u32
    {
        let seconds = cast(f64) .index.count * cast(f64) .info.frameRate.denominator() / cast(f64) .info.frameRate.numerator()
        if seconds <= 0 do
            return 0
        return cast(u32) Math.min(cast(f64) (frameEnd - .frameList) / seconds, cast(f64) Swag.U32.Max)
    }
}
