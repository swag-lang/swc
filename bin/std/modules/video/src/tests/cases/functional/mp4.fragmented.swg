#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

func fragmentedTagCount(bytes: const [..] u8, tag: string)->u64
{
    if bytes.count < 4 or tag.count != 4 do
        return 0

    var count = 0'u64
    for offset in bytes.count - 3
    {
        if Memory.compare(bytes.buffer + offset, tag.buffer, 4) == 0 do
            count += 1
    }

    return count
}

func fragmentedConfig()->Array'u8 fail
{
    var source = try ByteSource.openFile(videoFixturePath("ffmpeg-h264-baseline.packets").toString())
    let size   = try source.readBigEndian'u32()
    var config: Array'u8
    config.resize(size)
    try source.readExact(config.toSlice())
    return config
}

func fragmentedPacket(source: *ByteSource)->Array'u8 fail
{
    let size = try source.readBigEndian'u32()
    var result: Array'u8
    result.resize(size)
    try source.readExact(result.toSlice())
    return result
}

func fragmentedPacketSource()->ByteSource fail
{
    var source     = try ByteSource.openFile(videoFixturePath("ffmpeg-h264-baseline.packets").toString())
    let configSize = try source.readBigEndian'u32()
    try source.seek(source.position() + configSize)
    return source
}

// An initialization movie is written before the first packet.
#test
{
    let path = videoTempPath("fragmented-empty", "mp4")
    defer discard catch File.delete(path)

    let config = expect fragmentedConfig()
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice())
    expect writer.end()
    expect writer.end()

    let file = expect File.readAllBytes(path)
    let raw  = file.toSlice()
    Swag.require(raw[4] == 'f' and raw[5] == 't' and raw[6] == 'y' and raw[7] == 'p')
    Swag.require(fragmentedTagCount(raw, "moov") == 1)
    Swag.require(fragmentedTagCount(raw, "mvex") == 1)
    Swag.require(fragmentedTagCount(raw, "avcC") == 1)
    Swag.require(fragmentedTagCount(raw, "moof") == 0)
}

// Invalid AVC configuration is rejected before the destination is opened.
#test
{
    let path = videoTempPath("fragmented-invalid-config", "mp4")
    defer discard catch File.delete(path)

    var config = expect fragmentedConfig()
    config[5] = 0xE0
    var invalidConfig: Swag.Error
    discard catch Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice()) as invalidConfig
    Swag.require((invalidConfig.value() is InvalidFormatError))
}

// A fragmented writer accepts encoded AVC packets without accumulating the stream in memory.
#test
{
    let path = videoTempPath("fragmented-avc", "mp4")
    defer discard catch File.delete(path)

    var source     = expect ByteSource.openFile(videoFixturePath("ffmpeg-h264-baseline.packets").toString())
    let configSize = expect source.readBigEndian'u32()
    var config: Array'u8
    config.resize(configSize)
    expect source.readExact(config.toSlice())

    var writer = expect Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice())
    for index in 3
    {
        let packetSize = expect source.readBigEndian'u32()
        var bytes: Array'u8
        bytes.resize(packetSize)
        expect source.readExact(bytes.toSlice())
        expect writer.addPacket(EncodedPacket{bytes.toSlice(), cast(u64, index) * 512,
                                              cast(u64, index) * 512, 512, index == 0})
    }

    expect writer.end()
    expect writer.end()

    let file = expect File.readAllBytes(path)
    let raw  = file.toSlice()
    Swag.require(raw[4] == 'f' and raw[5] == 't' and raw[6] == 'y' and raw[7] == 'p')
    Swag.require(fragmentedTagCount(raw, "moov") == 1)
    Swag.require(fragmentedTagCount(raw, "mvex") == 1)
    Swag.require(fragmentedTagCount(raw, "avcC") == 1)
    Swag.require(fragmentedTagCount(raw, "moof") == 3)
    Swag.require(fragmentedTagCount(raw, "mdat") == 3)

    var reader = expect Reader.open(path)
    Swag.require(reader.width() == 64 and reader.height() == 48)
    Swag.require(reader.frameCount() == 3)
    Swag.require(reader.frameRate() == expect FrameRate.create(12_800, 512))
    Swag.require(Math.isEqualEpsilon(reader.frameTimestamp(2), 0.08, 0.000001))

    var original = expect Reader.open(videoFixturePath("ffmpeg-h264-baseline.mp4"))
    const Order: [3] u64 = [2, 0, 1]
    for index in Order
    {
        let actual   = expect reader.decodeFrame(index)
        let expected = expect original.decodeFrame(index)
        Swag.require(actual.pixelFormat == expected.pixelFormat and actual.byteCount == expected.byteCount)
        Swag.require(Memory.compare(actual.pixels.storage(), expected.pixels.storage(), actual.byteCount) == 0)
    }

    var lastFragment = raw.count
    for offset in raw.count - 3 where Memory.compare(raw.buffer + offset, "moof".buffer, 4) == 0 do
        lastFragment = offset - 4
    Swag.require(lastFragment < raw.count)

    // Every incomplete prefix of the final fragment leaves the preceding two frames playable.
    let expected = expect original.decodeFrame(1)
    for cut in lastFragment to raw.count - 1
    {
        var prefix = expect Reader.openMemory("stopped.mp4", raw[0 until cut])
        Swag.require(prefix.frameCount() == 2)
        let recovered = expect prefix.decodeFrame(1)
        Swag.require(recovered.byteCount == expected.byteCount)
        Swag.require(Memory.compare(recovered.pixels.storage(), expected.pixels.storage(), recovered.byteCount) == 0)
    }
}

