#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// Converts one planar sample the way the packed path does, so the two outputs are comparable.
func planarPixel(picture: const *PlanarFrame, x, y: s32)->Color
{
    let luma = cast(s32) picture.luma[cast(u64) y * cast(u64) picture.strideLuma + cast(u64) x]
    let base = cast(u64) (y / 2) * cast(u64) picture.strideChroma + cast(u64) (x / 2)
    let d    = cast(s32) picture.chromaB[base] - 128
    let e    = cast(s32) picture.chromaR[base] - 128
    let c    = Math.max(luma - 16, 0) * 298

    return Color.fromRgb(cast(u8) Math.clamp((c + 409 * e + 128) >> 8, 0, 255),
                         cast(u8) Math.clamp((c - 100 * d - 208 * e + 128) >> 8, 0, 255),
                         cast(u8) Math.clamp((c + 516 * d + 128) >> 8, 0, 255))
}

// Asserts that the planar output of `reader` carries exactly the picture its packed output does.
//
// The two paths share every stage but the last, so comparing them sample by sample is what pins
// the plane geometry, the crop and the half-resolution chroma of the planar one. Which picture it
// is remains the business of `h264.test.swg`.
func assertPlanarMatchesPacked(reader: *Reader, index: u64)
{
    var picture: PlanarFrame
    expect reader.decodeFramePlanesInto(&picture, index)
    @assert(picture.isValid())
    @assert(picture.width == reader.width() and picture.height == reader.height())
    @assert(picture.strideLuma == cast(u32) reader.width())
    @assert(picture.strideChroma == cast(u32) ((reader.width() + 1) / 2))
    @assert(picture.chromaHeight() == (reader.height() + 1) / 2)
    @assert(picture.luma.count == cast(u64) picture.width * cast(u64) picture.height)

    var packed: Image
    expect reader.decodeFrameInto(&packed, index)
    for y in picture.height
    {
        for x in picture.width
        {
            let planar = planarPixel(&picture, x, y)
            let target = packed.pixelColor(x, y)
            @assert(planar.r == target.r and planar.g == target.g and planar.b == target.b)
        }
    }
}

// A High-profile stream hands its pictures over unconverted.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-h264-high.mp4"))
    @assert(reader.hasPlanarFrames())
    for index in 3'u64 do
        assertPlanarMatchesPacked(&reader, index)
}

// A cropped stream hands over the visible window, not the coded one.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-h264-crop.mp4"))
    @assert(reader.hasPlanarFrames())
    assertPlanarMatchesPacked(&reader, 0)
    assertPlanarMatchesPacked(&reader, 1)
}

// Motion JPEG rides in the same container and does not reconstruct planes, so the reader says so
// instead of pretending, and the call fails rather than answering an empty picture.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mjpeg.mp4"))
    @assert(!reader.hasPlanarFrames())

    var picture: PlanarFrame
    catch reader.decodeFramePlanesInto(&picture, 0) as planarError
    @assert(planarError != null)
}
