#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// The information sheet links the longest-line measurement back to its source line.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-text-longest-line-", ".txt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "short\nlongest line\nend")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    let view = assume cast(*PlainText.Panel, window.currentView)
    completeTextReads(&host, view)
    completeTextStatistics(&host, view)
    Swag.require(view.statistics.longestLine == 2)

    view.describeInformation(window.infoSheet)
    window.infoSheet.open()

    var local: Math.Point
    var found = false
    let bounds = window.infoSheet.position
    for y in cast(u64, bounds.height)
    {
        for x in cast(u64, bounds.width)
        {
            let point = Math.Point{cast(f32, x), cast(f32, y)}
            if window.infoSheet.linkAt(point) != Swag.U64.Max
            {
                local = point
                found = true
                break
            }
        }
        if found do
            break
    }
    Swag.require(found)
    host.click(window.infoSheet.localToSurface(local))
    Swag.require(view.currentLine() == 2 and view.editor.selectionEnd().lineIndex == 1)

    Swag.require(window.activeChoiceIndex < window.instances.count)
    Swag.require(window.instances[window.activeChoiceIndex].view == window.currentView)
}
