#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors, Pixel

func sliceTestFrame(width, height: s32, mode: u32)->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(cast(u64, width) * cast(u64, height) * 3)
    for y in cast(u64, height)
    {
        for x in cast(u64, width)
        {
            let at = (y * cast(u64, width) + x) * 3
            let value = mode != 0 ? cast(u8, 30 + (x / 4 * 17 + y / 4 * 31) % 160 + mode - 1) : 72'u8
            rgb[at] = value
            rgb[at + 1] = value
            rgb[at + 2] = value
        }
    }
    let image = Image.create(width, height, .RGB8, rgb.toSlice())
    var result: Nv12Frame
    try result.convertFrom(&image)
    return result
}

func sliceTestScrolledFrame(shift: u64)->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(64 * 64 * 3)
    for y in 64'u64
    {
        for x in 64'u64
        {
            let sampleX = (x + shift) % 64
            let at = (y * 64 + x) * 3
            rgb[at] = cast(u8, (sampleX * 7 + y * 3) & 255)
            rgb[at + 1] = cast(u8, (sampleX * 5 + y * 11) & 255)
            rgb[at + 2] = cast(u8, (sampleX * 13 + y * 2) & 255)
        }
    }
    let image = Image.create(64, 64, .RGB8, rgb.toSlice())
    var result: Nv12Frame
    try result.convertFrom(&image)
    return result
}

