//! Format: ISO Base Media File Format (MP4/M4V/MOV) encoder component.
//! Supported: Motion JPEG video with 64-bit media data and classic sample tables.
//! Not supported: H.264 encoding, audio tracks, fragmented/encrypted media, edit lists, and metadata beyond the emitted core boxes.
//! Role: This file owns box emission, sample tables, timestamps, and top-level encoding.
//
#global namespace Mp4

using Core, Core.Errors, Pixel

const MediaDataId        = fourCc('m'u32, 'd'u32, 'a'u32, 't'u32)
const MovieHeaderId      = fourCc('m'u32, 'v'u32, 'h'u32, 'd'u32)
const TrackHeaderId      = fourCc('t'u32, 'k'u32, 'h'u32, 'd'u32)
const VideoMediaHeaderId = fourCc('v'u32, 'm'u32, 'h'u32, 'd'u32)
const DataInfoId         = fourCc('d'u32, 'i'u32, 'n'u32, 'f'u32)
const DataReferenceId    = fourCc('d'u32, 'r'u32, 'e'u32, 'f'u32)
const DataEntryUrlId     = fourCc('u'u32, 'r'u32, 'l'u32, ' 'u32)
const IsomBrandId        = fourCc('i'u32, 's'u32, 'o'u32, 'm'u32)
const Iso2BrandId        = fourCc('i'u32, 's'u32, 'o'u32, '2'u32)
const Mp41BrandId        = fourCc('m'u32, 'p'u32, '4'u32, '1'u32)

private const MaxFrameSide = 65_535's32
private const UndLanguage  = 0x55C4'u16

// One sample recorded while its payload is streamed into `mdat`.
private struct EncodedFrame
{
    offset: u64
    size:   u32
}

// Appends one byte.
private func writeU8(sink: *ByteSink, value: u8) fail => try sink.writeByte(value)

// Appends a big-endian 16-bit integer.
private func writeU16(sink: *ByteSink, value: u16) fail => try sink.writeBigEndian(value)

// Appends a big-endian 32-bit integer.
private func writeU32(sink: *ByteSink, value: u32) fail => try sink.writeBigEndian(value)

// Appends a big-endian 64-bit integer.
private func writeU64(sink: *ByteSink, value: u64) fail => try sink.writeBigEndian(value)

