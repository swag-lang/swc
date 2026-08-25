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
private const UndLanguage = 0x55C4'u16

// One sample recorded while its payload is streamed into `mdat`.
private struct EncodedFrame
{
    offset: u64
    size:   u32
}

// Appends one byte.
private func writeU8(sink: *Sink, value: u8) fail
{
    var stored = value
    sink.write(@mkslice(&stored, 1))
}

// Appends a big-endian 16-bit integer.
private func writeU16(sink: *Sink, value: u16) fail
{
    var bytes: [2] u8 = [cast(u8) ((value >> 8) & 0xFF), cast(u8) (value & 0xFF)]
    sink.write(bytes)
}

// Appends a big-endian 32-bit integer.
private func writeU32(sink: *Sink, value: u32) fail
{
    var bytes: [4] u8 = [cast(u8) ((value >> 24) & 0xFF), cast(u8) ((value >> 16) & 0xFF), cast(u8) ((value >> 8) & 0xFF), cast(u8) (value & 0xFF)]
    sink.write(bytes)
}

// Appends a big-endian 64-bit integer.
private func writeU64(sink: *Sink, value: u64) fail
{
    writeU32(sink, cast(u32) (value >> 32))
    writeU32(sink, cast(u32) (value & 0xFFFF_FFFF))
}

// Rewrites a big-endian 32-bit integer.
private func patchU32(sink: *Sink, offset: u64, value: u32) fail
{
    var bytes: [4] u8 = [cast(u8) ((value >> 24) & 0xFF), cast(u8) ((value >> 16) & 0xFF), cast(u8) ((value >> 8) & 0xFF), cast(u8) (value & 0xFF)]
    sink.patch(offset, bytes)
}

// Rewrites a big-endian 64-bit integer.
private func patchU64(sink: *Sink, offset: u64, value: u64) fail
{
    var bytes: [8] u8 = [cast(u8) ((value >> 56) & 0xFF), cast(u8) ((value >> 48) & 0xFF), cast(u8) ((value >> 40) & 0xFF), cast(u8) ((value >> 32) & 0xFF), cast(u8) ((value >> 24) & 0xFF), cast(u8) ((value >> 16) & 0xFF), cast(u8) ((value >> 8) & 0xFF), cast(u8) (value & 0xFF)]
    sink.patch(offset, bytes)
}

// Starts a compact box and returns its stream offset.
private func beginBox(sink: *Sink, kind: u32)->u64 fail
{
    let start = sink.position()
    writeU32(sink, 0)
    writeU32(sink, kind)
    return start
}

// Finishes a compact box by patching its size.
private func endBox(sink: *Sink, start: u64) fail
{
    let size = sink.position() - start
    if size > Swag.U32.Max do
        fail UnsupportedFormatError{"MP4 metadata box exceeds the four gigabytes its compact size can describe"}
    patchU32(sink, start, cast(u32) size)
}

// Writes the version and 24-bit flags of a full box.
private func writeFullBox(sink: *Sink, version: u8, flags: u32) fail
{
    writeU8(sink, version)
    writeU8(sink, cast(u8) ((flags >> 16) & 0xFF))
    writeU8(sink, cast(u8) ((flags >> 8) & 0xFF))
    writeU8(sink, cast(u8) (flags & 0xFF))
}

