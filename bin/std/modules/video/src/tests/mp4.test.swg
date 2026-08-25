#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// Returns the first byte of `tag`, or the byte count when it is absent.
func mp4FindTag(bytes: const [..] u8, tag: string)->u64
{
    if @countof(tag) > @countof(bytes) do
        return @countof(bytes)
    for offset in @countof(bytes) - @countof(tag) + 1
    {
        var matches = true
        for index in @countof(tag) where bytes[offset + index] != tag[index]
        {
            matches = false
            break
        }

        if matches do
            return offset
    }

    return @countof(bytes)
}

// Returns a big-endian 32-bit value from an independently inspected container.
func mp4ReadU32(bytes: const [..] u8, offset: u64)->u32
{
    return (cast(u32) bytes[offset] << 24) | (cast(u32) bytes[offset + 1] << 16) | (cast(u32) bytes[offset + 2] << 8) | cast(u32) bytes[offset + 3]
}

// Returns a big-endian 64-bit value from an independently inspected container.
func mp4ReadU64(bytes: const [..] u8, offset: u64)->u64
{
    return (cast(u64) mp4ReadU32(bytes, offset) << 32) | cast(u64) mp4ReadU32(bytes, offset + 4)
}

// FFmpeg puts the movie before its media payload, uses one chunk for ten samples, and identifies
// Motion JPEG through the generic `mp4v` entry with JPEG object type `0x6c`. It therefore exercises
// both table expansion and a top-level layout the encoder in this module does not produce.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mjpeg.mp4"))
    @assert(reader.width() == 64 and reader.height() == 48)
    @assert(reader.frameCount() == 10)
    @assert(reader.frameRate() == expect FrameRate.create(12_800, 512))
    @assert(Math.isEqualEpsilon(reader.durationInSeconds(), 0.4, 0.0001))

    const Frames: [3] u64 = [9, 0, 5]
    var frame: Image
    for index in Frames
    {
        expect reader.decodeFrameInto(&frame, index)
        videoAssertFixtureFrame(frame, index, tolerance: 4)
    }
}

// A Motion JPEG MP4 written by the module reads back out of order and preserves the exact rate.
#test
{
    const Size = 32's32
    let rate = expect FrameRate.create(30_000, 1_001)
    var clip = expect Clip.create(Size, Size, rate)
    expect clip.addFrame(videoGrayImage(Size, Size, 40))
    expect clip.addFrame(videoGrayImage(Size, Size, 120))
    expect clip.addFrame(videoGrayImage(Size, Size, 220))

    var options: Mp4.EncodeOptions
    options.quality = 85
    let bytes  = expect clip.encodeToBytes("clip.mp4", options)
    var reader = expect Reader.openMemory("clip.mp4", bytes.toSlice())
    @assert(reader.width() == Size and reader.height() == Size)
    @assert(reader.frameRate() == rate and reader.frameCount() == 3)
    @assert(reader.streamFormat().extensions == ".mp4;.m4v;.mov")
    videoAssertGray((expect reader.decodeFrame(2)).pixelColor(16, 16), 220, tolerance: 8)
    videoAssertGray((expect reader.decodeFrame(0)).pixelColor(16, 16), 40, tolerance: 8)

    // Inspect the container independently of the decoder: `mdat` uses an extended size and the
    // movie and 64-bit chunk table follow its streamed payload.
    let raw       = bytes.toSlice()
    let mediaData = mp4FindTag(raw, "mdat") - 4
    let movie     = mp4FindTag(raw, "moov") - 4
    @assert(mp4FindTag(raw, "ftyp") == 4)
    @assert(mp4ReadU32(raw, mediaData) == 1)
    @assert(mp4ReadU64(raw, mediaData + 8) == movie - mediaData)
    @assert(mp4FindTag(raw, "stsd") < bytes.count and mp4FindTag(raw, "mp4v") < bytes.count and mp4FindTag(raw, "esds") < bytes.count)
    @assert(mp4FindTag(raw, "stsz") < bytes.count and mp4FindTag(raw, "co64") < bytes.count)
}

