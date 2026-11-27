#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

const Fixture           = "synthetic-concatenated.mjpeg"
const Width             = 37_s32
const Height            = 29_s32
const FrameCount        = 5_u64
const FrameBytes        = cast(u64, Width * Height * 3)
const FirstPictureBytes = 2127_u64

func readReference()->Array!{u8} fail
{
    return try File.readAllBytes(Path.combine(testSourceRoot(#curlocation), "goldens", "synthetic-concatenated.rgb"))
}

func checkPicture(picture: const *Image, expected: const [..] u8, index: u64)
{
    Swag.require(picture.width == Width and picture.height == Height)
    Swag.require(picture.pixelFormat == .RGB8 and picture.pixels.count == FrameBytes)
    let reference = expected[index * FrameBytes until (index + 1) * FrameBytes]
    for channel, position in picture.pixels
    {
        // The RGB implementations use different integer IDCT and conversion rounding.
        Swag.require(Math.abs(cast(s32, channel) - reference[position]) <= 4)
    }
}

#test
{
    var reader = expect Reader.open(videoFixturePath(Fixture))
    Swag.require(reader.width() == Width and reader.height() == Height)
    Swag.require(reader.streamInfo().codecName == "Motion JPEG")
    Swag.require(reader.frameRate() == expect FrameRate.create(25, 1))
    Swag.require(reader.frameCount() == FrameCount)
    Swag.require(reader.audioTrackCount() == 0 and reader.subtitleTrackCount() == 0)
    Swag.require(not reader.hasPlanarFrames())
    Swag.require(Math.isEqualEpsilon(reader.durationInSeconds(), 0.20, 0.000001))
    Swag.require(reader.frameAtTime(0.20) == FrameCount)
    Swag.require(reader.syncFrameAt(Swag.U64.Max) == FrameCount)

    let reference = expect readReference()
    Swag.require(reference.count == FrameCount * FrameBytes)
    var picture: Image
    expect reader.decodeFrameInto(&picture, 0)
    let storage = picture.pixels.storage()
    for index in FrameCount
    {
        let timestamp = reader.frameTimestamp(index)
        Swag.require(Math.isEqualEpsilon(timestamp, cast(f64, index) * 0.04, 0.000001))
        Swag.require(reader.frameAtTime(timestamp) == index and reader.syncFrameAt(index) == index)
        expect reader.decodeFrameInto(&picture, index)
        Swag.require(picture.pixels.storage() == storage)
        checkPicture(&picture, reference.toSlice(), index)
    }

    var error: Swag.Error
    catch reader.decodeFrameInto(&picture, FrameCount) as error
    Swag.require(error.value() is BadParameterError)
}

#test
{
    let bytes     = expect File.readAllBytes(videoFixturePath(Fixture))
    let reference = expect readReference()
    var reader    = expect Reader.openMemory("clip.MJPG", bytes.toSlice(), pictureOnly: true)
    var picture: Image
    for index in [4_u64, 0, 2, 1, 3, 3]
    {
        expect reader.decodeFrameInto(&picture, index)
        checkPicture(&picture, reference.toSlice(), index)
    }

    let key = expect reader.decodeKeyPicture(0.125)
    checkPicture(&key, reference.toSlice(), 3)
}

#test
{
    let bytes     = expect File.readAllBytes(videoFixturePath(Fixture))
    let reference = expect readReference()
    let path      = videoTempPath("mjpeg-window", "mjpg")
    defer discard catch File.delete(path)

    // Put a header marker and then the first EOI on a source-window boundary. In both cases
    // the prefix byte is in one window and its code in the next one.
    for markerOffset in [2_u64, FirstPictureBytes - 2]
    {
        let inserted = ByteSource.WindowSize - 1 - markerOffset
        let length   = inserted - 2
        var padded: Array!{u8}
        padded.resize(inserted + 2)
        padded[0] = 0xFF
        padded[1] = 0xD8
        padded[2] = 0xFF
        padded[3] = 0xE8
        padded[4] = cast(u8, length >> 8)
        padded[5] = cast(u8, length & 255)
        padded[6] = 0xFF
        padded[7] = 0xD9
        padded.add(bytes.toSlice()[2 to])
        discard expect File.writeAllBytes(path, padded.toSlice())

        var reader = expect Reader.open(path)
        Swag.require(reader.frameCount() == FrameCount)
        var picture: Image
        for index in [4_u64, 0]
        {
            expect reader.decodeFrameInto(&picture, index)
            checkPicture(&picture, reference.toSlice(), index)
        }
    }
}

#test
{
    func reject(bytes: const [..] u8)
    {
        var error: Swag.Error
        discard catch Reader.openMemory("broken.mjpeg", bytes) as error
        Swag.require(error.value() is InvalidFormatError)
    }

    let bytes = expect File.readAllBytes(videoFixturePath(Fixture))
    let input = bytes.toSlice()
    reject(input[until 0])
    reject(input[until 1])
    reject(input[until input.count - 1])
    reject(input[1 to])

    var damaged: Array!{u8}
    damaged.add(input[until FirstPictureBytes - 2])
    damaged.add(input[FirstPictureBytes to])
    reject(damaged.toSlice())

    damaged.clear()
    damaged.add(input)

    // The first APP9 segment length includes its own two bytes.
    damaged[4] = 0
    damaged[5] = 1
    reject(damaged.toSlice())
    damaged[4] = 0xFF
    damaged[5] = 0xFF
    reject(damaged.toSlice())

    damaged[4] = input[4]
    damaged[5] = input[5]
    let second = Slice.findSubslice(input[FirstPictureBytes to], [0xFF_u8, 0xC0])
    Swag.require(second < input.count - FirstPictureBytes)
    damaged[FirstPictureBytes + second + 8] = cast(u8, Width + 1)
    var error: Swag.Error
    discard catch Reader.openMemory("variable.mjpeg", damaged.toSlice()) as error
    Swag.require(error.value() is UnsupportedFormatError)
}
