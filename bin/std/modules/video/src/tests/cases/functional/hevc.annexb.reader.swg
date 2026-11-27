#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors

const Width        = 96
const Height       = 64
const Luma         = Width * Height
const Chroma       = Luma / 4
const PictureBytes = Luma + 2 * Chroma

func expectReferencePlane(actual: const [..] u8, reference: const [*] u8, bytesPerSample: u64)
{
    if bytesPerSample == 1
    {
        Swag.require(Memory.compare(actual.buffer, reference, actual.count) == 0)
        return
    }

    for index in actual.count
    {
        let offset = index * 2
        let value  = cast(u32, reference[offset]) | (cast(u32, reference[offset + 1]) << 8)
        let sample = cast(u8, Math.min((value + 2) >> 2, 255_u32))
        Swag.require(actual[index] == sample)
    }
}

func expectReferencePicture(reader: *Reader, picture: *PlanarFrame, bytes: const [..] u8, index: u64, bytesPerSample: u64)
{
    expect reader.decodeFramePlanesInto(picture, index)
    let offset = index * PictureBytes * bytesPerSample
    Swag.require(picture.width == Width and picture.height == Height)
    Swag.require(picture.luma.count == Luma and
                 picture.chromaB.count == Chroma and
                 picture.chromaR.count == Chroma)
    expectReferencePlane(picture.luma.toSlice(), bytes.buffer + offset, bytesPerSample)
    expectReferencePlane(picture.chromaB.toSlice(), bytes.buffer + offset + Luma * bytesPerSample, bytesPerSample)
    expectReferencePlane(picture.chromaR.toSlice(), bytes.buffer + offset + (Luma + Chroma) * bytesPerSample, bytesPerSample)
}

// Main 10 with B pictures, two IDR groups and no access unit delimiters.
#test
{
    Swag.require(Reader.canOpen("capture.HEVC") and Reader.canOpen("capture.h265"))
    var reader = expect Reader.open(videoFixturePath("ffmpeg-hevc-annexb-main10.hevc"))
    Swag.require(reader.hasPlanarFrames() and reader.frameCount() == 12)
    Swag.require(reader.frameRate() == expect FrameRate.create(30_000, 1001))
    Swag.require(reader.syncFrameAt(0) == 0 and reader.syncFrameAt(1) == 6 and reader.syncFrameAt(7) == 12)
    Swag.require(Math.abs(reader.frameTimestamp(11) - 11 * 1001.0 / 30_000) < 0.000_000_01)
    Swag.require(reader.frameAtTime(0.201) == 6)

    let expected = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-annexb-main10.yuv"))
    Swag.require(expected.count == reader.frameCount() * PictureBytes * 2)
    var picture: PlanarFrame
    for index in reader.frameCount()
    {
        expectReferencePicture(&reader, &picture, expected.toSlice(), index, 2)
    }
}

#test
{
    let bytes    = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-annexb-main10.hevc"))
    let expected = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-annexb-main10.yuv"))
    var reader   = expect Reader.openMemory("capture.h265", bytes.toSlice())
    var picture: PlanarFrame
    for index in [8_u64, 0, 11, 6, 5, 1]
    {
        expectReferencePicture(&reader, &picture, expected.toSlice(), index, 2)
    }

    var rejected: Swag.Error
    discard catch reader.decodeFramePlanesInto(&picture, 12) as rejected
    Swag.require(rejected.value() is BadParameterError)
}

// Two independent slices per Main picture, with AUD and no VUI timing.
#test
{
    var reader   = expect Reader.open(videoFixturePath("ffmpeg-hevc-annexb-main.hevc"))
    let expected = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-annexb-main.yuv"))
    Swag.require(reader.frameCount() == 5 and reader.frameAtTime(0.121) == 3)
    Swag.require(reader.frameRate() == expect FrameRate.create(25, 1))
    Swag.require(expected.count == reader.frameCount() * PictureBytes)

    var picture: PlanarFrame
    for index in reader.frameCount()
    {
        expectReferencePicture(&reader, &picture, expected.toSlice(), index, 1)
    }
}