// Rejected packets do not advance the sequence or leave a partial fragment.
#test
{
    let path = videoTempPath("fragmented-invalid-packet", "mp4")
    defer discard catch File.delete(path)

    var source     = expect ByteSource.openFile(videoFixturePath("ffmpeg-h264-baseline.packets").toString())
    let configSize = expect source.readBigEndian'u32()
    var config: Array'u8
    config.resize(configSize)
    expect source.readExact(config.toSlice())

    let packetSize = expect source.readBigEndian'u32()
    var bytes: Array'u8
    bytes.resize(packetSize)
    expect source.readExact(bytes.toSlice())

    var writer = expect Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice())
    var rejected: Swag.Error
    discard catch writer.addPacket(EncodedPacket{bytes.toSlice(), 0, 0, 512, false}) as rejected
    Swag.require((rejected.value() is BadParameterError))

    let malformed: [5] u8 = [0, 0, 0, 3, 0x65]
    discard catch writer.addPacket(EncodedPacket{Swag.makeSlice(&malformed[0], malformed.count),
                                                 0, 0, 512, true}) as rejected
    Swag.require((rejected.value() is InvalidFormatError))

    expect writer.addPacket(EncodedPacket{bytes.toSlice(), 0, 0, 512, true})
    discard catch writer.addPacket(EncodedPacket{bytes.toSlice(), 0, 0, 512, true}) as rejected
    Swag.require((rejected.value() is BadParameterError))
    expect writer.end()

    let file = expect File.readAllBytes(path)
    Swag.require(fragmentedTagCount(file.toSlice(), "moof") == 1)
    Swag.require(fragmentedTagCount(file.toSlice(), "mdat") == 1)
}

// Fragment decode times and signed composition offsets retain exact presentation order.
#test
{
    let path = videoTempPath("fragmented-presentation", "mp4")
    defer discard catch File.delete(path)

    var source     = expect ByteSource.openFile(videoFixturePath("ffmpeg-h264-baseline.packets").toString())
    let configSize = expect source.readBigEndian'u32()
    var config: Array'u8
    config.resize(configSize)
    expect source.readExact(config.toSlice())

    var writer = expect Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice())
    const Decode:  [3] u64 = [1_000, 1_512, 2_024]
    const Present: [3] u64 = [1_000, 2_024, 1_512]
    for index in 3
    {
        let size = expect source.readBigEndian'u32()
        var packet: Array'u8
        packet.resize(size)
        expect source.readExact(packet.toSlice())
        expect writer.addPacket(EncodedPacket{packet.toSlice(), Decode[index], Present[index], 512, index == 0})
    }

    expect writer.end()

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 3)
    Swag.require(Math.isEqualEpsilon(reader.frameTimestamp(0), 0.0, 0.000001))
    Swag.require(Math.isEqualEpsilon(reader.frameTimestamp(1), 0.04, 0.000001))
    Swag.require(Math.isEqualEpsilon(reader.frameTimestamp(2), 0.08, 0.000001))

    var packets = expect Mp4.FragmentedPacketReader.open(path)
    Swag.require(packets.width() == 64 and packets.height() == 48)
    Swag.require(packets.timescale() == 12_800 and packets.packetCount() == 3)
    Swag.require(Memory.compare(packets.avcConfig().buffer, config.storage(), config.count) == 0)
    var original = expect fragmentedPacketSource()
    var bytes: Array'u8
    for index in 3
    {
        let packet   = expect packets.readPacket(index, &bytes)
        let expected = expect fragmentedPacket(&original)
        Swag.require(packet.decodeTime == Decode[index] and packet.presentationTime == Present[index])
        Swag.require(packet.duration == 512 and packet.isKeyFrame == (index == 0))
        Swag.require(packet.bytes.count == expected.count)
        Swag.require(Memory.compare(packet.bytes.buffer, expected.storage(), expected.count) == 0)
    }

    var rejected: Swag.Error
    discard catch packets.readPacket(3, &bytes) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch packets.audioTrack(0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch packets.readAudioPacket(0, 0, &bytes) as rejected
    Swag.require(rejected.value() is BadParameterError)
}

// The packet reader reports its fragmented-H.264 scope for a classic Motion JPEG MP4.
#test
{
    var rejected: Swag.Error
    discard catch Mp4.FragmentedPacketReader.open(videoFixturePath("ffmpeg-mjpeg.mp4")) as rejected
    Swag.require(rejected.value() is UnsupportedFormatError)
}

// A fragment with an offset outside its media-data box or an incomplete tail is rejected.
#test
{
    let path = videoTempPath("fragmented-broken", "mp4")
    defer discard catch File.delete(path)

    var source     = expect ByteSource.openFile(videoFixturePath("ffmpeg-h264-baseline.packets").toString())
    let configSize = expect source.readBigEndian'u32()
    var config: Array'u8
    config.resize(configSize)
    expect source.readExact(config.toSlice())
    let packetSize = expect source.readBigEndian'u32()
    var packet: Array'u8
    packet.resize(packetSize)
    expect source.readExact(packet.toSlice())

    var writer = expect Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice())
    expect writer.addPacket(EncodedPacket{packet.toSlice(), 0, 0, 512, true})
    expect writer.end()

    var bytes = expect File.readAllBytes(path)
    var truncated: Swag.Error
    discard catch Reader.openMemory("truncated.mp4", bytes.toSlice()[0 until bytes.count - 1]) as truncated
    Swag.require((truncated.value() is InvalidFormatError))

    var run = bytes.count
    for offset in bytes.count - 3 where Memory.compare(bytes.storage() + offset, "trun".buffer, 4) == 0
    {
        run = offset
        break
    }

    Swag.require(run < bytes.count)
    for i in 4 do
        bytes[run + 12 + i] = 0
    var badOffset: Swag.Error
    discard catch Reader.openMemory("bad-offset.mp4", bytes.toSlice()) as badOffset
    Swag.require((badOffset.value() is InvalidFormatError))
}

