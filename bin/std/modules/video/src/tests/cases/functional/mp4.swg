#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// Returns the first byte of `tag`, or the byte count when it is absent.
func mp4FindTag(bytes: const [..] u8, tag: string)->u64
{
    if tag.count > bytes.count do
        return bytes.count
    for offset in bytes.count - tag.count + 1
    {
        var matches = true
        for index in tag.count where bytes[offset + index] != tag[index]
        {
            matches = false
            break
        }

        if matches do
            return offset
    }

    return bytes.count
}

// Returns a big-endian 32-bit value from an independently inspected container.
func mp4ReadU32(bytes: const [..] u8, offset: u64)->u32 => (cast(u32, bytes[offset]) << 24) |
                                                           (cast(u32, bytes[offset + 1]) << 16) |
                                                           (cast(u32, bytes[offset + 2]) << 8) |
                                                           cast(u32, bytes[offset + 3])

// Returns a big-endian 64-bit value from an independently inspected container.
func mp4ReadU64(bytes: const [..] u8, offset: u64)->u64 => (cast(u64, mp4ReadU32(bytes, offset)) << 32) | cast(u64, mp4ReadU32(bytes, offset + 4))

func mp4AssertUnsignedCompositionOffset(rawOffset: u32) fail
{
    var bytes: [16] u8 = [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0]
    bytes[12] = cast(u8, (rawOffset >> 24) & 0xFF)
    bytes[13] = cast(u8, (rawOffset >> 16) & 0xFF)
    bytes[14] = cast(u8, (rawOffset >> 8) & 0xFF)
    bytes[15] = cast(u8, rawOffset & 0xFF)

    var source = ByteSource.openMemory(Swag.makeSlice(&bytes[0], bytes.count))
    var track: Mp4.Track
    track.times.add({1, 1})
    track.sizes.add(1)
    try track.parseCompositionOffsets(&source, bytes.count)
    let times = try track.sampleTimes()
    Swag.require(times.count == 1 and times[0] == cast(s64, rawOffset))
}

func mp4AssertSignedCompositionOffset(rawOffset: u32, expected: s64) fail
{
    var bytes: [16] u8 = [1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0]
    bytes[12] = cast(u8, (rawOffset >> 24) & 0xFF)
    bytes[13] = cast(u8, (rawOffset >> 16) & 0xFF)
    bytes[14] = cast(u8, (rawOffset >> 8) & 0xFF)
    bytes[15] = cast(u8, rawOffset & 0xFF)

    var source = ByteSource.openMemory(Swag.makeSlice(&bytes[0], bytes.count))
    var track: Mp4.Track
    track.times.add({1, 1})
    track.sizes.add(1)
    try track.parseCompositionOffsets(&source, bytes.count)
    let times = try track.sampleTimes()
    Swag.require(times.count == 1 and times[0] == expected)
}

// Pixel aspect ratio is stored beside the codec configuration in a visual sample entry.
#test
{
    var bytes: [94] u8
    bytes[78] = 0
    bytes[79] = 0
    bytes[80] = 0
    bytes[81] = 16
    bytes[82] = 'p'
    bytes[83] = 'a'
    bytes[84] = 's'
    bytes[85] = 'p'
    bytes[89] = 8
    bytes[93] = 9

    var source = ByteSource.openMemory(Swag.makeSlice(&bytes[0], bytes.count))
    var track: Mp4.Track
    let entry = Mp4.Box{kind: 0, data: 0, end: bytes.count}
    let found = expect track.parseCodecConfiguration(&source, entry, Mp4.AvcConfigId)
    Swag.require(not found)
    Swag.require(track.pixelAspectWidth == 8 and track.pixelAspectHeight == 9)

    // A container ratio overrides codec VUI; the display geometry remains separate from pixels.
    var picture: PictureStream
    picture.sampleAspectWidth = 16
    picture.sampleAspectHeight = 15
    let display = picture.displaySize(720, 480, track.pixelAspectWidth, track.pixelAspectHeight)
    Swag.require(display.width == 640 and display.height == 480)
    let codecDisplay = picture.displaySize(720, 480)
    Swag.require(codecDisplay.width == 768 and codecDisplay.height == 480)
}

