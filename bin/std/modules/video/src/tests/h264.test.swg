#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// Converts one frame of a raw 4:2:0 reference dump with the exact arithmetic the module's
// decoders use, so a correct H.264 decode matches it byte for byte.
func h264ReferenceFrame(bytes: const [..] u8, index: u64, width, height: s32)->Image
{
    let lumaSize     = cast(u64) width * cast(u64) height
    let chromaWidth  = cast(u64) (width + 1) / 2
    let chromaHeight = cast(u64) (height + 1) / 2
    let chromaSize   = chromaWidth * chromaHeight
    let frameSize    = lumaSize + chromaSize * 2
    let base         = index * frameSize
    @assert(base + frameSize <= @countof(bytes))

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
func h264AssertFrame(frame: Image, reference: const [..] u8, index: u64, width, height: s32)
{
    @assert(frame.width == width and frame.height == height and frame.pixelFormat == .RGB8)
    let expected   = h264ReferenceFrame(reference, index, width, height)
    var mismatches = 0'u64
    for position in frame.pixels.count where frame.pixels.buffer![position] != expected.pixels.buffer![position] do
        mismatches += 1
    if mismatches > 0 do
        @print("h264 frame ", index, ": ", mismatches, " of ", frame.pixels.count, " bytes differ\n")
    @assert(mismatches == 0)
}

// Decodes a whole stream in order and demands byte-exact frames.
func h264AssertStream(name: string, width, height: s32, frameCount: u64)
{
    if Jobs.isSynchronous() do
        discard expect Jobs.initialize(4)

    var reader = expect Reader.open(videoFixturePath(Format.toString("%.mp4", name).toString()))
    @assert(reader.width() == width and reader.height() == height)
    @assert(reader.frameCount() == frameCount)

    let reference = expect File.readAllBytes(videoFixturePath(Format.toString("%.yuv", name).toString()).toString())
    var frame: Image
    for index in frameCount
    {
        expect reader.decodeFrameInto(&frame, index)
        h264AssertFrame(frame, reference.toSlice(), index, width, height)
    }
}

// A forward seek crosses directly to the nearest useful sync sample instead of decoding the
// whole stream prefix. The pyramid fixture carries a later clean decode point.
#test
{
    var source              = expect Source.openFile(videoFixturePath("ffmpeg-h264-pyramid.mp4").toString())
    var decoder: Mp4.Decoder
    let idecoder: IDecoder = &decoder
    discard expect idecoder.open(&source)

    var expectedSync = cast(u64) decoder.avc.sampleAtRank[57]
    while expectedSync > 0 and decoder.avc.syncFlags[expectedSync] == 0 do
        expectedSync -= 1
    decoder.avc.seekTo(57)
    @assert(expectedSync > 0 and decoder.avc.nextDecode == expectedSync)

    let reference = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-pyramid.yuv").toString())
    var frame: Image
    expect idecoder.decodeFrame(&source, &frame)
    h264AssertFrame(frame, reference.toSlice(), 57, 96, 64)
}

// Constrained Baseline: CAVLC entropy coding, I and P slices, several references.
#test
{
    h264AssertStream("ffmpeg-h264-baseline", 64, 48, 20)
}

// High profile: CABAC, B frames with pyramid references, direct modes, weighted prediction,
// and the 8x8 transform.
#test
{
    h264AssertStream("ffmpeg-h264-high", 64, 48, 20)
}

// Frame cropping: a 60x34 picture inside 64x48 coded macroblocks.
#test
{
    h264AssertStream("ffmpeg-h264-crop", 60, 34, 8)
}

// High profile at x264 defaults: intra 8x8 prediction modes, a reference-B pyramid, and
// multi-partition B macroblocks whose motion feeds the entropy contexts across partitions.
#test
{
    h264AssertStream("ffmpeg-h264-pyramid", 96, 64, 60)
}

// Main profile with temporal direct modes, several references, and three CABAC slices per
// picture, so the contexts restart and neighbor availability stops at slice boundaries.
#test
{
    h264AssertStream("ffmpeg-h264-temporal", 96, 64, 60)
}

// A player that falls behind skips display ranks. Frames decoded for skipped ranks must be
// released, or a long playback starves the decoder's frame pool.
#test
{
    var source             = expect Source.openFile(videoFixturePath("ffmpeg-h264-pyramid.mp4").toString())
    var decoder:  Mp4.Decoder
    let idecoder: IDecoder = &decoder
    discard expect idecoder.open(&source)

    var frame: Image
    var index = 0'u64
    while index < 60
    {
        expect idecoder.seekFrame(&source, index)
        expect idecoder.decodeFrame(&source, &frame)
        index += 3
    }

    @assert(decoder.avc.pending.count <= 4)
}

// Random access decodes through the nearest sync sample and still matches, both across and
// inside groups of pictures.
#test
{
    var reader    = expect Reader.open(videoFixturePath("ffmpeg-h264-high.mp4"))
    let reference = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-high.yuv").toString())
    @assert(reader.frameRate() == expect FrameRate.create(12_800, 512))

    const Frames: [5] u64 = [17, 3, 12, 0, 19]
    var frame: Image
    for index in Frames
    {
        expect reader.decodeFrameInto(&frame, index)
        h264AssertFrame(frame, reference.toSlice(), index, 64, 48)
    }
}
