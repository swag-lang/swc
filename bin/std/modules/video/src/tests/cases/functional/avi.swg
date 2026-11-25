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
// of their own, it interleaves a PCM audio stream, and its header list carries chunks this
// decoder does not otherwise need.
#test
{
    var reader = expect Reader.open(videoFixturePath("cogliati-turning-pages.avi"))
    Swag.require(reader.width() == 160 and reader.height() == 120)
    Swag.require(reader.frameCount() == 233)
    Swag.require(reader.audioTrackCount() == 1)

    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleEncoding() == .Pcm8 and sound.sampleRateHz() == 11_024 and sound.numChannels() == 1)
    Swag.require(sound.sampleFrameCount() == 171_240 and sound.payloadSize() == 171_240 and sound.isPacketStream())
    let crossing = expect sound.readPayload(11_020, 8)
    Swag.require(Slice.equals(crossing.toSlice(), [127'u8, 127, 127, 126, 126, 125, 125, 125]))

    // The camera states its rate as 1000000/66666 rather than 15/1, and the decoder keeps what
    // the file says instead of rounding it to the rate the camera meant.
    Swag.require(reader.frameRate() == expect FrameRate.create(1_000_000, 66_666))
    Swag.require(Math.isEqualEpsilon(reader.frameRate().framesPerSecond(), 15.0, 0.001))
    Swag.require(Math.isEqualEpsilon(reader.durationInSeconds(), 15.53, 0.01))

    // The interleaved sound chunks are not pictures, and counting them as frames would be the
    // easiest mistake to make here.
    const Probes: [3] AviProbe = [AviProbe{0, 40, 30, 151, 119, 92},
                                  AviProbe{116, 80, 60, 160, 117, 84},
                                  AviProbe{232, 120, 90, 142, 105, 74}]
    aviAssertProbes("cogliati-turning-pages.avi", Probes, tolerance: 6)
}

// Both PCM tracks are interleaved with the video inside a record group.
#test
{
    var reader = expect Reader.open(videoFixturePath("edited-two-pcm-record-group.avi"))
    Swag.require(reader.frameCount() == 2 and reader.width() == 8 and reader.height() == 8)
    Swag.require(reader.audioTrackCount() == 2)

    let first  = unwrap reader.audioTrack(0)
    let second = unwrap reader.audioTrack(1)
    Swag.require(first.sampleEncoding() == .Pcm16 and first.numChannels() == 1)
    Swag.require(second.sampleEncoding() == .Pcm16 and second.numChannels() == 1)
    Swag.require(first.sampleRateHz() == 8_000 and first.sampleFrameCount() == 1_600)
    Swag.require(second.sampleRateHz() == 16_000 and second.sampleFrameCount() == 3_200)

    let firstPcm  = expect first.readPayload(0, first.payloadSize())
    let secondPcm = expect second.readPayload(0, second.payloadSize())
    Swag.require(Hash.Crc32.compute(firstPcm.toSlice()) == 0xD25725E9)
    Swag.require(Hash.Crc32.compute(secondPcm.toSlice()) == 0xBE5487FF)
}

// The same recording read backwards gives the same pictures as reading it forwards, because the
// container index says where every frame lies rather than the decoder remembering.
#test
{
    const Backwards: [3] AviProbe = [AviProbe{232, 120, 90, 142, 105, 74},
                                     AviProbe{116, 80, 60, 160, 117, 84},
                                     AviProbe{0, 40, 30, 151, 119, 92}]
    aviAssertProbes("cogliati-turning-pages.avi", Backwards, tolerance: 6)

    // Decoding a whole recording holds one frame, so the image the reader fills is the same one
    // from the first frame to the last.
    var reader = expect Reader.open(videoFixturePath("cogliati-turning-pages.avi"))
    var frame: Image
    expect reader.decodeFrameInto(&frame, 0)
    let storage = frame.pixels.buffer
    for index in 8'u64 do
        expect reader.decodeFrameInto(&frame, index * 29)
    Swag.require(frame.pixels.buffer == storage)
}

// Motion JPEG written by ffmpeg.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mjpeg-420.avi"))
    Swag.require(reader.width() == 64 and reader.height() == 48)
    Swag.require(reader.frameCount() == 10)
    Swag.require(reader.frameRate() == expect FrameRate.create(25, 1))

    var frame: Image
    const Sampled: [3] u64 = [0, 1, 9]
    for index in Sampled
    {
        expect reader.decodeFrameInto(&frame, index)
        videoAssertFixtureFrame(frame, index, tolerance: 4)
    }
}

// The same Layer III track decodes identically when interleaved with Motion JPEG in AVI.
#test
{
    let reader = expect Reader.open(videoFixturePath("ffmpeg-mjpeg-mp3.avi"))
    Swag.require(reader.frameCount() == 10 and reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleEncoding() == .Mp3 and sound.sampleRateHz() == 48_000 and sound.numChannels() == 1)

    let reference      = expect Reader.open(videoFixturePath("ffmpeg-h264-mp3.mp4"))
    let referenceSound = unwrap reference.audioTrack(0)
    Swag.require(sound.packetCount() == referenceSound.packetCount() and sound.sampleFrameCount() == referenceSound.sampleFrameCount())
    var decoded, expected: Array's16
    expect sound.decodePcm16(func|&decoded|(samples)
    {
        decoded.add(samples)
        return true
    })
    expect referenceSound.decodePcm16(func|&expected|(samples)
    {
        expected.add(samples)
        return true
    })
    Swag.require(Slice.equals(decoded.toSlice(), expected.toSlice()))
}

// Picture-only opening can use the video index even when walking the sound chunks would fail.
#test
{
    let original = videoFixturePath("ffmpeg-mjpeg-mp3.avi")
    var bytes    = expect File.readAllBytes(original)
    let movie    = Slice.findSubslice(bytes.toSlice(), "movi")
    Swag.require(movie + 12 <= bytes.count and aviHasId(bytes.toSlice(), movie + 4, "00dc"))
    let firstSize = cast(u64, aviReadU32(bytes.toSlice(), movie + 8))
    let audio     = movie + 12 + firstSize + (firstSize & 1)
    Swag.require(audio + 8 <= bytes.count and aviHasId(bytes.toSlice(), audio, "01wb"))
    aviWriteU32(bytes.toSlice(), audio + 4, Swag.U32.Max)

    let path = videoTempPath("avi-picture-only", "avi")
    defer discard catch File.delete(path)
    expect File.writeAllBytes(path, bytes.toSlice())

    var rejected: Swag.Error
    discard catch Reader.open(path) as rejected
    Swag.require(rejected.value() is InvalidFormatError)

    var reader    = expect Reader.open(path, pictureOnly: true)
    var reference = expect Reader.open(original)
    Swag.require(reader.audioTrackCount() == 0 and reader.frameCount() == reference.frameCount())
    let actual   = expect reader.decodeFrame(9)
    let expected = expect reference.decodeFrame(9)
    Swag.require(Slice.equals(actual.pixels.toSlice(), expected.pixels.toSlice()))
}

// ffmpeg codes 4:2:2 and 4:4:4 Motion JPEG with chroma grids that differ from the usual 4:2:0
// layout. Decode all three through the same public path and compare them with independent output.
#test
{
    const Files = ["ffmpeg-mjpeg-422.avi", "ffmpeg-mjpeg-444.avi"]
    for file in Files
    {
        var reader = expect Reader.open(videoFixturePath(file))
        Swag.require(reader.width() == 64 and reader.height() == 48)
        Swag.require(reader.frameCount() == 10)

        var frame: Image
        const Sampled: [3] u64 = [0, 1, 9]
        for index in Sampled
        {
            expect reader.decodeFrameInto(&frame, index)
            videoAssertFixtureFrame(frame, index, tolerance: 4)
        }
    }
}

// A broadcast rate is a ratio, and the stream header is what carries it exactly.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mjpeg-ntsc.avi"))
    Swag.require(reader.frameRate() == expect FrameRate.create(30_000, 1_001))
    Swag.require(reader.frameRate().framesPerSecond() > 29.97 and reader.frameRate().framesPerSecond() < 29.971)
    videoAssertFixtureFrame(expect reader.decodeFrame(9), 9, tolerance: 4)
}

