#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// One point of a decoded frame, and the colour an independent decoder reads there.
//
// Every expected value in this file comes from decoding the same fixture with ffmpeg, so a
// change in this module cannot move the expectation with it.
struct AviProbe
{
    frame:   u64
    x, y:    s32
    r, g, b: u8
}

// Reads `fileName` and asserts that every probe holds.
func aviAssertProbes(fileName: string, probes: const [..] AviProbe, tolerance: s32)
{
    var reader = expect Reader.open(videoFixturePath(fileName))
    var frame: Image
    for probe in probes
    {
        expect reader.decodeFrameInto(&frame, probe.frame)
        videoAssertColor(frame.pixelColor(probe.x, probe.y), probe.r, probe.g, probe.b, tolerance)
    }
}

// A recording written by a camera, which is the file class an AVI reader exists for.
//
// `cogliati-turning-pages.avi` was written by a Canon camera and nothing here matches what this
// module produces: its frames are 4:2:2 Motion JPEG with restart intervals and no Huffman table
// of their own, it interleaves a PCM audio stream this module has no use for, and its header
// list carries chunks this decoder never heard of.
#test
{
    var reader = expect Reader.open(videoFixturePath("cogliati-turning-pages.avi"))
    @assert(reader.width() == 160 and reader.height() == 120)
    @assert(reader.frameCount() == 233)

    // The camera states its rate as 1000000/66666 rather than 15/1, and the decoder keeps what
    // the file says instead of rounding it to the rate the camera meant.
    @assert(reader.frameRate() == expect FrameRate.create(1_000_000, 66_666))
    @assert(Math.isEqualEpsilon(reader.frameRate().framesPerSecond(), 15.0, 0.001))
    @assert(Math.isEqualEpsilon(reader.durationInSeconds(), 15.53, 0.01))

    // The interleaved sound chunks are not pictures, and counting them as frames would be the
    // easiest mistake to make here.
    const Probes: [3] AviProbe = [{0, 40, 30, 151, 119, 92},
                                  {116, 80, 60, 160, 117, 84},
                                  {232, 120, 90, 142, 105, 74}]
    aviAssertProbes("cogliati-turning-pages.avi", Probes, tolerance: 6)
}

// The same recording read backwards gives the same pictures as reading it forwards, because the
// container index says where every frame lies rather than the decoder remembering.
#test
{
    const Backwards: [3] AviProbe = [{232, 120, 90, 142, 105, 74},
                                     {116, 80, 60, 160, 117, 84},
                                     {0, 40, 30, 151, 119, 92}]
    aviAssertProbes("cogliati-turning-pages.avi", Backwards, tolerance: 6)

    // Decoding a whole recording holds one frame, so the image the reader fills is the same one
    // from the first frame to the last.
    var reader = expect Reader.open(videoFixturePath("cogliati-turning-pages.avi"))
    var frame: Image
    expect reader.decodeFrameInto(&frame, 0)
    let storage = frame.pixels.buffer
    for index in 8'u64 do
        expect reader.decodeFrameInto(&frame, index * 29)
    @assert(frame.pixels.buffer == storage)
}

// Motion JPEG written by ffmpeg.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mjpeg-420.avi"))
    @assert(reader.width() == 64 and reader.height() == 48)
    @assert(reader.frameCount() == 10)
    @assert(reader.frameRate() == expect FrameRate.create(25, 1))

    var frame: Image
    const Sampled: [3] u64 = [0, 1, 9]
    for index in Sampled
    {
        expect reader.decodeFrameInto(&frame, index)
        videoAssertFixtureFrame(frame, index, tolerance: 4)
    }
}

// ffmpeg codes 4:2:2 and 4:4:4 Motion JPEG with two chroma blocks per minimum coded unit, which
// the Pixel JPEG decoder does not read. The container is opened all the same — the geometry, the
// rate and the frame table all come out — and only decoding a picture reports the limit.
#test
{
    const Files = ["ffmpeg-mjpeg-422.avi", "ffmpeg-mjpeg-444.avi"]
    for file in Files
    {
        var reader = expect Reader.open(videoFixturePath(file))
        @assert(reader.width() == 64 and reader.height() == 48)
        @assert(reader.frameCount() == 10)

        discard catch reader.decodeFrame(0) as sampling
        @assert(sampling is UnsupportedFormatError)
    }
}

// A broadcast rate is a ratio, and the stream header is what carries it exactly.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mjpeg-ntsc.avi"))
    @assert(reader.frameRate() == expect FrameRate.create(30_000, 1_001))
    @assert(reader.frameRate().framesPerSecond() > 29.97 and reader.frameRate().framesPerSecond() < 29.971)
    videoAssertFixtureFrame(expect reader.decodeFrame(9), 9, tolerance: 4)
}

