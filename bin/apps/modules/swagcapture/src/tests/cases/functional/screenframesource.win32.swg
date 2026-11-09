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