// Uncompressed frames, in the two depths the format carries and at a width whose rows need
// padding. ffmpeg stores them top-down, with a negative bitmap height and no codec name at all.
#test
{
    var deep = expect Reader.open(videoFixturePath("ffmpeg-rawvideo-bgra.avi"))
    Swag.require(deep.width() == 32 and deep.height() == 24 and deep.frameCount() == 6)
    let deepFrame = expect deep.decodeFrame(5)
    videoAssertFixtureFrame(deepFrame, 5, tolerance: 0)
    videoAssertColor(deepFrame.pixelColor(31, 0), 0, 255, 0, tolerance: 0)
    videoAssertGray(deepFrame.pixelColor(31, 23), videoFixtureGray(5), tolerance: 0)

    var flat = expect Reader.open(videoFixturePath("ffmpeg-rawvideo-bgr24.avi"))
    videoAssertFixtureFrame(expect flat.decodeFrame(0), 0, tolerance: 0)

    // 33 pixels of 24 bits fill 99 bytes, and a bitmap row is padded to 100.
    var odd = expect Reader.open(videoFixturePath("ffmpeg-rawvideo-odd.avi"))
    Swag.require(odd.width() == 33 and odd.height() == 25 and odd.frameCount() == 3)
    for index in 3'u64
    {
        let frame = expect odd.decodeFrame(index)
        videoAssertFixtureFrame(frame, index, tolerance: 0)
        videoAssertColor(frame.pixelColor(32, 0), 0, 255, 0, tolerance: 0)
        videoAssertGray(frame.pixelColor(32, 24), videoFixtureGray(index), tolerance: 0)
    }
}