// Uncompressed frames, in the two depths the format carries and at a width whose rows need
// padding. ffmpeg stores them top-down, with a negative bitmap height and no codec name at all.
#test
{
    var deep = expect Reader.open(videoFixturePath("ffmpeg-rawvideo-bgra.avi"))
    @assert(deep.width() == 32 and deep.height() == 24 and deep.frameCount() == 6)
    videoAssertFixtureFrame(expect deep.decodeFrame(5), 5, tolerance: 0)

    var flat = expect Reader.open(videoFixturePath("ffmpeg-rawvideo-bgr24.avi"))
    videoAssertFixtureFrame(expect flat.decodeFrame(0), 0, tolerance: 0)

    // 33 pixels of 24 bits fill 99 bytes, and a bitmap row is padded to 100.
    var odd = expect Reader.open(videoFixturePath("ffmpeg-rawvideo-odd.avi"))
    @assert(odd.width() == 33 and odd.height() == 25 and odd.frameCount() == 3)
    for index in 3'u64 do
        videoAssertFixtureFrame(expect odd.decodeFrame(index), index, tolerance: 0)
}

// The container shapes a writer other than ffmpeg produces, injected into a file ffmpeg wrote so
// that only the shape under test differs: rows the other way up, no index at all, an index
// counted from the file, and frames grouped in the lists an OpenDML file uses.
#test
{
    const Files = ["edited-bottom-up.avi", "edited-no-index.avi", "edited-absolute-index.avi", "edited-record-groups.avi"]
    for file in Files
    {
        var reader = expect Reader.open(videoFixturePath(file))
        @assert(reader.width() == 32 and reader.height() == 24)
        @assert(reader.frameCount() == 6)
        videoAssertFixtureFrame(expect reader.decodeFrame(0), 0, tolerance: 0)
        videoAssertFixtureFrame(expect reader.decodeFrame(5), 5, tolerance: 0)
        videoAssertFixtureFrame(expect reader.decodeFrame(3), 3, tolerance: 0)
    }
}

// A frame that carries no payload repeats the picture before it, which is how the container
// holds a stream that pauses at a constant frame rate.
#test
{
    var reader = expect Reader.open(videoFixturePath("edited-dropped-frames.avi"))
    @assert(reader.frameCount() == 6)

    // Frames 3 and 4 were emptied, so both show the picture of frame 2. Reading them out of
    // order proves the answer does not depend on what was decoded before.
    videoAssertFixtureFrame(expect reader.decodeFrame(4), 2, tolerance: 0)
    videoAssertFixtureFrame(expect reader.decodeFrame(0), 0, tolerance: 0)
    videoAssertFixtureFrame(expect reader.decodeFrame(3), 2, tolerance: 0)
    videoAssertFixtureFrame(expect reader.decodeFrame(5), 5, tolerance: 0)
}

// A clip encoded as Motion JPEG reads back as the picture it was built from.
#test
{
    const Size = 32's32
    let rate = expect FrameRate.create(30, 1)
    var clip = expect Clip.create(Size, Size, rate)
    expect clip.addFrame(videoGrayImage(Size, Size, 90))
    expect clip.addFrame(videoGrayImage(Size, Size, 200))

    let bytes  = expect clip.encodeToBytes("clip.avi")
    var reader = expect Reader.openMemory("clip.avi", bytes.toSlice())
    @assert(reader.width() == Size and reader.height() == Size)
    @assert(reader.frameRate() == rate)
    @assert(reader.frameCount() == 2)
    @assert(reader.streamFormat().extensions == ".avi")
    @assert(Math.isEqualEpsilon(reader.durationInSeconds(), 2.0 / 30.0, 0.0001))

    // Reading the second frame first proves the index, not the order frames were written in.
    videoAssertGray((expect reader.decodeFrame(1)).pixelColor(16, 16), 200, tolerance: 6)
    videoAssertGray((expect reader.decodeFrame(0)).pixelColor(16, 16), 90, tolerance: 6)
}

// The quality of the frames is what the caller asks for, and nothing else about the stream
// changes with it.
#test
{
    let rate = expect FrameRate.create(25, 1)
    var clip = expect Clip.create(64, 48, rate)
    for index in 4'u64 do
        expect clip.addFrame(videoGrayImage(64, 48, cast(u8) (40 + index * 40)))

    var low: Avi.EncodeOptions
    low.quality = 20
    var high: Avi.EncodeOptions
    high.quality = 100

    let coarse = expect clip.encodeToBytes("coarse.avi", low)
    let fine   = expect clip.encodeToBytes("fine.avi", high)
    @assert(coarse.count < fine.count)

    var reader = expect Reader.openMemory("coarse.avi", coarse.toSlice())
    @assert(reader.frameCount() == 4)
    videoAssertGray((expect reader.decodeFrame(3)).pixelColor(32, 24), 160, tolerance: 10)
}

