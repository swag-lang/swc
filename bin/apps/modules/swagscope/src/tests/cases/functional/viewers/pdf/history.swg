#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// A bookmark jump can be undone and redone, each return restoring the place and the zoom the
// reader had; a new jump after a return drops the branch that return had left ahead.
#test
{
    var host: HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, scopeTestDataPath("document-outline.pdf"))
    let view    = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.resize(640, 360)
    view.applyLayout()

    let pdf = view.pdfView
    Swag.require(not view.history.canGoBack() and not view.history.canGoForward())
    pdf.setZoom(1)
    pdf.showPosition(0, {0, 120})

    view.showBookmark(1)
    Swag.require(pdf.pageIndex == 1 and view.history.canGoBack() and not view.history.canGoForward())
    pdf.zoomToFitWidth()

    view.goBack()
    Swag.require(pdf.pageIndex == 0 and pdf.zoomMode == .Free and pdf.effectiveZoom() == 1)
    Swag.require(not view.history.canGoBack() and view.history.canGoForward())

    view.goForward()
    Swag.require(pdf.pageIndex == 1 and pdf.zoomMode == .FitWidth)
    Swag.require(view.history.canGoBack() and not view.history.canGoForward())

    view.goBack()
    Swag.require(view.history.canGoForward())
    view.showBookmark(2)
    Swag.require(pdf.pageIndex == 2 and not view.history.canGoForward())
}

// Only a jump that moves the reader is remembered: a group bookmark and a refused page number
// leave the history alone, and a typed page is a jump like a bookmark.
#test
{
    var host: HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, scopeTestDataPath("document-outline.pdf"))
    let view    = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.resize(640, 360)
    view.applyLayout()

    view.showBookmark(3)
    view.showBookmark(99)
    Swag.require(not view.goToTypedPage("0") and not view.goToTypedPage("page"))
    Swag.require(not view.history.canGoBack())
    view.goBack()
    view.goForward()
    Swag.require(view.pdfView.pageIndex == 0)

    Swag.require(view.goToTypedPage("2") and view.pdfView.pageIndex == 1)
    Swag.require(view.history.canGoBack())
    view.goBack()
    Swag.require(view.pdfView.pageIndex == 0)
}

// Alt and the arrows walk the history from the page itself, and the lens names both steps in
// the reader's language, each faint while it has nowhere to go.
#test
{
    var host: HeadlessHost
    host.setup(640, 360)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, scopeTestDataPath("document-outline.pdf"))
    let view    = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.resize(640, 360)
    view.applyLayout()

    view.showBookmark(1)
    view.pdfView.setFocus()
    host.keyPress(.Left, .Alt)
    Swag.require(view.pdfView.pageIndex == 0)
    host.keyPress(.Right, .Alt)
    Swag.require(view.pdfView.pageIndex == 1)

    expect host.app.setLanguage("fr")
    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "PDF", host.theme)
    view.describeLens(&entries)
    var back, forward: const *Lens.Entry?
    for &entry in entries.section!.entries
    {
        if entry.title == "Retour dans le document" do
            back = entry
        elif entry.title == "Avancer dans le document" do
            forward = entry
    }

    Swag.require(back != null and forward != null)
    Swag.require(not back.disabled and forward.disabled)
}
