#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Only the separator can capture the pointer. Closing the split releases the capture
// before returning to a single view.
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()

    let divider = unwrap workspace.columnDividers[0]
    Swag.require(not divider.isLocallyVisible() and divider.mouseCapture() == null)

    let paths = [scopeTestDataPath("comprehensive.txt"), scopeTestDataPath("sample.cpp")]
    workspace.openScene(paths, .SideBySide)
    openViews(&host, workspace)

    var point = divider.localToSurface(divider.clientRect().center())
    Swag.require(host.surfaceWnd.windowAt(point.x, point.y) == divider)
    host.surfaceWnd.surface!.surfaceToScreen(&point)
    host.sendMouseEvent(divider, .Pressed, point, .Left, .None)
    Swag.require(divider.mouseCapture() == divider)
    host.moveMouse(point + Math.Point{100, 0})
    Swag.require(workspace.scene()!.split > 0.5)

    workspace.closeView()
    Swag.require(not divider.isLocallyVisible() and divider.mouseCapture() == null)
}
