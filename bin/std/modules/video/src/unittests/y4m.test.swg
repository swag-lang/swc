#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

private func videoTestImage(width, height: s32, pixels: const [..] u8)->Image
{
    return Image.create(width, height, .RGB8, pixels)
}

private func videoAssertColor(actual: Color, r, g, b: u8, tolerance = 3)
{
    @assert(Math.abs(cast(s32) actual.r - r) <= tolerance)
    @assert(Math.abs(cast(s32) actual.g - g) <= tolerance)
    @assert(Math.abs(cast(s32) actual.b - b) <= tolerance)
}

#test
{
    let rate = expect FrameRate.create(30_000, 1_001)
    @assert(rate.numerator() == 30_000)
    @assert(rate.denominator() == 1_001)
    @assert(rate.framesPerSecond() > 29.97 and rate.framesPerSecond() < 29.971)

    discard catch FrameRate.create(0, 1) as zeroNumerator
    discard catch FrameRate.create(1, 0) as zeroDenominator
    @assert(zeroNumerator is BadParameterError)
    @assert(zeroDenominator is BadParameterError)
}

#test
{
    const FullRangeRed = "YUV4MPEG2 W1 H1 F1:1 Ip A0:0 C444 XYSCSS=444 XCOLORRANGE=FULL\nFRAME\n"
    var bytes: Array'u8
    bytes.add(cast(const [..] u8) FullRangeRed)
    bytes.add([76'u8, 85, 255])
    let clip  = expect Clip.decode("full-range.y4m", bytes.toSlice())
    let frame = expect clip.decodeFrame(0)
    videoAssertColor(frame.pixelColor(0, 0), 255, 0, 0)
}

// The first encoded frame is specified byte for byte, independently of this module's decoder.
#test
{
    let rate  = expect FrameRate.create(25, 1)
    var clip  = expect Clip.create(2, 1, rate)
    let frame = videoTestImage(2, 1, [0'u8, 0, 0, 255, 255, 255])
    expect clip.addFrame(frame)

    let encoded = expect clip.encodeToBytes("sample.y4m")
    let header  = "YUV4MPEG2 W2 H1 F25:1 Ip A0:0 C444 XYSCSS=444 XCOLORRANGE=LIMITED\nFRAME\n"
    @assert(encoded.count == @countof(header) + 6)
    @assert(@mkstring(encoded.buffer, @countof(header)) == header)
    let payload = encoded.toSlice()[@countof(header) until encoded.count]
    const ExpectedPayload: [6] u8 = [16, 235, 128, 128, 128, 128]
    for value, index in ExpectedPayload do
        @assert(payload[index] == value)
}

#test
{
    let rate   = expect FrameRate.create(24, 1)
    var source = expect Clip.create(2, 2, rate)

    // Pixel storage is bottom-up. The two rows differ so the codec also proves Y4M's top-down
    // scan order instead of only preserving a flat color.
    let first = videoTestImage(2, 2, [0'u8, 0, 255, 255, 255, 255,
                                      255, 0, 0, 0, 255, 0])
    let second = videoTestImage(2, 2, [255'u8, 255, 0, 0, 255, 255,
                                       255, 0, 255, 16, 24, 32])
    expect source.addFrame(first)
    expect source.addFrame(second)

    let bytes   = expect source.encodeToBytes("roundtrip.y4m")
    let decoded = expect Clip.decode("roundtrip.y4m", bytes.toSlice())
    @assert(decoded.isValid())
    @assert(decoded.width() == 2 and decoded.height() == 2)
    @assert(decoded.frameCount() == 2)
    @assert(decoded.durationInSeconds() == 2.0 / 24.0)

    let frame0 = expect decoded.decodeFrame(0)
    let frame1 = expect decoded.decodeFrame(1)
    videoAssertColor(frame0.pixelColor(0, 0), 255, 0, 0)
    videoAssertColor(frame0.pixelColor(1, 0), 0, 255, 0)
    videoAssertColor(frame0.pixelColor(0, 1), 0, 0, 255)
    videoAssertColor(frame0.pixelColor(1, 1), 255, 255, 255)
    videoAssertColor(frame1.pixelColor(1, 0), 16, 24, 32)
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("video-y4m-%.y4m", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let rate   = expect FrameRate.create(12, 1)
    var source = expect Clip.create(1, 1, rate)
    expect source.addFrame(videoTestImage(1, 1, [40'u8, 120, 220]))
    expect source.save(fileName)

    let loaded = expect Clip.load(fileName)
    @assert(loaded.sourcePath() == fileName.toString())
    @assert(loaded.frameCount() == 1)
    let frame = expect loaded.decodeFrame(0)
    videoAssertColor(frame.pixelColor(0, 0), 40, 120, 220)
}

#test
{
    discard catch Clip.decode("bad.y4m", "not video") as missingHeader
    discard catch Clip.decode("bad.y4m", "YUV4MPEG2 W1 H1 F1:1 Ip A0:0 C420\nFRAME\nabc") as chroma
    discard catch Clip.decode("bad.y4m", "YUV4MPEG2 W1 H1 F1:1 Ip A0:0 C444\nFRAME\nab") as truncated
    discard catch Clip.decode("bad.mp4", "") as extension
    @assert(missingHeader is InvalidFormatError)
    @assert(chroma is UnsupportedFormatError)
    @assert(truncated is InvalidFormatError)
    @assert(extension is UnsupportedFormatError)

    let rate = expect FrameRate.create(30, 1)
    var clip = expect Clip.create(2, 2, rate)
    discard catch clip.addFrame(videoTestImage(1, 1, [0'u8, 0, 0])) as dimensions
    discard catch clip.encode("empty.y4m") as empty
    @assert(dimensions is BadParameterError)
    @assert(empty is InvalidFormatError)
}
