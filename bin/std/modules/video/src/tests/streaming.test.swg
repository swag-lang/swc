#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// A container chunk can begin with B-frames presented before the previous chunk's decode-order
// tail. Extending a live AVC stream preserves consumed ranks and merges that unconsumed overlap.
#test
{
    var stream: H264.AvcStream
    stream.frames.add([{0, 0, 0, true}, {0, 0, 400, false}, {0, 0, 100, false}, {0, 0, 500, false}])
    stream.sampleAtRank.add([0, 2, 1, 3])
    stream.rankOfSample.add([0, 2, 1, 3])
    stream.syncFlags.add([1, 0, 0, 0])
    stream.nextRank   = 2
    stream.nextDecode = 3

    const Added: [2] H264.SampleEntry = [{0, 0, 300, false}, {0, 0, 200, false}]
    expect stream.appendFrames(Added)

    @assert(stream.sampleAtRank.count == 6)
    @assert(stream.sampleAtRank[0] == 0 and stream.sampleAtRank[1] == 2)
    @assert(stream.sampleAtRank[2] == 5 and stream.sampleAtRank[3] == 4)
    @assert(stream.sampleAtRank[4] == 1 and stream.sampleAtRank[5] == 3)
    for rank in stream.sampleAtRank.count do
        @assert(stream.rankOfSample[cast(u64) stream.sampleAtRank[rank]] == cast(u32) rank)
    @assert(stream.nextRank == 2 and stream.nextDecode == 0 and stream.skipBefore == 2)
}

// Appending ahead of every sample already handed to H.264 updates presentation ranks without
// flushing the live prediction state. A cluster boundary during playback must not replay the GOP.
#test
{
    var stream: H264.AvcStream
    stream.frames.add([{0, 0, 0, true}, {0, 0, 100, false}, {0, 0, 400, false}, {0, 0, 500, false}])
    stream.sampleAtRank.add([0, 1, 2, 3])
    stream.rankOfSample.add([0, 1, 2, 3])
    stream.syncFlags.add([1, 0, 0, 0])
    stream.nextRank   = 1
    stream.nextDecode = 2

    const Added: [2] H264.SampleEntry = [{0, 0, 300, false}, {0, 0, 200, false}]
    expect stream.appendFrames(Added)

    @assert(stream.sampleAtRank.count == 6)
    @assert(stream.sampleAtRank[0] == 0 and stream.sampleAtRank[1] == 1)
    @assert(stream.sampleAtRank[2] == 5 and stream.sampleAtRank[3] == 4)
    @assert(stream.sampleAtRank[4] == 2 and stream.sampleAtRank[5] == 3)
    @assert(stream.nextRank == 1 and stream.nextDecode == 2 and stream.skipBefore == 0)
}

// Geometry and content of `bars-scroll-c420.y4m`, the long fixture of this suite.
//
// It is 400 frames of eight scrolling colour bars, with a corner block whose luma identifies the
// frame it belongs to. That block is what makes a decoded frame provable: a seek that landed on
// the wrong frame, or a stream walked from the wrong offset, cannot produce the right value.
const BarsFixture        = "bars-scroll-c420.y4m"
const BarsWidth          = 128's32
const BarsHeight         = 72's32
const BarsFrameCount     = 400'u64
const BarsBlockSize      = 16's32
const BarsBarWidth       = 16's32
const BarsTimecodePeriod = 220'u64

// One bar of the fixture, in the channel order the assertions read.
struct BarColor
{
    r, g, b: u8
}

// The eight bars, in the order the fixture scrolls them through.
const BarColors: [8] BarColor = [{255, 255, 255}, {255, 255, 0}, {0, 255, 255}, {0, 255, 0}, {255, 0, 255}, {255, 0, 0}, {0, 0, 255}, {0, 0, 0}]

// Returns the neutral value the corner block of frame `index` decodes to.
func barsTimecodeGray(index: u64)->s32
{
    return videoLumaToGray(cast(u8) (16 + index % BarsTimecodePeriod))
}

