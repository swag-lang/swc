#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// Matroska retains the AVC access units of the source MP4 byte for byte. Decoding both containers
// at non-sequential positions proves the EBML block index, presentation ordering, and sync seeks
// reach the same pictures without making the codec itself the oracle.
#test
{
    var matroska = expect Reader.open(videoFixturePath("ffmpeg-h264-two-aac.mkv"))
    var mp4      = expect Reader.open(videoFixturePath("ffmpeg-h264-baseline.mp4"))
    @assert(matroska.streamFormat().extensions == ".mkv")
    @assert(matroska.width() == 64 and matroska.height() == 48)
    @assert(matroska.frameCount() == 20 and matroska.frameRate() == expect FrameRate.create(25, 1))
    @assert(matroska.hasPlanarFrames())

    const Frames: [5] u64 = [19, 0, 7, 12, 3]
    var actual, expected: Image
    for index in Frames
    {
        expect matroska.decodeFrameInto(&actual, index)
        expect mp4.decodeFrameInto(&expected, index)
        @assert(actual.width == expected.width and actual.height == expected.height and actual.pixelFormat == expected.pixelFormat)
        @assert(Slice.equals(actual.pixels.toSlice(), expected.pixels.toSlice()))
        @assert(Math.isEqualEpsilon(matroska.frameTimestamp(index), mp4.frameTimestamp(index), 0.000001))
    }

    @assert(matroska.frameAtTime(0.3) == 7)
}

// Every supported AAC track is exposed independently, with the default track first. The fixture
// deliberately carries the same access units twice so their sparse packet ranges can be compared
// without decoding them or loading the container into memory.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-h264-two-aac.mkv"))
    @assert(reader.audioTrackCount() == 2)
    let primary   = reader.audioTrack(0)!
    let alternate = reader.audioTrack(1)!
    @assert(primary.sampleEncoding() == .AacLc and alternate.sampleEncoding() == .AacLc)
    @assert(primary.sampleRateHz() == 44_100 and alternate.sampleRateHz() == 44_100)
    @assert(primary.numChannels() == 2 and alternate.numChannels() == 2)
    @assert(primary.packetCount() != 0 and primary.packetCount() == alternate.packetCount())
    @assert(!primary.isDataPreloaded() and !alternate.isDataPreloaded())
    let primaryBytes   = expect primary.readPayload(0, primary.payloadSize())
    let alternateBytes = expect alternate.readPayload(0, alternate.payloadSize())
    @assert(Slice.equals(primaryBytes.toSlice(), alternateBytes.toSlice()))
}

// A long container catches index truncation, timestamp accumulation, and distant-seek defects
// that the compact fixture cannot reach. Its pictures repeat the short source stream, so a seek
// near ten minutes can still be checked pixel for pixel without storing another reference image.
#test
{
    var longStream = expect Reader.open(videoFixturePath("ffmpeg-h264-two-aac-10min.mkv"))
    var reference  = expect Reader.open(videoFixturePath("ffmpeg-h264-baseline.mp4"))
    @assert(longStream.frameCount() == 15_000 and longStream.audioTrackCount() == 2)
    @assert(longStream.audioTrack(0)!.packetCount() == 14_250 and longStream.audioTrack(1)!.packetCount() == 14_250)

    const Frames: [4] u64 = [14_999, 12_007, 7_500, 20]
    var actual, expected: Image
    for index in Frames
    {
        expect longStream.decodeFrameInto(&actual, index)
        expect reference.decodeFrameInto(&expected, index % reference.frameCount())
        @assert(Slice.equals(actual.pixels.toSlice(), expected.pixels.toSlice()))
        @assert(Math.isEqualEpsilon(longStream.frameTimestamp(index), cast(f64) index / 25.0, 0.000001))
    }

    @assert(longStream.frameAtTime(599.96) == 14_999)
}

// Memory-backed Matroska uses the borrowed bytes for video and does not manufacture file cursors
// for its sound tracks.
#test
{
    let bytes  = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-two-aac.mkv").toString())
    var reader = expect Reader.openMemory("clip.mkv", bytes.toSlice())
    @assert(reader.frameCount() == 20 and reader.audioTrackCount() == 0)
    let frame = expect reader.decodeFrame(10)
    @assert(frame.width == 64 and frame.height == 48)
}

// The registry claims Matroska alone, and malformed or unrelated EBML input remains a format
// error rather than being decoded from a coincidental extension.
#test
{
    @assert(Reader.canOpen("clip.mkv"))
    @assert(!Reader.canOpen("clip.webm"))

    const Truncated: [5] u8 = [0x1A, 0x45, 0xDF, 0xA3, 0x80]
    discard catch Reader.openMemory("broken.mkv", Truncated) as truncated
    @assert(truncated is InvalidFormatError)
}
