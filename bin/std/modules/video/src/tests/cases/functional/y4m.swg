#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

func y4mAspectBytes(aspect: string)->Array'u8
{
    var result: #returntype
    result.add(cast(const [..] u8, Format.toString("YUV4MPEG2 W8 H4 F1:1 Ip A% C444\nFRAME\n", aspect).toString()))
    result.resize(result.count + 96)
    return result
}

// A production Y4M fixture exercises the common 4:2:0 JPEG chroma layout through the
// streaming reader.
#test
{
    var reader = expect Reader.open(videoFixturePath("rav1e-c420jpeg.y4m"))
    Swag.require(reader.width() == 64 and reader.height() == 64)
    Swag.require(reader.frameRate() == expect FrameRate.create(25, 1))
    Swag.require(reader.frameCount() == 5)
    Swag.require(reader.streamFormat().extensions == ".y4m")

    let first = expect reader.decodeFrame(0)
    let last  = expect reader.decodeFrame(4)
    Swag.require(first.isValid() and last.isValid())
    videoAssertColor(first.pixelColor(0, 0), 36, 41, 53, tolerance: 0)
    videoAssertColor(first.pixelColor(32, 32), 173, 218, 253, tolerance: 0)
    Swag.require(last.pixelColor(0, 0) != last.pixelColor(32, 32))
}

// YUV4MPEG2 sample aspect tags affect display geometry without changing frame storage.
#test
{
    var nonSquareBytes = y4mAspectBytes("2:1")
    var nonSquare = expect Reader.openMemory("aspect.y4m", nonSquareBytes.toSlice())
    Swag.require(nonSquare.width() == 8 and nonSquare.height() == 4)
    Swag.require(nonSquare.displayWidth() == 16 and nonSquare.displayHeight() == 4)

    var squareBytes = y4mAspectBytes("1:1")
    var square = expect Reader.openMemory("square.y4m", squareBytes.toSlice())
    Swag.require(square.displayWidth() == 8 and square.displayHeight() == 4)
    var absentBytes = y4mAspectBytes("0:0")
    var absent = expect Reader.openMemory("absent.y4m", absentBytes.toSlice())
    Swag.require(absent.displayWidth() == 8 and absent.displayHeight() == 4)

    var overflowBytes = y4mAspectBytes("4294967295:1")
    var overflow = expect Reader.openMemory("overflow.y4m", overflowBytes.toSlice())
    Swag.require(overflow.streamInfo().displayWidth == 0 and overflow.streamInfo().displayHeight == 0)

    const Invalid = ["A", "A2", "A2:1:1", "A0:1", "A1:0"]
    for aspect in Invalid
    {
        let text = Format.toString("YUV4MPEG2 W8 H4 F1:1 Ip % C444\n", aspect)
        var error: Swag.Error
        discard catch Reader.openMemory("invalid.y4m", text.toSlice()) as error
        Swag.require(error.value() is InvalidFormatError)
    }
}

