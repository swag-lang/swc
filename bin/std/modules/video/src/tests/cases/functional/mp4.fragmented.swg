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
    var prefix = expect Reader.openMemory("stopped.mp4", raw[0 until lastFragment])
    Swag.require(prefix.frameCount() == 2)
    Swag.require((expect prefix.decodeFrame(1)).width == 64)
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
