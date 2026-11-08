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
