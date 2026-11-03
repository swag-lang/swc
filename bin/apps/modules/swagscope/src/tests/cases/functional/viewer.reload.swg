#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// External edits keep the Markdown reading position and zoom through progressive replacement.

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
        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.openFile(fileName, remember: false)
        completeViewerWindowClassification(&host, window)
        Swag.drainWork()
        if extension == ".txt" do
            assume cast(*PlainText.Panel, window.currentView).statisticsTask.wait()
        let key = String.from(window.choices[window.activeChoiceIndex].key)

        // Truncate while the progressive viewer still exists, then let the watcher reload it.
        source += extension == ".html" ? "<p>Replacement content.</p>\n" : "// Replacement content.\n"
        writeReloadFile(fileName, source)
        for 8 where window.pendingFile.isEmpty() do
            pollFileWatch(&host, window)
        Swag.require(not window.pendingFile.isEmpty())
        completeQueuedViewerFile(&host, window)
        for 64 where window.readingState.restoring do
            host.fireTimer(window.fileWatchTimer)
        Swag.require(window.choices[window.activeChoiceIndex].key == key)
        Swag.require(not window.readingState.restoring and window.currentView != null)
        Swag.require(window.fileWatch.current.size == source.length)

        // Editors also save by renaming a new file over the original path.
        let replacement = Testing.tempFilePath("scope-replacement-", extension)
        writeReloadFile(replacement, "Short replacement.\n")
        defer discard catch File.delete(replacement)
        expect File.move(fileName, replacement)
        for 8 where window.pendingFile.isEmpty() do
            pollFileWatch(&host, window)
        Swag.require(not window.pendingFile.isEmpty())
        completeQueuedViewerFile(&host, window)
        Swag.require(window.fileWatch.current.size == 19)
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
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    with let view = assume cast(*PdfDocument.Panel, window.currentView).pdfView
    {
        .setPageLayout(.Single)
        .setZoom(1.5)
        .showPage(1)
    }

    let zoomMode = view.zoomMode
    var page     = Pdf.Page.create(320, 220)
    document.addPage(#move page)
    expect document.save(fileName)
    Swag.require(view.pageCount() == 2)
    for 8 where window.pendingFile.isEmpty() do
        pollFileWatch(&host, window)
    Swag.require(not window.pendingFile.isEmpty())
    completeQueuedViewerFile(&host, window)
    for 64 where window.readingState.restoring do
        host.fireTimer(window.fileWatchTimer)
    let replacement = assume cast(*PdfDocument.Panel, window.currentView).pdfView
    Swag.require(replacement.pageCount() == 3 and replacement.pageIndex == 1)
    Swag.require(replacement.zoom == 1.5 and replacement.zoomMode == zoomMode)
    Swag.require(replacement.pageLayout == .Single)
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
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    let view = assume cast(*Markdown.View, window.currentView)
    let originalScroll = assume cast(*ScrollWnd, view.children[0])
    originalScroll.setScrollPos(0, originalScroll.scrollableClientRect().height * 0.75)
    discard host.render(view)
    for 128 where view.isLoading() do
        host.fireTimers()
    Swag.require(originalScroll.scrollPosition().y > 10_000)

    source.clear()
    for index in 400 do
        source += Format.toString("## Short section %\n\nReplacement paragraph.\n\n", index)
    writeReloadFile(fileName, source)
    for 8 where window.pendingFile.isEmpty() do
        pollFileWatch(&host, window)
    Swag.require(not window.pendingFile.isEmpty())
    completeViewerWindowClassification(&host, window)
    for 128
    {
        host.fireTimers()
        host.fireTimer(window.fileWatchTimer)
        host.advanceAnimations(0.1)
    }

    let replacement = assume cast(*Markdown.View, window.currentView)
    Swag.require(not window.readingState.restoring and not replacement.isLoading())
    let scroll   = assume cast(*ScrollWnd, replacement.children[0])
    let position = scroll.scrollPosition()
    for 32
    {
        host.fireTimers()
        host.fireTimer(window.fileWatchTimer)
        host.finishAnimations()
        Swag.require(window.pendingFile.isEmpty() and not window.readingState.restoring)
        Swag.require(scroll.scrollPosition() == position and not replacement.isLoading())
    }
}

// Metadata changes include same-size writes and replacement by another file.
#test
{
    var a: File.FileInfo
    a.size = 12
    var b = a
    b.lastWriteTime.year = 2026
    Swag.require(not ViewerFileWatch.sameFile(a, b))
    b = a
    b.creationTime.year = 2026
    Swag.require(not ViewerFileWatch.sameFile(a, b))
}

// Manual reload uses the same state transfer for a transformed, panned image.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let fileName = Path.combine(testSourceRoot(#curlocation), "datas/title.png")
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    with let view = assume cast(*Picture.Panel, window.currentView).imageView
    {
        .setZoom(2)
        .mirrorHorizontally()
        .rotateClockwise()
        .setPanOffset({31, -47})
    }

    let pan = view.panOffset
    window.reloadCurrentFile()
    completeQueuedViewerFile(&host, window)
    host.fireTimer(window.fileWatchTimer)
    let replacement = assume cast(*Picture.Panel, window.currentView).imageView
    Swag.require(not replacement.isFitted and replacement.zoom == 2)
    Swag.require(replacement.rotationQuarterTurns == 1 and replacement.isMirrored)
    Swag.require(replacement.panOffset == pan)
}

// Counting follows decoded scalars, source lines, and Unicode whitespace across chunk boundaries.
#test
{
    var counter: TextStatisticsCounter
    Swag.require(counter.finish().lines == 0 and counter.finish().words == 0 and counter.finish().characters == 0)
    counter.append("\uFEFF")
    Swag.require(counter.finish().lines == 0 and counter.finish().words == 0 and counter.finish().characters == 0)
    counter.append("one two\r")
    counter.append("\nthree\u00a0four\nlast")
    let result = counter.finish()
    Swag.require(result.lines == 3 and result.words == 5 and result.characters == 24)
}
