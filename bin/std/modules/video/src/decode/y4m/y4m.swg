//! Format: YUV4MPEG2 (Y4M) decoder component.
//! Supported: Progressive 8-bit mono, 4:1:1, 4:2:0, 4:2:2, and 4:4:4 planar frames with limited or full range and display geometry from aspect tags.
//! Not supported: Interlaced streams, bit depths above 8, alpha, and other chroma modes.
//! Role: This file owns stream headers, frame markers, planar decoding, seeking, and top-level decoding.
//
#global namespace Y4m

using Core, Core.Errors, Pixel

// Longest stream header or frame marker accepted, in bytes.
//
// The signature line of the format has no length limit, so a bound is what keeps a
// malformed or non-video file from being read into memory one byte at a time.
private const MaxLineBytes = 4096_u64

// Signature line and frame marker of the format.
const StreamSignature = "YUV4MPEG2"
const FrameMarker     = "FRAME"

// Size of the shortest frame marker, `FRAME` followed by a line feed.
private const ShortMarkerSize = 6_u64

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
    Yuv411     // Chroma at one-quarter the width.
    Yuv420     // Chroma at half the width and half the height.
    Yuv422     // Chroma at half the width.
    Yuv444     // Chroma at the full frame size.
    Mono       // Luma only, with no chroma plane at all.
}

// Everything the signature line says about the frames that follow it.
private struct Header
{
    info:         StreamInfo
    colorRange:   ColorRange
    chromaMode:   ChromaMode
    aspectWidth:  u32
    aspectHeight: u32
}

// Clamps one converted channel into the byte range.
func clampByte(value: s32)->u8 => cast(u8, Math.clamp(value, 0, 255))

private func parsePositiveU32(value, field: string)->u32 fail
{
    var parseErrorOutcome: Swag.Error
    var parsed: #decltype(expect StrConv.toU32(value))
    catch { parsed = try StrConv.toU32(value) } as parseErrorOutcome
    let parseError = parseErrorOutcome.value()
    if parseError != null or not parsed
    {
        fail InvalidFormatError{Errors.mkString(Format.toString("YUV4MPEG2 % needs a positive integer", field))}
    }

    return parsed
}