func sliceTestFirstMb(nal: const [..] u8)->u32
{
    Swag.require(nal.count >= 2)
    var bitPosition = 0'u64
    var zeroCount = 0'u32
    while true
    {
        Swag.require(1 + bitPosition / 8 < nal.count)
        let bit = (nal[1 + bitPosition / 8] >> cast(u8, 7 - bitPosition % 8)) & 1
        bitPosition += 1
        if bit do
            break
        zeroCount += 1
        Swag.require(zeroCount < 32)
    }
    var result = 0'u32
    for zeroCount
    {
        Swag.require(1 + bitPosition / 8 < nal.count)
        result = (result << 1) | cast(u32, (nal[1 + bitPosition / 8] >> cast(u8, 7 - bitPosition % 8)) & 1)
        bitPosition += 1
    }
    return result + (1'u32 << zeroCount) - 1
}

func sliceTestPacket(packet: const [..] u8, count, mbWidth, mbHeight: u32, key: bool)
{
    var offset = 0'u64
    for index in count
    {
        Swag.require(offset + 5 <= packet.count)
        let size = (cast(u64, packet[offset]) << 24) |
                   (cast(u64, packet[offset + 1]) << 16) |
                   (cast(u64, packet[offset + 2]) << 8) |
                   cast(u64, packet[offset + 3])
        offset += 4
        Swag.require(size > 1 and size <= packet.count - offset)
        let nal = packet[offset until offset + size]
        Swag.require(nal[0] == (key ? 0x65'u8 : 0x41'u8))
        Swag.require(sliceTestFirstMb(nal) == (index * mbHeight / count) * mbWidth)
        offset += size
    }
    Swag.require(offset == packet.count)
}

func sliceTestExact(original: const *Nv12Frame, decoded: const *PlanarFrame)
{
    Swag.require(decoded.width == original.width and decoded.height == original.height)
    Swag.require(decoded.luma.count == original.luma().count)
    Swag.require(Memory.compare(decoded.luma.storage(), original.luma().buffer,
                                decoded.luma.count) == 0)
    let uv = original.chroma()
    for index in decoded.chromaB.count
    {
        Swag.require(decoded.chromaB[index] == uv[index * 2])
        Swag.require(decoded.chromaR[index] == uv[index * 2 + 1])
    }
}

func sliceTestSameDecoded(left, right: const *PlanarFrame)
{
    Swag.require(left.width == right.width and left.height == right.height)
    Swag.require(Memory.compare(left.luma.storage(), right.luma.storage(), left.luma.count) == 0)
    Swag.require(Memory.compare(left.chromaB.storage(), right.chromaB.storage(), left.chromaB.count) == 0)
    Swag.require(Memory.compare(left.chromaR.storage(), right.chromaR.storage(), left.chromaR.count) == 0)
}

// Separate slices preserve exact pixels across flat boundaries, P-skip runs and a new IDR.
#test
{
    for count in [1'u32, 2, 4]
    {
        let path = videoTempPath("h264-encoder-slices", "mp4")
        defer discard catch File.delete(path)
        let flat = expect sliceTestFrame(66, 70, 0)
        let patterned = expect sliceTestFrame(66, 70, 1)
        let shifted = expect sliceTestFrame(66, 70, 2)
        var encoder = expect H264.Encoder.create(66, 70, keyInterval: 4, sliceCount: count)
        var duplicate = expect H264.Encoder.create(66, 70, keyInterval: 4, sliceCount: count)
        var writer = expect Mp4.FragmentedWriter.create(path, 66, 70, 90_000,
                                                        encoder.decoderConfig())
        let frames: [5] const *Nv12Frame = [&flat, &patterned, &shifted, &shifted, &flat]
        var previousSize = 0'u64
        for index in 5'u64
        {
            let packet = expect encoder.encode(frames[index], index * 3_000, 3_000)
            let matching = expect duplicate.encode(frames[index], index * 3_000, 3_000)
            Swag.require(packet.bytes.count == matching.bytes.count)
            Swag.require(Memory.compare(packet.bytes.buffer, matching.bytes.buffer,
                                        packet.bytes.count) == 0)
            sliceTestPacket(packet.bytes, count, 5, 5, index == 0 or index == 4)
            if index == 1 do
                previousSize = packet.bytes.count
            if index == 2 do
                Swag.require(packet.bytes.count < previousSize)
            expect writer.addPacket(packet)
        }
        expect writer.end()
        var reader = expect Reader.open(path)
        Swag.require(reader.frameCount() == 5)
        var decoded: PlanarFrame
        for index in 5'u64
        {
            expect reader.decodeFramePlanesInto(&decoded, index)
            sliceTestExact(frames[index], &decoded)
        }
    }
}

// Quantized IDR and P slices reconstruct one reference and retain it across repeated raw input.
#test
{
    for count in [1'u32, 2, 4]
    {
        let path = videoTempPath("h264-encoder-slices-qp", "mp4")
        defer discard catch File.delete(path)
        let first = expect sliceTestScrolledFrame(0)
        let changed = expect sliceTestScrolledFrame(1)
        var encoder = expect H264.Encoder.create(64, 64, quantizationQp: 28,
                                                  sliceCount: count)
        var duplicate = expect H264.Encoder.create(64, 64, quantizationQp: 28,
                                                    sliceCount: count)
        var writer = expect Mp4.FragmentedWriter.create(path, 64, 64, 90_000,
                                                        encoder.decoderConfig())
        let frames: [3] const *Nv12Frame = [&first, &changed, &changed]
        for index in 3'u64
        {
            let packet = expect encoder.encode(frames[index], index * 3_000, 3_000)
            let matching = expect duplicate.encode(frames[index], index * 3_000, 3_000)
            Swag.require(packet.bytes.count == matching.bytes.count)
            Swag.require(Memory.compare(packet.bytes.buffer, matching.bytes.buffer,
                                        packet.bytes.count) == 0)
            sliceTestPacket(packet.bytes, count, 4, 4, index == 0)
            expect writer.addPacket(packet)
        }
        expect writer.end()
        var reader = expect Reader.open(path)
        Swag.require(reader.frameCount() == 3)
        var decoded: PlanarFrame
        expect reader.decodeFramePlanesInto(&decoded, 0)
        Swag.require(decoded.width == first.width and decoded.height == first.height)
        expect reader.decodeFramePlanesInto(&decoded, 1)
        var reference: PlanarFrame = decoded
        expect reader.decodeFramePlanesInto(&decoded, 2)
        sliceTestSameDecoded(&reference, &decoded)
    }
}

// Slice counts must fit the picture and the bounded encoder contract.
#test
{
    let frame = expect sliceTestFrame(64, 64, 1)
    var defaultEncoder = expect H264.Encoder.create(64, 64)
    var explicitEncoder = expect H264.Encoder.create(64, 64, sliceCount: 1)
    let defaultPacket = expect defaultEncoder.encode(&frame, 0, 3_000)
    let explicitPacket = expect explicitEncoder.encode(&frame, 0, 3_000)
    Swag.require(defaultPacket.bytes.count == explicitPacket.bytes.count)
    Swag.require(Memory.compare(defaultPacket.bytes.buffer, explicitPacket.bytes.buffer,
                                defaultPacket.bytes.count) == 0)

    var rejected: Swag.Error
    discard catch H264.Encoder.create(64, 64, sliceCount: 0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch H264.Encoder.create(64, 64, sliceCount: 5) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch H264.Encoder.create(64, 64, sliceCount: 9) as rejected
    Swag.require(rejected.value() is BadParameterError)
}
