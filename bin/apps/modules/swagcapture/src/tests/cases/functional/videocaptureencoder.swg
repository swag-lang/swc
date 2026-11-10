#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel, Video

// A fast producer must retain every picture through bounded storage reuse and final draining.
#test
{
    let path = Gui.Testing.tempFilePath("capture-video-encoder-", ".mp4")
    defer discard catch File.delete(path)
    var recording = expect Mp4.SoftwareRecording.createVideoOnly(path, 32, 64, 90_000, keyInterval: 8, sliceCount: 4)
    var encoder: VideoCaptureEncoder
    expect encoder.start(&recording)
    var picture: Image
    for index in 32'u64
    {
        if not picture.isValid() do
            picture = Image.create(32, 64, .BGRA8)
        Memory.set(picture.pixels.storage(), cast(u8, index * 7), picture.byteCount)
        expect encoder.add(&picture, FrameSlot{index, index * 3_000, 3_000, 0}, false)
    }

    expect encoder.waitIdle()
    Swag.require(recording.videoFrameCount() == 32)

    // The final repeat is deliberately queued immediately before shutdown.
    expect encoder.add(&picture, FrameSlot{32, 96_000, 3_000, 0}, true)
    expect encoder.finish()
    encoder.close()
    expect recording.end()
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 33)
    for index in reader.frameCount()
    {
        let decoded = expect reader.decodeFrame(index)
        let wanted  = cast(s32, Math.min(index, 31'u64) * 7)
        Swag.require(Math.abs(cast(s32, decoded.pixels[0]) - wanted) <= 2,
                     "queued pictures must keep their own pixels and order")
    }

    let trimmed = Gui.Testing.tempFilePath("capture-video-encoder-trim-", ".mp4")
    defer discard catch File.delete(trimmed)
    let result = expect Mp4.trimSoftwareRecording(path, trimmed, 2, 31)
    Swag.require(result.encodedVideoFrames == 6 and result.copiedVideoFrames == 23,
                 "parallel-slice recordings must retain smart trimming")
    var cut = expect Reader.open(trimmed)
    Swag.require(cut.frameCount() == 29)
    for index in cut.frameCount()
    {
        let actual   = expect cut.decodeFrame(index)
        let original = expect reader.decodeFrame(index + 2)
        Swag.require(Math.abs(cast(s32, actual.pixels[0]) - original.pixels[0]) <= 2)
    }
}

// Encoder errors survive worker teardown and are returned rather than hanging a producer.
#test
{
    let path = Gui.Testing.tempFilePath("capture-video-encoder-error-", ".mp4")
    defer discard catch File.delete(path)
    var recording = expect Mp4.SoftwareRecording.createVideoOnly(path, 32, 16, 90_000)
    var encoder: VideoCaptureEncoder
    expect encoder.start(&recording)
    var wrong = Image.create(48, 16, .BGRA8)
    expect encoder.add(&wrong, FrameSlot{0, 0, 3_000, 0}, false)
    var error: Swag.Error
    catch encoder.finish() as error
    Swag.require(error.value() is BadParameterError)
    Swag.require(not encoder.worker.isValid())
    catch encoder.add(&wrong, FrameSlot{1, 3_000, 3_000, 0}, false) as error
    Swag.require(error.value() is BadParameterError)
}

// A cancelled recording may drop its worker while it is waiting with no submitted picture.
#test
{
    let path = Gui.Testing.tempFilePath("capture-video-encoder-empty-", ".mp4")
    defer discard catch File.delete(path)
    var recording = expect Mp4.SoftwareRecording.createVideoOnly(path, 32, 16, 90_000)
    scope
    {
        var encoder: VideoCaptureEncoder
        expect encoder.start(&recording)
    }

    Swag.require(recording.videoFrameCount() == 0)
}