// Asserts that a pixel taken at column `x`, below the corner block, holds the bar frame `index`
// scrolled to that column.
func barsAssertBar(actual: Color, x: s32, index: u64)
{
    let bar = BarColors[(cast(u64) (x / BarsBarWidth) + index) % @countof(BarColors)]
    videoAssertColor(actual, bar.r, bar.g, bar.b)
}

// Asserts that `frame` is frame `index` of the fixture, by its corner block and by two of its
// bars, taken below the block so the two patterns never overlap.
func barsAssertFrame(frame: Image, index: u64)
{
    videoAssertGray(frame.pixelColor(BarsBlockSize / 2, BarsBlockSize / 2), barsTimecodeGray(index))
    barsAssertBar(frame.pixelColor(4, BarsHeight - 8), 4, index)
    barsAssertBar(frame.pixelColor(BarsWidth - 4, BarsHeight - 8), BarsWidth - 4, index)
}

// A long stream is read in order into a single image: the reader holds one frame and a read
// window, so playing four hundred frames costs what playing one costs.
#test
{
    var reader = expect Reader.open(videoFixturePath(BarsFixture))
    @assert(reader.width() == BarsWidth and reader.height() == BarsHeight)
    @assert(reader.frameRate() == expect FrameRate.create(25, 1))
    @assert(reader.frameCount() == BarsFrameCount)
    @assert(Math.isEqualEpsilon(reader.durationInSeconds(), 16.0, 0.0001))

    var frame: Image
    for index in reader.frameCount()
    {
        expect reader.decodeFrameInto(&frame, index)
        videoAssertGray(frame.pixelColor(BarsBlockSize / 2, BarsBlockSize / 2), barsTimecodeGray(index))
    }

    // Every frame reused the same pixel storage.
    @assert(frame.width == BarsWidth and frame.height == BarsHeight)
    @assert(frame.pixelFormat == .RGB8)
    barsAssertFrame(frame, BarsFrameCount - 1)
}

// Seeking is what a timeline does, and it must land on the frame it names whichever way it
// jumps: to the end, back to the start, and to interior frames in both directions.
#test
{
    var reader = expect Reader.open(videoFixturePath(BarsFixture))

    const Probes: [8] u64 = [BarsFrameCount - 1, 0, 200, 37, 399, 1, 256, 255]
    var frame: Image
    for index in Probes
    {
        expect reader.decodeFrameInto(&frame, index)
        barsAssertFrame(frame, index)
    }

    // Decoding after a seek continues from where the seek landed.
    expect reader.decodeFrameInto(&frame, 256)
    barsAssertFrame(frame, 256)

    discard catch reader.decodeFrame(BarsFrameCount) as pastEnd
    @assert(pastEnd is BadParameterError)
}

// The same stream read from memory decodes to the same frames as read from the file: only the
// source differs, and the decoder never learns which one it has.
#test
{
    let bytes  = expect File.readAllBytes(videoFixturePath(BarsFixture).toString())
    var reader = expect Reader.openMemory(BarsFixture, bytes.toSlice())
    @assert(reader.frameCount() == BarsFrameCount)
    @assert(!@countof(reader.sourcePath()))

    var frame: Image
    const Probes: [3] u64 = [0, 137, BarsFrameCount - 1]
    for index in Probes
    {
        expect reader.decodeFrameInto(&frame, index)
        barsAssertFrame(frame, index)
    }
}

// Geometry of the stream the writer test produces. One frame is far larger than the write
// window, and the whole stream is far larger than anything the module holds at once.
const WrittenWidth      = 160's32
const WrittenHeight     = 120's32
const WrittenFrameCount = 300'u64

