#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Filtering the bookmarks keeps the ones that match, each still leading to its own place, and
// clearing the filter brings every bookmark back.
#test
{
    var host: HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, scopeTestDataPath("document-outline.pdf"))
    let view    = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.resize(640, 360)
    view.applyLayout()

    let outline = unwrap view.outline
    Swag.require(outline.rows.count == 4 and view.bookmarks.count == 4)

    view.pdfView.showPage(1)
    outline.setFilter("chapter")
    Swag.require(outline.rows.count == 1 and outline.rowTitles[0] == view.bookmarks[0].title)
    Swag.require(outline.markedTarget() == 0)

    outline.setFilter("SECTION")
    Swag.require(outline.rows.count == 2 and outline.rowTitles[1] == view.bookmarks[2].title)

    outline.setFilter("no bookmark has this name")
    Swag.require(outline.rows.isEmpty() and outline.status.isLocallyVisible())

    outline.setFilter("")
    Swag.require(outline.rows.count == 4)
    for row in 4 do
        Swag.require(outline.rowTitles[row] == view.bookmarks[row].title)
}

// The outline marks the bookmark being read as the pages move, without asking the document to
// move again, and keeps the mark through its filter.
#test
{
    var host: HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, scopeTestDataPath("document-outline.pdf"))
    let view    = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.resize(640, 360)
    view.applyLayout()

    let outline = unwrap view.outline
    let pdf     = view.pdfView
    var chosen  = 0
    outline.sigSelected += func|&chosen|(_, _) { chosen += 1 }

    // The bookmark in view is marked from the start, before the reader moves.
    Swag.require(outline.markedTarget() == 0 and chosen == 0)

    // An open outline follows the pages as they move.
    outline.toggle.setChecked(true)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    Swag.require(outline.markedTarget() == 0)

    pdf.setZoom(1)
    let section = &view.bookmarks[1]
    pdf.showPosition(section.pageIndex, section.position)
    Swag.require(outline.markedTarget() == 1)

    // Just above the bookmark's point, the reader is still in the part before it.
    pdf.showPosition(section.pageIndex, {section.position.x, section.position.y - 40})
    Swag.require(outline.markedTarget() == 0)

    pdf.showPage(0)
    Swag.require(outline.markedTarget() == 0)
    Swag.require(chosen == 0 and not view.history.canGoBack())

    // The mark survives a filter that still lists the bookmark, and moves to the nearest one
    // listed before it otherwise.
    pdf.showPosition(section.pageIndex, section.position)
    outline.setFilter("section")
    Swag.require(outline.markedTarget() == 1)
    outline.setFilter("chapter")
    Swag.require(outline.markedTarget() == 0)
    outline.setFilter("")
    Swag.require(outline.markedTarget() == 1 and chosen == 0)

    // A closed outline does not follow the pages; it marks the bookmark in view as it opens again.
    outline.toggle.setChecked(false)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    pdf.showPage(0)
    Swag.require(outline.markedTarget() == 1)
    outline.toggle.setChecked(true)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    Swag.require(outline.markedTarget() == 0 and chosen == 0)
}

// A bookmark chosen at the end of the document stays marked although its point cannot rise to
// the top of the view.
#test
{
    var host: HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, scopeTestDataPath("document-outline.pdf"))
    let view    = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.resize(640, 360)
    view.applyLayout()

    let outline = unwrap view.outline
    outline.list.selectLine(2)
    Swag.require(view.pdfView.readingProgress() >= 1)
    Swag.require(outline.markedTarget() == 2)
    view.followReading()
    Swag.require(outline.markedTarget() == 2)
}
