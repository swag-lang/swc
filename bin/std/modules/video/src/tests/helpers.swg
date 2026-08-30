#global if #command == Swag.CompilerCommand.Test

using Core, Pixel

// Returns the path of a fixture of this test suite.
func videoFixturePath(name: string)->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, Format.toString("datas/%", name).toString())
}

// Returns a unique path in the temporary directory, for a stream a test writes itself.
//
// `extension` carries no leading dot; it is what selects the codec the stream is written with.
func videoTempPath(name, extension: string)->String
{
    let directory = Env.getSpecialDirectory(.Temp)
    return Path.combine(directory.toString(), Format.toString("video-%-%.%", name, Guid64.random(), extension).toString())
}

func videoTestImage(width, height: s32, pixels: const [..] u8)->Image
{
    return Image.create(width, height, .RGB8, pixels)
}

// Returns an image whose every channel holds `value`, which encodes to a neutral frame.
func videoGrayImage(width, height: s32, value: u8)->Image
{
    var result: retval = Image.create(width, height, .RGB8)
    Memory.set(result.pixels.buffer!, value, result.pixels.count)
    return result
}

// Returns one YUV4MPEG2 4:2:0 payload of a flat frame of luma `luma`.
func videoFlatPayload(width, height: s32, luma: u8)->Array'u8
{
    let lumaSize = cast(u64) width * cast(u64) height

    var result: retval
    result.resize(lumaSize + lumaSize / 2)
    Memory.set(result.buffer!, luma, lumaSize)
    Memory.set(result.buffer! + lumaSize, 128, lumaSize / 2)
    return result
}

// Returns the value the limited-range BT.601 conversion produces for a neutral `luma`.
//
// It is the decoder's own arithmetic, written out: a test that reused the module's conversion
// would agree with it whatever it computed.
func videoLumaToGray(luma: u8)->s32
{
    let c = Math.max(cast(s32) luma - 16, 0)
    return Math.clamp((298 * c + 128) >> 8, 0, 255)
}

// Returns the neutral value a frame of `value` decodes back to once encoded.
//
// The encoder converts to limited-range BT.601 luma and the decoder converts back, so the two
// roundings are what the test compares against, not the value that was written.
func videoGrayRoundTrip(value: u8)->s32
{
    let luma = ((220 * cast(s32) value + 128) >> 8) + 16
    return videoLumaToGray(cast(u8) Math.clamp(luma, 0, 255))
}

func videoAssertColor(actual: Color, r, g, b: u8, tolerance = 3)
{
    Swag.assert(Math.abs(cast(s32) actual.r - r) <= tolerance)
    Swag.assert(Math.abs(cast(s32) actual.g - g) <= tolerance)
    Swag.assert(Math.abs(cast(s32) actual.b - b) <= tolerance)
}

func videoAssertGray(actual: Color, value: s32, tolerance = 3)
{
    videoAssertColor(actual, cast(u8) value, cast(u8) value, cast(u8) value, tolerance)
}

// One point of a fixture frame, and the colour it must hold.
//
// The `datas/ffmpeg-*` and `datas/edited-*` clips all show the same picture: three quadrants of
// fixed colour, which prove the frame was not turned over or transposed, and a fourth neutral
// one whose level identifies the frame. A seek landing on the wrong frame therefore cannot pass,
// and neither can a row order read backwards.
struct VideoFixtureSample
{
    x, y:    s32
    r, g, b: u8
}

// Returns the neutral level identifying frame `index` of a fixture clip.
func videoFixtureGray(index: u64)->s32 => cast(s32) (20 + 20 * index)

// Returns the four points frame `index` of a fixture of that geometry must hold.
func videoFixtureSamples(width, height: s32, index: u64)->[4] VideoFixtureSample
{
    let left   = width / 4
    let right  = width - width / 4
    let top    = height / 4
    let bottom = height - height / 4
    let gray   = cast(u8) videoFixtureGray(index)
    return [{left, top, 255, 0, 0},
            {right, top, 0, 255, 0},
            {left, bottom, 0, 0, 255},
            {right, bottom, gray, gray, gray}]
}

// Asserts that `frame` is frame `index` of a fixture clip.
func videoAssertFixtureFrame(frame: Image, index: u64, tolerance = 3)
{
    Swag.assert(frame.isValid())
    for sample in videoFixtureSamples(frame.width, frame.height, index) do
        videoAssertColor(frame.pixelColor(sample.x, sample.y), sample.r, sample.g, sample.b, tolerance)
}

