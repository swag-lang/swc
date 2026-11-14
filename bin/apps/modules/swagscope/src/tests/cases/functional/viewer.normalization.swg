#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Page navigation still works while Find owns focus, and never navigates to another file.
#test
{
    let fileName = createPdfFixture()
    defer discard catch File.delete(fileName)
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, false)
    let pdf    = assume cast(*PdfDocument.Panel, window.currentView)
    Swag.require(pdf.pageLabel.text() == "1 / 2")
    Swag.require(not pdf.previousButton.isEnabled() and pdf.nextButton.isEnabled())
    Swag.require(window.viewerBar.isLocallyVisible())
    Swag.require(window.documentArea().bottom() <= window.viewerBar.position.y)
    Swag.require(pdf.zoomLabel.surfaceRect().y >= window.readingLine.surfaceRect().y)
    window.showSearch()
    host.keyPress(.PageDown, .Control)
    Swag.require(pdf.pdfView.pageIndex == 1 and pdf.pageLabel.text() == "2 / 2")
    Swag.require(not pdf.nextButton.isEnabled() and window.searchBox.hasFocus())
    host.keyPress(.PageDown, .Control)
    Swag.require(pdf.pdfView.pageIndex == 1 and window.currentFile == fileName)
    host.keyPress(.PageUp, .Control)
    Swag.require(pdf.pdfView.pageIndex == 0 and pdf.pageLabel.text() == "1 / 2")
    window.searchNext.setFocus()
    host.keyPress(.Escape)
    Swag.require(not window.searchBar.isLocallyVisible())
}

// A font's total and ordinal remain valid after a jump, including both endpoints.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fontFixturePath(), true)
    let font   = assume cast(*Typeface.Panel, window.currentView)
    font.document.setFocus()
    let total = font.document.pageStarts.count
    Swag.require(total > 1 and font.pageLabel.text() == Viewer.pageText(0, total))
    host.keyPress(.PageDown, .Control)
    Swag.require(font.document.pageIndex == 1 and font.pageLabel.text() == Viewer.pageText(1, total))
    font.document.goToCharacterPage(font.document.pageStarts.back())
    host.keyPress(.PageDown, .Control)
    Swag.require(not font.nextButton.isEnabled() and font.previousButton.isEnabled())
    Swag.require(font.pageLabel.text() == Viewer.pageText(total - 1, total))
    font.document.goToCharacterPage(0x20)
    host.keyPress(.PageUp, .Control)
    Swag.require(not font.previousButton.isEnabled() and font.pageLabel.text() == Viewer.pageText(0, total))
}

// Search keeps room for typing beside the information sheet, without covering the document.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("comprehensive.txt"), true, width: ViewerWindow.MinWidth)
    window.toggleFilePanel()
    window.toggleInformation()
    window.showSearch()
    window.applyLayout()
    Swag.require(window.searchBox.position.width >= 120)
    Swag.require(window.searchBar.position.bottom() <= window.infoSheet.position.y)
    Swag.require(window.searchBox.surfaceRect().right() <= window.searchCloseButton.surfaceRect().x)
    Swag.require(window.searchBar.position.bottom() <= window.documentArea().y)
    window.searchBox.setText("the")
    host.clickWnd(window.searchCloseButton)
    Swag.require(not window.searchBar.isLocallyVisible() and window.searchBox.text() == "the")
    window.showSearch()
    Swag.require(window.searchBox.text() == "the" and window.searchBox.hasFocus())
}

// Image sets keep page arrows, total and endpoint behavior alongside the shared zoom readout.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("imageset-pages-raw.tiff"), false)
    let image  = assume cast(*Picture.Panel, window.currentView)
    image.imageView.setFocus()
    let count = cast(u64, image.imageView.movie.frameCount)
    Swag.require(count > 1 and image.frameLabel.text() == Viewer.pageText(0, count))
    host.keyPress(.PageDown, .Control)
    Swag.require(image.imageView.movie.frameIndex == 1 and image.frameLabel.text() == Viewer.pageText(1, count))
    image.imageView.setFrameIndex(cast(s32, count) - 1)
    Swag.require(not image.nextPage.isEnabled())
    host.keyPress(.PageDown, .Control)
    Swag.require(image.imageView.movie.frameIndex == cast(s32, count) - 1)
    window.currentCommands!.resize(240, window.currentCommands.position.height)
    window.currentCommands.applyLayout()
    Swag.require(image.previousPage.isLocallyVisible() and image.nextPage.isLocallyVisible())
    Swag.require(image.nextPage.position.right() <= 240)
}

// Packaged reading surfaces share one footer and the same page controls as PDF and images.
#test
{
    for fileName in ["viewer.comic.cbz", "viewer.epub"]
    {
        var host:     Testing.HeadlessHost
        let window = framedViewerWindow(&host, scopeTestDataPath(fileName), true)
        let view   = window.currentView
        var embedded: *EmbeddedViewer
        if view is Comic.Panel as comic
        {
            embedded = assume cast(*EmbeddedViewer, comic.embedded)
        }
        else
        {
            let epub = assume cast(*Epub.Panel, view)
            embedded = assume cast(*EmbeddedViewer, epub.embedded)
        }

        Swag.require(embedded.externalReadings and embedded.header.parent == window.currentInfo)
        Swag.require(not embedded.titleLabel.isLocallyVisible())
        Swag.require(embedded.header.position.width > 0 and embedded.currentInfo!.position.width > 0)
        Swag.require(embedded.currentInfo!.surfaceRect().right() <= window.readingLine.surfaceRect().right())
        Swag.require(window.viewerBar.isLocallyVisible() and window.readingLine.isLocallyVisible())
        window.viewerFocusTarget()?.setFocus()
        host.keyPress(.PageDown, .Control)
        completeQueuedViewerFile(&host, window)
        if view is Comic.Panel as comic
        {
            Swag.require(comic.activePage == 1 and comic.pageLabel.text() == "2 / 2", Format.toString("active % · pending % · readout %", comic.activePage, comic.pendingPage, comic.pageLabel.text()))
        }
        else
        {
            let epub = assume cast(*Epub.Panel, view)
            Swag.require(epub.chapter == 1 and epub.chapterLabel.text() == "2 / 2")
        }
    }
}
