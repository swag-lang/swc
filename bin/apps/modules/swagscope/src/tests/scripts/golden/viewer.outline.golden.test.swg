#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing, Viewers

// The panel is hosted at the information edge and exposes the document hierarchy in both languages.
#[Swag.TestTag("golden")]
#test
{
    let previous = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previous
    MarkdownText.g_ViewerSettings = {}
    let fileName = Testing.tempFilePath("scope-outline-", ".md")
    let source   = "# Document guide\n\nAn introduction to this document.\n\n## Getting started\n\nRead the first steps.\n\n### Installation\n\nInstall the application.\n\n### Configuration\n\nChoose your preferences.\n\n## Reference\n\nThe complete reference.\n\n### Commands\n\nThe available commands.\n\n###### Literal <b>tags</b> remain part of the heading, with a deliberately long title that continues well beyond the width of the outline panel and must remain available in full when the row is hovered.\n"
    discard expect File.writeAllBytes(fileName, source)
    defer discard catch File.delete(fileName)
    var host: HeadlessHost
    host.setup(880, 560)
    shipFrame(&host)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    Swag.assert(not window.readingLine.isLocallyVisible())
    Swag.assert(not window.viewerBar.isLocallyVisible())
    let zoom    = assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])
    let outline = unwrap zoom.outline
    Swag.assert(outline.load.started or outline.loaded)
    outline.toggle.setChecked(true)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    if outline.load.isPending() do
        completeViewerBackgroundLoad(&host, &outline.load)
    Swag.assert(outline.rows.count == 7 and outline.list.lineCount() == 7)
    window.applyLayout()
    let firstText = outline.list.cellTextRect(0, 0)
    let depths    = [0, 1, 2, 2, 1, 2, 5]
    for row, index in outline.rows
    {
        Swag.assert(row.parent == null and not row.canExpand())
        let text = outline.list.cellTextRect(cast(u32, index), 0)
        Swag.assert(Math.abs(text.x - firstText.x - depths[index] * 16) <= 1)
    }

    let longCell = outline.list.cellTextRect(6, 0)
    host.moveMouse(outline.list.listView.localToSurface(longCell.center()))
    Swag.assert(outline.list.listView.toolTip == outline.headings[6].title)

    outline.list.selectLine(0)
    host.focus(outline.list.listView)
    host.keyPress(.Left)
    Swag.assert(outline.list.lineCount() == 7)
    window.applyLayout()
    let previousScroll = assume cast(*ScrollWnd, window.currentView!.children[0]).scrollPosition().y
    let cell = outline.list.cellTextRect(5, 0)
    host.click(outline.list.listView.localToSurface(cell.center()))
    discard host.render(window)
    Swag.assert(outline.list.selectedLine() == outline.rows[5])
    Swag.assert(assume cast(*ScrollWnd, window.currentView.children[0]).scrollPosition().y > previousScroll)
    outline.list.selectLine(0)
    host.settleAnimations(window, 6)
    let scroll = assume cast(*ScrollWnd, window.currentView.children[0])
    scroll.setScrollPos(0, 150)
    let firstCell = outline.list.cellTextRect(0, 0)
    host.click(outline.list.listView.localToSurface(firstCell.center()))
    host.settleAnimations(window, 6)
    let firstHeading = scroll.view.children[0]
    let inset        = assume cast(*Markdown.View, window.currentView).documentStyle.topInset
    Swag.assert(Math.abs(firstHeading.surfaceRect().y - scroll.surfaceRect().y - inset) < 2)
    Swag.assert(not (outline.parent is FloatingPanel))
    Swag.assert(outline.surfaceRect().y - window.surfaceRect().y >= window.stripInset() + window.themeMetrics().floating_Inset)
    var image = host.render(window)
    image.crop(outline.surfaceRect())
    Pixel.Testing.assertImageGolden(&image, "viewer.outline.markdown")
    var whole = host.render(window)
    Pixel.Testing.assertImageGolden(&whole, "viewer.outline.markdown.window")

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    window.resize(880, 420)
    window.applyLayout()
    Swag.assert(outline.section!.text == "Plan" and outline.toggle.toolTip == "Plan")
    Swag.assert(window.outlineCaptionButton.toolTip == Format.toString("Plan (%)",
                                                                       Input.formatKeyShortcut(Input.KeyModifiers.Control | .Shift, .O)))
    Swag.assert(outline.list.selectedLine() == outline.rows[0])
    Testing.assertContentFits(outline)
    var french = host.render(window)
    french.crop(outline.surfaceRect())
    Pixel.Testing.assertImageGolden(&french, "viewer.outline.markdown.fr")
    window.setFullScreen(true)
    Swag.assert(not window.currentSidePanelHost!.isVisible())
    Swag.assert(not window.outlineCaptionButton.isLocallyVisible())
    window.setFullScreen(false)
    Swag.assert(window.currentSidePanelHost.isVisible())
    Swag.assert(window.outlineCaptionButton.isLocallyVisible())
    Swag.assert(not window.readingLine.isLocallyVisible())
    Swag.assert(not window.viewerBar.isLocallyVisible())
}