// BI_RGB 16-bit frames use the default RGB555 masks. This synthetic 5x2 stream has padded rows
// stored bottom-up, and its two frames use distinct colors to exercise seeking as well as pixels.
#test
{
    var reader = expect Reader.open(videoFixturePath("synthetic-rgb555-padding-bottom-up.avi"))
    Swag.require(reader.width() == 5 and reader.height() == 2 and reader.frameCount() == 2)

    var frame = expect reader.decodeFrame(1)
    videoAssertColor(frame.pixelColor(0, 0), 16, 33, 49, tolerance: 0)
    videoAssertColor(frame.pixelColor(4, 0), 74, 41, 24, tolerance: 0)
    videoAssertColor(frame.pixelColor(0, 1), 247, 16, 66, tolerance: 0)

    frame = expect reader.decodeFrame(0)
    videoAssertColor(frame.pixelColor(0, 0), 255, 0, 0, tolerance: 0)
    videoAssertColor(frame.pixelColor(2, 0), 0, 0, 255, tolerance: 0)
    videoAssertColor(frame.pixelColor(1, 1), 0, 255, 255, tolerance: 0)
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
        Swag.require(reader.width() == 32 and reader.height() == 24)
        Swag.require(reader.frameCount() == 6)
        videoAssertFixtureFrame(expect reader.decodeFrame(0), 0, tolerance: 0)
        videoAssertFixtureFrame(expect reader.decodeFrame(5), 5, tolerance: 0)
        videoAssertFixtureFrame(expect reader.decodeFrame(3), 3, tolerance: 0)
    }
}

