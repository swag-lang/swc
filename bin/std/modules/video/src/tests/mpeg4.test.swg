#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// Compares a decode against FFmpeg's, with the tolerance the format itself allows.
//
// Part 2 does not state a bit-exact inverse transform: clause A.1 requires only that a decoder
// stay within a stated accuracy, so two conforming decoders differ in the last level and the
// difference accumulates along a chain of predicted pictures. What a defect produces is not that:
// it is a block, a row, or a whole picture that is wrong. The measure is therefore the mean
// absolute difference over the sequence, plus a ceiling on any single sample.
func mpeg4AssertStream(name: string, container: string, width, height: s32, frameCount: u64, meanLimit: f64, worstLimit: s32)
{
    var reader = expect Reader.open(videoFixturePath(Format.toString("%.%", name, container).toString()))
    Swag.assert(reader.width() == width and reader.height() == height)

    let reference = expect File.readAllBytes(videoFixturePath(Format.toString("%.yuv", name).toString()).toString())
    let bytes     = reference.toSlice()
    let lumaSize  = cast(u64) width * cast(u64) height
    let chromaW   = cast(u64) ((width + 1) / 2)
    let chromaH   = cast(u64) ((height + 1) / 2)
    let frameSize = lumaSize + chromaW * chromaH * 2
    Swag.assert(bytes.count >= frameSize * frameCount)

    var total = 0.0'f64
    var count = 0'u64
    var worst = 0's32
    var frame: PlanarFrame
    for index in frameCount
    {
        expect reader.decodeFramePlanesInto(&frame, index)
        Swag.assert(frame.width == width and frame.height == height)

        let base = index * frameSize
        for y in cast(u64) height
        {
            for x in cast(u64) width
            {
                let got        = cast(s32) frame.luma[y * cast(u64) frame.strideLuma + x]
                let want       = cast(s32) bytes[base + y * cast(u64) width + x]
                let difference = Math.abs(got - want)
                total += cast(f64) difference
                worst = Math.max(worst, difference)
                count += 1
            }
        }
    }

    let mean = total / cast(f64) count
    if mean > meanLimit or worst > worstLimit do
        Swag.print("mpeg4 ", name, ": mean ", mean, " worst ", worst, " over ", count, " samples\n")
    Swag.assert(mean <= meanLimit)
    Swag.assert(worst <= worstLimit)
}

// Simple Profile: intra and predicted planes, the H.263 quantiser, half-sample motion, and four
// motion vectors where the encoder chose them.
#test
{
    mpeg4AssertStream("ffmpeg-mpeg4-simple", "mkv", 96, 64, 60, 0.2, 4)
}

// Bidirectional planes: the shape every DivX and Xvid file of that era has, with the MPEG
// quantiser and a display order that is not the decoding order.
#test
{
    mpeg4AssertStream("ffmpeg-mpeg4-bvop", "mkv", 96, 64, 60, 0.1, 4)
}

// The same content in AVI, which is where this codec mostly lived. That container states no
// decoding order, so the setup headers ride in the stream, a bidirectional plane is stored behind
// the plane it refers forward to, and a plane that codes nothing pads the sample it would have
// taken. Display order therefore comes from the clock the stream states.
#test
{
    mpeg4AssertStream("ffmpeg-mpeg4-packed", "avi", 96, 64, 60, 0.1, 4)
}

// The reader states the geometry from the setup headers, before any plane is read.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mpeg4-simple.mkv"))
    Swag.assert(reader.width() == 96 and reader.height() == 64)
    Swag.assert(reader.hasPlanarFrames())
}
