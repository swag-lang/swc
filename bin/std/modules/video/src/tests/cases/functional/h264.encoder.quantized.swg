#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors, Pixel

private func quantizedScrolledFrame(width, height, shiftX, shiftY: s32)->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(cast(u64, width) * cast(u64, height) * 3)
    for y in cast(u64, height)
    {
        for x in cast(u64, width)
        {
            let sampleX = (x + cast(u64, shiftX)) % cast(u64, width)
            let sampleY = (y + cast(u64, shiftY)) % cast(u64, height)
            let at = (y * cast(u64, width) + x) * 3
            rgb[at] = cast(u8, (sampleX * 7 + sampleY * 3) & 255)
            rgb[at + 1] = cast(u8, (sampleX * 5 + sampleY * 11) & 255)
            rgb[at + 2] = cast(u8, (sampleX * 13 + sampleY * 2) & 255)
        }
    }
    let image = Image.create(width, height, .RGB8, rgb.toSlice())
    var result: Nv12Frame
    try result.convertFrom(&image)
    return result
}

private impl Nv12Frame
{
    // Reuses the reader's decoded planes as the next encoder input, without an RGB roundtrip.
    mtd encoderSetDecoded(frame: const *PlanarFrame)
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

private func requireQuantizedFrame(expected: const *Nv12Frame, actual: const *PlanarFrame)
{
    Swag.require(expected.width == actual.width and expected.height == actual.height)
    Swag.require(Memory.compare(expected.luma().buffer, actual.luma.storage(),
                                actual.luma.count) == 0)
    let uv = expected.chroma()
    for pixel in actual.chromaB.count
    {
        Swag.require(actual.chromaB[pixel] == uv[pixel * 2])
        Swag.require(actual.chromaR[pixel] == uv[pixel * 2 + 1])
    }
}

// A lossy P picture becomes the exact reference of the next P. Feeding its decoded
// samples back must produce a tiny skip, then a copied 16x16 tile remains exact.
#test
{
    let path = videoTempPath("h264-encoder-quantized-reference", "mp4")
    defer discard catch File.delete(path)
    let first = expect quantizedScrolledFrame(64, 64, 0, 0)
    let changed = expect quantizedScrolledFrame(64, 64, 1, 1)
    var encoder = expect H264.Encoder.create(64, 64, quantizationQp: 28)
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 64, 90_000,
                                                    encoder.decoderConfig())
    let key = expect encoder.encode(&first, 0, 3_000)
    expect writer.addPacket(key)
    let lossy = expect encoder.encode(&changed, 3_000, 3_000)
    Swag.require(lossy.bytes.count < 64 * 64 * 3 / 2)
    expect writer.addPacket(lossy)
    expect writer.flush()

    var repeated: Nv12Frame
    scope
    {
        var prefix = expect Reader.open(path)
        var decoded: PlanarFrame
        expect prefix.decodeFramePlanesInto(&decoded, 0)
        Swag.require(decoded.width == first.width and decoded.height == first.height)
        expect prefix.decodeFramePlanesInto(&decoded, 1)
        repeated.encoderSetDecoded(&decoded)
        Swag.require(Memory.compare(repeated.bytes.storage(), changed.bytes.storage(),
                                    changed.bytes.count) != 0)
    }
    let skipped = expect encoder.encode(&repeated, 6_000, 3_000)
    Swag.require(skipped.bytes.count <= 20)
    expect writer.addPacket(skipped)

    var moved = repeated
    // Copy one complete tile leftward from the decoded reference, including its UV samples.
    for row in 16'u64
    {
        Memory.copy(moved.bytes.storage() + (16 + row) * 64 + 16,
                    repeated.bytes.storage() + (16 + row) * 64 + 32, 16)
    }
    let uvStart = 64'u64 * 64
    for row in 8'u64
    {
        Memory.copy(moved.bytes.storage() + uvStart + (8 + row) * 64 + 16,
                    repeated.bytes.storage() + uvStart + (8 + row) * 64 + 32, 16)
    }
    let motion = expect encoder.encode(&moved, 9_000, 3_000)
    Swag.require(motion.bytes.count < 256)
    expect writer.addPacket(motion)
    expect writer.end()

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 4)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 1)
    requireQuantizedFrame(&repeated, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 2)
    requireQuantizedFrame(&repeated, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 3)
    requireQuantizedFrame(&moved, &decoded)
}

// A static raw source after lossy P1 must hold P1's reconstructed pixels, rather than
// repeatedly quantizing the source against them or inserting unencoded source pixels.
#test
{
    let path = videoTempPath("h264-encoder-quantized-static-source", "mp4")
    defer discard catch File.delete(path)
    let first = expect quantizedScrolledFrame(64, 64, 0, 0)
    let changed = expect quantizedScrolledFrame(64, 64, 1, 1)
    var encoder = expect H264.Encoder.create(64, 64, quantizationQp: 28)
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 64, 90_000,
                                                    encoder.decoderConfig())
    expect writer.addPacket(expect encoder.encode(&first, 0, 3_000))
    expect writer.addPacket(expect encoder.encode(&changed, 3_000, 3_000))
    for frame in 2'u64 until 5
    {
        let held = expect encoder.encode(&changed, frame * 3_000, 3_000)
        Swag.require(held.bytes.count <= 20)
        expect writer.addPacket(held)
    }
    expect writer.end()
    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 1)
    var held: Nv12Frame
    held.encoderSetDecoded(&decoded)
    Swag.require(Memory.compare(held.bytes.storage(), changed.bytes.storage(),
                                changed.bytes.count) != 0)
    for frame in 2'u64 until 5
    {
        expect reader.decodeFramePlanesInto(&decoded, frame)
        requireQuantizedFrame(&held, &decoded)
    }
}

