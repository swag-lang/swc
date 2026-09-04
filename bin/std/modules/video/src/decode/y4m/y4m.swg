//! Format: YUV4MPEG2 (Y4M) decoder component.
//! Supported: Progressive 8-bit mono, 4:2:0, 4:2:2, and 4:4:4 planar frames with limited or full range.
//! Not supported: Interlaced streams, bit depths above 8, alpha, 4:1:1, and other chroma modes.
//! Role: This file owns stream headers, frame markers, planar decoding, seeking, and top-level decoding.
//
#global namespace Y4m

using Core, Core.Errors, Pixel

// Longest stream header or frame marker accepted, in bytes.
//
// The signature line of the format has no length limit, so a bound is what keeps a
// malformed or non-video file from being read into memory one byte at a time.
private const MaxLineBytes = 4096'u64

// Signature line and frame marker of the format.
const StreamSignature = "YUV4MPEG2"
const FrameMarker     = "FRAME"

// Size of the shortest frame marker, `FRAME` followed by a line feed.
private const ShortMarkerSize = 6'u64

// Frame index meaning that the source sits between two frames.
//
// A read that fails part way through a frame leaves the position meaningless, so it is what the
// decoder holds until a seek reestablishes where it is.
private const NoFrameIndex = Swag.U64.Max

// Range the luma and chroma samples of a stream use.
enum ColorRange
{
    Limited     // Luma in `[16, 235]`, which is what the format assumes without a tag.
    Full        // Luma in `[0, 255]`, declared by an `XCOLORRANGE=FULL` tag.
}

// Plane layout of the frames of a stream.
enum ChromaMode
{
    Yuv420     // Chroma at half the width and half the height.
    Yuv422     // Chroma at half the width.
    Yuv444     // Chroma at the full frame size.
    Mono       // Luma only, with no chroma plane at all.
}

// Everything the signature line says about the frames that follow it.
private struct Header
{
    info:       StreamInfo
    colorRange: ColorRange
    chromaMode: ChromaMode
}

// Clamps one converted channel into the byte range.
func clampByte(value: s32)->u8 => cast(u8) Math.clamp(value, 0, 255)

private func parsePositiveU32(value, field: string)->u32 fail
{
    let parsed = catch StrConv.toU32(value) as parseError
    if parseError != null or !parsed do
        fail InvalidFormatError{Errors.mkString(Format.toString("YUV4MPEG2 % needs a positive integer", field))}
    return parsed
}

private func parseHeader(line: string)->Header fail
{
    let tokens = Tokenize.split(line, ' 'u8)
    if !tokens.count or tokens[0] != StreamSignature do
        fail InvalidFormatError{"YUV4MPEG2 stream header is missing"}

    var result: retval
    result.chromaMode = .Yuv420
    var hasWidth, hasHeight, hasRate, hasInterlace: bool
    for token in tokens[1 until tokens.count]
    {
        if token.count < 2 do
            continue

        let value = token[1 until token.count]
        switch token[0]
        {
        case 'W':
            let width = parsePositiveU32(value, "width")
            if width > cast(u32) (Swag.S32.Max / 4) do
                fail UnsupportedFormatError{"YUV4MPEG2 frame width exceeds Pixel image storage"}
            result.info.width = cast(s32) width
            hasWidth          = true

        case 'H':
            let height = parsePositiveU32(value, "height")
            if height > Swag.S32.Max do
                fail UnsupportedFormatError{"YUV4MPEG2 frame height exceeds Pixel image storage"}
            result.info.height = cast(s32) height
            hasHeight          = true

        case 'F':
            let parts = Tokenize.split(value, ':'u8, removeEmpty: false)
            if parts.count != 2 do
                fail InvalidFormatError{"YUV4MPEG2 frame rate needs numerator:denominator"}
            let numerator   = parsePositiveU32(parts[0], "frame-rate numerator")
            let denominator = parsePositiveU32(parts[1], "frame-rate denominator")
            result.info.frameRate = FrameRate.create(numerator, denominator)
            hasRate               = true

        case 'I':
            if value != "p" do
                fail UnsupportedFormatError{"video decoder only supports progressive YUV4MPEG2 streams"}
            hasInterlace = true

        case 'C':
            switch value
            {
            case "420", "420jpeg", "420mpeg2", "420paldv": result.chromaMode = .Yuv420
            case "422":  result.chromaMode = .Yuv422
            case "444":  result.chromaMode = .Yuv444
            case "mono": result.chromaMode = .Mono
            default:     fail UnsupportedFormatError{Errors.mkString(Format.toString("video decoder does not support YUV4MPEG2 C% chroma", value))}
            }

        case 'X':
            if value == "COLORRANGE=FULL" do
                result.colorRange = .Full
            elif value == "COLORRANGE=LIMITED" do
                result.colorRange = .Limited

        default:

            // Aspect ratio, comments, and extension tags do not change the decoded frame planes.
            continue
        }
    }

    if !hasWidth or !hasHeight do
        fail InvalidFormatError{"YUV4MPEG2 stream needs width and height"}
    if !hasRate do
        fail InvalidFormatError{"YUV4MPEG2 stream needs a frame rate"}
    if !hasInterlace do
        fail InvalidFormatError{"YUV4MPEG2 stream needs an interlacing mode"}
    return result
}

