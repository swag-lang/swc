#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// A production Y4M fixture exercises the common 4:2:0 JPEG chroma layout through the
// streaming reader.
#test
{
    var reader = expect Reader.open(videoFixturePath("rav1e-c420jpeg.y4m"))
    @assert(reader.width() == 64 and reader.height() == 64)
    @assert(reader.frameRate() == expect FrameRate.create(25, 1))
    @assert(reader.frameCount() == 5)
    @assert(reader.streamFormat().extensions == ".y4m")

    let first = expect reader.decodeFrame(0)
    let last  = expect reader.decodeFrame(4)
    @assert(first.isValid() and last.isValid())
    videoAssertColor(first.pixelColor(0, 0), 36, 41, 53, tolerance: 0)
    videoAssertColor(first.pixelColor(32, 32), 173, 218, 253, tolerance: 0)
    @assert(last.pixelColor(0, 0) != last.pixelColor(32, 32))
}

// The plane layouts a real encoder writes, read from streams ffmpeg produced.
#test
{
    const Files = ["ffmpeg-c422.y4m", "ffmpeg-c444.y4m", "ffmpeg-ntsc-c420.y4m"]
    for file in Files
    {
        var reader = expect Reader.open(videoFixturePath(file))
        @assert(reader.width() == 32 and reader.height() == 24)
        @assert(reader.frameCount() == 3)

        var frame: Image
        for index in 3'u64
        {
            expect reader.decodeFrameInto(&frame, index)
            videoAssertFixtureFrame(frame, index, tolerance: 4)
        }
    }

    // A broadcast rate stays a ratio, and never becomes 29.97.
    var broadcast = expect Reader.open(videoFixturePath("ffmpeg-ntsc-c420.y4m"))
    @assert(broadcast.frameRate() == expect FrameRate.create(30_000, 1_001))

    // A monochrome stream keeps the luma of each quadrant and loses its colour. This one also
    // carries the full-range tag, which is the other conversion the decoder implements.
    var mono = expect Reader.open(videoFixturePath("ffmpeg-mono.y4m"))
    @assert(mono.width() == 32 and mono.height() == 24 and mono.frameCount() == 3)
    for index in 3'u64 do
        videoAssertFixtureLumaFrame(expect mono.decodeFrame(index), index, tolerance: 4)
}

// Two sequences of the standard research corpus, which are what this format is used for.
//
// Neither carries a chroma tag, so both exercise the implicit 4:2:0 default of the
// specification, and both declare a non-square pixel aspect ratio the decoder must ignore
// rather than refuse. The expected colours come from decoding the same files with ffmpeg.
#test
{
    var claire = expect Reader.open(videoFixturePath("xiph-claire-qcif.y4m"))
    @assert(claire.width() == 176 and claire.height() == 144)
    @assert(claire.frameCount() == 30)
    @assert(claire.frameRate() == expect FrameRate.create(6_000, 1_001))

    var frame: Image
    expect claire.decodeFrameInto(&frame, 0)
    videoAssertColor(frame.pixelColor(44, 36), 101, 140, 166, tolerance: 4)
    expect claire.decodeFrameInto(&frame, 29)
    videoAssertColor(frame.pixelColor(88, 72), 195, 146, 81, tolerance: 4)
    videoAssertColor(frame.pixelColor(132, 108), 0, 4, 109, tolerance: 4)

    var bus = expect Reader.open(videoFixturePath("xiph-bus-qcif-15fps.y4m"))
    @assert(bus.width() == 176 and bus.height() == 144)
    @assert(bus.frameCount() == 75)
    @assert(bus.frameRate() == expect FrameRate.create(15, 1))
    @assert(Math.isEqualEpsilon(bus.durationInSeconds(), 5.0, 0.0001))

    // Reading the last frame first, then the first, proves the computed offsets rather than a
    // decoder that only ever walks forward.
    expect bus.decodeFrameInto(&frame, 74)
    videoAssertColor(frame.pixelColor(88, 72), 108, 103, 100, tolerance: 4)
    expect bus.decodeFrameInto(&frame, 0)
    videoAssertColor(frame.pixelColor(44, 36), 23, 25, 20, tolerance: 4)
}

