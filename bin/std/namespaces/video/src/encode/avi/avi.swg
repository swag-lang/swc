//! Format: Audio Video Interleave (AVI/RIFF) encoder component.
//! Supported: Motion JPEG video in classic AVI or an OpenDML stream with RIFF AVIX continuations.
//! Not supported: Audio tracks and uncompressed output.
//! Role: This file owns RIFF chunk emission, stream indexes, frame writing, and top-level encoding.
//
#global namespace Avi

using Core, Core.Errors, Pixel

// Largest frame side an encoded stream can describe, bounded by the 16-bit frame rectangle of
// the stream header.
private const MaxFrameSide = 32_767_s32

// `AVIF_HASINDEX`: the first RIFF includes a legacy index.
private const MainHasIndex = 0x0000_0010_u32

// Quality the stream header reports when the writer does not measure one.
private const UnknownQuality = 0xFFFF_FFFF_u32

// OpenDML keeps each complete RIFF at or below 1 GiB. One reserved superindex entry
// addresses each RIFF, with a 64-bit absolute offset.
private const MaxRiffBytes = 1_u64 << 30
private const MaxRiffs     = 256_u64

// Identifiers for the header reservation and the standard index of video stream 00.
private const JunkId = fourCc('J'_u32, 'U'_u32, 'N'_u32, 'K'_u32)
private const StandardIndexId = fourCc('i'_u32, 'x'_u32, '0'_u32, '0'_u32)

// Identifier the frames of an encoded stream carry: compressed pictures of the first stream.
private const FrameChunkId = frameChunkId(0, 'd'_u32, 'c'_u32)

// Payload sizes, including list identifiers and payloads of nested chunks.
private const SuperIndexSize     = #sizeof(OpenDmlIndexHeader) + MaxRiffs * #sizeof(OpenDmlIndexReference)
private const ExtendedHeaderSize = 248_u64
private const ExtendedListSize   = FourCcSize + ChunkHeaderSize + ExtendedHeaderSize
private const StreamListSize     = FourCcSize + ChunkHeaderSize + #sizeof(StreamHeader) +
                                   ChunkHeaderSize + #sizeof(Bmp.Header) + ChunkHeaderSize + SuperIndexSize
private const HeaderListSize = FourCcSize + ChunkHeaderSize + #sizeof(MainHeader) +
                               ChunkHeaderSize + StreamListSize + ChunkHeaderSize + ExtendedListSize
private const ContinuationSize = 2 * (ChunkHeaderSize + FourCcSize)

// One entry of the index an encoder builds while it writes.
private struct IndexEntry
{
    offset: u32     // Offset of the frame chunk, relative to the frame-list identifier.
    size:   u32     // Length of the frame payload, in bytes.
}

