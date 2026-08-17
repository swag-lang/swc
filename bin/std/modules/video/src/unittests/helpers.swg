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
    @assert(Math.abs(cast(s32) actual.r - r) <= tolerance)
    @assert(Math.abs(cast(s32) actual.g - g) <= tolerance)
    @assert(Math.abs(cast(s32) actual.b - b) <= tolerance)
}

func videoAssertGray(actual: Color, value: s32, tolerance = 3)
{
    videoAssertColor(actual, cast(u8) value, cast(u8) value, cast(u8) value, tolerance)
}
