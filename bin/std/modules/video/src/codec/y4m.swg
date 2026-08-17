#global namespace Y4m

using Core, Core.Errors, Pixel

private const MaxHeaderBytes = 4096'u64

internal enum ColorRange
{
    Limited
    Full
}

internal enum ChromaMode
{
    Yuv420
    Yuv422
    Yuv444
    Mono
}

internal struct Index
{
    width:        s32
    height:       s32
    rate:         FrameRate
    colorRange:   ColorRange
    chromaMode:   ChromaMode
    frameOffsets: Array'u64
}

private func parsePositiveU32(value, field: string)->u32 fail
{
    let parsed = catch StrConv.toU32(value) as parseError
    if parseError != null or !parsed do
        fail InvalidFormatError{Errors.mkString(Format.toString("YUV4MPEG2 % needs a positive integer", field))}
    return parsed
}

private func parseHeader(line: string)->Index fail
{
    let tokens = Tokenize.split(line, ' 'u8)
    if !tokens.count or tokens[0] != "YUV4MPEG2" do
        fail InvalidFormatError{"YUV4MPEG2 stream header is missing"}

    var result: retval
    result.chromaMode = .Yuv420
    var hasWidth, hasHeight, hasRate, hasInterlace: bool
    for token in tokens[1 until tokens.count]
    {
        if @countof(token) < 2 do
            continue

        let value = token[1 until @countof(token)]
        switch token[0]
        {
        case 'W':
            let width = parsePositiveU32(value, "width")
            if width > cast(u32) (Swag.S32.Max / 4) do
                fail UnsupportedFormatError{"YUV4MPEG2 frame width exceeds Pixel image storage"}
            result.width = cast(s32) width
            hasWidth     = true

        case 'H':
            let height = parsePositiveU32(value, "height")
            if height > Swag.S32.Max do
                fail UnsupportedFormatError{"YUV4MPEG2 frame height exceeds Pixel image storage"}
            result.height = cast(s32) height
            hasHeight     = true

        case 'F':
            let parts = Tokenize.split(value, ':'u8, removeEmpty: false)
            if parts.count != 2 do
                fail InvalidFormatError{"YUV4MPEG2 frame rate needs numerator:denominator"}
            let numerator   = parsePositiveU32(parts[0], "frame-rate numerator")
            let denominator = parsePositiveU32(parts[1], "frame-rate denominator")
            result.rate = FrameRate.create(numerator, denominator)
            hasRate     = true

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

private func isFrameMarker(line: string)->bool
{
    return line == "FRAME" or Utf8.startsWith(line, "FRAME ")
}

private func readMemoryLine(bytes: const [..] u8, offset: *u64)->string fail
{
    if offset[] >= @countof(bytes) do
        fail InvalidFormatError{"YUV4MPEG2 line is truncated"}

    let start = offset[]
    while offset[] < @countof(bytes) and bytes[offset[]] != '\n'
    {
        offset[] += 1
        if offset[] - start > MaxHeaderBytes do
            fail InvalidFormatError{"YUV4MPEG2 line exceeds 4096 bytes"}
    }

    if offset[] == @countof(bytes) do
        fail InvalidFormatError{"YUV4MPEG2 line is truncated"}

    var end = offset[]
    offset[] += 1
    if end > start and bytes[end - 1] == '\r' do
        end -= 1
    return @mkstring(@dataof(bytes) + start, end - start)
}

private func readStreamLine(stream: *File.FileStream)->String fail
{
    var bytes: Array'u8
    while stream.position() < stream.size()
    {
        var value: u8
        if stream.read(&value, 1) != 1 do
            fail InvalidFormatError{"YUV4MPEG2 line is truncated"}
        if value == '\n'
        {
            if bytes.count and bytes.back() == '\r' do
                discard bytes.popBack()
            return String.from(@mkstring(bytes.buffer, bytes.count))
        }

        bytes.add(value)
        if bytes.count > MaxHeaderBytes do
            fail InvalidFormatError{"YUV4MPEG2 line exceeds 4096 bytes"}
    }

    fail InvalidFormatError{"YUV4MPEG2 line is truncated"}
}

internal func index(bytes: const [..] u8)->Index fail
{
    var offset: u64
    var result      = parseHeader(readMemoryLine(bytes, &offset))
    let payloadSize = framePayloadSize(result.width, result.height, result.chromaMode)

    while offset < @countof(bytes)
    {
        let marker = readMemoryLine(bytes, &offset)
        if !isFrameMarker(marker) do
            fail InvalidFormatError{"YUV4MPEG2 frame marker is missing"}
        if payloadSize > @countof(bytes) - offset do
            fail InvalidFormatError{"YUV4MPEG2 frame payload is truncated"}
        result.frameOffsets.add(offset)
        offset += payloadSize
    }

    if !result.frameOffsets.count do
        fail InvalidFormatError{"YUV4MPEG2 stream needs at least one frame"}
    return result
}

internal func index(fileName: string)->Index fail
{
    var stream      = File.openRead(fileName)
    var result      = parseHeader(readStreamLine(&stream).toString())
    let payloadSize = framePayloadSize(result.width, result.height, result.chromaMode)

    while stream.position() < stream.size()
    {
        let marker = readStreamLine(&stream)
        if !isFrameMarker(marker.toString()) do
            fail InvalidFormatError{"YUV4MPEG2 frame marker is missing"}
        if payloadSize > stream.size() - stream.position() do
            fail InvalidFormatError{"YUV4MPEG2 frame payload is truncated"}
        result.frameOffsets.add(stream.position())
        stream.skip(payloadSize)
    }

    if !result.frameOffsets.count do
        fail InvalidFormatError{"YUV4MPEG2 stream needs at least one frame"}
    return result
}

private func clampByte(value: s32)->u8 => cast(u8) Math.clamp(value, 0, 255)

private func decodePayload(payload: const [..] u8, width, height: s32, colorRange: ColorRange, chromaMode: ChromaMode)->Image
{
    let lumaSize       = cast(u64) width * cast(u64) height
    let chromaWidth    = chromaMode == .Yuv444 ? cast(u64) width : (cast(u64) width + 1) / 2
    let chromaHeight   = chromaMode == .Yuv420 ? (cast(u64) height + 1) / 2 : cast(u64) height
    let chromaSize     = chromaMode == .Mono ? 0 : chromaWidth * chromaHeight
    let chromaRowShift = chromaMode == .Yuv420 ? 1 : 0
    let chromaColShift = chromaMode == .Yuv444 ? 0 : 1
    var result: retval = Image.create(width, height, .RGB8)

    for y in height
    {
        let destinationRow = cast(u64) (height - y - 1) * cast(u64) result.rowStride
        for x in width
        {
            let source       = cast(u64) y * cast(u64) width + cast(u64) x
            let chromaSource = cast(u64) (y >> chromaRowShift) * chromaWidth + cast(u64) (x >> chromaColShift)
            let luma         = cast(s32) payload[source]
            let d            = chromaMode == .Mono ? 0 : cast(s32) payload[lumaSize + chromaSource] - 128
            let e            = chromaMode == .Mono ? 0 : cast(s32) payload[lumaSize + chromaSize + chromaSource] - 128
            let target       = result.pixels.buffer! + destinationRow + cast(u64) x * 3
            if colorRange == .Full
            {
                target[0] = clampByte(luma + ((359 * e + 128) >> 8))
                target[1] = clampByte(luma - ((88 * d + 183 * e + 128) >> 8))
                target[2] = clampByte(luma + ((454 * d + 128) >> 8))
            }
            else
            {
                let c = Math.max(luma - 16, 0)
                target[0] = clampByte((298 * c + 409 * e + 128) >> 8)
                target[1] = clampByte((298 * c - 100 * d - 208 * e + 128) >> 8)
                target[2] = clampByte((298 * c + 516 * d + 128) >> 8)
            }
        }
    }

    return result
}

internal func decodeFrame(bytes: const [..] u8, offset: u64, width, height: s32, colorRange: ColorRange, chromaMode: ChromaMode)->Image fail
{
    let payloadSize = framePayloadSize(width, height, chromaMode)
    if offset > @countof(bytes) or payloadSize > @countof(bytes) - offset do
        fail InvalidFormatError{"YUV4MPEG2 frame payload is truncated"}
    return decodePayload(bytes[offset until offset + payloadSize], width, height, colorRange, chromaMode)
}

internal func decodeFrame(fileName: string, offset: u64, width, height: s32, colorRange: ColorRange, chromaMode: ChromaMode)->Image fail
{
    let payloadSize = framePayloadSize(width, height, chromaMode)
    var payload: Array'u8
    payload.resize(payloadSize)

    var stream = File.openRead(fileName)
    if offset > stream.size() or payloadSize > stream.size() - offset do
        fail InvalidFormatError{"YUV4MPEG2 frame payload is truncated"}
    stream.seek(.Begin, offset)
    if stream.read(payload.toSlice()) != payloadSize do
        fail InvalidFormatError{"YUV4MPEG2 frame payload is truncated"}
    return decodePayload(payload.toSlice(), width, height, colorRange, chromaMode)
}

private func readRgb(image: Image, source: const [*] u8)->{ r: s32, g: s32, b: s32 }
{
    switch image.pixelFormat
    {
    case .RGB8, .RGBA8: return {source[0], source[1], source[2]}
    case .BGR8, .BGRA8: return {source[2], source[1], source[0]}
    }
}

private func encodeFrame(result: *ConcatBuffer, image: Image)
{
    let planeSize = cast(u64) image.width * cast(u64) image.height
    var payload: Array'u8
    payload.resize(planeSize * 3)
    let yPlane = payload.buffer!
    let uPlane = yPlane + planeSize
    let vPlane = uPlane + planeSize

    for y in image.height
    {
        let sourceRow = cast(u64) (image.height - y - 1) * cast(u64) image.rowStride
        for x in image.width
        {
            let source    = image.pixels.buffer! + sourceRow + cast(u64) x * image.bytesPerPixel
            let {r, g, b} = readRgb(image, source)
            let target    = cast(u64) y * cast(u64) image.width + cast(u64) x
            yPlane[target] = clampByte(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16)
            uPlane[target] = clampByte(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128)
            vPlane[target] = clampByte(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128)
        }
    }

    result.addBytes(payload.toSlice(), contiguous: false)
}

internal func encode(result: *ConcatBuffer, clip: const *Clip) fail
{
    Format.append(result, "YUV4MPEG2 W% H% F%:% Ip A0:0 C444 XYSCSS=444 XCOLORRANGE=LIMITED\n", clip.width(), clip.height(), clip.frameRate().numerator(), clip.frameRate().denominator())
    for index in clip.frameCount()
    {
        Format.append(result, "FRAME\n")
        let frame = try clip.decodeFrame(index)
        encodeFrame(result, frame)
    }
}