// A fixed-size `stsz` table has no per-sample payload to bound its count, so reject an
// unreasonable count before expanding the track's sample-size array.
#test
{
    var bytes: [12] u8 = [0, 0, 0, 0, 0, 0, 0, 1, 0, 0x10, 0, 1]
    var source = ByteSource.openMemory(Swag.makeSlice(&bytes[0], bytes.count))
    var track: Mp4.Track
    var rejected: Swag.Error
    discard catch track.parseSampleSizes(&source, bytes.count) as rejected
    Swag.require(rejected.value() is UnsupportedFormatError)
    Swag.require(track.sizes.count == 0)
}

// FFmpeg puts the movie before its media payload, uses one chunk for ten samples, and identifies
// Motion JPEG through the generic `mp4v` entry with JPEG object type `0x6c`. It therefore exercises
// both table expansion and a top-level layout the encoder in this module does not produce.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mjpeg.mp4"))
    Swag.require(reader.width() == 64 and reader.height() == 48)
    Swag.require(reader.frameCount() == 10)
    Swag.require(reader.frameRate() == expect FrameRate.create(12_800, 512))
    Swag.require(Math.isEqualEpsilon(reader.durationInSeconds(), 0.4, 0.0001))

    const Frames: [3] u64 = [9, 0, 5]
    var frame: Image
    for index in Frames
    {
        expect reader.decodeFrameInto(&frame, index)
        videoAssertFixtureFrame(frame, index, tolerance: 4)
    }
}

// Version-zero composition offsets are unsigned 32-bit values and retain their full range.
#test
{
    expect mp4AssertUnsignedCompositionOffset(0x8000_0001)
    expect mp4AssertUnsignedCompositionOffset(Swag.U32.Max)
}