#test
{
    let openGop = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-annexb-open-gop.hevc"))
    var rejected: Swag.Error
    discard catch Reader.openMemory("open.hevc", openGop.toSlice()) as rejected
    Swag.require(rejected.value() is UnsupportedFormatError)
    Swag.require(Core.Errors.message(rejected.value()) == "H.265 Annex B stream requires closed IDR groups")
}

#test
{
    let incomplete: [5] u8 = [0, 0, 1, 0x40, 1]
    let forbidden:  [6] u8 = [0, 0, 1, 0xC0, 1, 0x80]
    let temporal:   [6] u8 = [0, 0, 1, 0x40, 0, 0x80]
    var rejected:   Swag.Error
    for bytes in [incomplete[until incomplete.count], forbidden[until forbidden.count], temporal[until temporal.count]]
    {
        discard catch Reader.openMemory("invalid.hevc", bytes) as rejected
        Swag.require(rejected.value() is InvalidFormatError)
    }
}

// A new SPS changes both nominal timing and sample depth in this stream.
#test
{
    var bytes     = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-annexb-main10.hevc"))
    let alternate = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-annexb-main.hevc"))
    var source    = ByteSource.openMemory(alternate.toSlice())
    var scanner: AnnexBScanner
    expect scanner.open(&source)
    var unit: AnnexBNal
    while expect scanner.next(&source, &unit)
    {
        if alternate[unit.payload] >> 1 == Hevc.NalSps
        {
            bytes.add(alternate.toSlice()[unit.start until unit.payload + unit.size])
            break
        }
    }

    var rejected: Swag.Error
    discard catch Reader.openMemory("changing.hevc", bytes.toSlice()) as rejected
    Swag.require(rejected.value() is UnsupportedFormatError)
    Swag.require(Core.Errors.message(rejected.value()) == "H.265 Annex B stream changes its parameter sets")
}

func expectNativePicture(picture: *Hevc.Frame, reference: const [..] u8, rank: u64)
{
    Swag.require(picture.bitDepth == 10)
    var offset = rank * PictureBytes * 2
    for component in 3
    {
        let width  = component == 0 ? Width : Width / 2
        let height = component == 0 ? Height : Height / 2
        let stride = component == 0 ? picture.strideLuma : picture.strideChroma
        let plane  = component == 0 ? picture.luma.storage() : (component == 1 ? picture.chromaB.storage() : picture.chromaR.storage())
        let start  = cast(u64, Hevc.FramePadding) * (stride + 1)
        for y in height
        {
            let row = plane + start + y * stride
            for x in width
            {
                let expected = cast(u16, reference[offset]) | (cast(u16, reference[offset + 1]) << 8)
                Swag.require(row[x] == expected)
                offset += 2
            }
        }
    }

    // This harness has consumed the picture. Only reference use can keep it alive.
    picture.outputNeeded = false
}

// Compare the unreduced samples as well as the public planar output above.
#test
{
    let bytes     = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-annexb-main10.hevc"))
    let reference = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-annexb-main10.yuv"))
    var source    = ByteSource.openMemory(bytes.toSlice())
    var scanner: AnnexBScanner
    expect scanner.open(&source)

    var decoder: Hevc.Decoder
    var unit:    AnnexBNal
    var count = 0_u64
    var first = 0_u64
    while expect scanner.next(&source, &unit)
    {
        let started = expect decoder.readNalUnit(bytes.toSlice()[unit.payload until unit.payload + unit.size])
        if started and decoder.finishedFrame
        {
            let picture = decoder.finishedFrame
            if picture.isIrap
            {
                first = count
            }

            expectNativePicture(picture, reference.toSlice(), first + cast(u64, picture.poc))
            decoder.finishedFrame = null
            count += 1
        }
    }

    let last = unwrap expect decoder.finishPicture()
    expectNativePicture(last, reference.toSlice(), first + cast(u64, last.poc))
    Swag.require(count + 1 == 12)
}
