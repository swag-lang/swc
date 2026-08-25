#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

func waitForMatroskaAudio(reader: *Reader, count: u32)
{
    var attempts: u32
    while reader.audioTrackCount() != count and attempts < 1000
    {
        Threading.Thread.sleep(1'ms)
        attempts += 1
    }

    @assert(reader.audioTrackCount() == count)
}

// Indexed duration and track timing make a file-backed stream seekable before its complete frame
// table exists. The requested frame is indexed on demand without scanning the rest of the file.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-h264-two-aac.mkv"))
    @assert(reader.frameCount() == 0 and reader.durationInSeconds() > 0)
    let target = reader.frameAtTime(0.4)
    @assert(target == 10)

    var frame: Image
    expect reader.decodeFrameInto(&frame, target)
    @assert(frame.width == 64 and frame.height == 48)
}

// Matroska retains the AVC access units of the source MP4 byte for byte. Decoding both containers
// at non-sequential positions proves the EBML block index, presentation ordering, and sync seeks
// reach the same pictures without making the codec itself the oracle.
#test
{
    var matroska = expect Reader.open(videoFixturePath("ffmpeg-h264-two-aac.mkv"))
    var mp4      = expect Reader.open(videoFixturePath("ffmpeg-h264-baseline.mp4"))
    var indexed: Image
    expect matroska.decodeFrameInto(&indexed, 0)
    @assert(matroska.streamFormat().extensions == ".mkv")
    @assert(matroska.width() == 64 and matroska.height() == 48)
    @assert(matroska.frameCount() == 0 and matroska.frameRate() == expect FrameRate.create(25, 1))
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

    @assert(matroska.frameCount() == 20)
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
    @assert(primary.displayName() == "Primary" and alternate.displayName() == "Alternate")
    @assert(primary.language() == "und" and alternate.language() == "und")
    @assert(primary.sampleRateHz() == 44_100 and alternate.sampleRateHz() == 44_100)
    @assert(primary.numChannels() == 2 and alternate.numChannels() == 2)
    @assert(primary.packetCount() != 0 and primary.packetCount() == alternate.packetCount())
    @assert(!primary.isDataPreloaded() and !alternate.isDataPreloaded())
    let primaryBytes   = expect primary.readPayload(0, primary.payloadSize())
    let alternateBytes = expect alternate.readPayload(0, alternate.payloadSize())
    @assert(Slice.equals(primaryBytes.toSlice(), alternateBytes.toSlice()))
}

// Matroska maps every native multichannel packet codec to std/audio without copying payloads.
// The packet duration comes from the codec framing: AAC has 1,024 samples, both Dolby fixtures
// carry six-block sync frames with 1,536, and a FLAC frame states its own block size, 4,608 here.
#test
{
    const Files:        [4] string = ["ffmpeg-h264-aac-5.1.mkv", "ffmpeg-h264-ac3-5.1.mkv", "ffmpeg-h264-eac3-5.1.mkv", "ffmpeg-h264-flac-5.1.mkv"]
    const Encodings:    [4] Audio.SoundFileEncoding = [.AacLc, .Ac3, .Eac3, .Flac]
    const PacketFrames: [4] u32    = [1024, 1536, 1536, 4608]
    for fileIndex in @countof(Files)
    {
        var reader = expect Reader.open(videoFixturePath(Files[fileIndex]))
        waitForMatroskaAudio(&reader, 1)
        @assert(reader.audioTrackCount() == 1)
        let sound = reader.audioTrack(0)!
        @assert(sound.sampleEncoding() == Encodings[fileIndex])
        @assert(sound.sampleRateHz() == 48_000 and sound.numChannels() == 6)
        @assert(sound.speakerChannelMask() == 0x3F and !sound.isDataPreloaded())
        @assert((expect sound.packet(0)).sampleFrameCount == PacketFrames[fileIndex])
    }
}

// CodecDelay belongs to the decoded timeline, not to the audible one. Matroska converts its
// nanoseconds to sample frames and leaves the compressed packet index unchanged.
#test
{
    var plain   = expect Reader.open(videoFixturePath("ffmpeg-h264-two-aac.mkv"))
    var delayed = expect Reader.open(videoFixturePath("mkv-aac-codec-delay.mkv"))
    waitForMatroskaAudio(&plain, 2)
    waitForMatroskaAudio(&delayed, 2)
    let plainSound   = plain.audioTrack(0)!
    let delayedSound = delayed.audioTrack(0)!
    @assert(delayedSound.packetCount() == plainSound.packetCount())
    @assert(delayedSound.sampleFrameCount() + 1024 == plainSound.sampleFrameCount())
}