// The encoded container is a real AVI file: the totals its header carries are the ones the
// finished stream measured, and they are checked here without this module's own decoder.
#test
{
    let rate = expect FrameRate.create(24, 1)
    var clip = expect Clip.create(8, 4, rate)
    for 3 do
        expect clip.addFrame(videoGrayImage(8, 4, 64))

    let bytes = expect clip.encodeToBytes("totals.avi")
    let raw   = bytes.toSlice()
    @assert(aviHasId(raw, 0, "RIFF") and aviHasId(raw, 8, "AVI "))
    @assert(aviHasId(raw, 12, "LIST") and aviHasId(raw, 20, "hdrl"))
    @assert(aviHasId(raw, 24, "avih") and aviHasId(raw, 100, "strh") and aviHasId(raw, 164, "strf"))
    @assert(aviHasId(raw, 212, "LIST") and aviHasId(raw, 220, "movi") and aviHasId(raw, 224, "00dc"))

    // Everything the header could only know once the last frame landed.
    @assert(aviReadU32(raw, 4) == cast(u32) bytes.count - 8)
    @assert(aviReadU32(raw, 48) == 3)       // Frame count of the file header.
    @assert(aviReadU32(raw, 64) == 8)       // Frame width of the file header.
    @assert(aviReadU32(raw, 68) == 4)       // Frame height of the file header.
    @assert(aviReadU32(raw, 128) == 1)      // Rate denominator of the stream header.
    @assert(aviReadU32(raw, 132) == 24)     // Rate numerator of the stream header.
    @assert(aviReadU32(raw, 140) == 3)      // Frame count of the stream header.

    // The size of the frame list is what places the index right after the last frame.
    let indexStart = 220 + cast(u64) aviReadU32(raw, 216)
    @assert(aviHasId(raw, indexStart, "idx1"))
    @assert(aviReadU32(raw, indexStart + 4) == 3 * 16)
    @assert(aviHasId(raw, indexStart + 8, "00dc"))
    @assert(aviReadU32(raw, indexStart + 16) == 4)
    @assert(indexStart + 8 + 3 * 16 == bytes.count)
}

// A stream written to a file reads back through the file-backed sink, which is the path where
// the header totals are rewritten in place rather than in memory.
#test
{
    let fileName = videoTempPath("avi-roundtrip", "avi")
    defer discard catch File.delete(fileName)

    let rate = expect FrameRate.create(12, 1)
    var clip = expect Clip.create(8, 8, rate)
    expect clip.addFrame(videoGrayImage(8, 8, 32))
    expect clip.addFrame(videoGrayImage(8, 8, 128))
    expect clip.addFrame(videoGrayImage(8, 8, 224))
    expect clip.save(fileName)

    var reader = expect Reader.open(fileName)
    @assert(reader.sourcePath() == fileName.toString())
    @assert(reader.frameCount() == 3 and reader.width() == 8 and reader.height() == 8)

    var frame: Image
    expect reader.decodeFrameInto(&frame, 2)
    videoAssertGray(frame.pixelColor(4, 4), 224, tolerance: 10)

    // Decoding into the same image reuses its storage instead of allocating another frame.
    let storage = frame.pixels.buffer
    expect reader.decodeFrameInto(&frame, 0)
    videoAssertGray(frame.pixelColor(4, 4), 32, tolerance: 10)
    @assert(frame.pixels.buffer == storage)

    reader.close()
    @assert(!reader.isOpen())
}

#test
{
    discard catch Reader.openMemory("bad.avi", "not a riff file at all") as notRiff
    discard catch Reader.openMemory("bad.avi", "RIFFsizeWAVEfmt ") as notAvi
    @assert(notRiff is InvalidFormatError)
    @assert(notAvi is InvalidFormatError)

    // A container this module reads, truncated to its headers, has no frame to decode.
    var whole = expect File.readAllBytes(videoFixturePath("ffmpeg-rawvideo-bgr24.avi"))
    discard catch Reader.openMemory("short.avi", whole.toSlice()[0 until 2048]) as truncated
    @assert(truncated != null)
}

// Returns the little-endian 32-bit value the container stores at `offset`.
func aviReadU32(bytes: const [..] u8, offset: u64)->u32
{
    var result = 0'u32
    for shift in 4 do
        result |= cast(u32) bytes[offset + cast(u64) shift] << cast(u32) (shift * 8)
    return result
}

// Reports whether the four characters of `id` sit at `offset`.
func aviHasId(bytes: const [..] u8, offset: u64, id: string)->bool
{
    for index in 4 where bytes[offset + cast(u64) index] != id[index] do
        return false
    return true
}
