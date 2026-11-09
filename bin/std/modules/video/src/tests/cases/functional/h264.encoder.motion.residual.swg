#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

private func residualMotionFixture()->Nv12Frame fail
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
    mtd setResidualMotionDecoded(frame: const *PlanarFrame)
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

    mtd setResidualMotionShift(source: const *Nv12Frame)
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

private func requireSameResidualMotionPicture(a, b: const *PlanarFrame)
{
    Swag.require(a.width == b.width and a.height == b.height)
    Swag.require(Memory.compare(a.luma.storage(), b.luma.storage(), a.luma.count) == 0)
    Swag.require(Memory.compare(a.chromaB.storage(), b.chromaB.storage(), a.chromaB.count) == 0)
    Swag.require(Memory.compare(a.chromaR.storage(), b.chromaR.storage(), a.chromaR.count) == 0)
}

// A raw 16x8 translation uses residuals against a shifted reconstructed reference.
// Feeding P1 back from Reader as P2 proves that the local reference has no drift.
#test
{
    let path = videoTempPath("h264-motion-residual-diagonal", "mp4")
    defer discard catch File.delete(path)
    let first = expect residualMotionFixture()
    var moved: Nv12Frame
    moved.setResidualMotionShift(&first)
    var encoder = expect H264.Encoder.create(128, 128, quantizationQp: 28,
                                             sliceCount: 4)
    var writer = expect Mp4.FragmentedWriter.create(path, 128, 128, 90_000,
                                                    encoder.decoderConfig())
    expect writer.addPacket(expect encoder.encode(&first, 0, 3_000))
    let shifted = expect encoder.encode(&moved, 3_000, 3_000)
    Swag.require(shifted.bytes.count < 7_000)
    expect writer.addPacket(shifted)
    expect writer.flush()
    var reconstructed: Nv12Frame
    scope
    {
        var prefix = expect Reader.open(path)
        var picture: PlanarFrame
        expect prefix.decodeFramePlanesInto(&picture, 1)
        reconstructed.setResidualMotionDecoded(&picture)
        var squaredError = 0'u64
        let expected = moved.luma()
        for row in 16'u64 until 128
        {
            for column in 16'u64 until 128
            {
                let at = row * 128 + column
                let delta = cast(s32, picture.luma[at]) - cast(s32, expected[at])
                squaredError += cast(u64, delta * delta)
            }
        }
        Swag.require(squaredError < 112 * 112 * 400)
    }
    let held = expect encoder.encode(&reconstructed, 6_000, 3_000)
    Swag.require(held.bytes.count <= 64)
    expect writer.addPacket(held)
    expect writer.end()
    var reader = expect Reader.open(path)
    var p1, p2: PlanarFrame
    expect reader.decodeFramePlanesInto(&p1, 1)
    expect reader.decodeFramePlanesInto(&p2, 2)
    requireSameResidualMotionPicture(&p1, &p2)
}

private func residualMotionEdgeFixture()->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(130 * 74 * 3)
    for y in 74'u64
    {
        for x in 130'u64
        {
            let at = (y * 130 + x) * 3
            rgb[at] = cast(u8, (x * 73 + y * 29 + x * y * 3) & 255)
            rgb[at + 1] = cast(u8, (x * 31 + y * 97 + x * y * 5) & 255)
            rgb[at + 2] = cast(u8, (x * 53 + y * 17 + x * y * 7) & 255)
        }
    }
    let image = Image.create(130, 74, .RGB8, rgb.toSlice())
    var result: Nv12Frame
    try result.convertFrom(&image)
    return result
}

// Cropped edge macroblocks stay PCM while interior blocks can use shifted residuals.
#test
{
    let path = videoTempPath("h264-motion-residual-edge", "mp4")
    defer discard catch File.delete(path)
    let first = expect residualMotionEdgeFixture()
    var moved: Nv12Frame
    moved.setResidualMotionShift(&first)
    var encoder = expect H264.Encoder.create(130, 74, quantizationQp: 36,
                                             sliceCount: 2)
    var writer = expect Mp4.FragmentedWriter.create(path, 130, 74, 90_000,
                                                    encoder.decoderConfig())
    expect writer.addPacket(expect encoder.encode(&first, 0, 3_000))
    expect writer.addPacket(expect encoder.encode(&moved, 3_000, 3_000))
    expect writer.flush()
    var repeated: Nv12Frame
    scope
    {
        var prefix = expect Reader.open(path)
        var picture: PlanarFrame
        expect prefix.decodeFramePlanesInto(&picture, 1)
        Swag.require(picture.width == 130 and picture.height == 74)
        let sourceY = moved.luma()
        for row in 74'u64
        {
            let at = row * 130 + 128
            Swag.require(Memory.compare(picture.luma.storage() + at,
                                        sourceY.buffer + at, 2) == 0)
        }
        for row in 64'u64 until 74
        {
            let at = row * 130
            Swag.require(Memory.compare(picture.luma.storage() + at,
                                        sourceY.buffer + at, 130) == 0)
        }
        repeated.setResidualMotionDecoded(&picture)
    }
    let held = expect encoder.encode(&repeated, 6_000, 3_000)
    Swag.require(held.bytes.count <= 64)
    expect writer.addPacket(held)
    expect writer.end()
    var reader = expect Reader.open(path)
    var p1, p2: PlanarFrame
    expect reader.decodeFramePlanesInto(&p1, 1)
    expect reader.decodeFramePlanesInto(&p2, 2)
    requireSameResidualMotionPicture(&p1, &p2)
}
