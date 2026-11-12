#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag, Core, Pixel

// The test backend simulates desktop reads; this checks the source's storage and
// reopen contract without claiming to exercise native GDI on a Linux host.
#test
{
    var source = expect ScreenFrameSource.create(false, 10, 20, 6, 4)
    var frame: Image
    expect source.grabInto(&frame)
    Swag.require(frame.width == 6 and frame.height == 4 and frame.pixelFormat == .BGRA8)
    let storage = frame.pixels.storage()
    expect source.grabInto(&frame)
    Swag.require(frame.pixels.storage() == storage)
    expect source.reopen()
    expect source.grabInto(&frame)
    Swag.require(frame.pixels.storage() == storage)
    Swag.require(source.memoryDC == null and source.bitmap == null)
}

// Restoring the previous cursor rectangle touches only its pixels and ignores a replaced target.
#test
{
    var source = expect ScreenFrameSource.create(true, 0, 0, 6, 4)
    var frame = Image.create(6, 4, .BGRA8)
    frame.fill(Argb.White)
    source.saveCursorPixels(&frame, 1, 1, 3, 3)
    frame.fill(Argb.Black)
    source.restoreCursorPixels(&frame)
    Swag.require(frame.pixelColor(1, 1) == Argb.White)
    Swag.require(frame.pixelColor(2, 2) == Argb.White)
    Swag.require(frame.pixelColor(0, 0) == Argb.Black)

    source.saveCursorPixels(&frame, 1, 1, 3, 3)
    var replacement = Image.create(6, 4, .BGRA8)
    replacement.fill(Argb.Black)
    source.restoreCursorPixels(&replacement)
    Swag.require(replacement.pixelColor(1, 1) == Argb.Black and source.cursorBackup.isEmpty())

    Swag.require(source.cursorPixelsChanged(&frame, 1, 1, 3, 3))
    Swag.require(not source.cursorPixelsChanged(&frame, 1, 1, 3, 3))
    frame.fill(Argb.Black)
    Swag.require(source.cursorPixelsChanged(&frame, 1, 1, 3, 3))
    Swag.require(source.cursorPixelsChanged(&frame, 2, 1, 4, 3))
}