// Version-one composition offsets are signed, including both ends of the s32 range.
#test
{
    expect mp4AssertSignedCompositionOffset(0xFFFF_FFFF, -1)
    expect mp4AssertSignedCompositionOffset(0xFFFF_FF9C, -100)
    expect mp4AssertSignedCompositionOffset(0x8000_0000, -2_147_483_648's64)
    expect mp4AssertSignedCompositionOffset(0x7FFF_FFFF, 2_147_483_647's64)
}

// frameAtTime follows presentation timestamps when composition offsets extend the timeline
// beyond the average decode duration.
#test
{
    var track: Mp4.Track
    track.times.add({2, 100})
    track.sizes.add(1)
    track.sizes.add(1)
    track.ctsEntries.add({1, 0})
    track.ctsEntries.add({1, 100})
    track.timescale = 1000

    let times = expect track.sampleTimes()
    Swag.require(times.count == 2 and times[0] == 0 and times[1] == 200)
    let endTime = expect track.samplePresentationEnd(times.toSlice())
    Swag.require(endTime == 300)

    var decoder: Mp4.Decoder
    decoder.info.frameCount = times.count
    decoder.info.frameRate = expect track.frameRate()
    decoder.presentationTimescale = track.timescale
    decoder.presentationEndTime = endTime - times[0]
    for time in times do
        decoder.presentationTimes.add(time - times[0])
    Swag.require(decoder.presentationTimes[1] == 200)
    Swag.require(decoder.presentationEndTime == 300)
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
    Swag.require(reader.width() == Size and reader.height() == Size)
    Swag.require(reader.frameRate() == rate and reader.frameCount() == 3)
    Swag.require(reader.streamFormat().extensions == ".mp4;.m4v;.mov")
    videoAssertGray((expect reader.decodeFrame(2)).pixelColor(16, 16), 220, tolerance: 8)
    videoAssertGray((expect reader.decodeFrame(0)).pixelColor(16, 16), 40, tolerance: 8)

    // Inspect the container independently of the decoder: `mdat` uses an extended size and the
    // movie and 64-bit chunk table follow its streamed payload.
    let raw       = bytes.toSlice()
    let mediaData = mp4FindTag(raw, "mdat") - 4
    let movie     = mp4FindTag(raw, "moov") - 4
    Swag.require(mp4FindTag(raw, "ftyp") == 4)
    Swag.require(mp4ReadU32(raw, mediaData) == 1)
    Swag.require(mp4ReadU64(raw, mediaData + 8) == movie - mediaData)
    Swag.require(mp4FindTag(raw, "stsd") < bytes.count and
                 mp4FindTag(raw, "mp4v") < bytes.count and
                 mp4FindTag(raw, "esds") < bytes.count)
    Swag.require(mp4FindTag(raw, "stsz") < bytes.count and mp4FindTag(raw, "co64") < bytes.count)
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
    Swag.require(coarse.count < fine.count)
}

// MP4 sample aspect ratio is written as container metadata and does not alter coded dimensions.
#test
{
    let rate = expect FrameRate.create(24, 1)
    var clip = expect Clip.create(16, 16, rate)
    expect clip.addFrame(videoGrayImage(16, 16, 96))

    var defaults: Mp4.EncodeOptions
    let square = expect clip.encodeToBytes("square-pixels.mp4", defaults)
    Swag.require(mp4FindTag(square.toSlice(), "pasp") == square.count)

    var options: Mp4.EncodeOptions
    options.pixelAspectWidth = 16
    options.pixelAspectHeight = 15
    let bytes = expect clip.encodeToBytes("anamorphic.mp4", options)
    let raw = bytes.toSlice()
    let tag = mp4FindTag(raw, "pasp")
    Swag.require(tag < bytes.count and mp4ReadU32(raw, tag - 4) == 16)
    Swag.require(mp4ReadU32(raw, tag + 4) == 16 and mp4ReadU32(raw, tag + 8) == 15)

    var reader = expect Reader.openMemory("anamorphic.mp4", raw)
    Swag.require(reader.width() == 16 and reader.height() == 16 and reader.frameCount() == 1)
    Swag.require(reader.displayWidth() == 17 and reader.displayHeight() == 16)
    videoAssertGray((expect reader.decodeFrame(0)).pixelColor(8, 8), 96, tolerance: 8)

    var invalid = options
    invalid.pixelAspectHeight = 0
    var invalidOutcome: Swag.Error
    discard catch clip.encodeToBytes("invalid-aspect.mp4", invalid) as invalidOutcome
    Swag.require((invalidOutcome.value() is BadParameterError))
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
    Swag.require(reader.sourcePath() == fileName.toString())
    videoAssertGray((expect reader.decodeFrame(1)).pixelColor(8, 8), 192, tolerance: 8)
}

// Truncated metadata is malformed, while a valid `mp4v` track naming another object type is a
// supported container carrying a codec this implementation does not decode.
#test
{
    let fixture = expect File.readAllBytes(videoFixturePath("ffmpeg-mjpeg.mp4").toString())
    var truncatedOutcome: Swag.Error
    discard catch Reader.openMemory("short.mp4", fixture.toSlice()[0 until 96]) as truncatedOutcome
    let truncated = truncatedOutcome.value()
    Swag.require((truncated is InvalidFormatError))

    var unsupported = fixture
    let descriptor  = mp4FindTag(unsupported.toSlice(), "esds")
    var objectType  = descriptor + 4
    while objectType < unsupported.count and unsupported[objectType] != 0x6C do
        objectType += 1
    Swag.require(objectType < unsupported.count)
    unsupported[objectType] = 0x21

    var codecOutcome: Swag.Error
    discard catch Reader.openMemory("h264.mp4", unsupported.toSlice()) as codecOutcome
    let codec = codecOutcome.value()
    Swag.require((codec is UnsupportedFormatError))
}

// A file-backed MP4 exposes its AAC-LC access units as a streamed std/audio track and keeps
// variable presentation timestamps available to an audio-master player.
#test
{
    var reader = expect Reader.open(videoFixturePath("glint-aac-mjpeg.mp4"))
    Swag.require(reader.frameCount() == 10 and reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleEncoding() == .AacLc)
    Swag.require(sound.sampleRateHz() == 44_100 and sound.numChannels() == 2)
    Swag.require(sound.packetCount() >= 18 and not sound.isDataPreloaded())
    Swag.require(Math.isEqualEpsilon(reader.frameTimestamp(5), 0.2, 0.000001))
    Swag.require(reader.frameAtTime(0.219) == 5)
}

// A sample table states presentation durations, and a writer is free to spread them so a track's
// total lands where it wants. What a packet decodes to is the codec's business, so a table stating
// 1023 and 1025 either side of 1024 changes nothing about the sound that comes out of it.
#test
{
    var reader = expect Reader.open(videoFixturePath("glint-aac-drift.mp4"))
    Swag.require(reader.frameCount() == 10 and reader.audioTrackCount() == 1)

    let drifted = unwrap reader.audioTrack(0)
    Swag.require(drifted.sampleEncoding() == .AacLc)
    Swag.require(drifted.sampleRateHz() == 44_100 and drifted.numChannels() == 2)

    var steady = expect Reader.open(videoFixturePath("glint-aac-mjpeg.mp4"))
    let even   = unwrap steady.audioTrack(0)
    Swag.require(drifted.packetCount() == even.packetCount())
    Swag.require(drifted.sampleFrameCount() == even.sampleFrameCount())
}

// A version-zero single edit trims AAC priming and final padding on classic sample-table tracks.
#test
{
    var bytes = expect File.readAllBytes(videoFixturePath("glint-aac-mjpeg.mp4").toString())
    let firstEdit = mp4FindTag(bytes.toSlice(), "elst")
    Swag.require(firstEdit < bytes.count)
    let secondStart = firstEdit + 4
    let secondEdit  = secondStart + mp4FindTag(bytes.toSlice()[secondStart until], "elst")
    Swag.require(secondEdit < bytes.count and bytes[secondEdit + 4] == 0)

    // This fixture's second edit list belongs to its AAC track. Keep version zero, start after
    // one 1024-frame priming packet, and make the audible duration leave less than one packet of
    // padding. The unedited sample table contains 19 AAC packets (19456 frames).
    let raw = cast([*] u8, bytes.storage())
    raw[secondEdit + 12] = 0
    raw[secondEdit + 13] = 0
    raw[secondEdit + 14] = 1
    raw[secondEdit + 15] = 0x90 // 400 movie ticks = 17640 frames at 44.1 kHz / 1 kHz.
    raw[secondEdit + 16] = 0
    raw[secondEdit + 17] = 0
    raw[secondEdit + 18] = 4
    raw[secondEdit + 19] = 0

    let path = videoTempPath("mp4-version-zero-audio-edit", "mp4")
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, bytes.toSlice())
    var reader = expect Reader.open(path)
    Swag.require(reader.audioTrackCount() == 1)
    Swag.require((unwrap reader.audioTrack(0)).sampleFrameCount() == 17_640)
}

// ISO-BMFF MPEG-1/2 Audio tracks use the same packet decoder as Matroska Layer III tracks.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-h264-mp3.mp4"))
    Swag.require(reader.frameCount() == 8 and reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleEncoding() == Audio.SoundFileEncoding.Mp3)
    Swag.require(sound.sampleRateHz() == 48_000 and sound.numChannels() == 1)
    Swag.require(sound.packetCount() == 14 and sound.sampleFrameCount() == 14 * 1_152)
    Swag.require(Math.isEqualEpsilon(sound.timelineStartSeconds(), 0.0, 0.000001))
    Swag.require((expect sound.packet(7)).sampleFrameCount == 1_152)

    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(samples: const [..] s16)->bool
    {
        decoded.add(samples)
        return true
    })
    let wanted = expect File.readAllBytes(videoFixturePath("mp4-layer3-reference.pcm"))
    let wantedAt = cast(const [*] s16, wanted.storage())
    Swag.require(decoded.count == sound.sampleFrameCount() and wanted.count / #sizeof(s16) == decoded.count)
    var energy = 0.0'f64
    for index in decoded.count
    {
        let difference = cast(f64, decoded[index]) - cast(f64, wantedAt[index])
        energy += difference * difference
    }
    let rms = Math.sqrt(energy / cast(f64, decoded.count)) / 32768.0'f64
    Swag.require(rms <= 0.001'f64)
}

// MPEG audio object types may describe Layer I or II frames; reject those through std/audio's
// explicit Layer III-only header validation instead of opening a misleading packet stream.
#test
{
    var bytes = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-mp3.mp4"))
    let media = mp4FindTag(bytes.toSlice(), "mdat")
    var header = media
    while header + 1 < bytes.count and
          (bytes[header] != 0xFF or (bytes[header + 1] & 0xE0) != 0xE0 or (bytes[header + 1] & 0x06) != 0x02) do
        header += 1
    Swag.require(header + 1 < bytes.count)
    bytes[header + 1] = (bytes[header + 1] & 0xF9) | 0x04
    let path = videoTempPath("mp4-mpeg-layer-two", "mp4")
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, bytes.toSlice())
    var errOutcome: Swag.Error
    discard catch Reader.open(path) as errOutcome
    Swag.require(errOutcome.value() is UnsupportedFormatError)
}