// Three packets share one bounded fragment and retain independently seekable frame times.
#test
{
    let path = videoTempPath("fragmented-grouped", "mp4")
    defer discard catch File.delete(path)

    let config = expect fragmentedConfig()
    var source = expect fragmentedPacketSource()
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice(), Mp4.FragmentedOptions{3, 4 * 1024 * 1024})
    for index in 3
    {
        let packet = expect fragmentedPacket(&source)
        expect writer.addPacket(EncodedPacket{packet.toSlice(), cast(u64, index) * 512,
                                              cast(u64, index) * 512, 512, index == 0})
    }

    expect writer.end()

    let file = expect File.readAllBytes(path)
    Swag.require(fragmentedTagCount(file.toSlice(), "moof") == 1)
    Swag.require(fragmentedTagCount(file.toSlice(), "mdat") == 1)

    var reader   = expect Reader.open(path)
    var original = expect Reader.open(videoFixturePath("ffmpeg-h264-baseline.mp4"))
    Swag.require(reader.frameCount() == 3)
    const Order: [3] u64 = [2, 0, 1]
    for index in Order
    {
        Swag.require(Math.isEqualEpsilon(reader.frameTimestamp(index), cast(f64, index) * 0.04, 0.000001))
        let actual   = expect reader.decodeFrame(index)
        let expected = expect original.decodeFrame(index)
        Swag.require(actual.byteCount == expected.byteCount)
        Swag.require(Memory.compare(actual.pixels.storage(), expected.pixels.storage(), actual.byteCount) == 0)
    }
}

// Explicit flushing keeps earlier frames playable when the following group is interrupted.
#test
{
    let path = videoTempPath("fragmented-grouped-flush", "mp4")
    defer discard catch File.delete(path)

    let config = expect fragmentedConfig()
    var source = expect fragmentedPacketSource()
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice(), Mp4.FragmentedOptions{3, 4 * 1024 * 1024})
    for index in 3
    {
        let packet = expect fragmentedPacket(&source)
        expect writer.addPacket(EncodedPacket{packet.toSlice(), cast(u64, index) * 512,
                                              cast(u64, index) * 512, 512, index == 0})
        if index == 0 do
            expect writer.flush()
    }

    expect writer.end()

    let file = expect File.readAllBytes(path)
    let raw  = file.toSlice()
    Swag.require(fragmentedTagCount(raw, "moof") == 2)
    Swag.require(fragmentedTagCount(raw, "mdat") == 2)

    var secondFragment = raw.count
    var found = false
    for offset in raw.count - 3 where Memory.compare(raw.buffer + offset, "moof".buffer, 4) == 0
    {
        if found
        {
            secondFragment = offset - 4
            break
        }

        found = true
    }

    Swag.require(secondFragment < raw.count)

    var original = expect Reader.open(videoFixturePath("ffmpeg-h264-baseline.mp4"))
    let expected = expect original.decodeFrame(0)
    for cut in secondFragment to raw.count - 1
    {
        var reader = expect Reader.openMemory("stopped-group.mp4", raw[0 until cut])
        Swag.require(reader.frameCount() == 1)
        let actual = expect reader.decodeFrame(0)
        Swag.require(actual.byteCount == expected.byteCount)
        Swag.require(Memory.compare(actual.pixels.storage(), expected.pixels.storage(), actual.byteCount) == 0)
    }
}

// The byte bound emits a complete fragment before the packet-count bound is reached.
#test
{
    let path = videoTempPath("fragmented-byte-bound", "mp4")
    defer discard catch File.delete(path)

    let config = expect fragmentedConfig()
    var source = expect fragmentedPacketSource()
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice(), Mp4.FragmentedOptions{3, 1_500})
    for index in 3
    {
        let packet = expect fragmentedPacket(&source)
        expect writer.addPacket(EncodedPacket{packet.toSlice(), cast(u64, index) * 512,
                                              cast(u64, index) * 512, 512, index == 0})
    }

    expect writer.end()
    let file = expect File.readAllBytes(path)
    Swag.require(fragmentedTagCount(file.toSlice(), "moof") == 2)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 3)
}

// Invalid grouping limits are rejected before opening the destination.
#test
{
    let path = videoTempPath("fragmented-invalid-limits", "mp4")
    defer discard catch File.delete(path)
    let config = expect fragmentedConfig()
    var rejected: Swag.Error
    discard catch Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice(), Mp4.FragmentedOptions{0, 100}) as rejected
    Swag.require((rejected.value() is BadParameterError))
    discard catch Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice(), Mp4.FragmentedOptions{1_025, 100}) as rejected
    Swag.require((rejected.value() is BadParameterError))
    discard catch Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice(), Mp4.FragmentedOptions{3, 0}) as rejected
    Swag.require((rejected.value() is BadParameterError))
    discard catch Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice(), Mp4.FragmentedOptions{3, 100, 0}) as rejected
    Swag.require((rejected.value() is BadParameterError))
    discard catch Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice(), Mp4.FragmentedOptions{3, 100, 1_025}) as rejected
    Swag.require((rejected.value() is BadParameterError))
}

