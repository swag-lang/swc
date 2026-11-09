#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors, Pixel

private func quantizedRecordingPicture(shift: u64)->Image
{
    var rgb: Array'u8
    rgb.resize(64 * 64 * 3)
    for y in 64'u64
    {
        for x in 64'u64
        {
            let sampleX = (x + shift) % 64
            let sampleY = (y + shift) % 64
            let offset = (y * 64 + x) * 3
            rgb[offset]     = cast(u8, (sampleX * 7 + sampleY * 3) & 255)
            rgb[offset + 1] = cast(u8, (sampleX * 5 + sampleY * 11) & 255)
            rgb[offset + 2] = cast(u8, (sampleX * 13 + sampleY * 2) & 255)
        }
    }
    return Image.create(64, 64, .RGB8, rgb.toSlice())
}

// SoftwareRecording carries QP into H.264 while preserving exact IDR pictures,
// decode order, and the caller's repeated final frame in fragmented MP4.
#test
{
    let exactPath = videoTempPath("mp4-software-qp0", "mp4")
    let quantizedPath = videoTempPath("mp4-software-qp28", "mp4")
    let retainProbe = not Env.variable("SWAG_VIDEO_QP_PROBE").isEmpty()
    defer
    {
        if not retainProbe
        {
            discard catch File.delete(exactPath)
            discard catch File.delete(quantizedPath)
        }
    }
    var exact = expect Mp4.SoftwareRecording.createVideoOnly(exactPath, 64, 64, 90_000,
                                                             keyInterval: 4)
    var quantized = expect Mp4.SoftwareRecording.createVideoOnly(quantizedPath, 64, 64, 90_000,
                                                                 keyInterval: 4,
                                                                 quantizationQp: 28)
    let pacer = expect FramePacer.create(expect FrameRate.create(30, 1), 1_000_000, 90_000)
    for frame in 5'u64
    {
        let image = quantizedRecordingPicture(frame)
        let slot = expect pacer.slotAt(frame)
        expect exact.addFrame(&image, slot)
        expect quantized.addFrame(&image, slot)
    }
    let repeated = expect pacer.slotAt(5)
    expect exact.repeatLastFrame(repeated)
    expect quantized.repeatLastFrame(repeated)
    expect exact.end()
    expect quantized.end()

    Swag.require(exact.videoFrameCount() == 6 and quantized.videoFrameCount() == 6)
    Swag.require(exact.repeatedFrameCount() == 1 and quantized.repeatedFrameCount() == 1)
    Swag.require((expect File.info(quantizedPath)).size < (expect File.info(exactPath)).size)
    let summary = expect Mp4.summarizeFragmentedRecording(quantizedPath)
    Swag.require(summary.video.packetCount == 6 and summary.audioTracks.count == 0 and
                 not summary.hasIncompleteTail)
    var exactReader = expect Reader.open(exactPath)
    var quantizedReader = expect Reader.open(quantizedPath)
    Swag.require(exactReader.frameCount() == 6 and quantizedReader.frameCount() == 6)
    var exactFrame: PlanarFrame
    var quantizedFrame: PlanarFrame
    var previousLuma: Array'u8
    for frame in 6'u64
    {
        expect exactReader.decodeFramePlanesInto(&exactFrame, frame)
        expect quantizedReader.decodeFramePlanesInto(&quantizedFrame, frame)
        let image = quantizedRecordingPicture(Math.min(frame, 4'u64))
        var expected: Nv12Frame
        expect expected.convertFrom(&image)
        Swag.require(Slice.equals(exactFrame.luma.toSlice(), expected.luma()))
        if frame == 0 or frame == 4 do
            Swag.require(Slice.equals(quantizedFrame.luma.toSlice(), expected.luma()))
        if frame == 1 do
            Swag.require(not Slice.equals(quantizedFrame.luma.toSlice(), expected.luma()))
        if frame == 4 do
            previousLuma.add(quantizedFrame.luma.toSlice())
        if frame == 5 do
            Swag.require(Slice.equals(quantizedFrame.luma.toSlice(), previousLuma.toSlice()))
    }
    if retainProbe do
        Console.printf("Software MP4 QP probe: exact %, quantized %\n", exactPath, quantizedPath)
}

// Every constructor forwards QP validation before creating an MP4 writer.
#test
{
    let path = videoTempPath("mp4-software-qp-invalid", "mp4")
    defer discard catch File.delete(path)
    var rejected: Swag.Error
    discard catch Mp4.SoftwareRecording.createVideoOnly(path, 16, 16, 90_000,
                                                         quantizationQp: 52) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch Mp4.SoftwareRecording.create(path, 16, 16, 90_000, 48_000, 1,
                                                quantizationQp: 52) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch Mp4.SoftwareRecording.createWithAudioTracks(path, 16, 16, 90_000, [],
                                                               quantizationQp: 52) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(not File.exists(path))
}