// A child chunk must stay inside its `rec ` list even when later records remain inside `movi`.
#test
{
    var bytes       = expect File.readAllBytes(videoFixturePath("edited-record-groups.avi"))
    let raw         = bytes.toSlice()
    var firstRecord = 0'u64
    var foundRecord = false
    while firstRecord + 20 <= raw.count
    {
        if aviHasId(raw, firstRecord, "LIST") and
           aviHasId(raw, firstRecord + 8, "rec ") and
           aviHasId(raw, firstRecord + 12, "00dc")
        {
            foundRecord = true
            break
        }

        firstRecord += 1
    }

    Swag.require(foundRecord)

    let firstRecordSize = cast(u64, aviReadU32(raw, firstRecord + 4))
    let secondRecord    = firstRecord + 8 + firstRecordSize + (firstRecordSize & 1)
    Swag.require(aviHasId(raw, secondRecord, "LIST") and aviHasId(raw, secondRecord + 8, "rec "))
    let secondRecordSize = cast(u64, aviReadU32(raw, secondRecord + 4))
    let secondRecordEnd  = secondRecord + 8 + secondRecordSize + (secondRecordSize & 1)
    let crossingSize     = cast(u32, secondRecordEnd - (firstRecord + 20))
    let sizeOffset       = firstRecord + 16
    bytes[sizeOffset]     = cast(u8, crossingSize & 0xFF)
    bytes[sizeOffset + 1] = cast(u8, (crossingSize >> 8) & 0xFF)
    bytes[sizeOffset + 2] = cast(u8, (crossingSize >> 16) & 0xFF)
    bytes[sizeOffset + 3] = cast(u8, (crossingSize >> 24) & 0xFF)

    var rejected: Swag.Error
    discard catch Reader.openMemory("crossing-record.avi", bytes.toSlice()) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
}

// A frame chunk cannot claim payload bytes beyond the `movi` list that contains it.
#test
{
    var bytes     = expect File.readAllBytes(videoFixturePath("edited-no-index.avi"))
    let raw       = bytes.toSlice()
    var frameList = 0'u64
    while frameList + 4 <= raw.count and not aviHasId(raw, frameList, "movi") do
        frameList += 1
    Swag.require(frameList + 12 <= raw.count and aviHasId(raw, frameList + 4, "00dc"))

    let chunkSize = frameList + 8
    bytes[chunkSize]     = 0xFF
    bytes[chunkSize + 1] = 0xFF
    bytes[chunkSize + 2] = 0xFF
    bytes[chunkSize + 3] = 0xFF

    var rejected: Swag.Error
    discard catch Reader.openMemory("oversized-frame.avi", bytes.toSlice()) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
}

// An unusable `idx1` entry falls back to walking the frame list, preserving playable frames.
#test
{
    var bytes = expect File.readAllBytes(videoFixturePath("ffmpeg-rawvideo-bgr24.avi"))
    let raw   = bytes.toSlice()
    var index = 0'u64
    while index + 24 <= raw.count and not aviHasId(raw, index, "idx1") do
        index += 1
    Swag.require(index + 24 <= raw.count)

    let firstOffset = index + 16
    for byteIndex in 4'u64 do
        bytes[firstOffset + byteIndex] = 0xFF

    var reader = expect Reader.openMemory("bad-index.avi", bytes.toSlice())
    Swag.require(reader.frameCount() == 6)
    videoAssertFixtureFrame(expect reader.decodeFrame(5), 5, tolerance: 0)
}

// A valid but incomplete `idx1` must not hide frames still present in the movie list.
#test
{
    var bytes = expect File.readAllBytes(videoFixturePath("ffmpeg-rawvideo-bgr24.avi"))
    let raw   = bytes.toSlice()
    var index = 0'u64
    while index + 8 <= raw.count and not aviHasId(raw, index, "idx1") do
        index += 1
    Swag.require(index + 8 <= raw.count and aviReadU32(raw, index + 4) >= 6 * 16)

    bytes.resize(index + 8 + 16)
    bytes[index + 4] = 16
    bytes[index + 5] = 0
    bytes[index + 6] = 0
    bytes[index + 7] = 0
    let riffSize = cast(u32, bytes.count - 8)
    for byteIndex in 4 do
        bytes[4 + byteIndex] = cast(u8, (riffSize >> cast(u32, (byteIndex * 8))) & 0xFF)

    var reader = expect Reader.openMemory("partial-index.avi", bytes.toSlice())
    Swag.require(reader.frameCount() == 6)
    videoAssertFixtureFrame(expect reader.decodeFrame(5), 5, tolerance: 0)
}

