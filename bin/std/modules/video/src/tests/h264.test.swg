#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// A forward seek crosses directly to the nearest useful sync sample instead of decoding the
// whole stream prefix. The pyramid fixture carries a later clean decode point.
#test
{
    var source             = expect Source.openFile(videoFixturePath("ffmpeg-h264-pyramid.mp4").toString())
    var decoder:  Mp4.Decoder
    let idecoder: IDecoder = &decoder
    discard expect idecoder.open(&source)

    var expectedSync = cast(u64) decoder.video.avc.sampleAtRank[57]
    while expectedSync > 0 and decoder.video.avc.syncFlags[expectedSync] == 0 do
        expectedSync -= 1
    decoder.video.avc.seekTo(57)
    @assert(expectedSync > 0 and decoder.video.avc.nextDecode == expectedSync)

    let reference = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-pyramid.yuv").toString())
    var frame: Image
    expect idecoder.decodeFrame(&source, &frame)
    videoAssertReferenceFrame(frame, reference.toSlice(), 57, 96, 64)
}

// Constrained Baseline: CAVLC entropy coding, I and P slices, several references.
#test
{
    videoAssertReferenceStream("ffmpeg-h264-baseline", 64, 48, 20)
}

// The entropy producer keeps more than one successor parsed, so CABAC does not wait for the
// preceding picture's reconstruction, RGB conversion, and publication before starting again.
#test
{
    if Jobs.isSynchronous() do
        discard expect Jobs.initialize(16)

    var source             = expect Source.openFile(videoFixturePath("ffmpeg-h264-pyramid.mp4").toString())
    var decoder:  Mp4.Decoder
    let idecoder: IDecoder = &decoder
    discard expect idecoder.open(&source)

    var frame: Image
    for 20 do
        expect idecoder.decodeFrame(&source, &frame)
    decoder.video.avc.stopFrameThreads()
    @assert(decoder.video.avc.laneCount == 16)
    @assert(decoder.video.avc.threadedHighWater == 16)
}

// High profile: CABAC, B frames with pyramid references, direct modes, weighted prediction,
// and the 8x8 transform.
#test
{
    videoAssertReferenceStream("ffmpeg-h264-high", 64, 48, 20)
}

// Frame cropping: a 60x34 picture inside 64x48 coded macroblocks.
#test
{
    videoAssertReferenceStream("ffmpeg-h264-crop", 60, 34, 8)
}

// High profile at x264 defaults: intra 8x8 prediction modes, a reference-B pyramid, and
// multi-partition B macroblocks whose motion feeds the entropy contexts across partitions.
#test
{
    videoAssertReferenceStream("ffmpeg-h264-pyramid", 96, 64, 60)
}

// Main profile with temporal direct modes, several references, and three CABAC slices per
// picture, so the contexts restart and neighbor availability stops at slice boundaries.
#test
{
    videoAssertReferenceStream("ffmpeg-h264-temporal", 96, 64, 60)
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

    @assert(decoder.video.avc.pending.count <= 4)
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
        videoAssertReferenceFrame(frame, reference.toSlice(), index, 64, 48)
    }
}
