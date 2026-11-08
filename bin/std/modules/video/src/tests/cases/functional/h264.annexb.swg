#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

func annexPacket(source: *ByteSource)->Array'u8 fail
{
    let size = try source.readBigEndian'u32()
    var result: Array'u8
    result.resize(size)
    try source.readExact(result.toSlice())
    return result
}

func appendAnnexPacket(result: *Array'u8, packet: const [..] u8, startCode: const [..] u8)
{
    var offset = 0'u64
    while offset < packet.count
    {
        let size = Math.make32(packet[offset], packet[offset + 1], packet[offset + 2], packet[offset + 3])
        offset += 4
        result.add(startCode)
        result.add(packet[offset until offset + size])
        offset += size
    }
}

// AVC parameter sets and an IDR picture survive Annex B conversion and MP4 playback.
#test
{
    var source = expect ByteSource.openFile(videoFixturePath("ffmpeg-h264-baseline.packets").toString())
    let config = expect annexPacket(&source)
    let packet = expect annexPacket(&source)

    let spsSize  = Math.make16(config[6], config[7])
    let ppsCount = 8 + spsSize
    let ppsSize  = Math.make16(config[ppsCount + 1], config[ppsCount + 2])
    const Start: [4] u8 = [0, 0, 0, 1]
    let delimiter = Swag.makeSlice(&Start[0], Start.count)
    var annex: Array'u8
    annex.add(delimiter)
    annex.add(config.toSlice()[8 until 8 + spsSize])
    annex.add(delimiter)
    annex.add(config.toSlice()[ppsCount + 3 until ppsCount + 3 + ppsSize])
    appendAnnexPacket(&annex, packet.toSlice(), delimiter)

    let converted = expect H264.AnnexBAccessUnit.parse(annex.toSlice())
    Swag.require(converted.hasPicture and converted.isKeyFrame)
    Swag.require(converted.decoderConfig.count == config.count)
    Swag.require(Memory.compare(converted.decoderConfig.storage(), config.storage(), config.count) == 0)

    let path = videoTempPath("annexb-fragmented", "mp4")
    defer discard catch File.delete(path)
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 48, 12_800, converted.decoderConfig.toSlice())
    expect writer.addPacket(EncodedPacket{converted.bytes.toSlice(), 0, 0, 512,
                                          converted.isKeyFrame})
    expect writer.end()

    var reader   = expect Reader.open(path)
    var original = expect Reader.open(videoFixturePath("ffmpeg-h264-baseline.mp4"))
    let actual   = expect reader.decodeFrame(0)
    let expected = expect original.decodeFrame(0)
    Swag.require(actual.byteCount == expected.byteCount)
    Swag.require(Memory.compare(actual.pixels.storage(), expected.pixels.storage(), actual.byteCount) == 0)
}

// Three-byte start codes and trailing zero bytes preserve the original non-IDR packet.
#test
{
    var source = expect ByteSource.openFile(videoFixturePath("ffmpeg-h264-baseline.packets").toString())
    discard expect annexPacket(&source)
    discard expect annexPacket(&source)
    let packet = expect annexPacket(&source)
    const Start: [3] u8 = [0, 0, 1]
    var annex: Array'u8
    appendAnnexPacket(&annex, packet.toSlice(), Swag.makeSlice(&Start[0], Start.count))
    annex.add(0'u8)
    annex.add(0'u8)

    let converted = expect H264.AnnexBAccessUnit.parse(annex.toSlice())
    Swag.require(converted.hasPicture and not converted.isKeyFrame)
    Swag.require(converted.decoderConfig.isEmpty())
    Swag.require(converted.bytes.count == packet.count)
    Swag.require(Memory.compare(converted.bytes.storage(), packet.storage(), packet.count) == 0)
}

// Broken delimiters, empty NAL units and partial parameter sets are rejected.
#test
{
    const NoStart: [5] u8 = [3, 2, 1, 0x65, 1]
    const Empty:   [7] u8 = [0, 0, 1, 0, 0, 1, 0x65]
    const NoPps:   [8] u8 = [0, 0, 1, 0x67, 0x42, 0, 10, 0]
    const BadNal:  [4] u8 = [0, 0, 1, 0x80]
    var rejected: Swag.Error
    discard catch H264.AnnexBAccessUnit.parse(Swag.makeSlice(&NoStart[0], NoStart.count)) as rejected
    Swag.require((rejected.value() is InvalidFormatError))
    discard catch H264.AnnexBAccessUnit.parse(Swag.makeSlice(&Empty[0], Empty.count)) as rejected
    Swag.require((rejected.value() is InvalidFormatError))
    discard catch H264.AnnexBAccessUnit.parse(Swag.makeSlice(&NoPps[0], NoPps.count)) as rejected
    Swag.require((rejected.value() is InvalidFormatError))
    discard catch H264.AnnexBAccessUnit.parse(Swag.makeSlice(&BadNal[0], BadNal.count)) as rejected
    Swag.require((rejected.value() is InvalidFormatError))
}

// A parameter-set-only buffer can initialize a writer before the first coded picture arrives.
#test
{
    const Headers: [13] u8 = [0, 0, 1, 0x67, 0x42, 0, 10,
                              0, 0, 1, 0x68, 0xCE, 1]
    let converted = expect H264.AnnexBAccessUnit.parse(Swag.makeSlice(&Headers[0], Headers.count))
    Swag.require(not converted.hasPicture and not converted.isKeyFrame)
    Swag.require(converted.decoderConfig.count == 18)
    Swag.require(converted.decoderConfig[0] == 1 and converted.decoderConfig[1] == 0x42)
}