// The plane layouts a real encoder writes, read from streams ffmpeg produced.
#test
{
    const Files = ["ffmpeg-c422.y4m", "ffmpeg-c444.y4m", "ffmpeg-ntsc-c420.y4m"]
    for file in Files
    {
        var reader = expect Reader.open(videoFixturePath(file))
        Swag.require(reader.width() == 32 and reader.height() == 24)
        Swag.require(reader.frameCount() == 3)

        var frame: Image
        for index in 3'u64
        {
            expect reader.decodeFrameInto(&frame, index)
            videoAssertFixtureFrame(frame, index, tolerance: 4)
        }
    }

    // A broadcast rate stays a ratio, and never becomes 29.97.
    var broadcast = expect Reader.open(videoFixturePath("ffmpeg-ntsc-c420.y4m"))
    Swag.require(broadcast.frameRate() == expect FrameRate.create(30_000, 1_001))

    // A monochrome stream keeps the luma of each quadrant and loses its colour. This one also
    // carries the full-range tag, which is the other conversion the decoder implements.
    var mono = expect Reader.open(videoFixturePath("ffmpeg-mono.y4m"))
    Swag.require(mono.width() == 32 and mono.height() == 24 and mono.frameCount() == 3)
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
    Swag.require(claire.width() == 176 and claire.height() == 144)
    Swag.require(claire.frameCount() == 30)
    Swag.require(claire.frameRate() == expect FrameRate.create(6_000, 1_001))

    var frame: Image
    expect claire.decodeFrameInto(&frame, 0)
    videoAssertColor(frame.pixelColor(44, 36), 101, 140, 166, tolerance: 4)
    expect claire.decodeFrameInto(&frame, 29)
    videoAssertColor(frame.pixelColor(88, 72), 195, 146, 81, tolerance: 4)
    videoAssertColor(frame.pixelColor(132, 108), 0, 4, 109, tolerance: 4)

    var bus = expect Reader.open(videoFixturePath("xiph-bus-qcif-15fps.y4m"))
    Swag.require(bus.width() == 176 and bus.height() == 144)
    Swag.require(bus.frameCount() == 75)
    Swag.require(bus.frameRate() == expect FrameRate.create(15, 1))
    Swag.require(Math.isEqualEpsilon(bus.durationInSeconds(), 5.0, 0.0001))

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
        bytes.add(cast(const [..] u8, Format.toString("YUV4MPEG2 W2 H2 F1:1 Ip%\nFRAME\n", mode).toString()))
        bytes.add([81'u8, 81, 81, 81, 90, 240])
        var reader = expect Reader.openMemory("subsampled.y4m", bytes.toSlice())
        let frame  = expect reader.decodeFrame(0)
        videoAssertColor(frame.pixelColor(1, 1), 255, 0, 0, tolerance: 0)
    }
}

#test
{
    let rate = expect FrameRate.create(30_000, 1_001)
    Swag.require(rate.numerator() == 30_000)
    Swag.require(rate.denominator() == 1_001)
    Swag.require(rate.framesPerSecond() > 29.97 and rate.framesPerSecond() < 29.971)

    var zeroNumeratorOutcome: Swag.Error
    discard catch FrameRate.create(0, 1) as zeroNumeratorOutcome
    let zeroNumerator = zeroNumeratorOutcome.value()
    var zeroDenominatorOutcome: Swag.Error
    discard catch FrameRate.create(1, 0) as zeroDenominatorOutcome
    let zeroDenominator = zeroDenominatorOutcome.value()
    Swag.require((zeroNumerator is BadParameterError))
    Swag.require((zeroDenominator is BadParameterError))
}

#test
{
    const FullRangeRed = "YUV4MPEG2 W1 H1 F1:1 Ip A0:0 C444 XYSCSS=444 XCOLORRANGE=FULL\nFRAME\n"
    var bytes: Array'u8
    bytes.add(cast(const [..] u8, FullRangeRed))
    bytes.add([76'u8, 85, 255])
    var reader = expect Reader.openMemory("full-range.y4m", bytes.toSlice())
    let frame  = expect reader.decodeFrame(0)
    videoAssertColor(frame.pixelColor(0, 0), 255, 0, 0)
}

// C411 stores one chroma pair for each four horizontal luma samples.
#test
{
    var bytes: Array'u8
    bytes.add(cast(const [..] u8, "YUV4MPEG2 W8 H1 F1:1 Ip C411\nFRAME\n"))
    bytes.add([81'u8, 81, 81, 81, 41, 41, 41, 41, 90, 240, 240, 110])
    var reader = expect Reader.openMemory("4:1:1.y4m", bytes.toSlice())
    let frame  = expect reader.decodeFrame(0)
    videoAssertColor(frame.pixelColor(1, 0), 255, 0, 0, tolerance: 0)
    videoAssertColor(frame.pixelColor(6, 0), 0, 0, 255, tolerance: 0)
}

// A frame marker may carry per-frame parameters. They move every payload that follows, so the
// stream is walked instead of being addressed, and its frame count is reported as unknown.
#test
{
    var bytes: Array'u8
    bytes.add(cast(const [..] u8, "YUV4MPEG2 W1 H1 F1:1 Ip C444\n"))
    bytes.add(cast(const [..] u8, "FRAME Xsomething\n"))
    bytes.add([81'u8, 90, 240])
    bytes.add(cast(const [..] u8, "FRAME\n"))
    bytes.add([145'u8, 54, 34])

    var reader = expect Reader.openMemory("parameters.y4m", bytes.toSlice())
    Swag.require(not reader.frameCount())
    Swag.require(reader.durationInSeconds() == 0)

    let red = expect reader.decodeFrame(0)
    videoAssertColor(red.pixelColor(0, 0), 255, 0, 0)

    let green = expect reader.decodeFrame(1)
    videoAssertColor(green.pixelColor(0, 0), 0, 255, 0)

    // Reading a stream with an unknown length ends by failing, not by returning a frame.
    var endOfStreamOutcome: Swag.Error
    discard catch reader.decodeFrame(2) as endOfStreamOutcome
    let endOfStream = endOfStreamOutcome.value()
    Swag.require(endOfStream != null)

    // Seeking backwards rewinds and walks forward again.
    let again = expect reader.decodeFrame(0)
    videoAssertColor(again.pixelColor(0, 0), 255, 0, 0)
}

// Variable marker lengths can cancel out, so matching file size and the final marker alone
// does not prove that every frame has the first marker's stride.
#test
{
    var bytes: Array'u8
    bytes.add(cast(const [..] u8, "YUV4MPEG2 W1 H1 F1:1 Ip C444\n"))

    bytes.add(cast(const [..] u8, "FRAME \n"))
    bytes.add([81'u8, 90, 240])
    bytes.add(cast(const [..] u8, "FRAME X\n"))
    bytes.add([145'u8, 54, 34])
    bytes.add(cast(const [..] u8, "FRAME\n"))
    bytes.add([41'u8, 255, 107])
    bytes.add(cast(const [..] u8, "FRAME \n"))
    bytes.add([210'u8, 16, 146])

    var reader = expect Reader.openMemory("compensating-markers.y4m", bytes.toSlice())
    Swag.require(not reader.frameCount())
    let red    = expect reader.decodeFrame(0)
    let green  = expect reader.decodeFrame(1)
    let blue   = expect reader.decodeFrame(2)
    let yellow = expect reader.decodeFrame(3)
    videoAssertColor(red.pixelColor(0, 0), 255, 0, 0)
    videoAssertColor(green.pixelColor(0, 0), 0, 255, 0)
    videoAssertColor(blue.pixelColor(0, 0), 0, 0, 255)
    videoAssertColor(yellow.pixelColor(0, 0), 255, 255, 0)

    // The sequential fallback also repositions correctly for a backward request.
    let first = expect reader.decodeFrame(0)
    videoAssertColor(first.pixelColor(0, 0), 255, 0, 0)
}

// A read that fails part way through a frame leaves the source between two of them. The next
// decode must reposition rather than continue from there, whether it asks for the frame that
// failed or for another one.
#test
{
    var bytes: Array'u8
    bytes.add(cast(const [..] u8, "YUV4MPEG2 W1 H1 F1:1 Ip C444\n"))
    bytes.add(cast(const [..] u8, "FRAME\n"))
    bytes.add([81'u8, 90, 240])
    bytes.add(cast(const [..] u8, "FRAME\n"))
    bytes.add([145'u8, 54])

    // The truncated tail is not a frame, and the stream no longer tiles, so it is walked.
    var reader = expect Reader.openMemory("truncated.y4m", bytes.toSlice())
    Swag.require(not reader.frameCount())

    let red = expect reader.decodeFrame(0)
    videoAssertColor(red.pixelColor(0, 0), 255, 0, 0)

    var truncatedOutcome: Swag.Error
    discard catch reader.decodeFrame(1) as truncatedOutcome
    let truncated = truncatedOutcome.value()
    var truncatedAgainOutcome: Swag.Error
    discard catch reader.decodeFrame(1) as truncatedAgainOutcome
    let truncatedAgain = truncatedAgainOutcome.value()
    Swag.require((truncated is InvalidFormatError))
    Swag.require((truncatedAgain is InvalidFormatError))

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
    Swag.require(encoded.count == header.count + 6)
    Swag.require(Swag.makeString(encoded.buffer, header.count) == header)
    let payload = encoded.toSlice()[header.count until encoded.count]
    const ExpectedPayload: [6] u8 = [16, 235, 128, 128, 128, 128]
    for value, index in ExpectedPayload do
        Swag.require(payload[index] == value)
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
    Swag.require(source.frameCount() == 2)
    Swag.require((expect source.frame(1)).pixelColor(1, 0) == second.pixelColor(1, 0))

    let bytes   = expect source.encodeToBytes("roundtrip.y4m")
    var decoded = expect Reader.openMemory("roundtrip.y4m", bytes.toSlice())
    Swag.require(decoded.isOpen())
    Swag.require(decoded.width() == 2 and decoded.height() == 2)
    Swag.require(decoded.frameCount() == 2)
    Swag.require(decoded.durationInSeconds() == 2.0 / 24.0)

    let frame0 = expect decoded.decodeFrame(0)
    let frame1 = expect decoded.decodeFrame(1)
    videoAssertColor(frame0.pixelColor(0, 0), 255, 0, 0)
    videoAssertColor(frame0.pixelColor(1, 0), 0, 255, 0)
    videoAssertColor(frame0.pixelColor(0, 1), 0, 0, 255)
    videoAssertColor(frame0.pixelColor(1, 1), 255, 255, 255)
    videoAssertColor(frame1.pixelColor(1, 0), 16, 24, 32)
}

// The writer can select standard 4:1:1, 4:2:0, and 4:2:2 output layouts and advertises their sampling.
#test
{
    let rate = expect FrameRate.create(25, 1)
    var source = expect Clip.create(2, 2, rate)
    expect source.addFrame(videoTestImage(2, 2, [255'u8, 0, 0, 0, 255, 0,
                                                0, 0, 255, 255, 255, 255]))

    let full = expect source.encodeToBytes("full.y4m")
    let fullHeader = "YUV4MPEG2 W2 H2 F25:1 Ip A0:0 C444 XYSCSS=444 XCOLORRANGE=LIMITED\nFRAME\n"
    Swag.require(Swag.makeString(full.buffer, fullHeader.count) == fullHeader)
    let fullPayload = full.toSlice()[fullHeader.count until full.count]

    let options420 = Y4m.EncodeOptions{chroma: .Yuv420}
    let subsampled420 = expect source.encodeToBytes("420.y4m", options420)
    let header420 = "YUV4MPEG2 W2 H2 F25:1 Ip A0:0 C420jpeg XYSCSS=420JPEG XCOLORRANGE=LIMITED\nFRAME\n"
    Swag.require(Swag.makeString(subsampled420.buffer, header420.count) == header420)
    Swag.require(subsampled420.count == header420.count + 6)
    let payload420 = subsampled420.toSlice()[header420.count until subsampled420.count]
    for index in 4'u64 do
        Swag.require(payload420[index] == fullPayload[index])
    let meanU = (cast(u32, fullPayload[4]) + fullPayload[5] + fullPayload[6] + fullPayload[7] + 2) / 4
    let meanV = (cast(u32, fullPayload[8]) + fullPayload[9] + fullPayload[10] + fullPayload[11] + 2) / 4
    Swag.require(payload420[4] == meanU and payload420[5] == meanV)
    var reader420 = expect Reader.openMemory("420.y4m", subsampled420.toSlice())
    Swag.require(reader420.frameCount() == 1 and expect reader420.decodeFrame(0).isValid())

    let options422 = Y4m.EncodeOptions{chroma: .Yuv422}
    let subsampled422 = expect source.encodeToBytes("422.y4m", options422)
    let header422 = "YUV4MPEG2 W2 H2 F25:1 Ip A0:0 C422 XYSCSS=422 XCOLORRANGE=LIMITED\nFRAME\n"
    Swag.require(Swag.makeString(subsampled422.buffer, header422.count) == header422)
    Swag.require(subsampled422.count == header422.count + 8)
    let payload422 = subsampled422.toSlice()[header422.count until subsampled422.count]
    for row in 2'u64
    {
        let fullChroma = row * 2
        let reducedChroma = 4 + row
        let meanRowU = (cast(u32, fullPayload[4 + fullChroma]) + fullPayload[5 + fullChroma] + 1) / 2
        let meanRowV = (cast(u32, fullPayload[8 + fullChroma]) + fullPayload[9 + fullChroma] + 1) / 2
        Swag.require(payload422[reducedChroma] == meanRowU and
                     payload422[reducedChroma + 2] == meanRowV)
    }
    var reader422 = expect Reader.openMemory("422.y4m", subsampled422.toSlice())
    Swag.require(reader422.frameCount() == 1 and expect reader422.decodeFrame(0).isValid())

    var source411 = expect Clip.create(8, 1, rate)
    expect source411.addFrame(videoTestImage(8, 1, [255'u8, 0, 0, 255, 0, 0, 255, 0, 0,
                                                    255, 0, 0, 0, 0, 255, 0, 0, 255,
                                                    0, 0, 255, 0, 0, 255]))
    let options411 = Y4m.EncodeOptions{chroma: .Yuv411}
    let subsampled411 = expect source411.encodeToBytes("411.y4m", options411)
    let header411 = "YUV4MPEG2 W8 H1 F25:1 Ip A0:0 C411 XYSCSS=411 XCOLORRANGE=LIMITED\nFRAME\n"
    Swag.require(Swag.makeString(subsampled411.buffer, header411.count) == header411)
    Swag.require(subsampled411.count == header411.count + 12)
    let payload411 = subsampled411.toSlice()[header411.count until subsampled411.count]
    Swag.require(payload411[0] == 82 and payload411[4] == 41)
    Swag.require(payload411[8] == 90 and payload411[9] == 240)
    Swag.require(payload411[10] == 240 and payload411[11] == 110)
    var reader411 = expect Reader.openMemory("411.y4m", subsampled411.toSlice())
    let decoded411 = expect reader411.decodeFrame(0)
    videoAssertColor(decoded411.pixelColor(1, 0), 255, 0, 0, tolerance: 2)
    videoAssertColor(decoded411.pixelColor(6, 0), 0, 0, 255, tolerance: 0)

    var oddWidth = expect Clip.create(1, 2, rate)
    expect oddWidth.addFrame(videoTestImage(1, 2, [0'u8, 0, 0, 255, 255, 255]))
    var invalidOutcome: Swag.Error
    discard catch oddWidth.encodeToBytes("invalid.y4m", options422) as invalidOutcome
    Swag.require((invalidOutcome.value() is BadParameterError))

    var invalid411Width = expect Clip.create(6, 1, rate)
    expect invalid411Width.addFrame(videoTestImage(6, 1, [0'u8, 0, 0, 255, 255, 255,
                                                          0, 0, 0, 255, 255, 255,
                                                          0, 0, 0, 255, 255, 255]))
    var invalid411Outcome: Swag.Error
    discard catch invalid411Width.encodeToBytes("invalid-411.y4m", options411) as invalid411Outcome
    Swag.require((invalid411Outcome.value() is BadParameterError))
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
    Swag.require(loaded.sourcePath() == fileName.toString())
    Swag.require(loaded.frameCount() == 1)
    let frame = expect loaded.decodeFrame(0)
    videoAssertColor(frame.pixelColor(0, 0), 40, 120, 220)

    // Closing releases the file while the reader value is still alive.
    loaded.close()
    Swag.require(not loaded.isOpen())
}

#test
{
    var missingHeaderOutcome: Swag.Error
    discard catch Reader.openMemory("bad.y4m", "not video") as missingHeaderOutcome
    let missingHeader = missingHeaderOutcome.value()
    var chromaOutcome: Swag.Error
    discard catch Reader.openMemory("bad.y4m", "YUV4MPEG2 W1 H1 F1:1 Ip A0:0 C420p10\nFRAME\nabc") as chromaOutcome
    let chroma = chromaOutcome.value()
    var truncatedOutcome: Swag.Error
    discard catch Reader.openMemory("bad.y4m", "YUV4MPEG2 W1 H1 F1:1 Ip A0:0 C444\nFRAME\nab") as truncatedOutcome
    let truncated = truncatedOutcome.value()
    var noFrameOutcome: Swag.Error
    discard catch Reader.openMemory("bad.y4m", "YUV4MPEG2 W1 H1 F1:1 Ip A0:0 C444\n") as noFrameOutcome
    let noFrame = noFrameOutcome.value()
    var mp4HeaderOutcome: Swag.Error
    discard catch Reader.openMemory("bad.mp4", "") as mp4HeaderOutcome
    let mp4Header = mp4HeaderOutcome.value()
    Swag.require((missingHeader is InvalidFormatError))
    Swag.require((chroma is UnsupportedFormatError))
    Swag.require((truncated is InvalidFormatError))
    Swag.require((noFrame is InvalidFormatError))
    Swag.require((mp4Header is InvalidFormatError))

    let rate = expect FrameRate.create(30, 1)
    var clip = expect Clip.create(2, 2, rate)
    var dimensionsOutcome: Swag.Error
    discard catch clip.addFrame(videoTestImage(1, 1, [0'u8, 0, 0])) as dimensionsOutcome
    let dimensions = dimensionsOutcome.value()
    var emptyOutcome: Swag.Error
    discard catch clip.encode("empty.y4m") as emptyOutcome
    let empty = emptyOutcome.value()
    var emptyMp4Outcome: Swag.Error
    discard catch clip.encode("empty.mp4") as emptyMp4Outcome
    let emptyMp4 = emptyMp4Outcome.value()
    Swag.require((dimensions is BadParameterError))
    Swag.require((empty is InvalidFormatError))
    Swag.require((emptyMp4 is InvalidFormatError))
}

// The registry is the only thing that decides which extensions the module reads and writes.
#test
{
    Swag.require(Reader.canOpen("clip.y4m") and Reader.canOpen("CLIP.Y4M"))
    Swag.require(Reader.canOpen("clip.avi") and Reader.canOpen("CLIP.AVI"))
    Swag.require(Reader.canOpen("clip.mp4") and Reader.canOpen("clip.m4v") and Reader.canOpen("clip.mov"))
    Swag.require(not Reader.canOpen("clip") and not Reader.canOpen(""))
    Swag.require(Writer.canCreate("clip.y4m") and
                 Writer.canCreate("clip.avi") and
                 Writer.canCreate("clip.mp4") and
                 not Writer.canCreate("clip.mkv"))

    // The three writable formats are readable in the same order; Matroska is the read-only
    // container that follows them.
    let decodable = Reader.decodableFormats()
    let encodable = Writer.encodableFormats()
    Swag.require(decodable.count == 4 and encodable.count == 3)
    for index in encodable.count do
        Swag.require(decodable[index].name == encodable[index].name)
    Swag.require(decodable[0].matches("a.y4m") and
                 decodable[1].matches("a.avi") and
                 decodable[2].matches("a.mp4") and
                 decodable[2].matches("a.MOV"))
    Swag.require(decodable[3].matches("a.mkv") and not decodable[3].matches("a.webm"))
}
