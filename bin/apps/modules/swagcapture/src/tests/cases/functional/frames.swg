#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A recording written frame by frame reads back with the same pictures and timing, by index,
// out of order and by time; an unchanged frame costs a record without pixels.
#test
{
    let path = Gui.Testing.tempFilePath("frames-", ".frames")
    defer catch File.delete(path)

    var pictures: [6] Image
    pictures[0] = testFramePicture(10, 0)
    pictures[1] = testFramePicture(10, 4)
    pictures[2] = testFramePicture(10, 4)
    pictures[3] = testFramePicture(90, 20)
    pictures[4] = testFramePicture(90, 30)
    pictures[5] = testFramePicture(30, 50)

    // Half a second apart: frames 0, 2 and 4 are key records.
    expect testWriteFrames(path, pictures, 500_000)

    var reader = expect Frames.Reader.open(path)
    Swag.require(not reader.isRecovered)
    Swag.require(reader.frameCount() == 6)
    Swag.require(reader.endTime == 3_000_000)
    Swag.require(reader.timeOf(3) == 1_500_000)
    Swag.require(reader.frameAt(0) == 0)
    Swag.require(reader.frameAt(1_499_999) == 2)
    Swag.require(reader.frameAt(9_000_000) == 5)

    for i in 6 do
        Swag.require(testSamePixels(expect reader.read(i), &pictures[i]))
    let shuffled = [5'u64, 1, 3, 0, 4]
    for i in shuffled do
        Swag.require(testSamePixels(expect reader.read(i), &pictures[i]))
}

// A recording cut short, before its index was written, keeps every frame completely written.
#test
{
    let path = Gui.Testing.tempFilePath("frames-", ".frames")
    defer catch File.delete(path)

    var pictures: [3] Image
    pictures[0] = testFramePicture(10, 0)
    pictures[1] = testFramePicture(40, 8)
    pictures[2] = testFramePicture(70, 16)

    // Write the records, then cut the file in the middle of the last one, as a crash would.
    var writer = expect Frames.Writer.create(path, 64, 48, .BGRA8)
    for picture, i in pictures do
        expect writer.add(picture, i * 100_000)
    let cut = writer.sink.position() - 5
    expect writer.close(300_000)

    var bytes = expect File.readAllBytes(path)
    bytes.resize(cut)
    discard expect File.writeAllBytes(path, bytes.toSlice())

    var reader = expect Frames.Reader.open(path)
    Swag.require(reader.isRecovered)
    Swag.require(reader.frameCount() == 2)
    Swag.require(reader.endTime == 200_000)
    Swag.require(testSamePixels(expect reader.read(1), &pictures[1]))
}

// Only the rectangle that changed is stored between key records.
#test
{
    let before = testFramePicture(10, 4)
    let after  = testFramePicture(10, 20)
    let area   = Frames.Writer.changedArea(before, after)
    Swag.require(area.x == 4 and area.y == 10 and area.w == 26 and area.h == 10)
    Swag.require(Frames.Writer.changedArea(before, before).isEmpty())
}