// Encoding is streamed too: three hundred frames are written one at a time, and the result is
// read back the same way.
#test
{
    let fileName = videoTempPath("stream", "y4m")
    defer discard catch File.delete(fileName)

    let rate   = expect FrameRate.create(30, 1)
    var writer = expect Writer.create(fileName, WrittenWidth, WrittenHeight, rate)
    var source = videoGrayImage(WrittenWidth, WrittenHeight, 0)
    for index in WrittenFrameCount
    {
        Memory.set(source.pixels.buffer!, cast(u8) (16 + index % 200), source.pixels.count)
        expect writer.addFrame(source)
    }

    expect writer.end()
    @assert(writer.frameCount() == WrittenFrameCount)

    // The encoder writes 4:4:4 planes behind a bare frame marker, so the size of the result is
    // known exactly; a writer that dropped, repeated or buffered away a frame would not match it.
    let header    = "YUV4MPEG2 W160 H120 F30:1 Ip A0:0 C444 XYSCSS=444 XCOLORRANGE=LIMITED\n"
    let frameSize = cast(u64) WrittenWidth * cast(u64) WrittenHeight * 3 + 6
    let info      = expect File.info(fileName.toString())
    @assert(info.size == @countof(header) + WrittenFrameCount * frameSize)

    var reader = expect Reader.open(fileName)
    @assert(reader.frameCount() == WrittenFrameCount)
    @assert(reader.width() == WrittenWidth and reader.height() == WrittenHeight)

    var frame: Image
    const Probes: [4] u64 = [0, 199, 200, WrittenFrameCount - 1]
    for index in Probes
    {
        expect reader.decodeFrameInto(&frame, index)
        videoAssertGray(frame.pixelColor(WrittenWidth / 2, WrittenHeight / 2), videoGrayRoundTrip(cast(u8) (16 + index % 200)))
    }
}

// Geometry of the stream with a hole. Sixty-nine megabytes is far more than any buffer of this
// module holds, and one frame payload alone is larger than the read window.
const HoleWidth      = 320's32
const HoleHeight     = 240's32
const HoleFrameCount = 600'u64

// Opening a stream reads its header and one marker, and seeking computes an offset. That is the
// property that lets a video of any size open at once, and this is how it is proven: everything
// between the first frame and the last one is a hole no decoder could read. A reader that
// indexed the stream, scanned it, or read it to its end to count its frames would fail here
// instead of playing it.
#test
{
    let fileName = videoTempPath("hole", "y4m")
    defer discard catch File.delete(fileName)

    let header      = "YUV4MPEG2 W320 H240 F25:1 Ip C420jpeg\n"
    let payloadSize = cast(u64) HoleWidth * cast(u64) HoleHeight * 3 / 2
    let frameSize   = payloadSize + 6

    var stream = expect File.openWrite(fileName)
    expect stream.writeAll(cast(const [..] u8) header)
    expect stream.writeAll(cast(const [..] u8) "FRAME\n")
    expect stream.writeAll(videoFlatPayload(HoleWidth, HoleHeight, 100).toSlice())
    expect stream.resize(@countof(header) + HoleFrameCount * frameSize)

    var lastFrame: Array'u8
    lastFrame.add(cast(const [..] u8) "FRAME\n")
    lastFrame.add(videoFlatPayload(HoleWidth, HoleHeight, 200).toSlice())
    expect stream.writeAllAt(@countof(header) + (HoleFrameCount - 1) * frameSize, lastFrame.toSlice())
    stream.close()

    var reader = expect Reader.open(fileName)
    @assert(reader.frameCount() == HoleFrameCount)
    @assert(Math.isEqualEpsilon(reader.durationInSeconds(), 24.0, 0.0001))

    var frame: Image
    expect reader.decodeFrameInto(&frame, 0)
    videoAssertGray(frame.pixelColor(0, 0), videoLumaToGray(100))

    expect reader.decodeFrameInto(&frame, HoleFrameCount - 1)
    videoAssertGray(frame.pixelColor(HoleWidth - 1, HoleHeight - 1), videoLumaToGray(200))

    discard catch reader.decodeFrame(HoleFrameCount / 2) as holeError
    @assert(holeError is InvalidFormatError)
}
