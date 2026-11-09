#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

private func diagonalFixture()->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(128 * 128 * 3)
    for y in 128'u64
    {
        for x in 128'u64
        {
            let at = (y * 128 + x) * 3
            rgb[at] = cast(u8, (x * 73 + y * 29 + x * y * 3) & 255)
            rgb[at + 1] = cast(u8, (x * 31 + y * 97 + x * y * 5) & 255)
            rgb[at + 2] = cast(u8, (x * 53 + y * 17 + x * y * 7) & 255)
        }
    }
    let image = Image.create(128, 128, .RGB8, rgb.toSlice())
    var result: Nv12Frame
    try result.convertFrom(&image)
    return result
}

private impl Nv12Frame
{
    mtd setDiagonalDecoded(frame: const *PlanarFrame)
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

    mtd setDiagonalShift(source: const *Nv12Frame)
    {
        .width = source.width
        .height = source.height
        let width = cast(u64, .width)
        let height = cast(u64, .height)
        let uvStart = width * height
        .bytes.resize(uvStart + uvStart / 2)
        Memory.clear(.bytes.storage(), uvStart)
        for index in uvStart / 2 do
            .bytes[uvStart + index] = 128
        let original = source.bytes.storage()
        let shifted = .bytes.storage()
        for row in 8'u64 until height
        {
            Memory.copy(shifted + row * width + 16,
                        original + (row - 8) * width, width - 16)
        }
        for row in 4'u64 until height / 2
        {
            Memory.copy(shifted + uvStart + row * width + 16,
                        original + uvStart + (row - 4) * width, width - 16)
        }
    }
}

private func requireDiagonalInterior(decoded: const *PlanarFrame, moved: const *Nv12Frame)
{
    let expectedY = moved.luma()
    for row in 16'u64 until 128
    {
        let at = row * 128 + 16
        Swag.require(Memory.compare(decoded.luma.storage() + at,
                                    expectedY.buffer + at, 112) == 0)
    }
    let expectedUv = moved.chroma()
    for row in 8'u64 until 64
    {
        for column in 8'u64 until 64
        {
            let at = row * 64 + column
            let uv = row * 128 + column * 2
            Swag.require(decoded.chromaB[at] == expectedUv[uv] and
                         decoded.chromaR[at] == expectedUv[uv + 1])
        }
    }
}

// A tile translated twice by 16x8 pixels copies reconstructed luma/chroma exactly
// in its interior across Reader-decoded references and slice boundaries.
#test
{
    for count in [1'u32, 4]
    {
        let path = videoTempPath("h264-diagonal-motion", "mp4")
        defer discard catch File.delete(path)
        let source = expect diagonalFixture()
        var encoder = expect H264.Encoder.create(128, 128, quantizationQp: 0,
                                                 sliceCount: count)
        var writer = expect Mp4.FragmentedWriter.create(path, 128, 128, 90_000,
                                                        encoder.decoderConfig())
        expect writer.addPacket(expect encoder.encode(&source, 0, 3_000))
        expect writer.flush()
        var decodedSource: Nv12Frame
        scope
        {
            var reader = expect Reader.open(path)
            var decoded: PlanarFrame
            expect reader.decodeFramePlanesInto(&decoded, 0)
            decodedSource.setDiagonalDecoded(&decoded)
        }
        var moved: Nv12Frame
        moved.setDiagonalShift(&decodedSource)
        let packet = expect encoder.encode(&moved, 3_000, 3_000)
        Swag.require(packet.bytes.count < 7_000)
        expect writer.addPacket(packet)
        expect writer.flush()
        var firstDecoded: Nv12Frame
        scope
        {
            var prefix = expect Reader.open(path)
            var picture: PlanarFrame
            expect prefix.decodeFramePlanesInto(&picture, 1)
            requireDiagonalInterior(&picture, &moved)
            firstDecoded.setDiagonalDecoded(&picture)
        }
        var movedAgain: Nv12Frame
        movedAgain.setDiagonalShift(&firstDecoded)
        let second = expect encoder.encode(&movedAgain, 6_000, 3_000)
        Swag.require(second.bytes.count < 4_000)
        expect writer.addPacket(second)
        expect writer.end()
        var reader = expect Reader.open(path)
        var decoded: PlanarFrame
        expect reader.decodeFramePlanesInto(&decoded, 2)
        requireDiagonalInterior(&decoded, &movedAgain)
    }
}