// The public MP4 options select the JPEG quality of every sample.
#test
{
    var source  = expect Reader.open(videoFixturePath("ffmpeg-mjpeg.mp4"))
    let picture = expect source.decodeFrame(0)
    var clip    = expect Clip.create(picture.width, picture.height, expect FrameRate.create(25, 1))
    expect clip.addFrame(picture)

    var low: Mp4.EncodeOptions
    low.quality = 20
    var high: Mp4.EncodeOptions
    high.quality = 100
    let coarse = expect clip.encodeToBytes("coarse.mp4", low)
    let fine   = expect clip.encodeToBytes("fine.mp4", high)
    @assert(coarse.count < fine.count)
}

// File-backed patching produces the same seekable stream as memory-backed patching.
#test
{
    let fileName = videoTempPath("mp4-roundtrip", "mp4")
    defer discard catch File.delete(fileName)

    let rate = expect FrameRate.create(12, 1)
    var clip = expect Clip.create(16, 16, rate)
    expect clip.addFrame(videoGrayImage(16, 16, 32))
    expect clip.addFrame(videoGrayImage(16, 16, 192))
    expect clip.save(fileName)

    var reader = expect Reader.open(fileName)
    @assert(reader.sourcePath() == fileName.toString())
    videoAssertGray((expect reader.decodeFrame(1)).pixelColor(8, 8), 192, tolerance: 8)
}

// Truncated metadata is malformed, while a valid `mp4v` track naming another object type is a
// supported container carrying a codec this implementation does not decode.
#test
{
    let fixture = expect File.readAllBytes(videoFixturePath("ffmpeg-mjpeg.mp4").toString())
    discard catch Reader.openMemory("short.mp4", fixture.toSlice()[0 until 96]) as truncated
    @assert(truncated is InvalidFormatError)

    var unsupported = fixture
    let descriptor  = mp4FindTag(unsupported.toSlice(), "esds")
    var objectType  = descriptor + 4
    while objectType < unsupported.count and unsupported[objectType] != 0x6C do
        objectType += 1
    @assert(objectType < unsupported.count)
    unsupported[objectType] = 0x21

    discard catch Reader.openMemory("h264.mp4", unsupported.toSlice()) as codec
    @assert(codec is UnsupportedFormatError)
}

// A file-backed MP4 exposes its AAC-LC access units as a streamed std/audio track and keeps
// variable presentation timestamps available to an audio-master player.
#test
{
    var reader = expect Reader.open(videoFixturePath("glint-aac-mjpeg.mp4"))
    @assert(reader.frameCount() == 10 and reader.audioTrackCount() == 1)
    let sound = reader.audioTrack(0)!
    @assert(sound.sampleEncoding() == .AacLc)
    @assert(sound.sampleRateHz() == 44_100 and sound.numChannels() == 2)
    @assert(sound.packetCount() >= 18 and !sound.isDataPreloaded())
    @assert(Math.isEqualEpsilon(reader.frameTimestamp(5), 0.2, 0.000001))
    @assert(reader.frameAtTime(0.219) == 5)
}

// A sample table states presentation durations, and a writer is free to spread them so a track's
// total lands where it wants. What a packet decodes to is the codec's business, so a table stating
// 1023 and 1025 either side of 1024 changes nothing about the sound that comes out of it.
#test
{
    var reader = expect Reader.open(videoFixturePath("glint-aac-drift.mp4"))
    @assert(reader.frameCount() == 10 and reader.audioTrackCount() == 1)

    let drifted = reader.audioTrack(0)!
    @assert(drifted.sampleEncoding() == .AacLc)
    @assert(drifted.sampleRateHz() == 44_100 and drifted.numChannels() == 2)

    var steady = expect Reader.open(videoFixturePath("glint-aac-mjpeg.mp4"))
    let even   = steady.audioTrack(0)!
    @assert(drifted.packetCount() == even.packetCount())
    @assert(drifted.sampleFrameCount() == even.sampleFrameCount())
}