// Cropped edge macroblocks keep the exact PCM path, while full interior blocks can be lossy.
#test
{
    let path = videoTempPath("h264-encoder-quantized-edge", "mp4")
    defer discard catch File.delete(path)
    let first = expect quantizedScrolledFrame(34, 18, 0, 0)
    let changed = expect quantizedScrolledFrame(34, 18, 1, 1)
    var encoder = expect H264.Encoder.create(34, 18, quantizationQp: 36)
    var writer = expect Mp4.FragmentedWriter.create(path, 34, 18, 90_000,
                                                    encoder.decoderConfig())
    expect writer.addPacket(expect encoder.encode(&first, 0, 3_000))
    expect writer.addPacket(expect encoder.encode(&changed, 3_000, 3_000))
    expect writer.flush()
    var repeated: Nv12Frame
    scope
    {
        var prefix = expect Reader.open(path)
        var decoded: PlanarFrame
        expect prefix.decodeFramePlanesInto(&decoded, 1)
        repeated.encoderSetDecoded(&decoded)
    }
    expect writer.addPacket(expect encoder.encode(&repeated, 6_000, 3_000))
    expect writer.end()
    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 2)
    requireQuantizedFrame(&repeated, &decoded)
}

// Strong 4x4 chroma AC at the smallest and largest lossy QPs stays decodable through
// successive P pictures whose sources are not copied from the decoder between calls.
#test
{
    const Qps: [2] u32 = [1, 51]
    for qp in Qps
    {
        let path = videoTempPath("h264-encoder-quantized-chroma", "mp4")
        defer discard catch File.delete(path)
        var base = expect quantizedScrolledFrame(32, 32, 0, 0)
        let uvStart = 32'u64 * 32
        for sample in 32'u64 * 16 do
            base.bytes[uvStart + sample] = 128
        var phaseA = base
        var phaseB = base
        for row in 16'u64
        {
            for column in 16'u64
            {
                let at = uvStart + row * 32 + column * 2
                let high = (row + column) % 2 == 0
                phaseA.bytes[at] = high ? 255 : 0
                phaseA.bytes[at + 1] = high ? 0 : 255
                phaseB.bytes[at] = high ? 0 : 255
                phaseB.bytes[at + 1] = high ? 255 : 0
            }
        }
        var encoder = expect H264.Encoder.create(32, 32, quantizationQp: qp)
        var writer = expect Mp4.FragmentedWriter.create(path, 32, 32, 90_000,
                                                        encoder.decoderConfig())
        let key = expect encoder.encode(&base, 0, 3_000)
        let keySize = key.bytes.count
        expect writer.addPacket(key)
        for index in 4'u64
        {
            let next = index % 2 == 0 ? &phaseA : &phaseB
            let packet = expect encoder.encode(next, (index + 1) * 3_000, 3_000)
            Swag.require(packet.bytes.count < keySize)
            expect writer.addPacket(packet)
        }
        expect writer.end()
        var reader = expect Reader.open(path)
        Swag.require(reader.frameCount() == 5)
        var decoded: PlanarFrame
        expect reader.decodeFramePlanesInto(&decoded, 0)
        Swag.require(decoded.width == base.width and decoded.height == base.height)
        expect reader.decodeFramePlanesInto(&decoded, 1)
        let firstCb = decoded.chromaB[0]
        let firstCr = decoded.chromaR[0]
        expect reader.decodeFramePlanesInto(&decoded, 2)
        Swag.require(decoded.chromaB[0] != firstCb and decoded.chromaR[0] != firstCr)
        expect reader.decodeFramePlanesInto(&decoded, 3)
        expect reader.decodeFramePlanesInto(&decoded, 4)
    }
}

// Explicit QP zero retains the byte-exact legacy mode and rejects out-of-range QP.
#test
{
    let first = expect quantizedScrolledFrame(32, 32, 0, 0)
    let changed = expect quantizedScrolledFrame(32, 32, 1, 1)
    var exact = expect H264.Encoder.create(32, 32, quantizationQp: 0)
    var defaultMode = expect H264.Encoder.create(32, 32)
    let exactKey = expect exact.encode(&first, 0, 3_000)
    let defaultKey = expect defaultMode.encode(&first, 0, 3_000)
    Swag.require(Memory.compare(exactKey.bytes.buffer, defaultKey.bytes.buffer,
                                exactKey.bytes.count) == 0)
    let exactP = expect exact.encode(&changed, 3_000, 3_000)
    let defaultP = expect defaultMode.encode(&changed, 3_000, 3_000)
    Swag.require(exactP.bytes.count == defaultP.bytes.count and
                 Memory.compare(exactP.bytes.buffer, defaultP.bytes.buffer,
                                exactP.bytes.count) == 0)
    var rejected: Swag.Error
    discard catch H264.Encoder.create(32, 32, quantizationQp: 52) as rejected
    Swag.require(rejected.value() is BadParameterError)
}