// A long container catches cue-offset, timestamp accumulation, and distant-seek defects that the
// compact fixture cannot reach. Its pictures repeat the short source stream, so a seek near ten
// minutes can still be checked pixel for pixel without storing another reference image.
#test
{
    var longStream = expect Reader.open(videoFixturePath("ffmpeg-h264-two-aac-10min.mkv"))
    var reference  = expect Reader.open(videoFixturePath("ffmpeg-h264-baseline.mp4"))

    // Before any media window exists, resynchronization still resolves through the container's
    // cues. Returning the requested non-sync frame here makes a slow player decode the whole GOP
    // under its loading overlay instead of jumping to one independently decodable picture.
    @assert(longStream.syncFrameAt(1) == 12)
    @assert(longStream.syncFrameAt(20) == 20)
    @assert(longStream.syncFrameAt(21) == 32)
    @assert(longStream.syncFrameAt(12_007) == 12_012)
    @assert(longStream.syncFrameAt(14_999) == 15_000)

    var indexed: Image
    expect longStream.decodeFrameInto(&indexed, 12_007)
    @assert(longStream.frameCount() == 0)
    @assert(Math.isEqualEpsilon(longStream.durationInSeconds(), 600.0, 0.001))
    let seekSound = longStream.audioTrack(0)!
    @assert(seekSound.timelineStartSeconds() == 0 or seekSound.timelineStartSeconds() < 480.28)
    @assert(480.28 - seekSound.timelineStartSeconds() < seekSound.durationInSeconds())

    // The frame immediately after a distant seek also proves that seek-only decode bounding is
    // removed as soon as the requested picture has been returned.
    const Frames: [5] u64 = [14_999, 12_007, 12_008, 7_500, 20]
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

// The complete audio-only pass must not require picture samples after disabling picture indexing.
// The opening cluster is playable immediately; the background pass then replaces it with the
// complete ten-minute packet table instead of failing at the end of the segment.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-h264-two-aac-10min.mkv"))
    @assert(reader.audioTrackCount() == 2)
    var attempts: u32
    while reader.audioTrack(0)!.durationInSeconds() < 100 and attempts < 5000
    {
        Threading.Thread.sleep(1'ms)
        attempts += 1
    }

    @assert(reader.audioTrack(0)!.durationInSeconds() >= 100)
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

// An unsupported picture codec is rejected as soon as the track metadata names it. The damaged
// first cluster proves opening never reaches media data after that answer is already known.
#test
{
    var bytes = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-two-aac.mkv").toString())

    const AvcId     = "V_MPEG4/ISO/AVC"
    const UnknownId = "V_MPEG4/ISO/XYZ"
    #assert(@countof(AvcId) == @countof(UnknownId))
    let codecOffset = Utf8.indexOf(bytes.toSlice(), AvcId)
    @assert(codecOffset != Swag.U64.Max)
    Memory.copy(bytes.buffer! + codecOffset, @dataof(UnknownId), @countof(UnknownId))

    const ClusterId: [4] u8 = [0x1F, 0x43, 0xB6, 0x75]
    let clusterOffset = Slice.findSubslice(bytes.toSlice(), ClusterId)
    @assert(clusterOffset != Swag.U64.Max)
    bytes[clusterOffset] = 0

    discard catch Reader.openMemory("unsupported.mkv", bytes.toSlice()) as unsupported
    @assert(unsupported is UnsupportedFormatError)
}

// A file-backed reader returns after metadata even when the first media cluster is malformed.
// The deferred decoder is the operation that reaches the cluster and reports its error.
#test
{
    var bytes = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-two-aac.mkv").toString())
    const ClusterId: [4] u8 = [0x1F, 0x43, 0xB6, 0x75]
    let clusterOffset = Slice.findSubslice(bytes.toSlice(), ClusterId)
    @assert(clusterOffset != Swag.U64.Max)
    bytes[clusterOffset] = 0

    let fileName = videoTempPath("matroska-deferred-index", "mkv")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, bytes.toSlice())

    var reader = expect Reader.open(fileName)
    @assert(reader.frameCount() == 0)
    discard catch reader.decodeFrame(0) as clusterError
    @assert(clusterError is InvalidFormatError)
}

// Cancellation can come from a viewer thread while a file-backed reader is about to build its
// block index. The pending decode fails promptly and the reader remains safe to close.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-h264-two-aac.mkv"))
    reader.requestCancel()
    discard catch reader.decodeFrame(0) as cancelled
    @assert(cancelled is BadParameterError)
}

// A string element states its length, and a writer that reserved room for a longer value fills the
// rest with zeros. Those zeros are padding, not content: a codec identifier written that way names
// the same codec, and a reader that keeps them matches nothing.
#test
{
    let padded: [8] u8 = ['V', '_', 'X', 0, 0, 0, 0, 0]
    var cursor = Matroska.Cursor.open(padded[0 until 8])
    let value  = expect cursor.readString({0, 0, 8, false})
    @assert(value.toString() == "V_X")
    @assert(@countof(value.toString()) == 3)
}

// A value that fills its element is kept whole.
#test
{
    let exact: [3] u8 = ['V', '_', 'X']
    var cursor = Matroska.Cursor.open(exact[0 until 3])
    let value  = expect cursor.readString({0, 0, 3, false})
    @assert(value.toString() == "V_X")
}