// The specification's implicit 4:2:0 default and its named spellings all describe one layout,
// which no encoder writes four ways, so the header is stated here instead.
#test
{
    const Modes = ["", " C420", " C420mpeg2", " C420paldv"]
    for mode in Modes
    {
        var bytes: Array'u8
        bytes.add(cast(const [..] u8) Format.toString("YUV4MPEG2 W2 H2 F1:1 Ip%\nFRAME\n", mode).toString())
        bytes.add([81'u8, 81, 81, 81, 90, 240])
        var reader = expect Reader.openMemory("subsampled.y4m", bytes.toSlice())
        let frame  = expect reader.decodeFrame(0)
        videoAssertColor(frame.pixelColor(1, 1), 255, 0, 0, tolerance: 0)
    }
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
    var reader = expect Reader.openMemory("full-range.y4m", bytes.toSlice())
    let frame  = expect reader.decodeFrame(0)
    videoAssertColor(frame.pixelColor(0, 0), 255, 0, 0)
}

// A frame marker may carry per-frame parameters. They move every payload that follows, so the
// stream is walked instead of being addressed, and its frame count is reported as unknown.
#test
{
    var bytes: Array'u8
    bytes.add(cast(const [..] u8) "YUV4MPEG2 W1 H1 F1:1 Ip C444\n")
    bytes.add(cast(const [..] u8) "FRAME Xsomething\n")
    bytes.add([81'u8, 90, 240])
    bytes.add(cast(const [..] u8) "FRAME\n")
    bytes.add([145'u8, 54, 34])

    var reader = expect Reader.openMemory("parameters.y4m", bytes.toSlice())
    @assert(!reader.frameCount())
    @assert(reader.durationInSeconds() == 0)

    let red = expect reader.decodeFrame(0)
    videoAssertColor(red.pixelColor(0, 0), 255, 0, 0)

    let green = expect reader.decodeFrame(1)
    videoAssertColor(green.pixelColor(0, 0), 0, 255, 0)

    // Reading a stream with an unknown length ends by failing, not by returning a frame.
    discard catch reader.decodeFrame(2) as endOfStream
    @assert(endOfStream != null)

    // Seeking backwards rewinds and walks forward again.
    let again = expect reader.decodeFrame(0)
    videoAssertColor(again.pixelColor(0, 0), 255, 0, 0)
}

// A read that fails part way through a frame leaves the source between two of them. The next
// decode must reposition rather than continue from there, whether it asks for the frame that
// failed or for another one.
#test
{
    var bytes: Array'u8
    bytes.add(cast(const [..] u8) "YUV4MPEG2 W1 H1 F1:1 Ip C444\n")
    bytes.add(cast(const [..] u8) "FRAME\n")
    bytes.add([81'u8, 90, 240])
    bytes.add(cast(const [..] u8) "FRAME\n")
    bytes.add([145'u8, 54])

    // The truncated tail is not a frame, and the stream no longer tiles, so it is walked.
    var reader = expect Reader.openMemory("truncated.y4m", bytes.toSlice())
    @assert(!reader.frameCount())

    let red = expect reader.decodeFrame(0)
    videoAssertColor(red.pixelColor(0, 0), 255, 0, 0)

    discard catch reader.decodeFrame(1) as truncated
    discard catch reader.decodeFrame(1) as truncatedAgain
    @assert(truncated is InvalidFormatError)
    @assert(truncatedAgain is InvalidFormatError)

    let again = expect reader.decodeFrame(0)
    videoAssertColor(again.pixelColor(0, 0), 255, 0, 0)
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
    @assert(source.frameCount() == 2)
    @assert((expect source.frame(1)).pixelColor(1, 0) == second.pixelColor(1, 0))

    let bytes   = expect source.encodeToBytes("roundtrip.y4m")
    var decoded = expect Reader.openMemory("roundtrip.y4m", bytes.toSlice())
    @assert(decoded.isOpen())
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
    let fileName = videoTempPath("roundtrip", "y4m")
    defer discard catch File.delete(fileName)

    let rate   = expect FrameRate.create(12, 1)
    var source = expect Clip.create(1, 1, rate)
    expect source.addFrame(videoTestImage(1, 1, [40'u8, 120, 220]))
    expect source.save(fileName)

    var loaded = expect Reader.open(fileName)
    @assert(loaded.sourcePath() == fileName.toString())
    @assert(loaded.frameCount() == 1)
    let frame = expect loaded.decodeFrame(0)
    videoAssertColor(frame.pixelColor(0, 0), 40, 120, 220)

    // Closing releases the file while the reader value is still alive.
    loaded.close()
    @assert(!loaded.isOpen())
}

#test
{
    discard catch Reader.openMemory("bad.y4m", "not video") as missingHeader
    discard catch Reader.openMemory("bad.y4m", "YUV4MPEG2 W1 H1 F1:1 Ip A0:0 C420p10\nFRAME\nabc") as chroma
    discard catch Reader.openMemory("bad.y4m", "YUV4MPEG2 W1 H1 F1:1 Ip A0:0 C444\nFRAME\nab") as truncated
    discard catch Reader.openMemory("bad.y4m", "YUV4MPEG2 W1 H1 F1:1 Ip A0:0 C444\n") as noFrame
    discard catch Reader.openMemory("bad.mp4", "") as extension
    @assert(missingHeader is InvalidFormatError)
    @assert(chroma is UnsupportedFormatError)
    @assert(truncated is InvalidFormatError)
    @assert(noFrame is InvalidFormatError)
    @assert(extension is UnsupportedFormatError)

    let rate = expect FrameRate.create(30, 1)
    var clip = expect Clip.create(2, 2, rate)
    discard catch clip.addFrame(videoTestImage(1, 1, [0'u8, 0, 0])) as dimensions
    discard catch clip.encode("empty.y4m") as empty
    discard catch clip.encode("empty.mp4") as unsupported
    @assert(dimensions is BadParameterError)
    @assert(empty is InvalidFormatError)
    @assert(unsupported is UnsupportedFormatError)
}

// The registry is the only thing that decides which extensions the module reads and writes.
#test
{
    @assert(Reader.canOpen("clip.y4m") and Reader.canOpen("CLIP.Y4M"))
    @assert(Reader.canOpen("clip.avi") and Reader.canOpen("CLIP.AVI"))
    @assert(!Reader.canOpen("clip.mp4") and !Reader.canOpen("clip") and !Reader.canOpen(""))
    @assert(Writer.canCreate("clip.y4m") and Writer.canCreate("clip.avi") and !Writer.canCreate("clip.mkv"))

    // Every format is both read and written; a codec registered on one side alone would be a
    // stream this module can produce and not open again, or the reverse.
    let decodable = Reader.decodableFormats()
    let encodable = Writer.encodableFormats()
    @assert(decodable.count == 2 and encodable.count == 2)
    for format, index in decodable do
        @assert(format.name == encodable[index].name)
    @assert(decodable[0].matches("a.y4m") and decodable[1].matches("a.avi"))
}