private func parseHeader(line: string)->Header fail
{
    let tokens = Tokenize.split(line, ' '_u8)
    if not tokens.count or tokens[0] != StreamSignature
    {
        fail InvalidFormatError{"YUV4MPEG2 stream header is missing"}
    }

    var result: #returntype
    result.chromaMode = .Yuv420
    var hasWidth, hasHeight, hasRate, hasInterlace: bool
    for token in tokens[1 until tokens.count]
    {
        if token.count < 2
        {
            if token.count and token[0] == 'A'
            {
                fail InvalidFormatError{"YUV4MPEG2 aspect ratio needs width:height"}
            }

            if token.count and
               (token[0] == 'W' or
                token[0] == 'H' or
                token[0] == 'F' or
                token[0] == 'I' or
                token[0] == 'C' or
                token[0] == 'X')
            {
                fail InvalidFormatError{"YUV4MPEG2 header field needs a value"}
            }

            continue
        }

        let value = token[1 until token.count]
        switch token[0]
        {
        case 'W':
            let width = try parsePositiveU32(value, "width")
            if width > cast(u32, (Swag.S32.Max / 4))
            {
                fail UnsupportedFormatError{"YUV4MPEG2 frame width exceeds Pixel image storage"}
            }

            result.info.width = cast(s32, width)
            hasWidth = true

        case 'H':
            let height = try parsePositiveU32(value, "height")
            if height > Swag.S32.Max
            {
                fail UnsupportedFormatError{"YUV4MPEG2 frame height exceeds Pixel image storage"}
            }

            result.info.height = cast(s32, height)
            hasHeight = true

        case 'F':
            let parts = Tokenize.split(value, ':'_u8, removeEmpty: false)
            if parts.count != 2
            {
                fail InvalidFormatError{"YUV4MPEG2 frame rate needs numerator:denominator"}
            }

            let numerator   = try parsePositiveU32(parts[0], "frame-rate numerator")
            let denominator = try parsePositiveU32(parts[1], "frame-rate denominator")
            result.info.frameRate = try FrameRate.create(numerator, denominator)
            hasRate = true

        case 'I':
            if value != "p"
            {
                fail UnsupportedFormatError{"video decoder only supports progressive YUV4MPEG2 streams"}
            }

            hasInterlace = true

        case 'C':
            switch value
            {
            case "411":  result.chromaMode = .Yuv411
            case "420", "420jpeg", "420mpeg2", "420paldv": result.chromaMode = .Yuv420
            case "422":  result.chromaMode = .Yuv422
            case "444":  result.chromaMode = .Yuv444
            case "mono": result.chromaMode = .Mono
            default:     fail UnsupportedFormatError{Errors.mkString(Format.toString("video decoder does not support YUV4MPEG2 C% chroma", value))}
            }

        case 'A':
            let parts = Tokenize.split(value, ':'_u8, removeEmpty: false)
            if parts.count != 2
            {
                fail InvalidFormatError{"YUV4MPEG2 aspect ratio needs width:height"}
            }

            if parts[0] == "0" and parts[1] == "0"
            {
                result.aspectWidth  = 0
                result.aspectHeight = 0
            }
            else
            {
                result.aspectWidth  = try parsePositiveU32(parts[0], "aspect width")
                result.aspectHeight = try parsePositiveU32(parts[1], "aspect height")
            }

        case 'X':
            if value == "COLORRANGE=FULL"
            {
                result.colorRange = .Full
            }
            else if value == "COLORRANGE=LIMITED"
            {
                result.colorRange = .Limited
            }

        default:

            // Aspect ratio, comments, and extension tags do not change the decoded frame planes.
            continue
        }
    }

    if not hasWidth or not hasHeight
    {
        fail InvalidFormatError{"YUV4MPEG2 stream needs width and height"}
    }

    if not hasRate
    {
        fail InvalidFormatError{"YUV4MPEG2 stream needs a frame rate"}
    }

    if not hasInterlace
    {
        fail InvalidFormatError{"YUV4MPEG2 stream needs an interlacing mode"}
    }

    if result.aspectWidth and result.aspectHeight
    {
        let display = pictureDisplaySize(result.info.width, result.info.height, result.aspectWidth, result.aspectHeight)
        result.info.displayWidth  = display.width
        result.info.displayHeight = display.height
    }

    return result
}

private func framePayloadSize(width, height: s32, chromaMode: ChromaMode)->u64
{
    let lumaSize = cast(u64, width) * cast(u64, height)
    switch #complete chromaMode
    {
    case .Yuv411:
        let chromaSize = (cast(u64, width) + 3) / 4 * cast(u64, height)
        return lumaSize + chromaSize * 2

    case .Yuv420:
        let chromaSize = (cast(u64, width) + 1) / 2 * ((cast(u64, height) + 1) / 2)
        return lumaSize + chromaSize * 2

    case .Yuv422:
        let chromaSize = (cast(u64, width) + 1) / 2 * cast(u64, height)
        return lumaSize + chromaSize * 2

    case .Yuv444:
        return lumaSize * 3

    case .Mono:
        return lumaSize
    }
}

#[Swag.Inline]
private func(T, Full: bool) convertRgb(y, u, v: T)->{r: T, g: T, b: T}
{
    let width       = header.info.width
    let height      = header.info.height
    let chromaMode  = header.chromaMode
    let lumaSize    = cast(u64, width) * cast(u64, height)
    let chromaWidth = chromaMode == .Yuv444 ? cast(u64, width) :
                      (chromaMode == .Yuv411 ? (cast(u64, width) + 3) / 4 :
                       (cast(u64, width) + 1) / 2)
    let chromaHeight   = chromaMode == .Yuv420 ? (cast(u64, height) + 1) / 2 : cast(u64, height)
    let chromaSize     = chromaMode == .Mono ? 0 : chromaWidth * chromaHeight
    let chromaRowShift = chromaMode == .Yuv420 ? 1 : 0
    let chromaColShift = chromaMode == .Yuv444 ? 0 : (chromaMode == .Yuv411 ? 2 : 1)

    // Reusing the frame the caller already has is what keeps a whole stream at the memory cost
    // of one frame; a fresh image is created only when it cannot hold this one.
    if target.width != width or target.height != height or target.pixelFormat != .RGB8
    {
        target[] = Image.create(width, height, .RGB8)
    }

    for y in height
    {
        return {r: y + ((359 * v + 128) >> 8),
                g: y - ((88 * u + 183 * v + 128) >> 8),
                b: y + ((454 * u + 128) >> 8)}
    }
    else
    {
        let base = 298 * Math.max(y - 16, y - y) + 128
        return {r: (base + 409 * v) >> 8,
                g: (base - 100 * u - 208 * v) >> 8,
                b: (base + 516 * u) >> 8}
    }
}

