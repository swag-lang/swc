#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors

const Width        = 80
const Height       = 50
const Luma         = Width * Height
const Chroma       = Luma / 4
const PictureBytes = Luma + 2 * Chroma

func requireReferencePicture(reader: *Reader, picture: *PlanarFrame, bytes: const [..] u8, index: u64)
{
    expect reader.decodeFramePlanesInto(picture, index)
    let offset = index * PictureBytes
    Swag.require(picture.width == Width and picture.height == Height)
    Swag.require(picture.luma.count == Luma and
                 picture.chromaB.count == Chroma and
                 picture.chromaR.count == Chroma)
    Swag.require(Memory.compare(picture.luma.storage(), bytes.buffer + offset, Luma) == 0)
    Swag.require(Memory.compare(picture.chromaB.storage(), bytes.buffer + offset + Luma, Chroma) == 0)
    Swag.require(Memory.compare(picture.chromaR.storage(), bytes.buffer + offset + Luma + Chroma, Chroma) == 0)
}

// Twelve pictures with three slices each, two IDR groups, and no access unit delimiters.
// The fixture's B pictures are out of decode order.
#test
{
    Swag.require(Reader.canOpen("capture.H264") and Reader.canOpen("capture.264"))
    var reader = expect Reader.open(videoFixturePath("ffmpeg-h264-annexb.h264"))
    let rate   = reader.frameRate()
    Swag.require(reader.hasPlanarFrames() and reader.frameCount() == 12)
    Swag.require(rate.numerator() == 30_000 and rate.denominator() == 1001)
    Swag.require(reader.syncFrameAt(0) == 0 and reader.syncFrameAt(1) == 6 and reader.syncFrameAt(7) == 12)
    Swag.require(Math.abs(reader.frameTimestamp(11) - 11 * 1001.0 / 30_000) < 0.000_000_01)
    Swag.require(reader.frameAtTime(0.201) == 6)

    let expected = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-annexb.yuv"))
    var picture: PlanarFrame
    for index in reader.frameCount()
    {
        requireReferencePicture(&reader, &picture, expected.toSlice(), index)
    }
}

#test
{
    let source   = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-annexb.h264"))
    let expected = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-annexb.yuv"))
    var reader   = expect Reader.openMemory("capture.264", source.toSlice())
    var picture: PlanarFrame
    for index in [8_u64, 0, 11, 6, 5, 1]
    {
        requireReferencePicture(&reader, &picture, expected.toSlice(), index)
    }

    var rejected: Swag.Error
    discard catch reader.decodeFramePlanesInto(&picture, 12) as rejected
    Swag.require(rejected.value() is BadParameterError)
}

#test
{
    let invalidPrefix: [5] u8 = [4, 0, 0, 1, 7]
    let emptyNal:      [6] u8 = [0, 0, 1, 0, 0, 1]
    let forbiddenBit:  [5] u8 = [0, 0, 1, 0x87, 0x80]
    var rejected:      Swag.Error
    for bytes in [invalidPrefix[until invalidPrefix.count], emptyNal[until emptyNal.count], forbiddenBit[until forbiddenBit.count]]
    {
        discard catch Reader.openMemory("invalid.h264", bytes) as rejected
        Swag.require(rejected.value() is InvalidFormatError)
    }

    var truncated = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-annexb.h264"))
    truncated.add([0_u8, 0, 0, 1])
    discard catch Reader.openMemory("truncated.h264", truncated.toSlice()) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
}

// The index only reads slice headers. Decoding still requires every slice of the last picture.
#test
{
    let bytes  = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-annexb.h264"))
    var source = ByteSource.openMemory(bytes.toSlice())
    var scanner: AnnexBScanner
    expect scanner.open(&source)

    var last: AnnexBNal
    while expect scanner.next(&source, &last) {}

    var reader = expect Reader.openMemory("partial-picture.h264", bytes.toSlice()[until last.start])
    Swag.require(reader.frameCount() == 12)
    var picture:  PlanarFrame
    var rejected: Swag.Error
    // The final coded access unit is a B picture displayed before the final P picture.
    discard catch reader.decodeFramePlanesInto(&picture, 10) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
}

// A sequence without VUI has the same decoded pictures on the fallback clock.
#test
{
    var reader   = expect Reader.open(videoFixturePath("ffmpeg-h264-annexb-no-vui.h264"))
    let expected = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-annexb.yuv"))
    let rate     = reader.frameRate()
    Swag.require(rate.numerator() == 25 and rate.denominator() == 1)
    Swag.require(reader.frameCount() == 12 and reader.frameAtTime(0.241) == 6)

    var picture: PlanarFrame
    requireReferencePicture(&reader, &picture, expected.toSlice(), 6)
    requireReferencePicture(&reader, &picture, expected.toSlice(), 0)
}

// An SPS with a different definition invalidates a fixed-configuration index.
#test
{
    var bytes     = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-annexb.h264"))
    let alternate = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-annexb-no-vui.h264"))
    var source    = ByteSource.openMemory(alternate.toSlice())
    var scanner: AnnexBScanner
    expect scanner.open(&source)

    var unit: AnnexBNal
    var found = false
    while expect scanner.next(&source, &unit)
    {
        if (alternate[unit.payload] & 31) == 7
        {
            bytes.add(alternate.toSlice()[unit.start until unit.payload + unit.size])
            found = true
            break
        }
    }

    Swag.require(found)
    var rejected: Swag.Error
    discard catch Reader.openMemory("changing.h264", bytes.toSlice()) as rejected
    Swag.require(rejected.value() is UnsupportedFormatError)
}

// A start code's zero run and terminating one can lie in different file windows.
#test
{
    const Boundary = ByteSource.WindowSize
    var bytes: Array!{u8}
    bytes.resize(Boundary + 4)
    Memory.set(bytes.storage(), 0x55, bytes.count)
    bytes[0]            = 0
    bytes[1]            = 0
    bytes[2]            = 1
    bytes[Boundary - 2] = 0
    bytes[Boundary - 1] = 0
    bytes[Boundary]     = 1
    bytes[Boundary + 2] = 0
    bytes[Boundary + 3] = 0

    let path = videoTempPath("annexb-window", "h264")
    expect File.writeAllBytes(path, bytes.toSlice())
    defer catch File.delete(path)

    var source = expect ByteSource.openFile(path)
    var scanner: AnnexBScanner
    expect scanner.open(&source)
    var unit: AnnexBNal
    Swag.require(expect scanner.next(&source, &unit))
    Swag.require(unit.start == 0 and unit.payload == 3 and unit.size == Boundary - 5)

    expect source.seek(2)
    Swag.require(expect scanner.next(&source, &unit))
    Swag.require(unit.start == Boundary - 2 and unit.payload == Boundary + 1 and unit.size == 1)
    Swag.require(not (expect scanner.next(&source, &unit)))
}