// Rewrites one value of a header the sink already accepted.
private func(T) patchValue(sink: *ByteSink, offset: u64, value: T) fail
{
    var stored = value
    try sink.patch(offset, Swag.makeSlice(cast(const [*] u8, &stored), #sizeof(T)))
}

// Writes AVI files one frame at a time, compressing each of them as a JPEG image.
//
// The encoder writes one JPEG at a time and keeps only the current RIFF's frame index in
// memory. A single RIFF uses a classic `idx1` index. If a frame would overrun the RIFF,
// it finishes the current index, records its location in the reserved superindex, and
// begins an `AVIX` continuation. The header reservation becomes OpenDML during finalization.
//
// [[Avi.EncodeOptions]] selects the quality of the frames.
struct Encoder
{
    internal
    {
        info:            StreamInfo             // Geometry and rate of the stream.
        options:         EncodeOptions          // Compression the caller asked for.
        index:           Array!{IndexEntry}     // Frame offsets within the active RIFF.
        riffLimit = MaxRiffBytes                // Largest byte count of one complete RIFF.
        riffStart:       u64                    // Offset of the current RIFF identifier.
        frameList:       u64                    // Offset of the current movi identifier.
        mainHeader:      u64                    // Offset of the avih payload.
        streamHeader:    u64                    // Offset of the strh payload.
        superIndex:      u64                    // Offset of the reserved indx chunk.
        extendedHeader:  u64                    // Offset of the reserved odml list.
        standardIndexes: u64                    // Number of finished standard indexes.
        firstRiffFrames: u32                    // Legacy frame count in the original RIFF.
        frames:          u32                    // Total frame count over all RIFFs.
        frameBytes:      u64                    // Total size of the written frame chunks.
        largestFrame:    u64                    // Largest frame payload in bytes.
    }
}

impl IEncoder for Encoder
{
    mtd impl format()->StreamFormat => {"AVI - Audio Video Interleave", ".avi"}

    #[Swag.Propagate]
    mtd impl begin(sink: *ByteSink, info: StreamInfo, options: any?) fail
    {
        if info.width > MaxFrameSide or info.height > MaxFrameSide
        {
            fail UnsupportedFormatError{"AVI frame dimensions exceed what the container can describe"}
        }

        .info = info
        if options.buffer != null
        {
            Swag.assert(Swag.kindOf(options) == EncodeOptions)
            .options = cast(const *EncodeOptions, unwrap options.buffer)[]
        }

        .beginRiff(sink, AviId)

        sink.writeNative(ListId)
        sink.writeNative(cast(u32, HeaderListSize))
        sink.writeNative(HeaderListId)

        sink.writeNative(MainHeaderId)
        sink.writeNative(cast(u32, #sizeof(MainHeader)))
        .mainHeader = sink.position()
        sink.writeNative(.createMainHeader())

        sink.writeNative(ListId)
        sink.writeNative(cast(u32, StreamListSize))
        sink.writeNative(StreamListId)

        sink.writeNative(StreamHeaderId)
        sink.writeNative(cast(u32, #sizeof(StreamHeader)))
        .streamHeader = sink.position()
        sink.writeNative(.createStreamHeader())

        sink.writeNative(StreamFormatId)
        sink.writeNative(cast(u32, #sizeof(Bmp.Header)))
        sink.writeNative(.createFormatHeader())

        // Keep the short file a classic AVI. Only a multi-RIFF file enables these chunks.
        .superIndex = sink.position()
        sink.writeNative(JunkId)
        sink.writeNative(cast(u32, SuperIndexSize))
        var indexSpace: [SuperIndexSize] u8
        sink.write(indexSpace)

        .extendedHeader = sink.position()
        sink.writeNative(JunkId)
        sink.writeNative(cast(u32, ExtendedListSize))
        sink.writeNative(OpenDmlListId)
        sink.writeNative(OpenDmlHeaderId)
        sink.writeNative(cast(u32, ExtendedHeaderSize))
        var extendedSpace: [ExtendedHeaderSize] u8
        sink.write(extendedSpace)

        .beginFrameList(sink)
    }

    #[Swag.Propagate]
    mtd impl addFrame(sink: *ByteSink, image: Image) fail
    {
        var frameOptions: Jpg.EncodeOptions
        frameOptions.quality = .options.quality

        var encoded = image.encode(JpegName, frameOptions)
        encoded.makeLinear()

        let payload = unwrap encoded.toSlice()
        let size    = payload.count
        .reserve(sink, size)

        let offset = cast(u32, sink.position() - .frameList)
        sink.writeNative(FrameChunkId)
        sink.writeNative(cast(u32, size))
        sink.write(payload)

        // RIFF pads an odd payload so the next chunk starts on an even offset.
        if size & 1
        {
            sink.writeNative(0_u8)
        }

        .index.add(IndexEntry{offset, cast(u32, size)})
        .frames       += 1
        .frameBytes   += ChunkHeaderSize + size + (size & 1)
        .largestFrame = Math.max(.largestFrame, size)
    }

    #[Swag.Propagate]
    mtd impl end(sink: *ByteSink) fail
    {
        if not .frames
        {
            fail BadParameterError{"AVI stream needs at least one frame"}
        }

        .finishRiff(sink, openDml: .riffStart != 0)
        .patchTotals(sink)
    }
}

private impl Encoder
{
    #[Swag.Propagate]
    mtd beginRiff(sink: *ByteSink, kind: u32) fail
    {
        .riffStart = sink.position()
        sink.writeNative(RiffId)
        sink.writeNative(0_u32)
        sink.writeNative(kind)
    }

    #[Swag.Propagate]
    mtd beginFrameList(sink: *ByteSink) fail
    {
        sink.writeNative(ListId)
        sink.writeNative(0_u32)
        .frameList = sink.position()
        sink.writeNative(FrameListId)
    }

    // Includes index bytes when checking the new frame. If a rollover is needed, confirm that
    // the new frame fits in the next RIFF and that both indexes have reserved slots first.
    mtd reserve(sink: *ByteSink, size: u64) fail
    {
        if .frames == Swag.U32.Max
        {
            fail UnsupportedFormatError{"AVI stream exceeds the 32-bit frame count"}
        }

        if size > .riffLimit
        {
            fail UnsupportedFormatError{"AVI frame exceeds the RIFF size limit"}
        }

        let frameBytes = ChunkHeaderSize + size + (size & 1)
        let entries    = .index.count + 1
        let indexBytes = ChunkHeaderSize + #sizeof(OpenDmlIndexHeader) + entries * #sizeof(IndexEntry)
        let legacy     = .riffStart ? 0_u64 : ChunkHeaderSize + entries * IndexEntrySize
        if sink.position() - .riffStart + frameBytes + indexBytes + legacy <= .riffLimit
        {
            return
        }

        if .index.isEmpty() or
           ContinuationSize + frameBytes + ChunkHeaderSize +
           #sizeof(OpenDmlIndexHeader) + #sizeof(IndexEntry) > .riffLimit
        {
            fail UnsupportedFormatError{"AVI frame exceeds the RIFF size limit"}
        }

        if .standardIndexes >= MaxRiffs - 1
        {
            fail UnsupportedFormatError{"AVI stream exceeds the OpenDML superindex capacity"}
        }

        try .finishRiff(sink, openDml: true)
        try .beginRiff(sink, AvixId)
        try .beginFrameList(sink)
    }

    #[Swag.Propagate]
    mtd finishRiff(sink: *ByteSink, openDml: bool) fail
    {
        if openDml
        {
            .writeStandardIndex(sink)
        }

        let frameEnd = sink.position()
        if not .riffStart
        {
            sink.writeNative(IndexId)
            sink.writeNative(cast(u32, .index.count * IndexEntrySize))
            for entry in .index
            {
                sink.writeNative(IndexRecord{FrameChunkId, IndexKeyFrameFlag, entry.offset, entry.size})
            }

            .firstRiffFrames = cast(u32, .index.count)
        }

        patchValue(sink, .frameList - FourCcSize, cast(u32, frameEnd - .frameList))
        patchValue(sink, .riffStart + FourCcSize, cast(u32, sink.position() - .riffStart - ChunkHeaderSize))
        .index.clear()
    }

    #[Swag.Propagate]
    mtd writeStandardIndex(sink: *ByteSink) fail
    {
        let start = sink.position()
        sink.writeNative(StandardIndexId)
        sink.writeNative(cast(u32, #sizeof(OpenDmlIndexHeader) + .index.count * #sizeof(IndexEntry)))
        sink.writeNative(OpenDmlIndexHeader{entryWords: 2, kind: IndexOfChunks,
                                            count: cast(u32, .index.count), chunkId: FrameChunkId, base: .frameList})
        for entry in .index
        {
            // A standard index points at the payload. The legacy index points at the tag.
            sink.writeNative(IndexEntry{entry.offset + cast(u32, ChunkHeaderSize), entry.size})
        }

        let slot = .superIndex + ChunkHeaderSize + #sizeof(OpenDmlIndexHeader) +
                   .standardIndexes * #sizeof(OpenDmlIndexReference)
        patchValue(sink, slot, OpenDmlIndexReference{start, cast(u32, sink.position() - start), cast(u32, .index.count)})
        .standardIndexes += 1
    }

    // Returns the header of the file, with the totals it cannot know yet left at zero.
    mtd const createMainHeader()->MainHeader
    {
        var result: #returntype

        // The main header's integer microseconds are advisory; the stream header keeps the exact ratio.
        let framePeriod = 1_000_000_u64 * cast(u64, .info.frameRate.denominator()) /
                          cast(u64, .info.frameRate.numerator())
        result.microSecPerFrame = cast(u32, Math.min(Math.max(framePeriod, 1_u64), cast(u64, Swag.U32.Max)))
        result.flags   = MainHasIndex
        result.streams = 1
        result.width   = cast(u32, .info.width)
        result.height  = cast(u32, .info.height)
        return result
    }

    // Returns the header of the video stream, with its length left at zero.
    mtd const createStreamHeader()->StreamHeader
    {
        var result: #returntype
        result.kind        = VideoStreamId
        result.handler     = MotionJpegIds[0]
        result.scale       = .info.frameRate.denominator()
        result.rate        = .info.frameRate.numerator()
        result.quality     = UnknownQuality
        result.frameRight  = cast(s16, .info.width)
        result.frameBottom = cast(s16, .info.height)
        return result
    }

    // Returns the bitmap header describing the frames of the video stream.
    mtd const createFormatHeader()->Bmp.Header
    {
        var result: #returntype
        result.biSize        = cast(u32, #sizeof(Bmp.Header))
        result.biWidth       = .info.width
        result.biHeight      = .info.height
        result.biPlanes      = 1
        result.biBitCount    = 24
        result.biCompression = MotionJpegIds[0]
        result.biSizeImage   = cast(u32, (cast(u64, .info.width) * cast(u64, .info.height) * 3))
        return result
    }

    // Rewrites the header fields only the finished stream knows.
    #[Swag.Propagate]
    mtd const patchTotals(sink: *ByteSink) fail
    {
        var main = .createMainHeader()
        main.totalFrames         = .firstRiffFrames
        main.suggestedBufferSize = cast(u32, .largestFrame)
        main.maxBytesPerSec      = .bytesPerSecond()
        patchValue(sink, .mainHeader, main)

        var stream = .createStreamHeader()
        stream.length = .frames
        stream.suggestedBufferSize = cast(u32, .largestFrame)
        patchValue(sink, .streamHeader, stream)

        if .standardIndexes
        {
            patchValue(sink, .superIndex, OpenDmlIndexId)
            patchValue(sink,
                       .superIndex + ChunkHeaderSize,
                       OpenDmlIndexHeader{entryWords: 4, kind: IndexOfIndexes,
                                          count: cast(u32, .standardIndexes), chunkId: FrameChunkId})

            patchValue(sink, .extendedHeader, ListId)
            patchValue(sink, .extendedHeader + 2 * ChunkHeaderSize + FourCcSize, .frames)
        }
    }

    // Returns the average frame data rate of the finished stream, in bytes per second.
    mtd const bytesPerSecond()->u32
    {
        let seconds = cast(f64, .frames) * cast(f64, .info.frameRate.denominator()) / cast(f64, .info.frameRate.numerator())
        return cast(u32, Math.min(cast(f64, .frameBytes + FourCcSize) / seconds, cast(f64, Swag.U32.Max)))
    }
}
