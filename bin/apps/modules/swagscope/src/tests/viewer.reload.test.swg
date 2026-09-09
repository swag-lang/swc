#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

func writeReloadFile(fileName, text: string)
{
    var file = expect File.open(fileName, .Create, .Write, .ReadWrite | .Delete)
    discard expect file.write(cast(const [..] u8) text)
}

func pollFileWatch(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    host.fireTimer(window.fileWatchTimer)
    if window.fileWatch.load.started do
        window.fileWatch.load.task.wait()
    host.fireTimer(window.fileWatchTimer)
}

// External edits keep the Markdown reading position and zoom through progressive replacement.
#test
{
    var source: String
    for 120 do
        source += "A paragraph of the manuscript remains at the same reading position.\n\n"
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("scope-reload-%.md", Guid64.random()).toString())
    writeReloadFile(fileName.toString(), source.toString())
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName.toString(), remember: false)
    completeQueuedViewerFile(&host, window)
    window.searchBox.setText("manuscript")
    for 64 where window.searchTimer != null do
        host.fireTimer(window.searchTimer)
    let zoom = cast(*MarkdownZoomButton) window.currentInfo!.children[0]
    zoom.applyZoom(150)
    let view = cast(*Markdown.View) window.currentView!
    for 64 where view.isLoading() do
        host.fireTimers()
    (cast(*ScrollWnd) view.children[0]).setScrollPos(0, 700)
    for 64 where view.isLoading() do
        host.fireTimers()
    let position = (cast(*ScrollWnd) view.children[0]).scrollPosition()
    Swag.assert(position.y > 0)

    source += "The file now contains another paragraph.\n"
    writeReloadFile(fileName.toString(), source.toString())
    pollFileWatch(&host, window)
    Swag.assert(window.pendingFile.isEmpty())
    for 8 where window.pendingFile.isEmpty() do
        pollFileWatch(&host, window)
    Swag.assert(!window.pendingFile.isEmpty())
    completeQueuedViewerFile(&host, window)
    for 64 where window.readingState.restoring
    {
        host.fireTimers()
        host.fireTimer(window.fileWatchTimer)
    }

    Swag.assert(!window.readingState.restoring)
    Swag.assert(window.choices[window.activeChoiceIndex].key == "markdown")
    Swag.assert(window.searchBox.text() == "manuscript")
    Swag.assert((cast(*MarkdownZoomButton) window.currentInfo!.children[0]).zoomPercent == 150)
    Swag.assert((cast(*ScrollWnd) window.currentView!.children[0]).scrollPosition() == position)
    pollFileWatch(&host, window)
    Swag.assert(window.pendingFile.isEmpty())

    // A temporarily missing path leaves the current viewer readable; its return is observed.
    discard expect File.delete(fileName.toString())
    pollFileWatch(&host, window)
    Swag.assert(window.currentView != null and window.pendingFile.isEmpty())
    writeReloadFile(fileName.toString(), "Short document.\n")
    for 8 where window.pendingFile.isEmpty() do
        pollFileWatch(&host, window)
    completeQueuedViewerFile(&host, window)
    host.fireTimer(window.fileWatchTimer)
    Swag.assert((cast(*ScrollWnd) window.currentView!.children[0]).scrollPosition().y == 0)
}

// Metadata changes include same-size writes and replacement by another file.
#test
{
    var a: File.FileInfo
    a.size = 12
    var b = a
    b.lastWriteTime.year = 2026
    Swag.assert(!ViewerFileWatch.sameFile(a, b))
    b = a
    b.creationTime.year = 2026
    Swag.assert(!ViewerFileWatch.sameFile(a, b))
}

// Manual reload uses the same state transfer for a transformed, panned image.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/title.png")
    window.openFile(fileName.toString(), remember: false)
    completeQueuedViewerFile(&host, window)
    let view = (cast(*ImageViewer) window.currentView!).imageView
    view.setZoom(2)
    view.mirrorHorizontally()
    view.rotateClockwise()
    view.setPanOffset({31, -47})
    let pan = view.panOffset
    window.reloadCurrentFile()
    completeQueuedViewerFile(&host, window)
    host.fireTimer(window.fileWatchTimer)
    let replacement = (cast(*ImageViewer) window.currentView!).imageView
    Swag.assert(!replacement.isFitted and replacement.zoom == 2)
    Swag.assert(replacement.rotationQuarterTurns == 1 and replacement.isMirrored)
    Swag.assert(replacement.panOffset == pan)
}

// Counting follows source lines and Unicode whitespace, including a CRLF split across chunks.
#test
{
    var counter: TextStatisticsCounter
    Swag.assert(counter.finish().lines == 0 and counter.finish().words == 0)
    counter.append("\uFEFF")
    Swag.assert(counter.finish().lines == 0 and counter.finish().words == 0)
    counter.append("one two\r")
    counter.append("\nthree\u00a0four\nlast")
    let result = counter.finish()
    Swag.assert(result.lines == 3 and result.words == 5)
}
