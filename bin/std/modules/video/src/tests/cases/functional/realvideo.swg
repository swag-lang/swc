#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors

func realVideoCompareFrame(reader: *Reader, reference: const [..] u8, index: u64)
{
    var frame: PlanarFrame
    let size = 96_u64 * 64 * 3 / 2
    expect reader.decodeFramePlanesInto(&frame, index)
    Swag.require(frame.width == 96 and frame.height == 64)
    var offset = index * size
    for bytes in [frame.luma.toSlice(), frame.chromaB.toSlice(), frame.chromaR.toSlice()]
    {
        for actual, at in bytes
        {
            if actual != reference[offset + at]
            {
                Console.println("frame ", index, " sample ", offset + at - index * size, " actual ", actual, " expected ", reference[offset + at])
                Swag.require(false)
            }
        }

        offset += bytes.count
    }
}

// Independent RV40 encodings and FFmpeg YUV references pin all samples, display order,
// file/memory paths, and backward seeks across open groups of pictures.
func realVideoCompare(name: string)
{
    let path      = videoFixturePath(Format.toString("%.mkv", name))
    let golden    = name == "rv40-legacy-clock" ? "rv40-ipb" : name
    let reference = expect File.readAllBytes(Path.combine(testSourceRoot(#curlocation), Format.toString("goldens/%.yuv", golden)))
    let count     = reference.count / (96 * 64 * 3 / 2)
    var reader    = expect Reader.open(path, pictureOnly: true)
    for index in count
    {
        realVideoCompareFrame(&reader, reference.toSlice(), index)
    }

    for step in count
    {
        realVideoCompareFrame(&reader, reference.toSlice(), count - step - 1)
    }

    let bytes  = expect File.readAllBytes(path)
    var memory = expect Reader.openMemory(path, bytes.toSlice(), pictureOnly: true)
    for index in [count - 1, 0, count / 2, 1]
    {
        realVideoCompareFrame(&memory, reference.toSlice(), index)
    }

    Swag.require(memory.frameCount() == count)
    for index in count
    {
        Swag.require(Math.isEqualEpsilon(memory.frameTimestamp(index), cast(f64, index) / 25, 0.000001))
    }
}

#test { realVideoCompare("rv40-intra") }
#test { realVideoCompare("rv40-ipb") }
#test { realVideoCompare("rv40-adaptive") }
#test { realVideoCompare("rv40-legacy-clock") }
#test { realVideoCompare("rv40-slices") }

// A future reference can be indexed in one cluster and its B pictures in the next.
// Crossing the wrapping codec clock must preserve display order and the final reference.
#test
{
    let reference = expect File.readAllBytes(Path.combine(testSourceRoot(#curlocation), "goldens/rv40-slices.yuv"))
    var reader    = expect Reader.open(videoFixturePath("rv40-cluster-wrap.mkv"), pictureOnly: true)
    realVideoCompareFrame(&reader, reference.toSlice(), 0)
    Swag.require(reader.frameCount() == 0)

    const FrameCount = 13_u64
    for index in 1_u64 until FrameCount
    {
        realVideoCompareFrame(&reader, reference.toSlice(), index)
        Swag.require(Math.isEqualEpsilon(reader.frameTimestamp(index), cast(f64, index) / 25, 0.000001))
    }

    Swag.require(reader.frameCount() == FrameCount)
    Swag.require(reader.syncFrameAt(1) == 8 and reader.syncFrameAt(9) == FrameCount)

    var frame:   PlanarFrame
    var pastEnd: Swag.Error
    catch reader.decodeFramePlanesInto(&frame, FrameCount) as pastEnd
    Swag.require(pastEnd.value() is BadParameterError)

    for index in [7_u64, 8, 3, 12, 0]
    {
        realVideoCompareFrame(&reader, reference.toSlice(), index)
    }
}

// Motion uses the visible edges even when a whole partition lies outside the picture.
#test
{
    var plane: RealVideo.Plane
    plane.resize(11, 9)
    for y in 9_s32
    {
        let row = plane.at(0, y)
        for x in 11_s32
        {
            row[x] = cast(u8, ((x * 37 + y * 61 + x * y * 7) & 255))
        }
    }

    var luma: [80] u8
    Memory.set(&luma[0], 0xA5, luma.count)
    RealVideo.predictMotion(&luma[0], 10, &plane, 0, 0, 8, {-3, -2}, false)
    const FirstRow: [8] u8 = [0, 2, 41, 74, 101, 146, 237, 181]
    const LastRow:  [8] u8 = [148, 140, 62, 46, 130, 108, 164, 101]
    for column in 8_u64
    {
        Swag.require(luma[column] == FirstRow[column])
        Swag.require(luma[70 + column] == LastRow[column])
    }

    RealVideo.predictMotion(&luma[0], 10, &plane, 0, 0, 8, {-32768, 32767}, false)
    for row in 8_u64
    {
        for column in 8_u64
        {
            Swag.require(luma[row * 10 + column] == 232)
        }

        Swag.require(luma[row * 10 + 8] == 0xA5 and luma[row * 10 + 9] == 0xA5)
    }

    // The 3/4-by-3/4 chroma phase selects the half-by-half filter.
    var chroma: [16] u8
    RealVideo.predictMotion(&chroma[0], 4, &plane, 8, 6, 4, {7, 7}, true)
    const Chroma: [16] u8 = [138, 92, 69, 69, 130, 92, 72, 72, 126, 91, 138, 138, 126, 91, 138, 138]
    for sample, index in chroma
    {
        Swag.require(sample == Chroma[index])
    }
}

// Both transform passes retain the coefficient orientation and signed rounding.
#test
{
    const Block:   [16] s32 = [1024, -237, -2048, 13, -53, 2047, -69, 1, -32768, 0, 32767, -317, 30, 7, 223, -18]
    const Samples: [16] s32 = [327, -10038, -10607, -673, -18, 11366, 11366, -451, -363, 11096, 11464, 156, -821, -10491, -10100, 491]
    const Dc:      [16] s32 = [489, -15057, -15911, -1009, -28, 17048, 17049, -676, -545, 16643, 17195, 234, -1232, -15736, -15150, 735]
    var samples = Block
    RealVideo.inverseTransform(&samples, false)
    for actual, index in samples
    {
        Swag.require(actual == Samples[index])
    }

    var dc = Block
    RealVideo.inverseTransform(&dc, true)
    for actual, index in dc
    {
        Swag.require(actual == Dc[index])
    }
}

// The DC-only reconstruction shares the full transform's rounding and clips the same pixels.
#test
{
    var prediction: [28] u8
    for &sample, index in prediction
    {
        sample[] = cast(u8, (index * 47 & 255))
    }

    for dc in [-32768_s32, -1532, -511, -4, -3, 0, 3, 4, 511, 1532, 32767]
    {
        var reference = prediction
        var direct    = prediction
        var block: [16] s32
        block[0] = dc
        RealVideo.addResidual(reference.buffer, 7, &block)
        RealVideo.addDcResidual(direct.buffer, 7, dc)
        Swag.require(Memory.compare(reference.buffer, direct.buffer, prediction.count) == 0)
    }
}

// Every table edge preserves either its target row or its decoded leaf value.
#test
{
    Swag.require(#sizeof(RealVideo.CodeTree) * 2 == #sizeof(RealVideo.CodeTree32))
    for original, index in RealVideo.CodeTree32
    {
        let encoded = cast(s32, RealVideo.CodeTree[index])
        if original < 0
        {
            Swag.require(encoded >= 0xF000 and (encoded ^ 0xFFFF) == -original - 1)
        }
        else
        {
            Swag.require(encoded < 0xF000 and encoded * 2 == original)
        }
    }
}

// The packed reader and its short tail agree at an unaligned byte boundary.
#test
{
    const Bytes: [8] u8 = [0xDE, 0xAD, 0xBE, 0xEF, 0x56, 0xAB, 0x33, 0]
    for size in [6_u64, 8]
    {
        var bits = RealVideo.Bits.open(Bytes[until size])
        Swag.require(bits.read(4) == 0xD)
        Swag.require(bits.read(32) == 0xEADBEEF5)
        Swag.require(bits.read(12) == 0x6AB)
        if size == 8
        {
            Swag.require(bits.read(16) == 0x3300)
        }

        Swag.require(bits.read(0) == 0 and not bits.broken)
        Swag.require(bits.read(1) == 0 and bits.broken)
    }

    // PType[0] decodes a single set bit as symbol zero, including at the end of a slice.
    const Prefix: [2] u8 = [1, 0]
    for size in [1_u64, 2]
    {
        var bits = RealVideo.Bits.open(Prefix[until size])
        Swag.require(bits.read(7) == 0)
        Swag.require(bits.code(RealVideo.PType[0]) == 0 and not bits.broken)
        Swag.require(bits.position == 8)
    }
}

// A late RealVideo clock correction must not renumber a picture the caller already received.
#test
{
    var stream: RealVideo.Stream
    stream.frames.add([SampleEntry{0, 1, 0, true}, SampleEntry{1, 1, 80, false}])
    stream.rebuildOrder()

    // Model the stream after ranks 0 and 1 were returned from the two-sample window.
    stream.nextRank       = 2
    stream.emitRank       = 2
    stream.nextDecode     = 2
    stream.maxEmittedTime = 80
    stream.hasEmittedTime = true

    const LateClock: [1] SampleEntry = [SampleEntry{2, 1, 40, false}]
    var error: Swag.Error
    discard catch stream.appendFrames(LateClock) as error
    Swag.require(error.value() is InvalidFormatError)
    Swag.require(stream.frames.count == 2 and stream.nextRank == 2)

    // Equal timestamps are stable-appended after existing ranks and do not invalidate them.
    const EqualClock: [1] SampleEntry = [SampleEntry{2, 1, 80, false}]
    expect stream.appendFrames(EqualClock)
    Swag.require(stream.sampleAtRank[0] == 0 and stream.sampleAtRank[1] == 1)
    Swag.require(stream.nextRank == 2)
}

// A player behind its clock jumps forward to the next clean picture, never back to the last one.
#test
{
    var reader = expect Reader.open(videoFixturePath("rv40-ipb.mkv"), pictureOnly: true)
    var frame: PlanarFrame
    expect reader.decodeFramePlanesInto(&frame, 0)
    for expected, index in [0_u64, 4, 4, 4, 4, 8, 8, 8, 8, 9]
    {
        Swag.require(reader.syncFrameAt(index) == expected)
    }
}

func realVideoClockPacket(timestamp, kind: u32)->[13] u8
{
    var result: #returntype
    result[1] = 1
    let header = (kind << 29) | (timestamp << 6)
    for i in 4_u32
    {
        result[9 + i] = cast(u8, ((header >> (24 - i * 8)) & 255))
    }

    return result
}

// The 13-bit clock wraps independently of the container epoch and survives header stripping.
#test
{
    var clock: RealVideo.Clock
    let first     = realVideoClockPacket(8190, 0)
    let next      = realVideoClockPacket(30, 2)
    let between   = realVideoClockPacket(10, 3)
    let firstTime = expect clock.presentationTime(first, first[0 until 0], 1_000_000_000)
    let nextTime  = expect clock.presentationTime(next, first[0 until 0], 1_032_000_000)
    Swag.require(firstTime == 1_000_000_000 and nextTime == 1_032_000_000)
    let actual = expect clock.presentationTime(between[9 until 13], between[0 until 9], 1_033_000_000)
    Swag.require(actual == 1_012_000_000)
}

// A wrapped B-picture clock cannot move an already minimal container timestamp below s64.
#test
{
    var clock: RealVideo.Clock
    let anchor = realVideoClockPacket(0, 0)
    let behind = realVideoClockPacket(8191, 3)
    discard expect clock.presentationTime(anchor, anchor[0 until 0], Swag.S64.Min)

    var error: Swag.Error
    discard catch clock.presentationTime(behind, behind[0 until 0], Swag.S64.Min) as error
    Swag.require(error.value() is InvalidFormatError)
}

// Truncated entropy data fails normally, and a decoder can restart at the next intact I picture.
#test
{
    let bytes  = expect File.readAllBytes(videoFixturePath("rv40-ipb.mkv"))
    var source = ByteSource.openMemory(bytes.toSlice())
    var container: Matroska.Decoder
    let api:       IDecoder = &container
    discard expect api.open(&source)
    let entry  = container.video.realvideo.frames[0]
    let packet = bytes.toSlice()[entry.offset until entry.offset + entry.size]
    var decoder: RealVideo.Decoder
    expect decoder.configure(96, 64)
    var frame: PlanarFrame
    for length in [0_u64, 1, 9, 14, packet.count / 2]
    {
        var error: Swag.Error
        catch decoder.decode(packet[0 until length], &frame) as error
        Swag.require(error.value() is InvalidFormatError)
        expect decoder.decode(packet, &frame)
        Swag.require(frame.width == 96 and frame.height == 64)
    }

    let predicted = container.video.realvideo.frames[1]
    decoder.reset()
    var missingReference: Swag.Error
    catch decoder.decode(bytes.toSlice()[predicted.offset until predicted.offset + predicted.size], &frame) as missingReference
    Swag.require(missingReference.value() is InvalidFormatError)
}

// Two slices use the packet framing found in Matroska RealVideo tracks.
#test
{
    const bytes: [22] u8 = [1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 10, 11, 20, 21, 22]
    let packet = expect RealVideo.Packet.open(bytes)
    Swag.require(packet.offsets.count == 2)
    Swag.require(packet.slice(0) == bytes[17 until 19])
    Swag.require(packet.slice(1) == bytes[19 until 22])

    const bigEndian: [11] u8 = [0, 0, 0, 0, 1, 0, 0, 0, 0, 42, 43]
    let bigPacket = expect RealVideo.Packet.open(bigEndian)
    Swag.require(bigPacket.slice(0) == bigEndian[9 until 11])
}

// Reject truncation, invalid markers, and offsets that cannot delimit slices.
#test
{
    const empty:     [1] u8  = [0]
    const short:     [2] u8  = [0, 1]
    const marker:    [10] u8 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 42]
    const offset:    [10] u8 = [0, 1, 0, 0, 0, 1, 0, 0, 0, 42]
    const backwards: [19] u8 = [1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 42, 43]
    for bytes in [empty[0 until 0], short[0 until 2], marker[0 until 10], offset[0 until 10], backwards[0 until 19]]
    {
        var error: Swag.Error
        discard catch RealVideo.Packet.open(bytes) as error
        Swag.require(error.value() != null)
    }
}
