#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors, Pixel

func encoderFrame(width, height: s32, changeX = -1's32, changeY = -1's32)->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(cast(u64, width) * cast(u64, height) * 3)
    for y in cast(u64, height)
    {
        for x in cast(u64, width)
        {
            let offset = (y * cast(u64, width) + x) * 3
            rgb[offset]     = cast(u8, (x * 7 + y * 3) & 255)
            rgb[offset + 1] = cast(u8, (x * 5 + y * 11) & 255)
            rgb[offset + 2] = cast(u8, (x * 13 + y * 2) & 255)
            if changeX >= 0 and changeY >= 0 and
               x >= cast(u64, changeX) and x < cast(u64, changeX + 4) and
               y >= cast(u64, changeY) and y < cast(u64, changeY + 4)
            {
                rgb[offset]     = 255
                rgb[offset + 1] = 255
                rgb[offset + 2] = 255
            }
        }
    }
    let image = Image.create(width, height, .RGB8, rgb.toSlice())
    var result: Nv12Frame
    try result.convertFrom(&image)
    return result
}

func requireEncodedNv12(original: const *Nv12Frame, decoded: const *PlanarFrame)
{
    Swag.require(decoded.width == original.width and decoded.height == original.height)
    Swag.require(decoded.chromaShift == 1)
    Swag.require(decoded.matrix == .Bt709 and decoded.studioRange)
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

// PCM, unchanged P-skip, a changed edge macroblock, and a new IDR all round-trip exactly.
#test
{
    let path = videoTempPath("h264-encoder-roundtrip", "mp4")
    defer discard catch File.delete(path)
    let first   = expect encoderFrame(34, 18)
    let changed = expect encoderFrame(34, 18, 30, 14)
    var encoder = expect H264.Encoder.create(34, 18, keyInterval: 3)
    var writer  = expect Mp4.FragmentedWriter.create(path, 34, 18, 90_000,
                                                     encoder.decoderConfig())

    let firstPacket = expect encoder.encode(&first, 0, 3_000)
    Swag.require(firstPacket.isKeyFrame)
    let firstSize = firstPacket.bytes.count
    expect writer.addPacket(firstPacket)

    let still = expect encoder.encode(&first, 3_000, 3_000)
    Swag.require(not still.isKeyFrame and still.bytes.count < firstSize / 20)
    expect writer.addPacket(still)

    let partial = expect encoder.encode(&changed, 6_000, 3_000)
    Swag.require(not partial.isKeyFrame and partial.bytes.count < firstSize / 2)
    expect writer.addPacket(partial)

    let refreshed = expect encoder.encode(&changed, 9_000, 3_000)
    Swag.require(refreshed.isKeyFrame and refreshed.bytes.count > partial.bytes.count)
    expect writer.addPacket(refreshed)
    expect writer.end()

    var reader = expect Reader.open(path)
    Swag.require(reader.width() == 34 and reader.height() == 18)
    Swag.require(reader.frameCount() == 4 and reader.hasPlanarFrames())
    var decoded: PlanarFrame
    for index in 4'u64
    {
        expect reader.decodeFramePlanesInto(&decoded, index)
        requireEncodedNv12(index < 2 ? &first : &changed, &decoded)
    }
}

// The encoder validates dimensions and times before changing its reference picture.
#test
{
    var encoder = expect H264.Encoder.create(32, 16)
    let frame   = expect encoderFrame(32, 16)
    let wrong   = expect encoderFrame(34, 16)
    let first   = expect encoder.encode(&frame, 0, 1_000)
    let firstSize = first.bytes.count
    var rejected: Swag.Error
    discard catch encoder.encode(&wrong, 1_000, 1_000) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch encoder.encode(&frame, 500, 1_000) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch encoder.encode(&frame, 1_000, 0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch encoder.encode(&frame, Swag.U64.Max, 1) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(first.bytes.count == firstSize)
    let next = expect encoder.encode(&frame, 1_000, 1_000)
    Swag.require(not next.isKeyFrame and next.bytes.count < firstSize / 20)

    discard catch H264.Encoder.create(31, 16) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch H264.Encoder.create(32, 16, keyInterval: 0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch H264.Encoder.create(4096, 4096) as rejected
    Swag.require(rejected.value() is UnsupportedFormatError)
}

// A P slice can mix changed PCM blocks with skip runs at the start, middle, and end.
#test
{
    let path = videoTempPath("h264-encoder-mixed-skip", "mp4")
    defer discard catch File.delete(path)
    let base   = expect encoderFrame(50, 34)
    let start  = expect encoderFrame(50, 34, 0, 0)
    let middle = expect encoderFrame(50, 34, 24, 20)
    var encoder = expect H264.Encoder.create(50, 34, keyInterval: 10)
    var writer  = expect Mp4.FragmentedWriter.create(path, 50, 34, 90_000,
                                                     encoder.decoderConfig())
    let first = expect encoder.encode(&base, 0, 3_000)
    let firstSize = first.bytes.count
    expect writer.addPacket(first)
    let changedStart = expect encoder.encode(&start, 3_000, 3_000)
    Swag.require(changedStart.bytes.count < firstSize / 2)
    expect writer.addPacket(changedStart)
    let changedMiddle = expect encoder.encode(&middle, 6_000, 3_000)
    let changedSize = changedMiddle.bytes.count
    expect writer.addPacket(changedMiddle)
    let unchanged = expect encoder.encode(&middle, 9_000, 3_000)
    Swag.require(unchanged.bytes.count < changedSize / 20)
    expect writer.addPacket(unchanged)
    expect writer.end()

    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 0)
    requireEncodedNv12(&base, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 1)
    requireEncodedNv12(&start, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 2)
    requireEncodedNv12(&middle, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 3)
    requireEncodedNv12(&middle, &decoded)
}

// The smallest cropped picture survives the PCM and skip paths.
#test
{
    let path = videoTempPath("h264-encoder-tiny", "mp4")
    defer discard catch File.delete(path)
    let frame = expect encoderFrame(2, 2)
    var encoder = expect H264.Encoder.create(2, 2)
    var writer  = expect Mp4.FragmentedWriter.create(path, 2, 2, 1_000,
                                                     encoder.decoderConfig())
    expect writer.addPacket(expect encoder.encode(&frame, 0, 40))
    expect writer.addPacket(expect encoder.encode(&frame, 80, 40))
    expect writer.end()
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 2)
    Swag.require(Math.isEqualEpsilon(reader.frameTimestamp(1), 0.08, 0.000001))
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 1)
    requireEncodedNv12(&frame, &decoded)
}

// An IDR before the eight-bit frame number wraps leaves later pictures independently seekable.
#test
{
    let path = videoTempPath("h264-encoder-frame-number", "mp4")
    defer discard catch File.delete(path)
    let frame = expect encoderFrame(16, 16)
    var encoder = expect H264.Encoder.create(16, 16, keyInterval: 255)
    var writer  = expect Mp4.FragmentedWriter.create(path, 16, 16, 30_000,
                                                     encoder.decoderConfig())
    for index in 257'u64
    {
        let packet = expect encoder.encode(&frame, index * 1_000, 1_000)
        Swag.require(packet.isKeyFrame == (index == 0 or index == 255))
        expect writer.addPacket(packet)
    }
    expect writer.end()

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 257)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 254)
    requireEncodedNv12(&frame, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 256)
    requireEncodedNv12(&frame, &decoded)
}
