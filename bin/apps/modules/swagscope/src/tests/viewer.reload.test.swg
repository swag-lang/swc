#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

func writeReloadFile(fileName, text: string)
{
    var file = expect File.openWrite(fileName)
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
    let previous = g_MarkdownViewerSettings
    defer g_MarkdownViewerSettings = previous
    g_MarkdownViewerSettings = {}
    var source: String
    for 12_000 do
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
    Swag.assert(not window.pendingFile.isEmpty())
    completeQueuedViewerFile(&host, window)
    for 64 where window.readingState.restoring
    {
        host.fireTimers()
        host.fireTimer(window.fileWatchTimer)
    }

    Swag.assert(not window.readingState.restoring)
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
    Swag.assert((cast(*ScrollWnd) window.currentView.children[0]).scrollPosition().y == 0)
}

// Idle document streams permit exclusive saves before all their content has been consumed.
#test
{
    for extension in [".txt", ".cpp", ".html"]
    {
        let fileName = Testing.tempFilePath("scope-live-", extension)
        var source: String
        for 2_000 do
            source += extension == ".html" ? "<p>A paragraph in the document before the external edit.</p>\n" : "// A line in the document before the external edit.\n"
        writeReloadFile(fileName, source)
        defer discard catch File.delete(fileName)

        var host: Testing.HeadlessHost
        host.setup(960, 680)
        defer host.shutdown()
        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.openFile(fileName, remember: false)
        completeViewerWindowClassification(&host, window)
        Swag.drainWork()
        if extension == ".txt" do
            (cast(*TextView) window.currentView!).statisticsThread.wait()
        let key = String.from(window.choices[window.activeChoiceIndex].key.toString())

        // Truncate while the progressive viewer still exists, then let the watcher reload it.
        source += extension == ".html" ? "<p>Replacement content.</p>\n" : "// Replacement content.\n"
        writeReloadFile(fileName, source)
        for 8 where window.pendingFile.isEmpty() do
            pollFileWatch(&host, window)
        Swag.assert(not window.pendingFile.isEmpty())
        completeQueuedViewerFile(&host, window)
        for 64 where window.readingState.restoring do
            host.fireTimer(window.fileWatchTimer)
        Swag.assert(window.choices[window.activeChoiceIndex].key == key)
        Swag.assert(not window.readingState.restoring and window.currentView != null)
        Swag.assert(window.fileWatch.current.size == source.length)

        // Editors also save by renaming a new file over the original path.
        let replacement = Testing.tempFilePath("scope-replacement-", extension)
        writeReloadFile(replacement, "Short replacement.\n")
        defer discard catch File.delete(replacement)
        expect File.move(fileName, replacement)
        for 8 where window.pendingFile.isEmpty() do
            pollFileWatch(&host, window)
        Swag.assert(not window.pendingFile.isEmpty())
        completeQueuedViewerFile(&host, window)
        Swag.assert(window.fileWatch.current.size == 19)
    }
}

// A PDF snapshot allows exclusive truncation and keeps the page and zoom on automatic reload.
#test
{
    let fileName = Testing.tempFilePath("scope-reload-", ".pdf")
    var document = Pdf.Document.create()
    for 2
    {
        var page = Pdf.Page.create(320, 220)
        document.addPage(#move page)
    }

    expect document.save(fileName)
    defer discard catch File.delete(fileName)
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    let view = (cast(*PdfViewer) window.currentView!).pdfView
    view.setPageLayout(.Single)
    view.setZoom(1.5)
    view.showPage(1)
    let zoomMode = view.zoomMode
    var page     = Pdf.Page.create(320, 220)
    document.addPage(#move page)
    expect document.save(fileName)
    Swag.assert(view.pageCount() == 2)
    for 8 where window.pendingFile.isEmpty() do
        pollFileWatch(&host, window)
    Swag.assert(not window.pendingFile.isEmpty())
    completeQueuedViewerFile(&host, window)
    for 64 where window.readingState.restoring do
        host.fireTimer(window.fileWatchTimer)
    let replacement = (cast(*PdfViewer) window.currentView!).pdfView
    Swag.assert(replacement.pageCount() == 3 and replacement.pageIndex == 1)
    Swag.assert(replacement.zoom == 1.5 and replacement.zoomMode == zoomMode)
    Swag.assert(replacement.pageLayout == .Single)
}

// A much shorter replacement must settle instead of repeatedly restoring an unreachable viewport.
#test
{
    let fileName = Testing.tempFilePath("scope-shrinking-", ".md")
    var source: String
    for index in 12_000 do
        source += Format.toString("## Section %\n\nA paragraph of the original manuscript.\n\n", index)
    writeReloadFile(fileName, source)
    defer discard catch File.delete(fileName)
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    host.setReducedMotion(false)
    defer host.shutdown()
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    let view = cast(*Markdown.View) window.currentView!
    let originalScroll = cast(*ScrollWnd) view.children[0]
    originalScroll.setScrollPos(0, originalScroll.scrollableClientRect().height * 0.75)
    discard host.render(view)
    for 128 where view.isLoading() do
        host.fireTimers()
    Swag.assert(originalScroll.scrollPosition().y > 10_000)

    source.clear()
    for index in 400 do
        source += Format.toString("## Short section %\n\nReplacement paragraph.\n\n", index)
    writeReloadFile(fileName, source)
    for 8 where window.pendingFile.isEmpty() do
        pollFileWatch(&host, window)
    Swag.assert(not window.pendingFile.isEmpty())
    completeViewerWindowClassification(&host, window)
    for 128
    {
        host.fireTimers()
        host.fireTimer(window.fileWatchTimer)
        host.advanceAnimations(0.1)
    }

    let replacement = cast(*Markdown.View) window.currentView!
    Swag.assert(not window.readingState.restoring and not replacement.isLoading())
    let scroll   = cast(*ScrollWnd) replacement.children[0]
    let position = scroll.scrollPosition()
    for 32
    {
        host.fireTimers()
        host.fireTimer(window.fileWatchTimer)
        host.finishAnimations()
        Swag.assert(window.pendingFile.isEmpty() and not window.readingState.restoring)
        Swag.assert(scroll.scrollPosition() == position and not replacement.isLoading())
    }
}

// Metadata changes include same-size writes and replacement by another file.
#test
{
    var a: File.FileInfo
    a.size = 12
    var b = a
    b.lastWriteTime.year = 2026
    Swag.assert(not ViewerFileWatch.sameFile(a, b))
    b = a
    b.creationTime.year = 2026
    Swag.assert(not ViewerFileWatch.sameFile(a, b))
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
    Swag.assert(not replacement.isFitted and replacement.zoom == 2)
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