// Rewrites a big-endian 32-bit integer.
private func patchU32(sink: *ByteSink, offset: u64, value: u32) fail
{
    let stored = Math.nativeToBigEndian(value)
    try sink.patch(offset, Swag.makeSlice(cast(const [*] u8) &stored, #sizeof(u32)))
}

// Rewrites a big-endian 64-bit integer.
private func patchU64(sink: *ByteSink, offset: u64, value: u64) fail
{
    let stored = Math.nativeToBigEndian(value)
    try sink.patch(offset, Swag.makeSlice(cast(const [*] u8) &stored, #sizeof(u64)))
}

// Starts a compact box and returns its stream offset.
private func beginBox(sink: *ByteSink, kind: u32)->u64 fail
{
    let start = sink.position()
    try writeU32(sink, 0)
    try writeU32(sink, kind)
    return start
}

// Finishes a compact box by patching its size.
private func endBox(sink: *ByteSink, start: u64) fail
{
    let size = sink.position() - start
    if size > Swag.U32.Max do
        fail UnsupportedFormatError{"MP4 metadata box exceeds the four gigabytes its compact size can describe"}
    try patchU32(sink, start, cast(u32) size)
}

// Writes the version and 24-bit flags of a full box.
private func writeFullBox(sink: *ByteSink, version: u8, flags: u32) fail
{
    try writeU8(sink, version)
    try writeU8(sink, cast(u8) ((flags >> 16) & 0xFF))
    try writeU8(sink, cast(u8) ((flags >> 8) & 0xFF))
    try writeU8(sink, cast(u8) (flags & 0xFF))
}

// Writes the identity transform used by movie and track headers.
private func writeIdentityMatrix(sink: *ByteSink) fail
{
    const Matrix: [9] u32 = [0x0001_0000, 0, 0, 0, 0x0001_0000, 0, 0, 0, 0x4000_0000]
    for value in Matrix do
        try writeU32(sink, value)
}

// Writes MP4 files whose samples are independently encoded JPEG images.
//
// Frames are appended directly to one extended-size `mdat` box. The encoder retains only their
// offsets and sizes, then writes the movie and sample tables after the last frame and patches the
// media-data size. [[Mp4.EncodeOptions]] selects the JPEG quality.
struct Encoder
{
    internal
    {
        info:          StreamInfo
        options:       EncodeOptions
        frames:        Array'EncodedFrame
        mediaData:     u64
        mediaDataSize: u64
    }
}

impl IEncoder for Encoder
{
    mtd impl format()->StreamFormat => {"MP4 - ISO Base Media File Format", ".mp4;.m4v;.mov"}

    mtd impl begin(sink: *ByteSink, info: StreamInfo, options: any?) fail
    {
        if info.width > MaxFrameSide or info.height > MaxFrameSide do
            fail UnsupportedFormatError{"MP4 frame dimensions exceed what the visual sample entry can describe"}

        .info = info
        if options.buffer != null
        {
            Swag.assert(Swag.kindOf(options) == EncodeOptions)
            .options = options.buffer![as EncodeOptions]
        }

        try .writeFileType(sink)
        .mediaData = sink.position()
        try writeU32(sink, 1)
        try writeU32(sink, MediaDataId)
        .mediaDataSize = sink.position()
        try writeU64(sink, 0)
    }

    mtd impl addFrame(sink: *ByteSink, image: Image) fail
    {
        if .frames.count >= Swag.U32.Max do
            fail UnsupportedFormatError{"MP4 stream exceeds the frame count its sample tables can describe"}

        var frameOptions: Jpg.EncodeOptions
        frameOptions.quality = .options.quality
        var encoded = try image.encode(JpegName, frameOptions)
        encoded.makeLinear()
        let payload = encoded.toSlice()!
        if payload.count > Swag.U32.Max do
            fail UnsupportedFormatError{"MP4 JPEG sample exceeds the four gigabytes its sample table can describe"}

        .frames.add({sink.position(), cast(u32) payload.count})
        try sink.write(payload)
    }

    mtd impl end(sink: *ByteSink) fail
    {
        if not .frames.count do
            fail BadParameterError{"MP4 stream needs at least one frame"}
        try patchU64(sink, .mediaDataSize, sink.position() - .mediaData)
        try .writeMovie(sink)
    }
}

private impl Encoder
{
    mtd const duration()->u64 fail
    {
        let delta = cast(u64) .info.frameRate.denominator()
        if .frames.count > Swag.U64.Max / delta do
            fail UnsupportedFormatError{"MP4 stream duration exceeds the 64-bit media timeline"}
        return .frames.count * delta
    }

    mtd const writeFileType(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, FileTypeId)
        try writeU32(sink, IsomBrandId)
        try writeU32(sink, 0x0000_0200)
        try writeU32(sink, IsomBrandId)
        try writeU32(sink, Iso2BrandId)
        try writeU32(sink, Mp41BrandId)
        try endBox(sink, box)
    }

    mtd const writeMovie(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, MovieId)
        try .writeMovieHeader(sink)
        try .writeTrack(sink)
        try endBox(sink, box)
    }

    mtd const writeMovieHeader(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, MovieHeaderId)
        try writeFullBox(sink, 1, 0)
        try writeU64(sink, 0)
        try writeU64(sink, 0)
        try writeU32(sink, .info.frameRate.numerator())
        try writeU64(sink, try .duration())
        try writeU32(sink, 0x0001_0000)
        try writeU16(sink, 0x0100)
        try writeU16(sink, 0)
        try writeU32(sink, 0)
        try writeU32(sink, 0)
        try writeIdentityMatrix(sink)
        for 6 do
            try writeU32(sink, 0)
        try writeU32(sink, 2)
        try endBox(sink, box)
    }

    mtd const writeTrack(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, TrackId)
        try .writeTrackHeader(sink)
        try .writeMedia(sink)
        try endBox(sink, box)
    }

    mtd const writeTrackHeader(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, TrackHeaderId)
        try writeFullBox(sink, 1, 7)
        try writeU64(sink, 0)
        try writeU64(sink, 0)
        try writeU32(sink, 1)
        try writeU32(sink, 0)
        try writeU64(sink, try .duration())
        try writeU32(sink, 0)
        try writeU32(sink, 0)
        try writeU16(sink, 0)
        try writeU16(sink, 0)
        try writeU16(sink, 0)
        try writeU16(sink, 0)
        try writeIdentityMatrix(sink)
        try writeU32(sink, cast(u32) .info.width << 16)
        try writeU32(sink, cast(u32) .info.height << 16)
        try endBox(sink, box)
    }

    mtd const writeMedia(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, MediaId)
        try .writeMediaHeader(sink)
        try .writeHandler(sink)
        try .writeMediaInfo(sink)
        try endBox(sink, box)
    }

    mtd const writeMediaHeader(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, MediaHeaderId)
        try writeFullBox(sink, 1, 0)
        try writeU64(sink, 0)
        try writeU64(sink, 0)
        try writeU32(sink, .info.frameRate.numerator())
        try writeU64(sink, try .duration())
        try writeU16(sink, UndLanguage)
        try writeU16(sink, 0)
        try endBox(sink, box)
    }

    mtd const writeHandler(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, HandlerId)
        try writeFullBox(sink, 0, 0)
        try writeU32(sink, 0)
        try writeU32(sink, VideoHandlerId)
        try writeU32(sink, 0)
        try writeU32(sink, 0)
        try writeU32(sink, 0)
        try sink.writeText("Swag Motion JPEG\x00")
        try endBox(sink, box)
    }

    mtd const writeMediaInfo(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, MediaInfoId)
        try .writeVideoMediaHeader(sink)
        try .writeDataInfo(sink)
        try .writeSampleTable(sink)
        try endBox(sink, box)
    }

    mtd const writeVideoMediaHeader(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, VideoMediaHeaderId)
        try writeFullBox(sink, 0, 1)
        try writeU16(sink, 0)
        try writeU16(sink, 0)
        try writeU16(sink, 0)
        try writeU16(sink, 0)
        try endBox(sink, box)
    }

    mtd const writeDataInfo(sink: *ByteSink) fail
    {
        let dinf = try beginBox(sink, DataInfoId)
        let dref = try beginBox(sink, DataReferenceId)
        try writeFullBox(sink, 0, 0)
        try writeU32(sink, 1)
        let url = try beginBox(sink, DataEntryUrlId)
        try writeFullBox(sink, 0, 1)
        try endBox(sink, url)
        try endBox(sink, dref)
        try endBox(sink, dinf)
    }

    mtd const writeSampleTable(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, SampleTableId)
        try .writeSampleDescription(sink)
        try .writeTimeToSample(sink)
        try .writeSampleToChunk(sink)
        try .writeSampleSizes(sink)
        try .writeChunkOffsets(sink)
        try endBox(sink, box)
    }

    mtd const writeSampleDescription(sink: *ByteSink) fail
    {
        let stsd = try beginBox(sink, SampleDescriptionId)
        try writeFullBox(sink, 0, 0)
        try writeU32(sink, 1)

        let entry = try beginBox(sink, Mpeg4VisualId)
        try writeU32(sink, 0)
        try writeU16(sink, 0)
        try writeU16(sink, 1)
        try writeU16(sink, 0)
        try writeU16(sink, 0)
        try writeU32(sink, 0)
        try writeU32(sink, 0)
        try writeU32(sink, 0)
        try writeU16(sink, cast(u16) .info.width)
        try writeU16(sink, cast(u16) .info.height)
        try writeU32(sink, 72 << 16)
        try writeU32(sink, 72 << 16)
        try writeU32(sink, 0)
        try writeU16(sink, 1)

        const Compressor = "Swag Motion JPEG"
        try writeU8(sink, cast(u8) Compressor.count)
        try sink.writeText(Compressor)
        for 31 - Compressor.count do
            try writeU8(sink, 0)
        try writeU16(sink, 24)
        try writeU16(sink, 0xFFFF)
        try .writeElementaryStreamDescriptor(sink)
        try endBox(sink, entry)
        try endBox(sink, stsd)
    }

    // Identifies the generic `mp4v` sample entry as ISO/IEC 10918-1 JPEG.
    mtd const writeElementaryStreamDescriptor(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, ElementaryStreamId)
        try writeFullBox(sink, 0, 0)

        try writeU8(sink, 3)
        try writeU8(sink, 21)
        try writeU16(sink, 1)
        try writeU8(sink, 0)

        try writeU8(sink, 4)
        try writeU8(sink, 13)
        try writeU8(sink, JpegObjectType)
        try writeU8(sink, 0x11)
        try writeU8(sink, 0)
        try writeU8(sink, 0)
        try writeU8(sink, 0)
        try writeU32(sink, 0)
        try writeU32(sink, 0)

        try writeU8(sink, 6)
        try writeU8(sink, 1)
        try writeU8(sink, 2)
        try endBox(sink, box)
    }

    mtd const writeTimeToSample(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, TimeToSampleId)
        try writeFullBox(sink, 0, 0)
        try writeU32(sink, 1)
        try writeU32(sink, cast(u32) .frames.count)
        try writeU32(sink, .info.frameRate.denominator())
        try endBox(sink, box)
    }

    mtd const writeSampleToChunk(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, SampleToChunkId)
        try writeFullBox(sink, 0, 0)
        try writeU32(sink, 1)
        try writeU32(sink, 1)
        try writeU32(sink, 1)
        try writeU32(sink, 1)
        try endBox(sink, box)
    }

    mtd const writeSampleSizes(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, SampleSizeId)
        try writeFullBox(sink, 0, 0)
        try writeU32(sink, 0)
        try writeU32(sink, cast(u32) .frames.count)
        for frame in .frames do
            try writeU32(sink, frame.size)
        try endBox(sink, box)
    }

    mtd const writeChunkOffsets(sink: *ByteSink) fail
    {
        let box = try beginBox(sink, ChunkOffset64Id)
        try writeFullBox(sink, 0, 0)
        try writeU32(sink, cast(u32) .frames.count)
        for frame in .frames do
            try writeU64(sink, frame.offset)
        try endBox(sink, box)
    }
}
