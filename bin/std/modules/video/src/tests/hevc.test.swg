#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// The same access units, muxed two ways, decode to the same pictures.
//
// `ffmpeg-hevc-main.mkv` is a stream copy of `ffmpeg-hevc-main.mp4`, so a difference between these
// two results is the container reader and never the decoder.
#test
{
    videoAssertReferenceStream("ffmpeg-hevc-main", 96, 64, 60)
}

#test
{
    videoAssertReferenceStream("ffmpeg-hevc-main", 96, 64, 60, "mkv")
}

// An `hev1` sample entry, whose access units repeat the parameter sets the entry already carries,
// with three slices per picture so entropy contexts restart inside a frame.
#test
{
    videoAssertReferenceStream("ffmpeg-hevc-inband", 96, 64, 60)
}

// A forward seek crosses to the nearest sync sample instead of decoding the whole stream prefix,
// and the picture it lands on is the one that display rank names.
#test
{
    var source             = expect Source.openFile(videoFixturePath("ffmpeg-hevc-main.mp4").toString())
    var decoder:  Mp4.Decoder
    let idecoder: IDecoder = &decoder
    discard expect idecoder.open(&source)

    var expectedSync = cast(u64) decoder.video.hevc.sampleAtRank[47]
    while expectedSync > 0 and decoder.video.hevc.syncFlags[expectedSync] == 0 do
        expectedSync -= 1
    decoder.video.hevc.seekTo(47)
    @assert(expectedSync > 0 and decoder.video.hevc.nextDecode == expectedSync)

    let reference = expect File.readAllBytes(videoFixturePath("ffmpeg-hevc-main.yuv").toString())
    var frame: Image
    expect idecoder.decodeFrame(&source, &frame)
    videoAssertReferenceFrame(frame, reference.toSlice(), 47, 96, 64)
}

// The reader reports the track geometry from the decoder configuration record, before any access
// unit is read.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-hevc-main.mp4"))
    @assert(reader.width() == 96 and reader.height() == 64)
    @assert(reader.frameCount() == 60)
    @assert(reader.hasPlanarFrames())
}

// Identity weights at integer positions go directly from the reference pictures to the result.
// This covers both the packed two-reference average and the packed ten-to-eight-bit handoff.
#test
{
    var sps: Hevc.Sps
    sps.width           = 32
    sps.height          = 32
    sps.subWidthC       = 2
    sps.subHeightC      = 2
    sps.chromaArrayType = 1
    sps.bitDepthLuma    = 10
    sps.bitDepthChroma  = 10

    var current, reference0, reference1: Hevc.Frame
    current.prepare(&sps)
    reference0.prepare(&sps)
    reference1.prepare(&sps)
    for y in 32's32
    {
        for x in 32's32
        {
            reference0.lumaAtMutable(x, y)[0] = cast(u16) (x + y)
            reference1.lumaAtMutable(x, y)[0] = cast(u16) (100 + 2 * x + y)
        }
    }

    for y in 16's32
    {
        for x in 16's32
        {
            reference0.chromaAtMutable(0, x, y)[0] = cast(u16) (20 + x + y)
            reference1.chromaAtMutable(0, x, y)[0] = cast(u16) (60 + 2 * x + y)
            reference0.chromaAtMutable(1, x, y)[0] = cast(u16) (40 + x + y)
            reference1.chromaAtMutable(1, x, y)[0] = cast(u16) (80 + 2 * x + y)
        }
    }

    var pps: Hevc.Pps
    pps.weightedBipred = true
    var decoder: Hevc.Decoder
    decoder.activeSps            = &sps
    decoder.activePps            = &pps
    decoder.current              = &current
    decoder.header.sliceType     = Hevc.SliceTypeB
    decoder.header.hasWeights    = true
    decoder.refList.frames[0, 0] = &reference0
    decoder.refList.frames[1, 0] = &reference1
    for list in Hevc.ListCount
    {
        decoder.header.weights[list, 0].lumaWeight      = 1
        decoder.header.weights[list, 0].chromaWeight[0] = 1
        decoder.header.weights[list, 0].chromaWeight[1] = 1
    }

    var motion: Hevc.PuMotion
    motion.predFlags = 3
    motion.refIdx    = [0, 0]
    decoder.interPredict(0, 0, 32, 32, &motion)

    var picture: PlanarFrame
    current.writePlanar(&picture, &sps)
    for y in 32's32
    {
        for x in 32's32
        {
            let reconstructed = (x + y + 100 + 2 * x + y + 1) >> 1
            @assert(picture.luma[cast(u64) y * cast(u64) picture.strideLuma + cast(u64) x] == cast(u8) ((reconstructed + 2) >> 2))
        }
    }

    for y in 16's32
    {
        for x in 16's32
        {
            let blue  = (20 + x + y + 60 + 2 * x + y + 1) >> 1
            let red   = (40 + x + y + 80 + 2 * x + y + 1) >> 1
            let index = cast(u64) y * cast(u64) picture.strideChroma + cast(u64) x
            @assert(picture.chromaB[index] == cast(u8) ((blue + 2) >> 2))
            @assert(picture.chromaR[index] == cast(u8) ((red + 2) >> 2))
        }
    }
}
