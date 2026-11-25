#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// The video index crosses a file read window and must still address both sides of it.
#[Swag.TestTag("stress")]
#test
{
    const WindowFrames = ByteSource.WindowSize / Avi.IndexEntrySize
    const Frames       = WindowFrames + 9
    let path = videoTempPath("avi-index-window", "avi")
    defer discard catch File.delete(path)

    let rate   = expect FrameRate.create(30, 1)
    var writer = expect Writer.create(path, 8, 8, rate)
    let dark   = videoGrayImage(8, 8, 40)
    let light  = videoGrayImage(8, 8, 200)
    for index in Frames do
        expect writer.addFrame(index < WindowFrames ? dark : light)
    expect writer.end()

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == Frames)
    videoAssertGray((expect reader.decodeFrame(Frames - 1)).pixelColor(4, 4), 200, tolerance: 6)
    videoAssertGray((expect reader.decodeFrame(WindowFrames - 1)).pixelColor(4, 4), 40, tolerance: 6)
    videoAssertGray((expect reader.decodeFrame(WindowFrames)).pixelColor(4, 4), 200, tolerance: 6)
}
