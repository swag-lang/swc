#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing

#test
{
    let fileName = Testing.tempFilePath("scope-outline-", ".html")
    discard expect File.writeAllBytes(fileName, "<html><body><h1>Guide</h1><div style='height:800px'></div><h2>Details</h2><div style='height:800px'></div></body></html>")
    defer discard catch File.delete(fileName)
    var host: HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    var session = openTestViewer(htmlViewerPlugin(), &host.root, fileName)
    let view    = cast(*HtmlViewer) session.view!
    for 128 where session.isLoading!(session.view!) do
        host.fireTimers()
    let outline = cast(*DocumentOutline) session.sidePanel!.children[0]
    Swag.assert(outline.rows.count == 2)
    outline.list.selectLine(1)
    let scroll = cast(*ScrollWnd) view.view.children[0]
    Swag.assert(scroll.scrollPosition().y > 700)
    view.setZoom(150)
    Swag.assert(outline.rows.count == 2 and outline.list.selectedLine() == outline.rows[1])
    outline.list.selectLine(0)
    Swag.assert(scroll.scrollPosition().y < 2)
}

#test
{
    let bodies = [
        "<office:text><text:h text:outline-level='1'>Guide</text:h><text:p>Introduction</text:p><text:h text:outline-level='3'>Details</text:h><text:p>Explanation</text:p></office:text>",
        "<office:spreadsheet><table:table table:name='First'><table:table-row><table:table-cell><text:p>Cell</text:p></table:table-cell></table:table-row></table:table><table:table table:name='Second'><table:table-row><table:table-cell><text:p>Other cell</text:p></table:table-cell></table:table-row></table:table></office:spreadsheet>",
        "<office:presentation><draw:page draw:name='First'><text:h>First</text:h></draw:page><draw:page draw:name='Second'><text:h>Second</text:h></draw:page></office:presentation>",
        "<office:drawing><draw:page draw:name='First'><text:h>First</text:h></draw:page><draw:page draw:name='Second'><text:h>Second</text:h></draw:page></office:drawing>"]
    let extensions = [".fodt", ".fods", ".fodp", ".fodg"]
    for body, index in bodies
    {
        let fileName = Testing.tempFilePath("scope-outline-", extensions[index])
        let source   = Format.toString("<?xml version='1.0'?><office:document-content xmlns:office='urn:o' xmlns:text='urn:t' xmlns:table='urn:table' xmlns:draw='urn:draw'><office:body>%</office:body></office:document-content>", body)
        discard expect File.writeAllBytes(fileName, source)
        defer discard catch File.delete(fileName)
        var host: HeadlessHost
        host.setup(640, 360)
        defer host.shutdown()
        var session = openTestViewer(openDocumentViewerPlugin(), &host.root, fileName)
        let view    = cast(*OpenDocumentViewer) session.view!
        completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
        Swag.assert(view.failureReason.isEmpty())
        let outline = view.outline!
        Swag.assert(outline.rows.count == 2)
        outline.list.selectLine(1)
        if index == 0 do
            Swag.assert(outline.rows[1].level == 1 and not outline.rows[0].canExpand())
        elif index == 1 do
            Swag.assert(view.sheetIndex == 1)
        else do
            Swag.assert(view.slideIndex == 1)
    }
}

// The panel is hosted at the information edge and exposes the document hierarchy in both languages.
#[Swag.TestTag("golden")]
#test
{
    let previous = g_MarkdownViewerSettings
    defer g_MarkdownViewerSettings = previous
    g_MarkdownViewerSettings = {}
    let fileName = Testing.tempFilePath("scope-outline-", ".md")
    let source   = "# Document guide\n\nAn introduction to this document.\n\n## Getting started\n\nRead the first steps.\n\n### Installation\n\nInstall the application.\n\n### Configuration\n\nChoose your preferences.\n\n## Reference\n\nThe complete reference.\n\n### Commands\n\nThe available commands.\n"
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) source)
    defer discard catch File.delete(fileName)
    var host: HeadlessHost
    host.setup(880, 560)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    let zoom    = cast(*MarkdownZoomButton) window.currentInfo!.children[0]
    let outline = zoom.outline!
    Swag.assert(not outline.load.started)
    outline.toggle.setChecked(true)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    completeViewerBackgroundLoad(&host, &outline.load, outline.loadTimer)
    Swag.assert(outline.rows.count == 6 and outline.list.lineCount() == 6)
    window.applyLayout()
    let firstText = outline.list.cellTextRect(0, 0)
    let depths    = [0, 1, 2, 2, 1, 2]
    for row, index in outline.rows
    {
        Swag.assert(row.parent == null and not row.canExpand())
        let text = outline.list.cellTextRect(cast(u32) index, 0)
        Swag.assert(Math.abs(text.x - firstText.x - depths[index] * 16) <= 1)
    }

    outline.list.selectLine(0)
    host.focus(outline.list.listView)
    host.keyPress(.Left)
    Swag.assert(outline.list.lineCount() == 6)
    window.applyLayout()
    let previousScroll = (cast(*ScrollWnd) window.currentView!.children[0]).scrollPosition().y
    let cell = outline.list.cellTextRect(5, 0)
    host.click(outline.list.listView.localToSurface(cell.center()))
    discard host.render(window)
    Swag.assert(outline.list.selectedLine() == outline.rows[5])
    Swag.assert((cast(*ScrollWnd) window.currentView!.children[0]).scrollPosition().y > previousScroll)
    outline.list.selectLine(0)
    host.settleAnimations(window, 6)
    let scroll = cast(*ScrollWnd) window.currentView!.children[0]
    scroll.setScrollPos(0, 150)
    let firstCell = outline.list.cellTextRect(0, 0)
    host.click(outline.list.listView.localToSurface(firstCell.center()))
    host.settleAnimations(window, 6)
    let firstHeading = scroll.view.children[0]
    let inset        = (cast(*Markdown.View) window.currentView!).documentStyle.topInset
    Swag.assert(Math.abs(firstHeading.surfaceRect().y - scroll.surfaceRect().y - inset) < 2)
    var image = host.render(window)
    image.crop(outline.surfaceRect())
    Pixel.Testing.assertImageGolden(&image, "viewer.outline.markdown")
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    window.resize(880, 420)
    window.applyLayout()
    Swag.assert(outline.title.text() == "Plan" and outline.toggle.toolTip == "Plan")
    Swag.assert(outline.list.selectedLine() == outline.rows[0])
    Testing.assertContentFits(outline)
    var french = host.render(window)
    french.crop(outline.surfaceRect())
    Pixel.Testing.assertImageGolden(&french, "viewer.outline.markdown.fr")
    window.setFullScreen(true)
    Swag.assert(not window.currentSidePanelHost!.isVisible())
    window.setFullScreen(false)
    Swag.assert(window.currentSidePanelHost!.isVisible())
}

#test
{
    var host: HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let path    = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/document-outline.pdf")
    var session = openTestViewer(pdfViewerPlugin(), &host.root, path)
    let view    = cast(*PdfViewer) session.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    let outline = view.outline!
    Swag.assert(outline.rows.count == 4 and outline.rows[1].level == 1 and not outline.rows[0].canExpand())
    view.pdfView.setZoom(1)
    outline.list.selectLine(1)
    Swag.assert(view.pdfView.pageIndex == 1)
    outline.list.selectLine(0)
    Swag.assert(view.pdfView.pageIndex == 0)
    outline.list.selectLine(3)
    Swag.assert(view.pdfView.pageIndex == 0)
}