// MPEG-4 I-pictures remain resynchronization points when a valid AVI has no `idx1` chunk.
#test
{
    var bytes = expect File.readAllBytes(videoFixturePath("ffmpeg-mpeg4-packed.avi"))
    var index = 0'u64
    while index + 8 <= bytes.count and not aviHasId(bytes.toSlice(), index, "idx1") do
        index += 1
    Swag.require(index + 8 <= bytes.count)

    // Keep the media and headers, remove the optional index, and repair the RIFF length.
    bytes.resize(index)
    aviWriteU32(bytes.toSlice(), 4, cast(u32, bytes.count - 8))

    var reader = expect Reader.openMemory("packed-no-index.avi", bytes.toSlice())
    Swag.require(reader.frameCount() == 60)
    Swag.require(reader.syncFrameAt(1) == 28)
    Swag.require(reader.syncFrameAt(31) == 58)

    var frame: Image
    expect reader.decodeFrameInto(&frame, 58)
    Swag.require(frame.width == 96 and frame.height == 64)
    let reference = expect reader.decodeFrame(28)
    let initial   = expect reader.decodeFrame(0)
    reader.close()

    // MPEG-4 user data can place a VOP marker beyond the first file read window.
    let movieList = Slice.findSubslice(bytes.toSlice(), "movi")
    Swag.require(movieList < bytes.count)
    var chunk = movieList + 4
    for 28
    {
        let size = cast(u64, aviReadU32(bytes.toSlice(), chunk + 4))
        chunk += 8 + size + (size & 1)
    }

    func padHeader(bytes: *Array'u8, chunk: u64, userData: const [..] u8)
    {
        let frameSize = aviReadU32(bytes.toSlice(), chunk + 4)
        let payload   = chunk + 8
        const Vop: [4] u8 = [0'u8, 0, 1, 0xB6]
        let vop = Slice.findSubslice(bytes.toSlice()[payload until payload + frameSize], Vop)
        Swag.require(vop < frameSize)
        bytes.insertAt(payload + vop, userData)
        aviWriteU32(bytes.toSlice(), chunk + 4, frameSize + cast(u32, userData.count))
    }

    var userData: Array'u8
    userData.resize(2 * ByteSource.WindowSize)
    Memory.set(userData.storage(), 'A', userData.count)
    userData[0] = 0
    userData[1] = 0
    userData[2] = 1
    userData[3] = 0xB2
    padHeader(&bytes, chunk, userData.toSlice())
    padHeader(&bytes, movieList + 4, userData.toSlice())
    aviWriteU32(bytes.toSlice(), movieList - 4, cast(u32, bytes.count - movieList))
    aviWriteU32(bytes.toSlice(), 4, cast(u32, bytes.count - 8))

    let path = videoTempPath("avi-vop-window", "avi")
    defer discard catch File.delete(path)
    expect File.writeAllBytes(path, bytes.toSlice())
    var file = expect Reader.open(path)
    Swag.require(file.frameCount() == 60 and file.syncFrameAt(1) == 28 and file.syncFrameAt(31) == 58)
    expect file.decodeFrameInto(&frame, 0)
    Swag.require(Slice.equals(frame.pixels.toSlice(), initial.pixels.toSlice()))
    expect file.decodeFrameInto(&frame, 28)
    Swag.require(Slice.equals(frame.pixels.toSlice(), reference.pixels.toSlice()))
}

// An AVI's keyframe slot can be followed by B-pictures that appear before the keyframe.
// Every random-access result must match playback, including the final B- and I-pictures.
#test
{
    let path   = videoFixturePath("ffmpeg-mpeg4-packed.avi")
    var linear = expect Reader.open(path)
    let bytes  = expect File.readAllBytes(path)
    var random = expect Reader.openMemory("mpeg4.avi", bytes.toSlice())
    var checksums: [60] u32
    Swag.require(random.frameCount() == checksums.count)

    var image: Image
    for rank in checksums.count
    {
        expect linear.decodeFrameInto(&image, rank)
        checksums[rank] = Hash.Crc32.compute(image.pixels.toSlice())
    }

    for index in checksums.count
    {
        let rank = checksums.count - index - 1
        expect random.decodeFrameInto(&image, rank)
        Swag.require(Hash.Crc32.compute(image.pixels.toSlice()) == checksums[rank])
    }
}

// The packets in B-pictures 1 and 2 contain runs of implicit macroblocks at their ends.
// Seeking back from red frames must reconstruct all of the original blue luma samples.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mpeg4-b-packets.avi"))
    Swag.require(reader.frameCount() == 9)
    var frame: PlanarFrame
    for rank in [8'u64, 1, 7, 2]
    {
        expect reader.decodeFramePlanesInto(&frame, rank)
        Swag.require(frame.width == 352 and frame.height == 256)
        if rank < 4 do
            Swag.require(Hash.Crc32.compute(frame.luma.toSlice()) == 0x288A1990)
        else do
            Swag.require(frame.luma[136 * frame.strideLuma + 20] == 81)
    }
}

// A frame that carries no payload repeats the picture before it, which is how the container
// holds a stream that pauses at a constant frame rate.
#test
{
    var reader = expect Reader.open(videoFixturePath("edited-dropped-frames.avi"))
    Swag.require(reader.frameCount() == 6)

    // Frames 3 and 4 were emptied, so both show the picture of frame 2. Reading them out of
    // order proves the answer does not depend on what was decoded before.
    videoAssertFixtureFrame(expect reader.decodeFrame(4), 2, tolerance: 0)
    videoAssertFixtureFrame(expect reader.decodeFrame(0), 0, tolerance: 0)
    videoAssertFixtureFrame(expect reader.decodeFrame(3), 2, tolerance: 0)
    videoAssertFixtureFrame(expect reader.decodeFrame(5), 5, tolerance: 0)
}

// Low-delay MPEG-4 pictures keep their AVI order across a backward VOP timestamp.
#test
{
    var reader = expect Reader.open(videoFixturePath("edited-mpeg4-avi-clock.avi"))
    Swag.require(reader.frameCount() == 10)

    // The timestamp steps backward at frame 4. Check both sequential decode and random access.
    var frame: PlanarFrame
    for index in reader.frameCount()
    {
        expect reader.decodeFramePlanesInto(&frame, index)
        Swag.require(frame.luma[0] == cast(u8, (24 + index * 20)))
    }

    const Seeks: [4] u64 = [5, 3, 4, 9]
    for index in Seeks
    {
        expect reader.decodeFramePlanesInto(&frame, index)
        Swag.require(frame.luma[0] == cast(u8, (24 + index * 20)))
    }
}

// AVI keeps the time of every video slot, including dropped pictures interleaved with sound.
#test
{
    const Luma: [9] u8 = [24, 24, 24, 24, 44, 64, 84, 104, 124]
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mpeg4-mp3-dropped.avi"))
    Swag.require(reader.frameCount() == Luma.count)
    Swag.require(reader.frameRate() == expect FrameRate.create(8, 1))
    Swag.require(reader.frameTimestamp(4) == 0.5)
    Swag.require(reader.syncFrameAt(1) == 4)
    Swag.require(reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleEncoding() == .Mp3 and sound.sampleRateHz() == 48_000)
    var audible: bool
    expect sound.decodePcm16(0, 11_520, func|&audible|(samples)
    {
        for sample in samples where sample != 0 do
            audible = true
        return true
    })
    Swag.require(audible)

    var frame: PlanarFrame
    for index in Luma.count
    {
        expect reader.decodeFramePlanesInto(&frame, index)
        Swag.require(frame.luma[0] == Luma[index])
    }

    // Seek into the run of empty chunks through the packed-colour entry point as well.
    let first = expect reader.decodeFrame(0)
    discard expect reader.decodeFrame(8)
    let repeated = expect reader.decodeFrame(2)
    Swag.require(Slice.equals(first.pixels.toSlice(), repeated.pixels.toSlice()))
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
    Swag.require(reader.width() == Size and reader.height() == Size)
    Swag.require(reader.frameRate() == rate)
    Swag.require(reader.frameCount() == 2)
    Swag.require(reader.audioTrackCount() == 0)
    Swag.require(reader.streamFormat().extensions == ".avi")
    Swag.require(Math.isEqualEpsilon(reader.durationInSeconds(), 2.0 / 30.0, 0.0001))

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
        expect clip.addFrame(videoGrayImage(64, 48, cast(u8, (40 + index * 40))))

    var low: Avi.EncodeOptions
    low.quality = 20
    var high: Avi.EncodeOptions
    high.quality = 100

    let coarse = expect clip.encodeToBytes("coarse.avi", low)
    let fine   = expect clip.encodeToBytes("fine.avi", high)
    Swag.require(coarse.count < fine.count)

    var reader = expect Reader.openMemory("coarse.avi", coarse.toSlice())
    Swag.require(reader.frameCount() == 4)
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
    Swag.require(aviHasId(raw, 0, "RIFF") and aviHasId(raw, 8, "AVI "))
    Swag.require(aviHasId(raw, 12, "LIST") and aviHasId(raw, 20, "hdrl"))
    Swag.require(aviHasId(raw, 24, "avih") and aviHasId(raw, 100, "strh") and aviHasId(raw, 164, "strf"))
    Swag.require(aviHasId(raw, 212, "LIST") and aviHasId(raw, 220, "movi") and aviHasId(raw, 224, "00dc"))

    // Everything the header could only know once the last frame landed.
    Swag.require(aviReadU32(raw, 4) == cast(u32, bytes.count) - 8)
    Swag.require(aviReadU32(raw, 48) == 3)       // Frame count of the file header.
    Swag.require(aviReadU32(raw, 64) == 8)       // Frame width of the file header.
    Swag.require(aviReadU32(raw, 68) == 4)       // Frame height of the file header.
    Swag.require(aviReadU32(raw, 128) == 1)      // Rate denominator of the stream header.
    Swag.require(aviReadU32(raw, 132) == 24)     // Rate numerator of the stream header.
    Swag.require(aviReadU32(raw, 140) == 3)      // Frame count of the stream header.

    // The size of the frame list is what places the index right after the last frame.
    let indexStart = 220 + cast(u64, aviReadU32(raw, 216))
    Swag.require(aviHasId(raw, indexStart, "idx1"))
    Swag.require(aviReadU32(raw, indexStart + 4) == 3 * 16)
    Swag.require(aviHasId(raw, indexStart + 8, "00dc"))
    Swag.require(aviReadU32(raw, indexStart + 16) == 4)
    Swag.require(indexStart + 8 + 3 * 16 == bytes.count)
}

// The approximate `avih` frame period stays representable at the ends of the stream-rate range.
#test
{
    var slowBuffer: ConcatBuffer
    let slowRate   = expect FrameRate.create(1, 4_295)
    var slowWriter = expect Writer.createMemory("slow.avi", &slowBuffer, 2, 2, slowRate)
    expect slowWriter.addFrame(videoGrayImage(2, 2, 80))
    expect slowWriter.end()
    let slowBytes = slowBuffer.toArray()
    let slow      = slowBytes.toSlice()
    Swag.require(aviReadU32(slow, 32) == Swag.U32.Max)
    Swag.require(aviReadU32(slow, 128) == 4_295 and aviReadU32(slow, 132) == 1)

    var fastBuffer: ConcatBuffer
    let fastRate   = expect FrameRate.create(Swag.U32.Max, 1)
    var fastWriter = expect Writer.createMemory("fast.avi", &fastBuffer, 2, 2, fastRate)
    expect fastWriter.addFrame(videoGrayImage(2, 2, 80))
    expect fastWriter.end()
    let fastBytes = fastBuffer.toArray()
    let fast      = fastBytes.toSlice()
    Swag.require(aviReadU32(fast, 32) == 1)
    Swag.require(aviReadU32(fast, 128) == 1 and aviReadU32(fast, 132) == Swag.U32.Max)
}

// Finalizing an AVI without video frames is rejected before writing its empty index.
#test
{
    var buffer: ConcatBuffer
    let rate   = expect FrameRate.create(24, 1)
    var writer = expect Writer.createMemory("empty.avi", &buffer, 2, 2, rate)
    let opened = buffer.toArray()

    var rejected: Swag.Error
    discard catch writer.end() as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(Slice.equals(buffer.toSlice(), opened.toSlice()))
}

// A failed frame write ends the writer before its partial AVI index can be used by end().
#test
{
    var buffer: ConcatBuffer
    let rate   = expect FrameRate.create(24, 1)
    var writer = expect Writer.createMemory("failed-frame.avi", &buffer, 2, 2, rate)
    expect writer.sink.close()

    let frame = videoGrayImage(2, 2, 96)
    var rejected: Swag.Error
    discard catch writer.addFrame(frame) as rejected
    Swag.require(rejected.value() is BadParameterError and writer.frameCount() == 0)

    var repeated: Swag.Error
    discard catch writer.end() as repeated
    Swag.require(repeated.value() is BadParameterError)
    discard catch writer.addFrame(frame) as repeated
    Swag.require(repeated.value() is BadParameterError)
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
    Swag.require(reader.sourcePath() == fileName.toString())
    Swag.require(reader.frameCount() == 3 and reader.width() == 8 and reader.height() == 8)

    var frame: Image
    expect reader.decodeFrameInto(&frame, 2)
    videoAssertGray(frame.pixelColor(4, 4), 224, tolerance: 10)

    // Decoding into the same image reuses its storage instead of allocating another frame.
    let storage = frame.pixels.buffer
    expect reader.decodeFrameInto(&frame, 0)
    videoAssertGray(frame.pixelColor(4, 4), 32, tolerance: 10)
    Swag.require(frame.pixels.buffer == storage)

    reader.close()
    Swag.require(not reader.isOpen())
}

#test
{
    var notRiffOutcome: Swag.Error
    discard catch Reader.openMemory("bad.avi", "not a riff file at all") as notRiffOutcome
    let notRiff = notRiffOutcome.value()
    var notAviOutcome: Swag.Error
    discard catch Reader.openMemory("bad.avi", "RIFFsizeWAVEfmt ") as notAviOutcome
    let notAvi = notAviOutcome.value()
    Swag.require((notRiff is InvalidFormatError))
    Swag.require((notAvi is InvalidFormatError))

    // A container this module reads, truncated to its headers, has no frame to decode.
    var whole = expect File.readAllBytes(videoFixturePath("ffmpeg-rawvideo-bgr24.avi"))
    var truncatedOutcome: Swag.Error
    discard catch Reader.openMemory("short.avi", whole.toSlice()[0 until 2048]) as truncatedOutcome
    let truncated = truncatedOutcome.value()
    Swag.require(truncated != null)
}

// Returns the little-endian 32-bit value the container stores at `offset`.
func aviReadU32(bytes: const [..] u8, offset: u64)->u32
{
    var result = 0'u32
    for shift in 4 do
        result |= cast(u32, bytes[offset + cast(u64, shift)]) << cast(u32, (shift * 8))
    return result
}

func aviWriteU32(bytes: [..] u8, offset: u64, value: u32)
{
    for index in 4'u64 do
        bytes[offset + index] = cast(u8, (value >> cast(u32, index * 8)) & 0xFF)
}

// Reports whether the four characters of `id` sit at `offset`.
func aviHasId(bytes: const [..] u8, offset: u64, id: string)->bool
{
    for index in 4 where bytes[offset + cast(u64, index)] != id[index] do
        return false
    return true
}