// Video and AAC packets interleave in separate fragments and both tracks remain readable.
#test
{
    let path = videoTempPath("fragmented-aac", "mp4")
    defer discard catch File.delete(path)

    let config = expect fragmentedConfig()
    const AudioConfig: [2] u8 = [0x12, 0x10]
    var video  = expect fragmentedPacketSource()
    var audio  = expect ByteSource.openFile(videoFixturePath("glint-aac-lc-stereo.packets").toString())
    var writer = expect Mp4.FragmentedWriter.createWithAudio(path,
                                                             64,
                                                             48,
                                                             12_800,
                                                             config.toSlice(),
                                                             Mp4.FragmentedAudioConfig{44_100, 2,
                                                                                       Swag.makeSlice(&AudioConfig[0], 2)},
                                                             Mp4.FragmentedOptions{3, 4 * 1024 * 1024})
    for index in 3
    {
        let picture = expect fragmentedPacket(&video)
        expect writer.addPacket(EncodedPacket{picture.toSlice(), cast(u64, index) * 512,
                                              cast(u64, index) * 512, 512, index == 0})
        let sound = expect fragmentedPacket(&audio)
        expect writer.addAudioPacket(EncodedPacket{sound.toSlice(), cast(u64, index) * 1024,
                                                   cast(u64, index) * 1024, 1024, true})
    }

    expect writer.end()

    let file = expect File.readAllBytes(path)
    Swag.require(fragmentedTagCount(file.toSlice(), "moof") == 6)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 3 and reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleEncoding() == .AacLc)
    Swag.require(sound.sampleRateHz() == 44_100 and sound.numChannels() == 2)
    Swag.require(sound.packetCount() == 3 and sound.sampleFrameCount() == 3 * 1024)
    Swag.require(Math.isEqualEpsilon(sound.timelineStartSeconds(), 0.0, 0.000001))

    var source   = expect ByteSource.openFile(path)
    var expected = expect ByteSource.openFile(videoFixturePath("glint-aac-lc-stereo.packets").toString())
    for index in 3
    {
        let bytes  = expect fragmentedPacket(&expected)
        let packet = expect sound.packet(index)
        Swag.require(packet.byteSize == bytes.count and packet.sampleFrameCount == 1024)
        expect source.seek(packet.sourceOffset)
        var actual: Array'u8
        actual.resize(packet.byteSize)
        expect source.readExact(actual.toSlice())
        Swag.require(Memory.compare(actual.storage(), bytes.storage(), bytes.count) == 0)
    }

    let cutPath = videoTempPath("fragmented-aac-cut", "mp4")
    defer discard catch File.delete(cutPath)
    var lastFragment = file.count
    for offset in file.count - 3 where Memory.compare(file.storage() + offset, "moof".buffer, 4) == 0 do
        lastFragment = offset - 4
    Swag.require(lastFragment < file.count)
    const CutOffsets: [3] u64 = [4, 20, 1]
    for offset in CutOffsets
    {
        let cut = offset == 1 ? file.count - 1 : lastFragment + offset
        discard expect File.writeAllBytes(cutPath, file.toSlice()[0 until cut])
        var recovered = expect Reader.open(cutPath)
        Swag.require(recovered.frameCount() == 3 and recovered.audioTrackCount() == 1)
        Swag.require((unwrap recovered.audioTrack(0)).packetCount() == 2)
    }
}

// AAC configuration and packet timing errors do not produce a partial media fragment.
#test
{
    let path = videoTempPath("fragmented-aac-rejected", "mp4")
    defer discard catch File.delete(path)
    let config = expect fragmentedConfig()
    const AudioConfig: [2] u8 = [0x12, 0x10]
    var rejected: Swag.Error
    discard catch Mp4.FragmentedWriter.createWithAudio(path,
                                                       64,
                                                       48,
                                                       12_800,
                                                       config.toSlice(),
                                                       Mp4.FragmentedAudioConfig{48_000, 2,
                                                                                 Swag.makeSlice(&AudioConfig[0], 2)}) as rejected
    Swag.require((rejected.value() is BadParameterError))

    var writer = expect Mp4.FragmentedWriter.createWithAudio(path,
                                                             64,
                                                             48,
                                                             12_800,
                                                             config.toSlice(),
                                                             Mp4.FragmentedAudioConfig{44_100, 2,
                                                                                       Swag.makeSlice(&AudioConfig[0], 2)})
    var source = expect ByteSource.openFile(videoFixturePath("glint-aac-lc-stereo.packets").toString())
    let sound  = expect fragmentedPacket(&source)
    discard catch writer.addAudioPacket(EncodedPacket{sound.toSlice(), 0, 0, 1023, true}) as rejected
    Swag.require((rejected.value() is BadParameterError))
    expect writer.addAudioPacket(EncodedPacket{sound.toSlice(), 0, 0, 1024, true})
    discard catch writer.addAudioPacket(EncodedPacket{sound.toSlice(), 2048, 2048, 1024, true}) as rejected
    Swag.require((rejected.value() is BadParameterError))
    expect writer.end()
    let file = expect File.readAllBytes(path)
    Swag.require(fragmentedTagCount(file.toSlice(), "moof") == 1)
}