#[Swag.Inline]
private func widenBytes(samples: Math.Simd.U8x16)->Math.Simd.S32x4 =>
    cast #bit(Math.Simd.S32x4, Math.Simd.widenLow(Math.Simd.widenLow(samples)))

#[Swag.Inline]
private func(Shift: u32) chroma4(source: const [*] u8)->Math.Simd.S32x4
{
    #static if Shift == 0 {
        return widenBytes(cast #bit(Math.Simd.U8x16, Math.Simd.splat(cast(const [*] u32, source)[0]))) - 128
    }
    else {
        return Math.Simd.splat(cast(s32, source[0]) - 128)
    }
}

#[Swag.Inline]
private func packedSamples(value: Math.Simd.S32x4)->Math.Simd.U8x16
{
    let shorts = Math.Simd.packSigned(value, value)
    return Math.Simd.packUnsigned(shorts, shorts)
}

#[Swag.Inline]
private func storeRgb4(target: [*] u8, r, g, b: Math.Simd.S32x4)
{
    const Pixels = cast(Math.Simd.U8x16, [0_u8, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 128, 128, 128, 128])
    let rg     = Math.Simd.interleaveLow(packedSamples(r), packedSamples(g))
    let bx     = Math.Simd.interleaveLow(packedSamples(b), Math.Simd.splat(0_u8))
    let words  = Math.Simd.interleaveLow(cast #bit(Math.Simd.U16x8, rg), cast #bit(Math.Simd.U16x8, bx))
    let packed = Math.Simd.shuffle(cast #bit(Math.Simd.U8x16, words), Pixels)
    cast([*] u64, target)[0] = cast #bit(Math.Simd.U64x2, packed)[0]
    cast([*] u32, target)[2] = cast #bit(Math.Simd.U32x4, packed)[2]
}

private func(Shift: u32, Mono: bool, Full: bool) decodeRows(target: *Image, payload: const [..] u8, header: const *Header)
{
    let width       = cast(u64, header.info.width)
    let height      = cast(u64, header.info.height)
    let chromaWidth = (width + (1_u64 << Shift) - 1) >> Shift
    let chromaSize  = chromaWidth * height
    let groups      = width / 4
    let packed      = unwrap payload.buffer
    let output      = target.pixels.storage()
    let stride      = cast(u64, target.rowStride)
    for row in height
    {
        let luma        = packed + row * width
        let destination = output + (height - row - 1) * stride
        var cb          = packed
        var cr          = packed
        #static if not Mono
        {
            cb = packed + width * height + row * chromaWidth
            cr = cb + chromaSize
        }

        for group in groups
        {
            let col = group * 4
            let y   = widenBytes(cast #bit(Math.Simd.U8x16, Math.Simd.splat(cast(const [*] u32, luma + col)[0])))
            var u, v: Math.Simd.S32x4
            #static if not Mono
            {
                u = chroma4!{Shift}(cb + (col >> Shift))
                v = chroma4!{Shift}(cr + (col >> Shift))
            }

            let rgb = convertRgb!{Math.Simd.S32x4, Full}(y, u, v)
            storeRgb4(destination + col * 3, rgb.r, rgb.g, rgb.b)
        }

        for col in groups * 4 until width
        {
            var u, v: s32
            #static if not Mono
            {
                u = cast(s32, cb[col >> Shift]) - 128
                v = cast(s32, cr[col >> Shift]) - 128
            }

            let rgb   = convertRgb!{s32, Full}(cast(s32, luma[col]), u, v)
            let pixel = destination + col * 3
            pixel[0] = clampByte(rgb.r)
            pixel[1] = clampByte(rgb.g)
            pixel[2] = clampByte(rgb.b)
        }
    }
}

private struct ChromaCorrection
{
    red, green, blue: Math.Simd.S16x8
    redFraction, greenFraction, blueFraction: Math.Simd.S16x8
}

#[Swag.Inline]
private func duplicateChroma4(source: const [*] u8)->Math.Simd.S16x8
{
    using Math.Simd
    let bytes = cast #bit(U8x16, splat(cast(const [*] u32, source)[0]))
    let words = widenLow(bytes)
    return cast #bit(S16x8, interleaveLow(words, words)) - 128
}

#[Swag.Inline]
private func(Full: bool) chromaCorrection8(cb, cr: const [*] u8)->ChromaCorrection
{
    let u = duplicateChroma4(cb)
    let v = duplicateChroma4(cr)
    var result: #returntype
    #static if Full
    {
        result.red   = v + ((103 * v + 128) >> 8)
        result.green = -v - ((88 * u - 73 * v + 128) >> 8)
        result.blue  = u + ((198 * u + 128) >> 8)
    }
    else
    {
        // Split coefficients at 256 so each correction and its fraction fit signed lanes.
        let red   = 153 * v
        let green = -100 * u + 48 * v
        let blue  = 4 * u
        result.red           = v + (red >> 8)
        result.green         = (green >> 8) - v
        result.blue          = (u << 1) + (blue >> 8)
        result.redFraction   = red & 255
        result.greenFraction = green & 255
        result.blueFraction  = blue & 255
    }

    return result
}

#[Swag.Inline]
private func(Full: bool) convertSubsampled8(target: [*] u8, luma: const [*] u8, correction: const *ChromaCorrection)
{
    using Math.Simd
    const TripletLowRg  = cast(U8x16, [0_u8, 8, 128, 1, 9, 128, 2, 10, 128, 3, 11, 128, 4, 12, 128, 5])
    const TripletLowB   = cast(U8x16, [128_u8, 128, 0, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 4, 128])
    const TripletHighRg = cast(U8x16, [13_u8, 128, 6, 14, 128, 7, 15, 128, 128, 128, 128, 128, 128, 128, 128, 128])
    const TripletHighB  = cast(U8x16, [128_u8, 5, 128, 128, 6, 128, 128, 7, 128, 128, 128, 128, 128, 128, 128, 128])
    let lumaBytes = cast #bit(U8x16, splat(cast(const [*] u64, luma)[0]))
    var y         = cast #bit(S16x8, widenLow(lumaBytes))
    var fraction: S16x8
    #static if not Full
    {
        y = Math.max(y - 16, splat(0_s16))
        let remainder = 42 * y + 128
        y        += remainder >> 8
        fraction = remainder & 255
    }

    var red   = y + correction.red
    var green = y + correction.green
    var blue  = y + correction.blue
    #static if not Full
    {
        // Carry the low byte into the combined value before clamping to an RGB sample.
        red   += (fraction + correction.redFraction) >> 8
        green += (fraction + correction.greenFraction) >> 8
        blue  += (fraction + correction.blueFraction) >> 8
    }

    let rg = packUnsigned(red, green)
    let b  = packUnsigned(blue, blue)
    store(target, shuffle(rg, TripletLowRg) | shuffle(b, TripletLowB))
    storeLow8(target + 16, shuffle(rg, TripletHighRg) | shuffle(b, TripletHighB))
}

private func(Full: bool, Pair: bool) decodeSubsampledRow(target: [*] u8, luma, cb, cr: const [*] u8, width, stride: u64)
{
    using Math.Simd
    let groups = width / 8
    for group in groups
    {
        let correction = chromaCorrection8!{Full}(cb + group * 4, cr + group * 4)
        convertSubsampled8!{Full}(target + group * 24, luma + group * 8, &correction)
        #static if Pair {
            convertSubsampled8!{Full}(target - stride + group * 24, luma + width + group * 8, &correction)
        }
    }

    const Rows = Pair ? 2_u64 : 1_u64
    for row in Rows
    {
        let destination = target - row * stride
        let y = luma + row * width
        for col in groups * 8 until width
        {
            let u     = cast(s32, cb[col / 2]) - 128
            let v     = cast(s32, cr[col / 2]) - 128
            let rgb   = convertRgb!{s32, Full}(cast(s32, y[col]), u, v)
            let pixel = destination + col * 3
            pixel[0] = clampByte(rgb.r)
            pixel[1] = clampByte(rgb.g)
            pixel[2] = clampByte(rgb.b)
        }
    }
}

private func(Full: bool, Vertical: bool) decodeSubsampled(target: *Image, payload: const [..] u8, header: const *Header)
{
    const RowCount = Vertical ? 2_u64 : 1_u64
    let width       = cast(u64, header.info.width)
    let height      = cast(u64, header.info.height)
    let stride      = cast(u64, target.rowStride)
    let chromaWidth = (width + 1) / 2
    let chromaSize  = chromaWidth * ((height + RowCount - 1) / RowCount)
    let y           = unwrap payload.buffer
    let cb          = y + width * height
    let cr          = cb + chromaSize
    let output      = target.pixels.storage() + (height - 1) * stride
    for pair in height / RowCount
    {
        let row    = pair * RowCount
        let chroma = pair * chromaWidth
        decodeSubsampledRow!{Full, Vertical}(output - row * stride, y + row * width, cb + chroma, cr + chroma, width, stride)
    }

    #static if Vertical
    {
        if height % 2
        {
            let chroma = (height / 2) * chromaWidth
            decodeSubsampledRow!{Full, false}(target.pixels.storage(), y + (height - 1) * width, cb + chroma, cr + chroma, width, stride)
        }
    }
}

private func(Full: bool) decodeRowsForRange(target: *Image, payload: const [..] u8, header: const *Header)
{
    switch #complete header.chromaMode
    {
    case .Yuv411: decodeRows!{2, false, Full}(target, payload, header)
    case .Yuv420: decodeSubsampled!{Full, true}(target, payload, header)
    case .Yuv422: decodeSubsampled!{Full, false}(target, payload, header)
    case .Yuv444: decodeRows!{0, false, Full}(target, payload, header)
    case .Mono:   decodeRows!{0, true, Full}(target, payload, header)
    }
}

private func decodePayload(target: *Image, payload: const [..] u8, header: const *Header)
{
    let width  = header.info.width
    let height = header.info.height

    // Reuse the caller's destination when it has the correct geometry and RGB layout.
    if target.width != width or target.height != height or target.pixelFormat != .RGB8 {
        target[] = Image.create(width, height, .RGB8)
    }
    if header.colorRange == .Full {
        decodeRowsForRange!{true}(target, payload, header)
    }
    else {
        decodeRowsForRange!{false}(target, payload, header)
    }
}

// Reads YUV4MPEG2 streams one frame at a time.
//
// Frames of a stream all have the same payload size. The decoder checks each frame marker at
// open while skipping the image payloads; uniform markers permit arithmetic seeks without an
// offset table. Variable markers fall back to sequential reading and report no frame count.
struct Decoder
{
    internal
    {
        header:         Header         // What the signature line described.
        payloadSize:    u64            // Size of one frame payload, in bytes.
        firstMarker:    u64            // Offset of the first frame marker.
        markerSize:     u64            // Size of the first frame marker, in bytes.
        frameStride:    u64            // Offset from one frame marker to the next.
        nextIndex:      u64            // Index of the frame the decoder is positioned on.
        isRandomAccess: bool           // Whether frame offsets can be computed instead of walked.
        payload:        Array!{u8}     // Scratch storage of one encoded frame.
    }
}

impl IDecoder for Decoder
{
    mtd impl format()->StreamFormat => {"Y4M - YUV4MPEG2 video", ".y4m"}

    mtd impl open(source: *ByteSource)->StreamInfo fail
    {
        .header      = try parseHeader(try source.readLine(MaxLineBytes).toString())
        .payloadSize = framePayloadSize(.header.info.width, .header.info.height, .header.chromaMode)
        .firstMarker = source.position()
        if source.isAtEnd()
        {
            fail InvalidFormatError{"YUV4MPEG2 stream needs at least one frame"}
        }

        .markerSize  = try .readMarker(source)
        .frameStride = .markerSize + .payloadSize
        if .payloadSize > source.remaining()
        {
            fail InvalidFormatError{"YUV4MPEG2 frame payload is truncated"}
        }

        // Every frame occupies the same number of bytes when its marker carries no per-frame
        // parameter, which is how the whole format is written in practice. Tiling and the last
        // marker are cheap filters; checking every marker is still needed because variable marker
        // lengths can cancel each other out. A stream failing any check is walked instead, and
        // reports no frame count rather than a computed one that would be wrong.
        let span = source.size() - .firstMarker
        var result: #returntype = .header.info
        result.codecName  = "Uncompressed YUV"
        result.frameCount = span / .frameStride
        .isRandomAccess   = not (span % .frameStride) and .probeUniformFrames(source, result.frameCount)
        if not .isRandomAccess
        {
            result.frameCount = 0
        }

        try source.seek(.firstMarker)
        .nextIndex = 0
        return result
    }

    mtd impl syncFrameAt(index: u64)->u64 => index

    mtd impl seekFrame(source: *ByteSource, index: u64) fail
    {
        if index == .nextIndex and .nextIndex != NoFrameIndex
        {
            return
        }

        if .isRandomAccess
        {
            try source.seek(.firstMarker + index * .frameStride)
            .nextIndex = index
            return
        }

        // Without uniform markers there is nothing to compute: the stream is walked, from the
        // current position when the target is ahead of it, and from the first frame otherwise.
        var walked = .nextIndex
        if walked == NoFrameIndex or index < walked
        {
            try source.seek(.firstMarker)
            walked = 0
        }

        .nextIndex = NoFrameIndex
        while walked < index
        {
            discard try .readMarker(source)
            try source.skip(.payloadSize)
            walked += 1
        }

        .nextIndex = index
    }

    mtd impl decodeFrame(source: *ByteSource, target: *Image) fail
    {
        let current = .nextIndex
        .nextIndex = NoFrameIndex

        discard try .readMarker(source)
        if .payloadSize > source.remaining()
        {
            fail InvalidFormatError{"YUV4MPEG2 frame payload is truncated"}
        }

        if .payload.count != .payloadSize
        {
            .payload.resize(.payloadSize)
        }

        try source.readExact(.payload.toSlice())
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
    mtd readMarker(source: *ByteSource)->u64 fail
    {
        var marker: [ShortMarkerSize] u8
        try source.readExact(marker)
        if Swag.memcmp(&marker[0], FrameMarker.buffer, FrameMarker.count) != 0
        {
            fail InvalidFormatError{"YUV4MPEG2 frame marker is missing"}
        }

        if marker[ShortMarkerSize - 1] == '\n'
        {
            return ShortMarkerSize
        }

        if marker[ShortMarkerSize - 1] != ' ' and marker[ShortMarkerSize - 1] != '\r'
        {
            fail InvalidFormatError{"YUV4MPEG2 frame marker is missing"}
        }

        var size = ShortMarkerSize
        while true
        {
            let value = try source.readByte()
            size += 1
            if value == '\n'
            {
                return size
            }

            if size > MaxLineBytes
            {
                fail InvalidFormatError{"YUV4MPEG2 frame marker exceeds its maximum length"}
            }
        }
    }

    // Reports whether every frame really starts where a constant frame size says it does.
    //
    // Marker sizes can differ and later changes can compensate for earlier ones, leaving the
    // file length and last marker at the expected offsets. The caller seeks back to the first
    // frame after this probe either way.
    mtd probeUniformFrames(source: *ByteSource, frameCount: u64)->bool
    {
        if not frameCount
        {
            return false
        }

        var probeErrorOutcome: Swag.Error
        catch .checkUniformFrames(source, frameCount) as probeErrorOutcome
        let probeError = probeErrorOutcome.value()
        return probeError == null
    }

    // Fails unless every frame in the candidate count has the first marker's size.
    mtd checkUniformFrames(source: *ByteSource, frameCount: u64) fail
    {
        try source.seek(.firstMarker)
        for frameCount
        {
            if try .readMarker(source) != .markerSize
            {
                fail InvalidFormatError{"YUV4MPEG2 frame markers do not have a constant size"}
            }

            if .payloadSize > source.remaining()
            {
                fail InvalidFormatError{"YUV4MPEG2 frame payload is truncated"}
            }

            try source.skip(.payloadSize)
        }
    }
}
