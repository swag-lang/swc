#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Saves a PDF of `pages` empty pages in `fileName`, or in a temporary file.
func resumePdf(pages: u32, name: string = "")->String
{
    let fileName = name.count ? String.from(name) : Testing.tempFilePath("scope-resume-", ".pdf")
    var document = Pdf.Document.create()
    for pages
    {
        var page = Pdf.Page.create(320, 220)
        document.addPage(#move page)
    }

    expect document.save(fileName)
    return fileName
}

// Lets the window retire its viewer and show the home again.
func completeHome(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    for 64 where not window.home.isLocallyVisible()
    {
        Swag.drainWork()
        host.pump()
        if window.startupTimer do
            host.fireTimer(window.startupTimer)
    }

    Swag.require(window.home.isLocallyVisible())
}

// A document left in its middle keeps where it was left; the home names it and its action takes
// the document up again there. Read through, it keeps nothing.
#test
{
    let fileName = resumePdf(4)
    defer discard catch File.delete(fileName)
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.systemPlaces.clear()
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    let opened = String.from(window.currentFile)
    assume cast(*PdfDocument.Panel, window.currentView).pdfView.showPage(2)

    window.closeFile()
    completeHome(&host, window)
    let point = window.resumePoint(opened)
    Swag.require(point != null and point.page == 2 and point.pages == 4 and point.length == 0)
    Swag.require(point.positionText() == Format.toString(appStrings().home_ResumePage, 3, 4))
    Swag.require(point.shortText() == "p. 3 / 4")
    Swag.require(window.home.isLocallyVisible() and window.home.rows.count == 1)
    Swag.require(point.positionText() == window.home.resumeButton.text())
    Swag.require(window.home.resumeButton.isLocallyVisible() and window.home.restartButton.isLocallyVisible())

    // The card's action opens the document at the page it was left at.
    window.home.openRow(0)
    completeQueuedViewerFile(&host, window)
    for 64 where window.readingState.restoring do
        host.fireTimer(window.fileWatchTimer)
    let view = assume cast(*PdfDocument.Panel, window.currentView).pdfView
    Swag.require(view.pageIndex == 2)

    // Read to its last page, the document has nothing left to take up again.
    view.showPage(3)
    window.closeFile()
    completeHome(&host, window)
    Swag.require(window.resumePoint(opened) == null)
    Swag.require(window.home.resumeButton.text() == appStrings().home_Open)
    Swag.require(not window.home.restartButton.isLocallyVisible())
}

// Start Over opens the file from its start and forgets where it was left; leaving the history
// forgets the point too, and the points survive the saved state of the window.
#test
{
    let fileName = resumePdf(5)
    defer discard catch File.delete(fileName)
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.systemPlaces.clear()
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    let opened = String.from(window.currentFile)
    assume cast(*PdfDocument.Panel, window.currentView).pdfView.showPage(1)
    window.closeFile()
    completeHome(&host, window)
    Swag.require(window.resumePoint(opened) != null)

    let saved = saveViewerState(window)
    window.resumePoints.clear()
    loadViewerState(window, saved.toSlice())
    let loaded = window.resumePoint(opened)
    Swag.require(loaded != null and loaded.page == 1 and loaded.pages == 5 and loaded.reading.viewer == "pdf")

    window.home.restartRow(0)
    Swag.require(window.resumePoint(opened) == null)
    completeQueuedViewerFile(&host, window)
    Swag.require(assume cast(*PdfDocument.Panel, window.currentView).pdfView.pageIndex == 0)

    assume cast(*PdfDocument.Panel, window.currentView).pdfView.showPage(2)
    window.closeFile()
    completeHome(&host, window)
    Swag.require(window.resumePoint(opened) != null)
    window.forgetRecent(opened)
    Swag.require(window.resumePoint(opened) == null and window.resumePoints.isEmpty())
}

// A recording is named by its time, anything else by the share already read.
#test
{
    var point: ViewerResumePoint
    point.seconds  = 4332
    point.length   = 7020
    point.progress = 0.62
    Swag.require(point.positionText() == Format.toString(appStrings().home_ResumeAt, "1:12:12"))
    Swag.require(point.shortText() == "1:12:12 / 1:57:00")

    point.seconds, point.length = 0
    point.progress = 0.384
    Swag.require(point.positionText() == Format.toString(appStrings().home_ResumeShare, 38))
    Swag.require(point.shortText() == "38 %")
}

// The folders explored lately stand on the home, most recent first and without repeats; a first
// launch offers the system's places, and the two direct actions stand in for the card.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let datas  = scopeTestDataDirectory()
    let parent = String.from(Path.directoryName(datas) orelse "")
    window.systemPlaces.clear()
    window.systemPlaces.add(datas)
    window.systemPlaces.add(Path.combine(datas, "no such folder"))
    window.showEmpty(appStrings().ui_DropTitle)

    let home = window.home
    Swag.require(home.rows.isEmpty() and not home.explored and home.places.count == 1)
    Swag.require(home.openButton.isLocallyVisible() and home.exploreButton.isLocallyVisible())
    Swag.require(not home.resumeButton.isLocallyVisible() and not home.clearButton.isLocallyVisible())

    window.rememberExplored(datas)
    window.rememberExplored(parent)
    window.rememberExplored(datas.toString())
    Swag.require(window.exploredFolders.count == 2 and window.exploredFolders[0] == datas)
    home.refresh()
    Swag.require(home.explored and home.places.count == 2 and home.placeShown(1))
    Swag.require(home.placeName(0) == "datas")

    // A chip explores its folder.
    host.click(home.localToSurface(home.placeRect(0).center()))
    Swag.require(window.isExploring())
    completeExplorer(&host, unwrap window.explorer)
    Swag.require(window.exploredFolders[0] == datas)

    window.clearRecent()
    Swag.require(window.exploredFolders.isEmpty())
}

// The explorer names the action of a file left in its middle by where it takes it up again, in
// the sheet and the lens alike, and opening the file from the explorer resumes it there.
#test
{
    let folder = Testing.tempFilePath("scope-resume-folder-", "")
    expect Directory.create(folder, recurse: true)
    let fileName = resumePdf(6, Path.combine(folder, "left.pdf"))
    defer discard catch File.delete(fileName)
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    assume cast(*PdfDocument.Panel, window.currentView).pdfView.showPage(3)

    window.openExplorer(folder)
    let explorer = unwrap window.explorer
    completeExplorer(&host, explorer)
    var index = Swag.U64.Max
    for &entry, i in explorer.entries where entry.name == "left.pdf" do
        index = i
    Swag.require(index < explorer.entries.count)
    explorer.selected = index
    let point = window.resumePoint(explorer.entries[index].path)
    Swag.require(point != null and point.page == 3)
    Swag.require(point.positionText() == explorer.openActionName())
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.OpenChosen).name == point.positionText())

    explorer.activate(index)
    completeQueuedViewerFile(&host, window)
    for 64 where window.readingState.restoring do
        host.fireTimer(window.fileWatchTimer)
    Swag.require(assume cast(*PdfDocument.Panel, window.currentView).pdfView.pageIndex == 3)
}