// Sound recorded before the first picture is trimmed to the video's presentation origin.
#test
{
    let path = videoTempPath("fragmented-aac-lead", "mp4")
    defer discard catch File.delete(path)
    let config = expect fragmentedConfig()
    const AudioConfig: [2] u8 = [0x12, 0x10]
    var writer = expect Mp4.FragmentedWriter.createWithAudio(path,
                                                             64,
                                                             48,
                                                             12_800,
                                                             config.toSlice(),
                                                             Mp4.FragmentedAudioConfig{44_100, 2,
                                                                                       Swag.makeSlice(&AudioConfig[0], 2)})
    var video   = expect fragmentedPacketSource()
    let picture = expect fragmentedPacket(&video)
    expect writer.addPacket(EncodedPacket{picture.toSlice(), 512, 512, 512, true})
    var audio = expect ByteSource.openFile(videoFixturePath("glint-aac-lc-stereo.packets").toString())
    for index in 3
    {
        let sound = expect fragmentedPacket(&audio)
        expect writer.addAudioPacket(EncodedPacket{sound.toSlice(), cast(u64, index) * 1024,
                                                   cast(u64, index) * 1024, 1024, true})
    }

    expect writer.end()

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 1 and reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.packetCount() == 3 and sound.sampleFrameCount() == 3 * 1024 - 1_764)
    Swag.require(Math.isEqualEpsilon(sound.timelineStartSeconds(), 0.0, 0.000001))
}

// Two AAC tracks keep separate packet indices and presentation origins.
#test
{
    let path = videoTempPath("fragmented-two-aac", "mp4")
    defer discard catch File.delete(path)
    let config = expect fragmentedConfig()
    const AudioConfig: [2] u8 = [0x12, 0x10]
    let Tracks: [2] Mp4.FragmentedAudioConfig = [
        {44_100, 2, Swag.makeSlice(&AudioConfig[0], 2)},
        {44_100, 2, Swag.makeSlice(&AudioConfig[0], 2)}]
    var tooMany: Array'Mp4.FragmentedAudioConfig
    for 5 do
        tooMany.add(Tracks[0])
    var rejected: Swag.Error
    discard catch Mp4.FragmentedWriter.createWithAudioTracks(path, 64, 48, 12_800, config.toSlice(), tooMany.toSlice()) as rejected
    Swag.require((rejected.value() is BadParameterError))
    var writer = expect Mp4.FragmentedWriter.createWithAudioTracks(path, 64, 48, 12_800, config.toSlice(), Swag.makeSlice(&Tracks[0], 2))
    var video  = expect fragmentedPacketSource()
    var audio  = expect ByteSource.openFile(videoFixturePath("glint-aac-lc-stereo.packets").toString())
    for index in 3
    {
        let picture = expect fragmentedPacket(&video)
        expect writer.addPacket(EncodedPacket{picture.toSlice(), cast(u64, index) * 512,
                                              cast(u64, index) * 512, 512, index == 0})
        let sound = expect fragmentedPacket(&audio)
        expect writer.addAudioPacket(EncodedPacket{sound.toSlice(), cast(u64, index) * 1024,
                                                   cast(u64, index) * 1024, 1024, true},
                                     0)
        if index < 2 do
            expect writer.addAudioPacket(EncodedPacket{sound.toSlice(), cast(u64, index + 1) * 1024,
                                                       cast(u64, index + 1) * 1024, 1024, true},
                                         1)
    }

    const Empty: [1] u8 = [0]
    discard catch writer.addAudioPacket(EncodedPacket{Swag.makeSlice(&Empty[0], 1), 0, 0, 1024, true}, 2) as rejected
    Swag.require((rejected.value() is BadParameterError))
    expect writer.end()

    let file = expect File.readAllBytes(path)
    Swag.require(fragmentedTagCount(file.toSlice(), "moof") == 8)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 3 and reader.audioTrackCount() == 2)
    let first  = unwrap reader.audioTrack(0)
    let second = unwrap reader.audioTrack(1)
    Swag.require(first.packetCount() == 3 and second.packetCount() == 2)
    Swag.require(first.sampleFrameCount() == 3 * 1024 and second.sampleFrameCount() == 2 * 1024)
    Swag.require(Math.isEqualEpsilon(first.timelineStartSeconds(), 0.0, 0.000001))
    Swag.require(Math.isEqualEpsilon(second.timelineStartSeconds(), 1024.0 / 44_100.0, 0.000001))
    Swag.require((expect first.packet(0)).sourceOffset != (expect second.packet(0)).sourceOffset)
}

// Interleaved submissions form bounded video and AAC groups without losing either timeline.
#test
{
    let path = videoTempPath("fragmented-grouped-aac", "mp4")
    defer discard catch File.delete(path)
    let config = expect fragmentedConfig()
    const AudioConfig: [2] u8 = [0x12, 0x10]
    var writer = expect Mp4.FragmentedWriter.createWithAudio(path,
                                                             64,
                                                             48,
                                                             12_800,
                                                             config.toSlice(),
                                                             Mp4.FragmentedAudioConfig{44_100, 2,
                                                                                       Swag.makeSlice(&AudioConfig[0], 2)},
                                                             Mp4.FragmentedOptions{3, 4 * 1024 * 1024, 3})
    var video = expect fragmentedPacketSource()
    var audio = expect ByteSource.openFile(videoFixturePath("glint-aac-lc-stereo.packets").toString())
    for index in 3
    {
        let picture = expect fragmentedPacket(&video)
        expect writer.addPacket(EncodedPacket{picture.toSlice(), cast(u64, index) * 512,
                                              cast(u64, index) * 512, 512, index == 0})
        let sound = expect fragmentedPacket(&audio)
        expect writer.addAudioPacket(EncodedPacket{sound.toSlice(), cast(u64, index) * 1024,
                                                   cast(u64, index) * 1024, 1024, true})
    }

    expect writer.end()

    let file = expect File.readAllBytes(path)
    Swag.require(fragmentedTagCount(file.toSlice(), "moof") == 2)
    Swag.require(fragmentedTagCount(file.toSlice(), "mdat") == 2)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 3 and reader.audioTrackCount() == 1)
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.packetCount() == 3 and sound.sampleFrameCount() == 3 * 1024)
}

