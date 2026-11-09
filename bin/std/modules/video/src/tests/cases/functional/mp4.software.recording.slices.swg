#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors, Pixel

private func slicedRecordingPicture(shift: u64)->Image
{
    var image = Image.create(64, 64, .BGRA8)
    for y in 64'u64
    {
        for x in 64'u64
        {
            let offset = (y * 64 + x) * 4
            image.pixels[offset]     = cast(u8, (x * 7 + y * 3 + shift * 5) & 255)
            image.pixels[offset + 1] = cast(u8, (x * 5 + y * 11 + shift * 9) & 255)
            image.pixels[offset + 2] = cast(u8, (x * 13 + y * 2 + shift * 7) & 255)
            image.pixels[offset + 3] = 255
        }
    }
    return image
}

// Two and four H.264 slices survive SoftwareRecording's MP4 packet conversion,
// including IDR, quantized P pictures and a repeated final picture.
#test
{
    const SliceCounts: [2] u32 = [2, 4]
    const Quantizers:  [2] u32 = [0, 28]
    let retainProbe = not Env.variable("SWAG_VIDEO_SLICE_PROBE").isEmpty()
    for scenario in 2'u64
    {
        let sliceCount = SliceCounts[scenario]
        let qp = Quantizers[scenario]
        let path = videoTempPath(sliceCount == 2 ? "mp4-software-slice2" :
                                                  "mp4-software-slice4", "mp4")
        defer
        {
            if not retainProbe do
                discard catch File.delete(path)
        }
        var recorder = expect Mp4.SoftwareRecording.createVideoOnly(
            path, 64, 64, 90_000, keyInterval: 3,
            quantizationQp: qp, sliceCount: sliceCount)
        let pacer = expect FramePacer.create(expect FrameRate.create(30, 1),
                                             1_000_000, 90_000)
        for frame in 4'u64
        {
            let image = slicedRecordingPicture(frame)
            expect recorder.addFrame(&image, expect pacer.slotAt(frame))
        }
        expect recorder.repeatLastFrame(expect pacer.slotAt(4))
        expect recorder.end()
        Swag.require(recorder.videoFrameCount() == 5 and recorder.repeatedFrameCount() == 1)
        let summary = expect Mp4.summarizeFragmentedRecording(path)
        Swag.require(summary.video.packetCount == 5 and summary.audioTracks.count == 0 and
                     not summary.hasIncompleteTail)
        var reader = expect Reader.open(path)
        Swag.require(reader.frameCount() == 5 and reader.audioTrackCount() == 0)
        var decoded: PlanarFrame
        var previousLuma: Array'u8
        for frame in 5'u64
        {
            expect reader.decodeFramePlanesInto(&decoded, frame)
            let image = slicedRecordingPicture(Math.min(frame, 3'u64))
            var expected: Nv12Frame
            expect expected.convertFrom(&image)
            if qp == 0 do
                Swag.require(Slice.equals(decoded.luma.toSlice(), expected.luma()))
            Swag.require(decoded.width == 64 and decoded.height == 64)
            if qp != 0 and frame == 1 do
                Swag.require(not Slice.equals(decoded.luma.toSlice(), expected.luma()))
            if frame == 3 do
                previousLuma.add(decoded.luma.toSlice())
            if frame == 4 do
                Swag.require(Slice.equals(decoded.luma.toSlice(), previousLuma.toSlice()))
        }
        if retainProbe do
            Console.printf("Software MP4 slice probe: % slices, QP %, path %\n",
                           sliceCount, qp, path)
    }
}

// All factory variants reject zero slices and counts above the picture's rows or the limit.
#test
{
    let path = videoTempPath("mp4-software-slice-invalid", "mp4")
    defer discard catch File.delete(path)
    var rejected: Swag.Error
    discard catch Mp4.SoftwareRecording.createVideoOnly(path, 64, 64, 90_000,
                                                         sliceCount: 0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch Mp4.SoftwareRecording.create(path, 64, 64, 90_000, 48_000, 1,
                                                sliceCount: 5) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch Mp4.SoftwareRecording.createWithAudioTracks(path, 64, 64, 90_000, [],
                                                               sliceCount: 9) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(not File.exists(path))
}
