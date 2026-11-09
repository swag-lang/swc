#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

private func intraKeyFixture(width, height: s32)->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(cast(u64, width) * cast(u64, height) * 3)
    for y in cast(u64, height)
    {
        for x in cast(u64, width)
        {
            let at = (y * cast(u64, width) + x) * 3
            rgb[at] = cast(u8, (x * 7 + y * 3 + x * y) & 255)
            rgb[at + 1] = cast(u8, (x * 13 + y * 17) & 255)
            rgb[at + 2] = cast(u8, (x * 23 + y * 11) & 255)
        }
    }
    let image = Image.create(width, height, .RGB8, rgb.toSlice())
    var result: Nv12Frame
    try result.convertFrom(&image)
    return result
}

private func requireSameIntraPicture(a, b: const *PlanarFrame)
{
    Swag.require(a.width == b.width and a.height == b.height)
    Swag.require(Memory.compare(a.luma.storage(), b.luma.storage(), a.luma.count) == 0)
    Swag.require(Memory.compare(a.chromaB.storage(), b.chromaB.storage(), a.chromaB.count) == 0)
    Swag.require(Memory.compare(a.chromaR.storage(), b.chromaR.storage(), a.chromaR.count) == 0)
}

private impl Nv12Frame
{
    mtd shiftIntraLuma()
    {
        for index in cast(u64, .width) * cast(u64, .height) do
            .bytes[index] = cast(u8, (cast(u32, .bytes[index]) + 31) & 255)
    }


    mtd setIntraDecoded(frame: const *PlanarFrame)
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

// A decoded IDR fed back as P1 must skip against the encoder's own reconstructed
// reference. P2 then changes the raw source again, exercising prediction after skip.
#test
{
    let path = videoTempPath("h264-quantized-idr-reference", "mp4")
    defer discard catch File.delete(path)
    let source = expect intraKeyFixture(64, 64)
    var encoder = expect H264.Encoder.create(64, 64, quantizationQp: 36)
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 64, 90_000,
                                                    encoder.decoderConfig())
    expect writer.addPacket(expect encoder.encode(&source, 0, 3_000))
    expect writer.flush()
    var decodedSource: Nv12Frame
    scope
    {
        var prefix = expect Reader.open(path)
        var picture: PlanarFrame
        expect prefix.decodeFramePlanesInto(&picture, 0)
        decodedSource.setIntraDecoded(&picture)
        Swag.require(Memory.compare(decodedSource.bytes.storage(), source.bytes.storage(),
                                    source.bytes.count) != 0)
    }
    let held = expect encoder.encode(&decodedSource, 3_000, 3_000)
    Swag.require(held.bytes.count <= 20)
    expect writer.addPacket(held)
    expect writer.addPacket(expect encoder.encode(&source, 6_000, 3_000))
    expect writer.end()
    var reader = expect Reader.open(path)
    var keyFrame, heldFrame, changedFrame: PlanarFrame
    expect reader.decodeFramePlanesInto(&keyFrame, 0)
    expect reader.decodeFramePlanesInto(&heldFrame, 1)
    requireSameIntraPicture(&keyFrame, &heldFrame)
    expect reader.decodeFramePlanesInto(&changedFrame, 2)
    Swag.require(changedFrame.width == 64 and changedFrame.height == 64)
}