// Explicit flush completes partial groups for both tracks; a later group remains readable.
#test
{
    let path = videoTempPath("fragmented-grouped-aac-flush", "mp4")
    defer discard catch File.delete(path)
    let config = expect fragmentedConfig()
    const AudioConfig: [2] u8 = [0x12, 0x10]
    var writer = expect Mp4.FragmentedWriter.createWithAudio(path,
                                                             64,
                                                             48,
                                                             12_800,
                                                             config.toSlice(),
                                                             Mp4.FragmentedAudioConfig{44_100, 2,
                                                                                       Swag.makeSlice(&AudioConfig[0], 2)},
                                                             Mp4.FragmentedOptions{3, 4 * 1024 * 1024, 3})
    var video = expect fragmentedPacketSource()
    var audio = expect ByteSource.openFile(videoFixturePath("glint-aac-lc-stereo.packets").toString())
    for index in 3
    {
        let picture = expect fragmentedPacket(&video)
        expect writer.addPacket(EncodedPacket{picture.toSlice(), cast(u64, index) * 512,
                                              cast(u64, index) * 512, 512, index == 0})
        let sound = expect fragmentedPacket(&audio)
        expect writer.addAudioPacket(EncodedPacket{sound.toSlice(), cast(u64, index) * 1024,
                                                   cast(u64, index) * 1024, 1024, true})
        if index == 0 do
            expect writer.flush()
    }

    expect writer.end()

    let file = expect File.readAllBytes(path)
    Swag.require(fragmentedTagCount(file.toSlice(), "moof") == 4)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 3 and (unwrap reader.audioTrack(0)).packetCount() == 3)
}

// Each AAC track forms its own group, including a partial final group.
#test
{
    let path = videoTempPath("fragmented-grouped-two-aac", "mp4")
    defer discard catch File.delete(path)
    let config = expect fragmentedConfig()
    const AudioConfig: [2] u8 = [0x12, 0x10]
    let tracks: [2] Mp4.FragmentedAudioConfig = [
        {44_100, 2, Swag.makeSlice(&AudioConfig[0], 2)},
        {44_100, 2, Swag.makeSlice(&AudioConfig[0], 2)}]
    var writer = expect Mp4.FragmentedWriter.createWithAudioTracks(path, 64, 48, 12_800, config.toSlice(), Swag.makeSlice(&tracks[0], 2), Mp4.FragmentedOptions{3, 4 * 1024 * 1024, 3})
    var video  = expect fragmentedPacketSource()
    var audio  = expect ByteSource.openFile(videoFixturePath("glint-aac-lc-stereo.packets").toString())
    for index in 3
    {
        let picture = expect fragmentedPacket(&video)
        expect writer.addPacket(EncodedPacket{picture.toSlice(), cast(u64, index) * 512,
                                              cast(u64, index) * 512, 512, index == 0})
        let sound = expect fragmentedPacket(&audio)
        expect writer.addAudioPacket(EncodedPacket{sound.toSlice(), cast(u64, index) * 1024,
                                                   cast(u64, index) * 1024, 1024, true},
                                     0)
        if index < 2 do
            expect writer.addAudioPacket(EncodedPacket{sound.toSlice(), cast(u64, index + 1) * 1024,
                                                       cast(u64, index + 1) * 1024, 1024, true},
                                         1)
    }

    expect writer.end()

    let file = expect File.readAllBytes(path)
    Swag.require(fragmentedTagCount(file.toSlice(), "moof") == 3)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 3 and reader.audioTrackCount() == 2)
    Swag.require((unwrap reader.audioTrack(0)).packetCount() == 3)
    Swag.require((unwrap reader.audioTrack(1)).packetCount() == 2)

    var packets = expect Mp4.FragmentedPacketReader.open(path)
    Swag.require(packets.packetCount() == 3 and packets.audioTrackCount() == 2)
    let firstAudio  = expect packets.audioTrack(0)
    let secondAudio = expect packets.audioTrack(1)
    Swag.require(firstAudio.packetCount == 3 and secondAudio.packetCount == 2)
    Swag.require(firstAudio.sampleRate == 44_100 and firstAudio.channelCount == 2)
    let copiedTracks: [2] Mp4.FragmentedAudioConfig = [
        {firstAudio.sampleRate,  firstAudio.channelCount,  firstAudio.decoderConfig},
        {secondAudio.sampleRate, secondAudio.channelCount, secondAudio.decoderConfig}]
    let copyPath = videoTempPath("fragmented-remux-two-aac", "mp4")
    defer discard catch File.delete(copyPath)
    var remux = expect Mp4.FragmentedWriter.createWithAudioTracks(copyPath,
                                                                  packets.width(),
                                                                  packets.height(),
                                                                  packets.timescale(),
                                                                  packets.avcConfig(),
                                                                  Swag.makeSlice(&copiedTracks[0], 2),
                                                                  Mp4.FragmentedOptions{3, 4 * 1024 * 1024, 3})
    var payload: Array'u8
    for index in 3
    {
        let picture = expect packets.readPacket(index, &payload)
        expect remux.addPacket(picture)
        for audioIndex in 2 where index < (audioIndex == 0 ? firstAudio.packetCount : secondAudio.packetCount)
        {
            let sound = expect packets.readAudioPacket(audioIndex, index, &payload)
            expect remux.addAudioPacket(sound, cast(u32, audioIndex))
        }
    }

    expect remux.end()

    var copied = expect Mp4.FragmentedPacketReader.open(copyPath)
    Swag.require(copied.packetCount() == 3 and copied.audioTrackCount() == 2)
    var originalBytes: Array'u8
    var copiedBytes:   Array'u8
    for index in 3
    {
        let originalPacket = expect packets.readPacket(index, &originalBytes)
        let copiedPacket   = expect copied.readPacket(index, &copiedBytes)
        Swag.require(originalPacket.decodeTime == copiedPacket.decodeTime and
                     originalPacket.presentationTime == copiedPacket.presentationTime and
                     originalPacket.bytes.count == copiedPacket.bytes.count)
        Swag.require(Memory.compare(originalPacket.bytes.buffer, copiedPacket.bytes.buffer, originalPacket.bytes.count) == 0)
    }

    for audioIndex in 2
    {
        let sourceTrack = expect packets.audioTrack(audioIndex)
        let copiedTrack = expect copied.audioTrack(audioIndex)
        Swag.require(sourceTrack.packetCount == copiedTrack.packetCount)
        for index in sourceTrack.packetCount
        {
            let originalPacket = expect packets.readAudioPacket(audioIndex, index, &originalBytes)
            let copiedPacket   = expect copied.readAudioPacket(audioIndex, index, &copiedBytes)
            Swag.require(originalPacket.decodeTime == copiedPacket.decodeTime and
                         originalPacket.bytes.count == copiedPacket.bytes.count)
            Swag.require(Memory.compare(originalPacket.bytes.buffer, copiedPacket.bytes.buffer, originalPacket.bytes.count) == 0)
        }
    }
}

