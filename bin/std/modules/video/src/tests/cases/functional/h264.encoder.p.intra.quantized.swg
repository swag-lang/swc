#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

private impl Nv12Frame
{
    mtd fillPIntraPattern(width, height: s32)
    {
        .width = width
        .height = height
        let count = cast(u64, width) * cast(u64, height)
        .bytes.resize(count + count / 2)
        for y in cast(u64, height)
        {
            for x in cast(u64, width) do
                .bytes[y * cast(u64, width) + x] = cast(u8, (x * 7 + y * 13 + x * y) & 255)
        }
        for y in cast(u64, height) / 2
        {
            for x in cast(u64, width) / 2
            {
                let at = count + y * cast(u64, width) + x * 2
                .bytes[at] = cast(u8, (x * 5 + y * 3) & 255)
                .bytes[at + 1] = cast(u8, (x * 11 + y * 17) & 255)
            }
        }
    }

    mtd fillPIntraFlat(width, height: s32, valueY, valueU, valueV: u8)
    {
        .width = width
        .height = height
        let count = cast(u64, width) * cast(u64, height)
        .bytes.resize(count + count / 2)
        for index in count do
            .bytes[index] = valueY
        for index in count / 4
        {
            .bytes[count + index * 2] = valueU
            .bytes[count + index * 2 + 1] = valueV
        }
    }

    mtd setPIntraDecoded(frame: const *PlanarFrame)
    {
        .width = frame.width
        .height = frame.height
        let lumaSize = cast(u64, .width) * cast(u64, .height)
        .bytes.resize(lumaSize + lumaSize / 2)
        Memory.copy(.bytes.storage(), frame.luma.storage(), lumaSize)
        for pixel in lumaSize / 4
        {
            .bytes[lumaSize + pixel * 2] = frame.chromaB[pixel]
            .bytes[lumaSize + pixel * 2 + 1] = frame.chromaR[pixel]
        }
    }
}

private func samePIntraPicture(a, b: const *PlanarFrame)->bool
{
    return a.width == b.width and a.height == b.height and
           Memory.compare(a.luma.storage(), b.luma.storage(), a.luma.count) == 0 and
           Memory.compare(a.chromaB.storage(), b.chromaB.storage(), a.chromaB.count) == 0 and
           Memory.compare(a.chromaR.storage(), b.chromaR.storage(), a.chromaR.count) == 0
}

// A flat P input follows a textured IDR whose lossy reconstructed boundaries do not
// match the source. Repeating raw input and then the Reader's P1 both hold the
// reconstructed P1; P4 changes the flat source again.
#test
{
    let path = videoTempPath("h264-quantized-p-intra-flat", "mp4")
    defer discard catch File.delete(path)
    var key, flat, changed: Nv12Frame
    key.fillPIntraPattern(64, 64)
    flat.fillPIntraFlat(64, 64, 83, 117, 141)
    changed.fillPIntraFlat(64, 64, 91, 121, 137)
    var encoder = expect H264.Encoder.create(64, 64, 60, 28, 2)
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 64, 90_000,
                                                    encoder.decoderConfig())
    expect writer.addPacket(expect encoder.encode(&key, 0, 3_000))
    let first = expect encoder.encode(&flat, 3_000, 3_000)
    Swag.require(first.bytes.count <= 512)
    expect writer.addPacket(first)
    expect writer.flush()
    var decodedSource: Nv12Frame
    scope
    {
        var prefix = expect Reader.open(path)
        var decoded: PlanarFrame
        expect prefix.decodeFramePlanesInto(&decoded, 1)
        decodedSource.setPIntraDecoded(&decoded)
    }
    let held = expect encoder.encode(&flat, 6_000, 3_000)
    Swag.require(held.bytes.count <= 32)
    expect writer.addPacket(held)
    let decodedHeld = expect encoder.encode(&decodedSource, 9_000, 3_000)
    Swag.require(decodedHeld.bytes.count <= 32)
    expect writer.addPacket(decodedHeld)
    expect writer.addPacket(expect encoder.encode(&changed, 12_000, 3_000))
    expect writer.end()
    var reader = expect Reader.open(path)
    var p1, p2, p3, p4: PlanarFrame
    expect reader.decodeFramePlanesInto(&p1, 1)
    expect reader.decodeFramePlanesInto(&p2, 2)
    expect reader.decodeFramePlanesInto(&p3, 3)
    expect reader.decodeFramePlanesInto(&p4, 4)
    Swag.require(samePIntraPicture(&p1, &p2))
    Swag.require(samePIntraPicture(&p1, &p3))
    Swag.require(not samePIntraPicture(&p3, &p4))
}

// QP 36 keeps the established inter path: quantized intra cannot be assumed
// to anchor a flat neighbour at this coarser quantization step.
#test
{
    var key, flat: Nv12Frame
    key.fillPIntraPattern(64, 64)
    flat.fillPIntraFlat(64, 64, 83, 117, 141)
    var encoder = expect H264.Encoder.create(64, 64, 60, 36, 2)
    discard expect encoder.encode(&key, 0, 3_000)
    let p = expect encoder.encode(&flat, 3_000, 3_000)
    Swag.require(p.bytes.count == 2_118)
}

// Cropped PCM edges and slice starts stay decodable next to quantized flat interiors.
#test
{
    let path = videoTempPath("h264-quantized-p-intra-edge", "mp4")
    defer discard catch File.delete(path)
    var key, flat: Nv12Frame
    key.fillPIntraPattern(130, 74)
    flat.fillPIntraFlat(130, 74, 83, 117, 141)
    var encoder = expect H264.Encoder.create(130, 74, 60, 28, 2)
    var writer = expect Mp4.FragmentedWriter.create(path, 130, 74, 90_000,
                                                    encoder.decoderConfig())
    expect writer.addPacket(expect encoder.encode(&key, 0, 3_000))
    expect writer.addPacket(expect encoder.encode(&flat, 3_000, 3_000))
    expect writer.addPacket(expect encoder.encode(&flat, 6_000, 3_000))
    expect writer.end()
    var reader = expect Reader.open(path)
    var p1, p2: PlanarFrame
    expect reader.decodeFramePlanesInto(&p1, 1)
    expect reader.decodeFramePlanesInto(&p2, 2)
    Swag.require(samePIntraPicture(&p1, &p2))
}
