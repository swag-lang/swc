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

func encoderScrolledFrame(width, height, shiftX, shiftY: s32)->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(cast(u64, width) * cast(u64, height) * 3)
    for y in cast(u64, height)
    {
        for x in cast(u64, width)
        {
            let sampleX = (x + cast(u64, shiftX)) % cast(u64, width)
            let sampleY = (y + cast(u64, shiftY)) % cast(u64, height)
            let offset = (y * cast(u64, width) + x) * 3
            rgb[offset]     = cast(u8, (sampleX * 7 + sampleY * 3) & 255)
            rgb[offset + 1] = cast(u8, (sampleX * 5 + sampleY * 11) & 255)
            rgb[offset + 2] = cast(u8, (sampleX * 13 + sampleY * 2) & 255)
        }
    }
    let image = Image.create(width, height, .RGB8, rgb.toSlice())
    var result: Nv12Frame
    try result.convertFrom(&image)
    return result
}

func encoderSolidFrame(width, height: s32, red, green, blue: u8)->Nv12Frame fail
{
    var rgb: Array'u8
    rgb.resize(cast(u64, width) * cast(u64, height) * 3)
    for pixel in cast(u64, width) * cast(u64, height)
    {
        rgb[pixel * 3] = red
        rgb[pixel * 3 + 1] = green
        rgb[pixel * 3 + 2] = blue
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

// Vertical and horizontal screen scrolls use exact inter prediction for most blocks.
#test
{
    let path = videoTempPath("h264-encoder-scroll", "mp4")
    defer discard catch File.delete(path)
    let first = expect encoderScrolledFrame(128, 128, 0, 0)
    let vertical = expect encoderScrolledFrame(128, 128, 0, 16)
    let diagonal = expect encoderScrolledFrame(128, 128, 16, 16)
    let smallScroll = expect encoderScrolledFrame(128, 128, 16, 18)
    var encoder = expect H264.Encoder.create(128, 128, keyInterval: 10)
    var writer = expect Mp4.FragmentedWriter.create(path, 128, 128, 90_000,
                                                    encoder.decoderConfig())
    let key = expect encoder.encode(&first, 0, 3_000)
    let keySize = key.bytes.count
    expect writer.addPacket(key)
    let movedDown = expect encoder.encode(&vertical, 3_000, 3_000)
    Swag.require(movedDown.bytes.count < keySize / 3)
    expect writer.addPacket(movedDown)
    let movedRight = expect encoder.encode(&diagonal, 6_000, 3_000)
    Swag.require(movedRight.bytes.count < keySize / 3)
    expect writer.addPacket(movedRight)
    let still = expect encoder.encode(&diagonal, 9_000, 3_000)
    Swag.require(still.bytes.count < keySize / 20)
    expect writer.addPacket(still)
    let twoPixels = expect encoder.encode(&smallScroll, 12_000, 3_000)
    Swag.require(twoPixels.bytes.count < keySize / 3)
    expect writer.addPacket(twoPixels)
    expect writer.end()

    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 0)
    requireEncodedNv12(&first, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 1)
    requireEncodedNv12(&vertical, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 2)
    requireEncodedNv12(&diagonal, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 3)
    requireEncodedNv12(&diagonal, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 4)
    requireEncodedNv12(&smallScroll, &decoded)
}

// When there is no exact whole-pixel match, a changed P picture retains exact samples.
#test
{
    let path = videoTempPath("h264-encoder-unmatched", "mp4")
    defer discard catch File.delete(path)
    let first = expect encoderScrolledFrame(64, 64, 0, 0)
    let changed = expect encoderScrolledFrame(64, 64, 1, 1)
    var encoder = expect H264.Encoder.create(64, 64)
    var writer = expect Mp4.FragmentedWriter.create(path, 64, 64, 90_000,
                                                    encoder.decoderConfig())
    let key = expect encoder.encode(&first, 0, 3_000)
    let keySize = key.bytes.count
    expect writer.addPacket(key)
    let fallback = expect encoder.encode(&changed, 3_000, 3_000)
    Swag.require(fallback.bytes.count > keySize / 2)
    expect writer.addPacket(fallback)
    expect writer.end()
    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 1)
    requireEncodedNv12(&changed, &decoded)
}

// A flat-color key picture and a full-screen color change avoid raw PCM beyond the first block.
#test
{
    let path = videoTempPath("h264-encoder-flat", "mp4")
    defer discard catch File.delete(path)
    let first = expect encoderSolidFrame(128, 128, 30, 90, 200)
    let changed = expect encoderSolidFrame(128, 128, 200, 50, 30)
    var encoder = expect H264.Encoder.create(128, 128, keyInterval: 2)
    var writer = expect Mp4.FragmentedWriter.create(path, 128, 128, 90_000,
                                                    encoder.decoderConfig())
    let key = expect encoder.encode(&first, 0, 3_000)
    Swag.require(key.bytes.count < 2_000)
    expect writer.addPacket(key)
    let recolored = expect encoder.encode(&changed, 3_000, 3_000)
    Swag.require(recolored.bytes.count < 2_000)
    expect writer.addPacket(recolored)
    let newKey = expect encoder.encode(&changed, 6_000, 3_000)
    Swag.require(newKey.isKeyFrame and newKey.bytes.count < 2_000)
    expect writer.addPacket(newKey)
    expect writer.end()

    var reader = expect Reader.open(path)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 0)
    requireEncodedNv12(&first, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 1)
    requireEncodedNv12(&changed, &decoded)
    expect reader.decodeFramePlanesInto(&decoded, 2)
    requireEncodedNv12(&changed, &decoded)
}
