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
