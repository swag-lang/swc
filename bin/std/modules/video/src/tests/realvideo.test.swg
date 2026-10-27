#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors

func realVideoCompareFrame(reader: *Reader, reference: const [..] u8, index: u64)
{
    var frame: PlanarFrame
    let size = 96'u64 * 64 * 3 / 2
    expect reader.decodeFramePlanesInto(&frame, index)
    Swag.assert(frame.width == 96 and frame.height == 64)
    var offset = index * size
    for bytes in [frame.luma.toSlice(), frame.chromaB.toSlice(), frame.chromaR.toSlice()]
    {
        for actual, at in bytes
        {
            if actual != reference[offset + at]
            {
                Console.println("frame ", index, " sample ", offset + at - index * size, " actual ", actual, " expected ", reference[offset + at])
                Swag.assert(false)
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
    let reference = expect File.readAllBytes(Path.combine(unwrap Path.directoryName(#curlocation.fileName), Format.toString("goldens/%.yuv", golden)))
    let count     = reference.count / (96 * 64 * 3 / 2)
    var reader    = expect Reader.open(path, pictureOnly: true)
    for index in count do
        realVideoCompareFrame(&reader, reference.toSlice(), index)
    for step in count do
        realVideoCompareFrame(&reader, reference.toSlice(), count - step - 1)

    let bytes  = expect File.readAllBytes(path)
    var memory = expect Reader.openMemory(path, bytes.toSlice(), pictureOnly: true)
    for index in [count - 1, 0, count / 2, 1] do
        realVideoCompareFrame(&memory, reference.toSlice(), index)
    Swag.assert(memory.frameCount() == count)
    for index in count do
        Swag.assert(Math.isEqualEpsilon(memory.frameTimestamp(index), cast(f64, index) / 25, 0.000001))
}

#test { realVideoCompare("rv40-intra") }
#test { realVideoCompare("rv40-ipb") }
#test { realVideoCompare("rv40-adaptive") }
#test { realVideoCompare("rv40-legacy-clock") }
#test { realVideoCompare("rv40-slices") }

// A player behind its clock jumps forward to the next clean picture, never back to the last one.
#test
{
    var reader = expect Reader.open(videoFixturePath("rv40-ipb.mkv"), pictureOnly: true)
    var frame: PlanarFrame
    expect reader.decodeFramePlanesInto(&frame, 0)
    for expected, index in [0'u64, 4, 4, 4, 4, 8, 8, 8, 8, 9] do
        Swag.assert(reader.syncFrameAt(index) == expected)
}

func realVideoClockPacket(timestamp, kind: u32)->[13] u8
{
    var result: #returntype
    result[1] = 1
    let header = (kind << 29) | (timestamp << 6)
    for i in 4'u32 do
        result[9 + i] = cast(u8, ((header >> (24 - i * 8)) & 255))
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
    Swag.assert(firstTime == 1_000_000_000 and nextTime == 1_032_000_000)
    let actual = expect clock.presentationTime(between[9 until 13], between[0 until 9], 1_033_000_000)
    Swag.assert(actual == 1_012_000_000)
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
    for length in [0'u64, 1, 9, 14, packet.count / 2]
    {
        var error: Swag.Error
        catch decoder.decode(packet[0 until length], &frame) as error
        Swag.assert(error.value() is InvalidFormatError)
        expect decoder.decode(packet, &frame)
        Swag.assert(frame.width == 96 and frame.height == 64)
    }

    let predicted = container.video.realvideo.frames[1]
    decoder.reset()
    var missingReference: Swag.Error
    catch decoder.decode(bytes.toSlice()[predicted.offset until predicted.offset + predicted.size], &frame) as missingReference
    Swag.assert(missingReference.value() is InvalidFormatError)
}

// Two slices use the packet framing found in Matroska RealVideo tracks.
#test
{
    const bytes: [22] u8 = [1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 10, 11, 20, 21, 22]
    let packet = expect RealVideo.Packet.open(bytes)
    Swag.assert(packet.offsets.count == 2)
    Swag.assert(packet.slice(0) == bytes[17 until 19])
    Swag.assert(packet.slice(1) == bytes[19 until 22])

    const bigEndian: [11] u8 = [0, 0, 0, 0, 1, 0, 0, 0, 0, 42, 43]
    let bigPacket = expect RealVideo.Packet.open(bigEndian)
    Swag.assert(bigPacket.slice(0) == bigEndian[9 until 11])
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
        Swag.assert(error.value() != null)
    }
}