// A textured IDR is coded smaller than raw PCM, and a repeated source preserves its
// reconstructed picture without another transform pass.
#test
{
    let path = videoTempPath("h264-quantized-idr", "mp4")
    defer discard catch File.delete(path)
    let source = expect intraKeyFixture(64, 64)
    var legacy = expect H264.Encoder.create(64, 64, quantizationQp: 0)
    let pcm = expect legacy.encode(&source, 0, 3_000)
    var encoder = expect H264.Encoder.create(64, 64, quantizationQp: 36)
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 64, 90_000,
                                                    encoder.decoderConfig())
    let key = expect encoder.encode(&source, 0, 3_000)
    Swag.require(key.isKeyFrame and key.bytes.count < pcm.bytes.count / 2)
    expect writer.addPacket(key)
    for index in 1'u64 until 4
    {
        let held = expect encoder.encode(&source, index * 3_000, 3_000)
        Swag.require(held.bytes.count <= 20)
        expect writer.addPacket(held)
    }
    expect writer.end()
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 4)
    var keyFrame, heldFrame: PlanarFrame
    expect reader.decodeFramePlanesInto(&keyFrame, 0)
    var squaredError = 0'u64
    for index in keyFrame.luma.count
    {
        let delta = cast(s32, keyFrame.luma[index]) - cast(s32, source.luma()[index])
        squaredError += cast(u64, delta * delta)
    }
    Swag.require(squaredError > 0 and squaredError < keyFrame.luma.count * 1_000)
    for index in 1'u64 until 4
    {
        expect reader.decodeFramePlanesInto(&heldFrame, index)
        requireSameIntraPicture(&keyFrame, &heldFrame)
    }
}

// Cropped edges remain decodable when only whole interior macroblocks take intra residuals.
#test
{
    let path = videoTempPath("h264-quantized-idr-edge", "mp4")
    defer discard catch File.delete(path)
    let source = expect intraKeyFixture(34, 18)
    var encoder = expect H264.Encoder.create(34, 18, quantizationQp: 36)
    var writer = expect Mp4.FragmentedWriter.create(path, 34, 18, 90_000,
                                                    encoder.decoderConfig())
    expect writer.addPacket(expect encoder.encode(&source, 0, 3_000))
    expect writer.addPacket(expect encoder.encode(&source, 3_000, 3_000))
    expect writer.end()
    var reader = expect Reader.open(path)
    var first, held: PlanarFrame
    expect reader.decodeFramePlanesInto(&first, 0)
    expect reader.decodeFramePlanesInto(&held, 1)
    requireSameIntraPicture(&first, &held)
}

// Each slice starts its own prediction and CAVLC contexts, including at a new IDR
// after two P pictures. The extreme QPs exercise different luma/chroma level ranges.
#test
{
    const Qps: [2] u32 = [1, 51]
    for qp in Qps
    {
        let path = videoTempPath("h264-quantized-idr-slices", "mp4")
        defer discard catch File.delete(path)
        let initial = expect intraKeyFixture(64, 64)
        var shifted = initial
        shifted.shiftIntraLuma()
        var encoder = expect H264.Encoder.create(64, 64, 3, qp, 2)
        var writer = expect Mp4.FragmentedWriter.create(path, 64, 64, 90_000,
                                                        encoder.decoderConfig())
        expect writer.addPacket(expect encoder.encode(&initial, 0, 3_000))
        expect writer.addPacket(expect encoder.encode(&shifted, 3_000, 3_000))
        let held = expect encoder.encode(&shifted, 6_000, 3_000)
        Swag.require(held.bytes.count <= 32)
        expect writer.addPacket(held)
        expect writer.addPacket(expect encoder.encode(&shifted, 9_000, 3_000))
        expect writer.addPacket(expect encoder.encode(&shifted, 12_000, 3_000))
        expect writer.end()
        var reader = expect Reader.open(path)
        Swag.require(reader.frameCount() == 5)
        var beforeKey, heldFrame, afterKey, afterHeld: PlanarFrame
        expect reader.decodeFramePlanesInto(&beforeKey, 1)
        expect reader.decodeFramePlanesInto(&heldFrame, 2)
        requireSameIntraPicture(&beforeKey, &heldFrame)
        expect reader.decodeFramePlanesInto(&afterKey, 3)
        expect reader.decodeFramePlanesInto(&afterHeld, 4)
        requireSameIntraPicture(&afterKey, &afterHeld)
    }
}