// The byte bound completes an AAC group before its next packet would exceed the limit.
#test
{
    let path = videoTempPath("fragmented-grouped-aac-bytes", "mp4")
    defer discard catch File.delete(path)
    let config = expect fragmentedConfig()
    const AudioConfig: [2] u8 = [0x12, 0x10]
    var writer = expect Mp4.FragmentedWriter.createWithAudio(path,
                                                             64,
                                                             48,
                                                             12_800,
                                                             config.toSlice(),
                                                             Mp4.FragmentedAudioConfig{44_100, 2,
                                                                                       Swag.makeSlice(&AudioConfig[0], 2)},
                                                             Mp4.FragmentedOptions{3, 360, 3})
    var video   = expect fragmentedPacketSource()
    let picture = expect fragmentedPacket(&video)
    expect writer.addPacket(EncodedPacket{picture.toSlice(), 0, 0, 512, true})
    var audio = expect ByteSource.openFile(videoFixturePath("glint-aac-lc-stereo.packets").toString())
    for index in 3
    {
        let sound = expect fragmentedPacket(&audio)
        expect writer.addAudioPacket(EncodedPacket{sound.toSlice(), cast(u64, index) * 1024,
                                                   cast(u64, index) * 1024, 1024, true})
    }

    expect writer.end()

    let file = expect File.readAllBytes(path)
    Swag.require(fragmentedTagCount(file.toSlice(), "moof") == 3)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 1 and (unwrap reader.audioTrack(0)).packetCount() == 3)
}

