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
    Swag.require(reader.width() == width and reader.height() == height)

    let reference = expect File.readAllBytes(videoFixturePath(Format.toString("%.yuv", name).toString()).toString())
    let bytes     = reference.toSlice()
    let lumaSize  = cast(u64, width) * cast(u64, height)
    let chromaW   = cast(u64, ((width + 1) / 2))
    let chromaH   = cast(u64, ((height + 1) / 2))
    let frameSize = lumaSize + chromaW * chromaH * 2
    Swag.require(bytes.count >= frameSize * frameCount)

    var total = 0.0'f64
    var count = 0'u64
    var worst = 0's32
    var frame: PlanarFrame
    for index in frameCount
    {
        expect reader.decodeFramePlanesInto(&frame, index)
        Swag.require(frame.width == width and frame.height == height)

        let base = index * frameSize
        for y in cast(u64, height)
        {
            for x in cast(u64, width)
            {
                let got        = cast(s32, frame.luma[y * cast(u64, frame.strideLuma) + x])
                let want       = cast(s32, bytes[base + y * cast(u64, width) + x])
                let difference = Math.abs(got - want)
                total += cast(f64, difference)
                worst = Math.max(worst, difference)
                count += 1
            }
        }
    }

    let mean = total / cast(f64, count)
    if mean > meanLimit or worst > worstLimit do
        Swag.print("mpeg4 ", name, ": mean ", mean, " worst ", worst, " over ", count, " samples\n")
    Swag.require(mean <= meanLimit)
    Swag.require(worst <= worstLimit)
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

// A player behind its clock jumps forward to the next clean picture, never back to the last one.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mpeg4-bvop.mkv"))
    Swag.require(reader.syncFrameAt(0) == 0)
    Swag.require(reader.syncFrameAt(1) == 30)
    Swag.require(reader.syncFrameAt(30) == 30)
    Swag.require(reader.syncFrameAt(31) == 59)
    Swag.require(reader.syncFrameAt(60) == 60)
}

// The reader states the geometry from the setup headers, before any plane is read.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-mpeg4-simple.mkv"))
    Swag.require(reader.width() == 96 and reader.height() == 64)
    Swag.require(reader.hasPlanarFrames())
}

// A resync header repeats the forward and backward motion-code ranges. Zero has no legal range
// and must be rejected here, before motion-vector decoding uses it to choose a shift count.
#test
{
    const ZeroForward:  [3] u8 = [0x06, 0xA8, 0x00]     // P plane, header extension, fcode_forward = 0.
    const ZeroBackward: [3] u8 = [0x06, 0xB0, 0x20]     // B plane, fcode_forward = 1, fcode_backward = 0.

    var decoder: Mpeg4.Decoder
    decoder.layer.mbWidth           = 1
    decoder.layer.mbHeight          = 1
    decoder.layer.quantPrecision    = 5
    decoder.layer.timeIncrementBits = 1

    var header:   Mpeg4.PlaneHeader
    var index  = 0'u64
    var reader = Mpeg4.BitReader.create(Swag.makeSlice(&ZeroForward[0], ZeroForward.count))
    var rejected: Swag.Error
    discard catch decoder.readPacketHeader(&reader, &header, &index) as rejected
    Swag.require(rejected.value() is InvalidFormatError)

    reader = Mpeg4.BitReader.create(Swag.makeSlice(&ZeroBackward[0], ZeroBackward.count))
    discard catch decoder.readPacketHeader(&reader, &header, &index) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
}