private func framePayloadSize(width, height: s32, chromaMode: ChromaMode)->u64
{
    let lumaSize = cast(u64) width * cast(u64) height
    switch chromaMode
    {
    case .Yuv420:
        let chromaSize = (cast(u64) width + 1) / 2 * ((cast(u64) height + 1) / 2)
        return lumaSize + chromaSize * 2

    case .Yuv422:
        let chromaSize = (cast(u64) width + 1) / 2 * cast(u64) height
        return lumaSize + chromaSize * 2

    case .Yuv444:
        return lumaSize * 3

    case .Mono:
        return lumaSize
    }
}

private func decodePayload(target: *Image, payload: const [..] u8, header: const *Header)
{
    let width          = header.info.width
    let height         = header.info.height
    let chromaMode     = header.chromaMode
    let lumaSize       = cast(u64) width * cast(u64) height
    let chromaWidth    = chromaMode == .Yuv444 ? cast(u64) width : (cast(u64) width + 1) / 2
    let chromaHeight   = chromaMode == .Yuv420 ? (cast(u64) height + 1) / 2 : cast(u64) height
    let chromaSize     = chromaMode == .Mono ? 0 : chromaWidth * chromaHeight
    let chromaRowShift = chromaMode == .Yuv420 ? 1 : 0
    let chromaColShift = chromaMode == .Yuv444 ? 0 : 1

    // Reusing the frame the caller already has is what keeps a whole stream at the memory cost
    // of one frame; a fresh image is created only when it cannot hold this one.
    if target.width != width or target.height != height or target.pixelFormat != .RGB8 do
        target[] = Image.create(width, height, .RGB8)

    for y in height
    {
        let destinationRow = cast(u64) (height - y - 1) * cast(u64) target.rowStride
        for x in width
        {
            let source       = cast(u64) y * cast(u64) width + cast(u64) x
            let chromaSource = cast(u64) (y >> chromaRowShift) * chromaWidth + cast(u64) (x >> chromaColShift)
            let luma         = cast(s32) payload[source]
            let d            = chromaMode == .Mono ? 0 : cast(s32) payload[lumaSize + chromaSource] - 128
            let e            = chromaMode == .Mono ? 0 : cast(s32) payload[lumaSize + chromaSize + chromaSource] - 128
            let destination  = target.pixels.buffer! + destinationRow + cast(u64) x * 3
            if header.colorRange == .Full
            {
                destination[0] = clampByte(luma + ((359 * e + 128) >> 8))
                destination[1] = clampByte(luma - ((88 * d + 183 * e + 128) >> 8))
                destination[2] = clampByte(luma + ((454 * d + 128) >> 8))
            }
            else
            {
                let c = Math.max(luma - 16, 0)
                destination[0] = clampByte((298 * c + 409 * e + 128) >> 8)
                destination[1] = clampByte((298 * c - 100 * d - 208 * e + 128) >> 8)
                destination[2] = clampByte((298 * c + 516 * d + 128) >> 8)
            }
        }
    }
}

// Reads YUV4MPEG2 streams one frame at a time.
//
// Frames of a stream all have the same payload size, and every practical writer emits the
// same bare frame marker, so the decoder locates frame `n` by arithmetic instead of indexing
// the file: opening a stream reads its header and nothing else, whatever its length. A stream
// whose markers are not uniform is read sequentially instead, and reports no frame count.
struct Decoder
{
    internal
    {
        header:         Header       // What the signature line described.
        payloadSize:    u64          // Size of one frame payload, in bytes.
        firstMarker:    u64          // Offset of the first frame marker.
        markerSize:     u64          // Size of the first frame marker, in bytes.
        frameStride:    u64          // Offset from one frame marker to the next.
        nextIndex:      u64          // Index of the frame the decoder is positioned on.
        isRandomAccess: bool         // Whether frame offsets can be computed instead of walked.
        payload:        Array'u8     // Scratch storage of one encoded frame.
    }
}

impl IDecoder for Decoder
{
    mtd impl format()->StreamFormat => {"Y4M - YUV4MPEG2 video", ".y4m"}