// A completed file can append a 64-bit index pointing to each video key-frame fragment.
#test
{
    let path = videoTempPath("fragmented-indexed", "mp4")
    defer discard catch File.delete(path)
    let config = expect fragmentedConfig()
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 48, 12_800, config.toSlice(), Mp4.FragmentedOptions{3, 4 * 1024 * 1024, 1, true})
    var video  = expect fragmentedPacketSource()
    let first  = expect fragmentedPacket(&video)
    expect writer.addPacket(EncodedPacket{first.toSlice(), 512, 512, 512, true})
    let second = expect fragmentedPacket(&video)
    expect writer.addPacket(EncodedPacket{second.toSlice(), 1024, 1024, 512, false})
    expect writer.addPacket(EncodedPacket{first.toSlice(), 1536, 1536, 512, true})
    expect writer.end()

    let file = expect File.readAllBytes(path)
    let raw  = file.toSlice()
    Swag.require(fragmentedTagCount(raw, "moof") == 2)
    Swag.require(fragmentedTagCount(raw, "mfra") == 1 and fragmentedTagCount(raw, "tfra") == 1)
    Swag.require(fragmentedTagCount(raw, "mfro") == 1)
    var moofOffsets: [2] u64
    var moofIndex  = 0
    var tfraOffset = raw.count
    var mfraOffset = raw.count
    for offset in raw.count - 3
    {
        if Memory.compare(raw.buffer + offset, "moof".buffer, 4) == 0
        {
            moofOffsets[moofIndex] = offset - 4
            moofIndex += 1
        }

        if Memory.compare(raw.buffer + offset, "tfra".buffer, 4) == 0 do
            tfraOffset = offset - 4
        if Memory.compare(raw.buffer + offset, "mfra".buffer, 4) == 0 do
            mfraOffset = offset - 4
    }

    Swag.require(moofIndex == 2 and tfraOffset < raw.count and mfraOffset < raw.count)
    var source = ByteSource.openMemory(raw)
    expect source.seek(tfraOffset)
    Swag.require(expect source.readBigEndian'u32() == 64)
    expect source.skip(4)
    Swag.require(expect source.readBigEndian'u32() == 0x01000000)
    Swag.require(expect source.readBigEndian'u32() == 1)
    Swag.require(expect source.readBigEndian'u32() == 1)
    Swag.require(expect source.readBigEndian'u32() == 2)
    for index in 2
    {
        Swag.require(expect source.readBigEndian'u64() == cast(u64, index) * 1024 + 512)
        Swag.require(expect source.readBigEndian'u64() == moofOffsets[index])
        Swag.require(expect source.readBigEndian'u8() == 1)
        Swag.require(expect source.readBigEndian'u8() == 1)
        Swag.require(expect source.readBigEndian'u16() == 1)
    }

    expect source.seek(raw.count - 4)
    Swag.require(expect source.readBigEndian'u32() == raw.count - mfraOffset)

    var index = expect Mp4.FragmentedIndex.open(path)
    Swag.require(index.entryCount() == 2)
    var rejected: Swag.Error
    discard catch Mp4.FragmentedIndex.open(path, 0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch Mp4.FragmentedIndex.open(path, 2) as rejected
    Swag.require(rejected.value() is UnsupportedFormatError)
    let firstPoint = expect index.point(0)
    let lastPoint  = expect index.point(1)
    Swag.require(firstPoint.decodeTime == 512 and firstPoint.moofOffset == moofOffsets[0])
    Swag.require(lastPoint.decodeTime == 1536 and lastPoint.moofOffset == moofOffsets[1])
    var found: Mp4.FragmentedSeekPoint
    Swag.require(not expect index.tryFindAtOrBefore(511, &found))
    Swag.require(expect index.tryFindAtOrBefore(1535, &found))
    Swag.require(found.decodeTime == 512 and found.sampleNumber == 1)
    Swag.require(expect index.tryFindAtOrBefore(1536, &found))
    Swag.require(found.decodeTime == 1536 and found.moofOffset == moofOffsets[1])
    Swag.require(expect index.tryFindAtOrBefore(Swag.U64.Max, &found))
    Swag.require(found.decodeTime == 1536)
    index.close()

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 3)
    let frame = expect reader.decodeFrame(2)
    Swag.require(frame.width == 64 and frame.height == 48)
    for cut in mfraOffset to raw.count - 1
    {
        var recovered = expect Reader.openMemory("indexed-cut.mp4", raw[0 until cut])
        Swag.require(recovered.frameCount() == 3)
    }

    let cutPath = videoTempPath("fragmented-index-missing", "mp4")
    defer discard catch File.delete(cutPath)
    discard expect File.writeAllBytes(cutPath, raw[0 until mfraOffset])
    discard catch Mp4.FragmentedIndex.open(cutPath) as rejected
    Swag.require(rejected.value() is InvalidFormatError)

    var damaged: Array'u8
    damaged.add(raw)
    damaged[tfraOffset + 32] = 0xFF
    discard expect File.writeAllBytes(cutPath, damaged.toSlice())
    discard catch Mp4.FragmentedIndex.open(cutPath) as rejected
    Swag.require(rejected.value() is InvalidFormatError)

    damaged.clear()
    damaged.add(raw)
    for byte in 8 do
        damaged[tfraOffset + 44 + byte] = 0
    discard expect File.writeAllBytes(cutPath, damaged.toSlice())
    discard catch Mp4.FragmentedIndex.open(cutPath) as rejected
    Swag.require(rejected.value() is InvalidFormatError)

    // Version zero and four-byte fragment/run/sample numbers are also valid ISO-BMFF indexes.
    var trailer: ConcatBuffer
    var sink = ByteSink.createMemory(&trailer)
    expect sink.writeBigEndian(88'u32)
    expect sink.writeText("mfra")
    expect sink.writeBigEndian(64'u32)
    expect sink.writeText("tfra")
    expect sink.writeBigEndian(0'u32)
    expect sink.writeBigEndian(1'u32)
    expect sink.writeBigEndian(0x3F'u32)
    expect sink.writeBigEndian(2'u32)
    for index in 2
    {
        expect sink.writeBigEndian(cast(u32, index) * 1024 + 512)
        expect sink.writeBigEndian(cast(u32, moofOffsets[index]))
        for 3 do
            expect sink.writeBigEndian(1'u32)
    }

    expect sink.writeBigEndian(16'u32)
    expect sink.writeText("mfro")
    expect sink.writeBigEndian(0'u32)
    expect sink.writeBigEndian(88'u32)
    var legacy: Array'u8
    legacy.add(raw[0 until mfraOffset])
    let trailerBytes = trailer.toArray()
    legacy.add(trailerBytes.toSlice())
    discard expect File.writeAllBytes(cutPath, legacy.toSlice())
    var legacyIndex = expect Mp4.FragmentedIndex.open(cutPath)
    Swag.require(legacyIndex.entryCount() == 2)
    let point = expect legacyIndex.point(1)
    Swag.require(point.decodeTime == 1536 and point.moofOffset == moofOffsets[1])
}