// Writes the identity transform used by movie and track headers.
private func writeIdentityMatrix(sink: *Sink) fail
{
    const Matrix: [9] u32 = [0x0001_0000, 0, 0, 0, 0x0001_0000, 0, 0, 0, 0x4000_0000]
    for value in Matrix do
        writeU32(sink, value)
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

    mtd impl begin(sink: *Sink, info: StreamInfo, options: #null any) fail
    {
        if info.width > MaxFrameSide or info.height > MaxFrameSide do
            fail UnsupportedFormatError{"MP4 frame dimensions exceed what the visual sample entry can describe"}

        .info = info
        if @dataof(options) != null
        {
            Debug.assert(@kindof(options) == EncodeOptions)
            .options = @dataof(options)![as EncodeOptions]
        }

        .writeFileType(sink)
        .mediaData = sink.position()
        writeU32(sink, 1)
        writeU32(sink, MediaDataId)
        .mediaDataSize = sink.position()
        writeU64(sink, 0)
    }

    mtd impl addFrame(sink: *Sink, image: Image) fail
    {
        if .frames.count >= Swag.U32.Max do
            fail UnsupportedFormatError{"MP4 stream exceeds the frame count its sample tables can describe"}

        var frameOptions: Jpg.EncodeOptions
        frameOptions.quality = .options.quality
        var encoded = image.encode(JpegName, frameOptions)
        encoded.makeLinear()
        let payload = encoded.toSlice()!
        if @countof(payload) > Swag.U32.Max do
            fail UnsupportedFormatError{"MP4 JPEG sample exceeds the four gigabytes its sample table can describe"}

        .frames.add({sink.position(), cast(u32) @countof(payload)})
        sink.write(payload)
    }

    mtd impl end(sink: *Sink) fail
    {
        if !.frames.count do
            fail BadParameterError{"MP4 stream needs at least one frame"}
        patchU64(sink, .mediaDataSize, sink.position() - .mediaData)
        .writeMovie(sink)
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

    mtd const writeFileType(sink: *Sink) fail
    {
        let box = beginBox(sink, FileTypeId)
        writeU32(sink, IsomBrandId)
        writeU32(sink, 0x0000_0200)
        writeU32(sink, IsomBrandId)
        writeU32(sink, Iso2BrandId)
        writeU32(sink, Mp41BrandId)
        endBox(sink, box)
    }

    mtd const writeMovie(sink: *Sink) fail
    {
        let box = beginBox(sink, MovieId)
        .writeMovieHeader(sink)
        .writeTrack(sink)
        endBox(sink, box)
    }

    mtd const writeMovieHeader(sink: *Sink) fail
    {
        let box = beginBox(sink, MovieHeaderId)
        writeFullBox(sink, 1, 0)
        writeU64(sink, 0)
        writeU64(sink, 0)
        writeU32(sink, .info.frameRate.numerator())
        writeU64(sink, .duration())
        writeU32(sink, 0x0001_0000)
        writeU16(sink, 0x0100)
        writeU16(sink, 0)
        writeU32(sink, 0)
        writeU32(sink, 0)
        writeIdentityMatrix(sink)
        for 6 do
            writeU32(sink, 0)
        writeU32(sink, 2)
        endBox(sink, box)
    }

    mtd const writeTrack(sink: *Sink) fail
    {
        let box = beginBox(sink, TrackId)
        .writeTrackHeader(sink)
        .writeMedia(sink)
        endBox(sink, box)
    }

    mtd const writeTrackHeader(sink: *Sink) fail
    {
        let box = beginBox(sink, TrackHeaderId)
        writeFullBox(sink, 1, 7)
        writeU64(sink, 0)
        writeU64(sink, 0)
        writeU32(sink, 1)
        writeU32(sink, 0)
        writeU64(sink, .duration())
        writeU32(sink, 0)
        writeU32(sink, 0)
        writeU16(sink, 0)
        writeU16(sink, 0)
        writeU16(sink, 0)
        writeU16(sink, 0)
        writeIdentityMatrix(sink)
        writeU32(sink, cast(u32) .info.width << 16)
        writeU32(sink, cast(u32) .info.height << 16)
        endBox(sink, box)
    }

    mtd const writeMedia(sink: *Sink) fail
    {
        let box = beginBox(sink, MediaId)
        .writeMediaHeader(sink)
        .writeHandler(sink)
        .writeMediaInfo(sink)
        endBox(sink, box)
    }

    mtd const writeMediaHeader(sink: *Sink) fail
    {
        let box = beginBox(sink, MediaHeaderId)
        writeFullBox(sink, 1, 0)
        writeU64(sink, 0)
        writeU64(sink, 0)
        writeU32(sink, .info.frameRate.numerator())
        writeU64(sink, .duration())
        writeU16(sink, UndLanguage)
        writeU16(sink, 0)
        endBox(sink, box)
    }

    mtd const writeHandler(sink: *Sink) fail
    {
        let box = beginBox(sink, HandlerId)
        writeFullBox(sink, 0, 0)
        writeU32(sink, 0)
        writeU32(sink, VideoHandlerId)
        writeU32(sink, 0)
        writeU32(sink, 0)
        writeU32(sink, 0)
        sink.writeText("Swag Motion JPEG\x00")
        endBox(sink, box)
    }

    mtd const writeMediaInfo(sink: *Sink) fail
    {
        let box = beginBox(sink, MediaInfoId)
        .writeVideoMediaHeader(sink)
        .writeDataInfo(sink)
        .writeSampleTable(sink)
        endBox(sink, box)
    }

    mtd const writeVideoMediaHeader(sink: *Sink) fail
    {
        let box = beginBox(sink, VideoMediaHeaderId)
        writeFullBox(sink, 0, 1)
        writeU16(sink, 0)
        writeU16(sink, 0)
        writeU16(sink, 0)
        writeU16(sink, 0)
        endBox(sink, box)
    }

    mtd const writeDataInfo(sink: *Sink) fail
    {
        let dinf = beginBox(sink, DataInfoId)
        let dref = beginBox(sink, DataReferenceId)
        writeFullBox(sink, 0, 0)
        writeU32(sink, 1)
        let url = beginBox(sink, DataEntryUrlId)
        writeFullBox(sink, 0, 1)
        endBox(sink, url)
        endBox(sink, dref)
        endBox(sink, dinf)
    }

    mtd const writeSampleTable(sink: *Sink) fail
    {
        let box = beginBox(sink, SampleTableId)
        .writeSampleDescription(sink)
        .writeTimeToSample(sink)
        .writeSampleToChunk(sink)
        .writeSampleSizes(sink)
        .writeChunkOffsets(sink)
        endBox(sink, box)
    }

    mtd const writeSampleDescription(sink: *Sink) fail
    {
        let stsd = beginBox(sink, SampleDescriptionId)
        writeFullBox(sink, 0, 0)
        writeU32(sink, 1)

        let entry = beginBox(sink, Mpeg4VisualId)
        writeU32(sink, 0)
        writeU16(sink, 0)
        writeU16(sink, 1)
        writeU16(sink, 0)
        writeU16(sink, 0)
        writeU32(sink, 0)
        writeU32(sink, 0)
        writeU32(sink, 0)
        writeU16(sink, cast(u16) .info.width)
        writeU16(sink, cast(u16) .info.height)
        writeU32(sink, 72 << 16)
        writeU32(sink, 72 << 16)
        writeU32(sink, 0)
        writeU16(sink, 1)

        const Compressor = "Swag Motion JPEG"
        writeU8(sink, cast(u8) @countof(Compressor))
        sink.writeText(Compressor)
        for 31 - @countof(Compressor) do
            writeU8(sink, 0)
        writeU16(sink, 24)
        writeU16(sink, 0xFFFF)
        .writeElementaryStreamDescriptor(sink)
        endBox(sink, entry)
        endBox(sink, stsd)
    }

    // Identifies the generic `mp4v` sample entry as ISO/IEC 10918-1 JPEG.
    mtd const writeElementaryStreamDescriptor(sink: *Sink) fail
    {
        let box = beginBox(sink, ElementaryStreamId)
        writeFullBox(sink, 0, 0)

        writeU8(sink, 3)
        writeU8(sink, 21)
        writeU16(sink, 1)
        writeU8(sink, 0)

        writeU8(sink, 4)
        writeU8(sink, 13)
        writeU8(sink, JpegObjectType)
        writeU8(sink, 0x11)
        writeU8(sink, 0)
        writeU8(sink, 0)
        writeU8(sink, 0)
        writeU32(sink, 0)
        writeU32(sink, 0)

        writeU8(sink, 6)
        writeU8(sink, 1)
        writeU8(sink, 2)
        endBox(sink, box)
    }

    mtd const writeTimeToSample(sink: *Sink) fail
    {
        let box = beginBox(sink, TimeToSampleId)
        writeFullBox(sink, 0, 0)
        writeU32(sink, 1)
        writeU32(sink, cast(u32) .frames.count)
        writeU32(sink, .info.frameRate.denominator())
        endBox(sink, box)
    }

    mtd const writeSampleToChunk(sink: *Sink) fail
    {
        let box = beginBox(sink, SampleToChunkId)
        writeFullBox(sink, 0, 0)
        writeU32(sink, 1)
        writeU32(sink, 1)
        writeU32(sink, 1)
        writeU32(sink, 1)
        endBox(sink, box)
    }

    mtd const writeSampleSizes(sink: *Sink) fail
    {
        let box = beginBox(sink, SampleSizeId)
        writeFullBox(sink, 0, 0)
        writeU32(sink, 0)
        writeU32(sink, cast(u32) .frames.count)
        for frame in .frames do
            writeU32(sink, frame.size)
        endBox(sink, box)
    }

    mtd const writeChunkOffsets(sink: *Sink) fail
    {
        let box = beginBox(sink, ChunkOffset64Id)
        writeFullBox(sink, 0, 0)
        writeU32(sink, cast(u32) .frames.count)
        for frame in .frames do
            writeU64(sink, frame.offset)
        endBox(sink, box)
    }
}