// Asserts that `frame` is frame `index` of a fixture clip carrying luma alone.
//
// A monochrome stream keeps the luma of each quadrant and loses its colour, so the three fixed
// quadrants become the BT.601 luma of red, green and blue.
func videoAssertFixtureLumaFrame(frame: Image, index: u64, tolerance = 3)
{
    let samples = videoFixtureSamples(frame.width, frame.height, index)
    const Luma: [3] s32 = [76, 150, 29]
    for value, position in Luma do
        videoAssertGray(frame.pixelColor(samples[position].x, samples[position].y), value, tolerance)
    videoAssertGray(frame.pixelColor(samples[3].x, samples[3].y), videoFixtureGray(index), tolerance)
}

// Converts one frame of a raw 4:2:0 reference dump with the exact arithmetic the module's
// decoders use, so a correct H.264 decode matches it byte for byte.
func videoReferenceFrame(bytes: const [..] u8, index: u64, width, height: s32)->Image
{
    let lumaSize     = cast(u64) width * cast(u64) height
    let chromaWidth  = cast(u64) (width + 1) / 2
    let chromaHeight = cast(u64) (height + 1) / 2
    let chromaSize   = chromaWidth * chromaHeight
    let frameSize    = lumaSize + chromaSize * 2
    let base         = index * frameSize
    Swag.assert(base + frameSize <= bytes.count)

    var result: retval = Image.create(width, height, .RGB8)
    for y in height
    {
        let destinationRow = cast(u64) (height - y - 1) * cast(u64) result.rowStride
        for x in width
        {
            let luma         = cast(s32) bytes[base + cast(u64) y * cast(u64) width + cast(u64) x]
            let chromaSource = cast(u64) (y >> 1) * chromaWidth + cast(u64) (x >> 1)
            let d            = cast(s32) bytes[base + lumaSize + chromaSource] - 128
            let e            = cast(s32) bytes[base + lumaSize + chromaSize + chromaSource] - 128
            let c            = Math.max(luma - 16, 0)
            let destination  = result.pixels.buffer! + destinationRow + cast(u64) x * 3
            destination[0] = cast(u8) Math.clamp((298 * c + 409 * e + 128) >> 8, 0, 255)
            destination[1] = cast(u8) Math.clamp((298 * c - 100 * d - 208 * e + 128) >> 8, 0, 255)
            destination[2] = cast(u8) Math.clamp((298 * c + 516 * d + 128) >> 8, 0, 255)
        }
    }

    return result
}

// Compares a decoded frame against the reference, reporting the first difference.
func videoAssertReferenceFrame(frame: Image, reference: const [..] u8, index: u64, width, height: s32)
{
    Swag.assert(frame.width == width and frame.height == height and frame.pixelFormat == .RGB8)
    let expected   = videoReferenceFrame(reference, index, width, height)
    var mismatches = 0'u64
    for position in frame.pixels.count where frame.pixels.buffer![position] != expected.pixels.buffer![position] do
        mismatches += 1
    if mismatches > 0 do
        Swag.print("frame ", index, ": ", mismatches, " of ", frame.pixels.count, " bytes differ\n")
    Swag.assert(mismatches == 0)
}

// Decodes a whole stream in order and demands byte-exact frames.
//
// `container` carries no leading dot: it names the file beside `name.yuv` the stream is read from,
// so one reference dump serves every container the same access units were muxed into.
func videoAssertReferenceStream(name: string, width, height: s32, frameCount: u64, container = "mp4")
{
    if Jobs.isSynchronous() do
        discard expect Jobs.initialize(16)

    var reader = expect Reader.open(videoFixturePath(Format.toString("%.%", name, container).toString()))
    Swag.assert(reader.width() == width and reader.height() == height)

    let reference = expect File.readAllBytes(videoFixturePath(Format.toString("%.yuv", name).toString()).toString())
    var frame: Image
    for index in frameCount
    {
        expect reader.decodeFrameInto(&frame, index)
        videoAssertReferenceFrame(frame, reference.toSlice(), index, width, height)
    }

    // A progressive container only knows its length once the stream has been walked, so the count
    // is demanded here rather than at open.
    Swag.assert(reader.frameCount() == frameCount)
}