    mtd impl open(source: *Source)->StreamInfo fail
    {
        .header      = parseHeader(source.readLine(MaxLineBytes).toString())
        .payloadSize = framePayloadSize(.header.info.width, .header.info.height, .header.chromaMode)
        .firstMarker = source.position()
        if source.isAtEnd() do
            fail InvalidFormatError{"YUV4MPEG2 stream needs at least one frame"}

        .markerSize  = .readMarker(source)
        .frameStride = .markerSize + .payloadSize
        if .payloadSize > source.remaining() do
            fail InvalidFormatError{"YUV4MPEG2 frame payload is truncated"}

        // Every frame occupies the same number of bytes when its marker carries no per-frame
        // parameter, which is how the whole format is written in practice. Two cheap checks prove
        // it on a stream of any length: the frames must tile the file exactly, and the last marker
        // must be where that tiling says it is. A stream failing either one is walked instead,
        // and reports no frame count rather than a computed one that would be wrong.
        let span           = source.size() - .firstMarker
        var result: retval = .header.info
        result.frameCount = span / .frameStride
        .isRandomAccess   = !(span % .frameStride) and .probeLastFrame(source, result.frameCount)
        if !.isRandomAccess do
            result.frameCount = 0

        source.seek(.firstMarker)
        .nextIndex = 0
        return result
    }

    mtd impl syncFrameAt(index: u64)->u64 => index

    mtd impl seekFrame(source: *Source, index: u64) fail
    {
        if index == .nextIndex and .nextIndex != NoFrameIndex do
            return

        if .isRandomAccess
        {
            source.seek(.firstMarker + index * .frameStride)
            .nextIndex = index
            return
        }

        // Without uniform markers there is nothing to compute: the stream is walked, from the
        // current position when the target is ahead of it, and from the first frame otherwise.
        var walked = .nextIndex
        if walked == NoFrameIndex or index < walked
        {
            source.seek(.firstMarker)
            walked = 0
        }

        .nextIndex = NoFrameIndex
        while walked < index
        {
            discard .readMarker(source)
            source.skip(.payloadSize)
            walked += 1
        }

        .nextIndex = index
    }

    mtd impl decodeFrame(source: *Source, target: *Image) fail
    {
        let current = .nextIndex
        .nextIndex = NoFrameIndex

        discard .readMarker(source)
        if .payloadSize > source.remaining() do
            fail InvalidFormatError{"YUV4MPEG2 frame payload is truncated"}

        if .payload.count != .payloadSize do
            .payload.resize(.payloadSize)
        source.readExact(.payload.toSlice())
        decodePayload(target, .payload.toSlice(), &.header)
        .nextIndex = current + 1
    }
}

private impl Decoder
{
    // Reads one frame marker and returns the number of bytes it occupies.
    //
    // A marker may carry per-frame parameters after `FRAME`. They change nothing in the payload
    // that follows, but they do change where it starts, which is why the size is returned.
    mtd readMarker(source: *Source)->u64 fail
    {
        var marker: [ShortMarkerSize] u8
        source.readExact(marker)
        if Swag.memcmp(&marker[0], FrameMarker.buffer, FrameMarker.count) != 0 do
            fail InvalidFormatError{"YUV4MPEG2 frame marker is missing"}
        if marker[ShortMarkerSize - 1] == '\n' do
            return ShortMarkerSize
        if marker[ShortMarkerSize - 1] != ' ' and marker[ShortMarkerSize - 1] != '\r' do
            fail InvalidFormatError{"YUV4MPEG2 frame marker is missing"}

        var size = ShortMarkerSize
        while true
        {
            let value = source.readByte()
            size += 1
            if value == '\n' do
                return size
            if size > MaxLineBytes do
                fail InvalidFormatError{"YUV4MPEG2 frame marker exceeds its maximum length"}
        }
    }

    // Reports whether the last frame really starts where a constant frame size says it does.
    //
    // The position of `source` is left wherever the probe stopped; the caller seeks back to the
    // first frame either way.
    mtd probeLastFrame(source: *Source, frameCount: u64)->bool
    {
        if !frameCount do
            return false

        catch .checkFrameAt(source, .firstMarker + (frameCount - 1) * .frameStride) as probeError
        return probeError == null
    }

    // Fails unless a complete frame of the constant size starts at `offset`.
    mtd checkFrameAt(source: *Source, offset: u64) fail
    {
        source.seek(offset)
        if .readMarker(source) != .markerSize do
            fail InvalidFormatError{"YUV4MPEG2 frame markers do not have a constant size"}
        if .payloadSize > source.remaining() do
            fail InvalidFormatError{"YUV4MPEG2 frame payload is truncated"}
    }
}
