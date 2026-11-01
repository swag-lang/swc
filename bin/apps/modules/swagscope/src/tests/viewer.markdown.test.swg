#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing, Viewers

// A missing optional family must fall back without installing or loading an application asset.
#test
{
    let absent = MarkdownText.systemFaces(["Swag Scope unavailable font family 794501"])
    for face in absent do
        Swag.assert(face == null)
    let absentAgain = MarkdownText.systemFaces(["Swag Scope unavailable font family 794501"])
    Swag.assert(absent == absentAgain)

    let installed = FontFamily.enumerateSystemFonts()
    if not installed.isEmpty()
    {
        let name     = installed[0].name.toString()
        let direct   = MarkdownText.systemFaces([name])
        let fallback = MarkdownText.systemFaces(["Swag Scope unavailable font family 794501", name])
        Swag.assert(direct == fallback)
    }
}

// Markdown places its options on the line of readings, and floats no commands over the document.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(markdownFixturePath(), remember: false)
    completeQueuedViewerFile(&host, window)

    let actions = unwrap window.currentActions
    Swag.assert(actions.parent == window.readingLine and actions.isLocallyVisible())
    Swag.assert(window.currentCommands == null)
    window.revealViewerBar()
    Swag.assert(not window.viewerBar.isLocallyVisible())
    let options = assume cast(*IconButton, actions.children[0])
    Swag.assert(options.arrowPosition == .RightDownward)
}

internal func markdownFixturePath()->String       => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/comprehensive.md")
internal func markdownWhiteyFixturePath()->String => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/whitey.md")

// Theme and line width are viewer preferences, not properties of one Markdown file.
#test
{
    let previous = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previous
    MarkdownText.g_ViewerSettings = {themeIndex: 3, widthIndex: 2}

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    var first         = openTestViewer(MarkdownText.viewerPlugin(), &host.root, markdownFixturePath(), commandParent: &host.root)
    let firstOptions  = assume cast(*IconButton, first.actions!.children[0])
    let firstZoom     = assume cast(*MarkdownText.ZoomButton, first.info!.children[0])
    let firstMarkdown = assume cast(*Markdown.View, first.view)
    assertViewerInfoButton(firstZoom)
    Swag.assert(first.info.preferredSize.x == Viewer.ZoomSlotWidth)

    var options: OptionSheet.Page
    MarkdownText.describeOptions(&options, firstMarkdown, firstZoom)
    Swag.assert(options.rows[0].value == MarkdownText.texts().ui_Wide and options.rows[1].value == "Night")

    host.activateOptionRowWhenShown(MarkdownText.texts().ui_Width)
    host.thenActivateOptionRow(MarkdownText.texts().ui_Narrow)
    host.thenActivateOptionRow(MarkdownText.texts().ui_Theme)
    host.thenActivateOptionRow("Whitey")
    MarkdownText.showOptions(firstOptions, firstMarkdown, firstZoom)
    Swag.assert(host.autoHandled and firstMarkdown.hasFocus())
    Swag.assert(MarkdownText.g_ViewerSettings.widthIndex == 0 and MarkdownText.g_ViewerSettings.themeIndex == 5)

    var second = openTestViewer(MarkdownText.viewerPlugin(), &host.root, markdownWhiteyFixturePath(), commandParent: &host.root)
    var secondOptions: OptionSheet.Page
    MarkdownText.describeOptions(&secondOptions, assume cast(*Markdown.View, second.view), assume cast(*MarkdownText.ZoomButton, second.info!.children[0]))
    Swag.assert(secondOptions.rows[0].value == MarkdownText.texts().ui_Narrow and secondOptions.rows[1].value == "Whitey")

    let oldWidth = String.from(MarkdownText.texts().ui_Narrow)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    var translated: OptionSheet.Page
    MarkdownText.describeOptions(&translated, firstMarkdown, firstZoom)
    Swag.assert(translated.rows[0].value == MarkdownText.texts().ui_Narrow and translated.rows[0].value.raw != oldWidth)
    Swag.assert(firstOptions.toolTip == "Options")
    Swag.assert(firstZoom.toolTip == MarkdownText.texts().ui_ZoomMenu)
    Swag.assert(MarkdownText.g_ViewerSettings.widthIndex == 0 and MarkdownText.g_ViewerSettings.themeIndex == 5)
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.assert(oldWidth == MarkdownText.texts().ui_Narrow)
}

// File-open failures cross the viewer boundary instead of becoming viewer-specific content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)

    let fileName = Gui.Testing.tempFilePath("scope-markdown-missing-", ".md")
    var result   = openTestViewer(MarkdownText.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view == null and result.commands == null)
    Swag.assert(not result.failureReason.isEmpty())
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-markdown-", ".md")
    defer discard catch File.delete(fileName)

    var source = expect File.readAllText(markdownFixturePath())
    for 160 do
        source += "A README paragraph remains available for progressive wheel navigation.\n\n"
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(960, 680)

    let infoBar = Wnd.create'Wnd(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle = .Bottom

    var result = openTestViewer(MarkdownText.viewerPlugin(), &host.root, fileName, commandParent: &host.root, infoParent: infoBar)
    let wnd    = result.view
    Swag.assert(wnd != null)
    Swag.assert(result.actions != null)
    Swag.assert(result.revealMatch != null and result.searchBounds != null and result.clearSearch != null)
    Swag.assert(result.isLoading != null and result.isLoading())
    Swag.assert(Utf8.contains(result.details, "Markdown"))
    let commands = result.actions
    commands.applyLayout()

    // Pointer use of the document options must return focus to the Markdown canvas once the sheet
    // closes, leaving navigation keys attached to the document.
    let optionsButton = assume cast(*IconButton, commands.children[0])
    Swag.assert(assume cast(*Markdown.View, wnd).hasFocus())
    host.activateOptionRowWhenShown(MarkdownText.texts().ui_Width)
    host.clickWnd(optionsButton)
    Swag.assert(host.autoHandled)
    Swag.assert(assume cast(*Markdown.View, wnd).hasFocus() and not optionsButton.hasFocus())

    // The application spinner follows scheduled work, not lazy source left on disk.
    for 64 where result.isLoading() do
        host.fireTimers()
    Swag.assert(not result.isLoading())
    Swag.assert(assume cast(*Markdown.View, wnd).hasUnloadedSource())
}

// Reveals a marker beyond the initial resident window of a multi-megabyte Markdown document while
// leaving the remaining source on disk.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-markdown-large-", ".md")
    defer discard catch File.delete(fileName)

    let fixture       = expect File.readAllText(markdownFixturePath())
    let query         = "distant markdown verification marker"
    let fixtureOffset = Utf8.indexOf(fixture, query)
    Swag.assert(fixtureOffset != Swag.U64.Max)
    var source: String
    for 32_000 do
        source += "## Streamed section\n\nA paragraph remains outside the resident window.\n\n"
    let offset = source.length + fixtureOffset
    source += fixture
    for 8_000 do
        source += "A trailing paragraph keeps the document large.\n\n"
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    with let view = Markdown.View.createFile(&host.root, fileName)
    {
        .resize(960, 680)
        .applyLayout()
    }

    let revealed = view.revealFileOffset(offset, query)
    Swag.assert(revealed)

    var found:  bool
    var bounds: Math.Rectangle
    for 4_000 where view.hasUnloadedSource() and not found
    {
        host.fireTimers()
        found = view.searchMatchRect(&bounds)
    }

    Swag.assert(found and not bounds.isEmpty())
    Swag.assert(view.hasUnloadedSource())
    Swag.assert(view.loadedDocumentHeight() > view.documentStyle.topInset)
    let revealedBounds = bounds
    for 64 do
        host.fireTimers()
    Swag.assert(view.searchMatchRect(&bounds))
    Swag.assert(Math.abs(bounds.y - revealedBounds.y) < 1)
    view.clearSearchHighlight()
    Swag.assert(not view.searchMatchRect(&bounds))
}

// Exercises every shipped appearance headlessly, including page color, typography, reading
// measure, and Whitey's light, spaced, centered headings.
#test
{
    let source = expect File.readAllText(markdownFixturePath())
    let backgrounds: [6] u32 = [0xFF17181C, 0xFFFFFFFF, 0xFFF3F2EE, 0xFF363B40, 0xFFFFFFFF, 0xFFFEFEFE]
    var host:        Testing.HeadlessHost
    host.setup(960, 680)

    for themeIndex in backgrounds.count
    {
        let view = Markdown.View.createText(&host.root, source)
        view.resize(960, 680)
        MarkdownText.applyViewerStyle(view, themeIndex, 1)
        view.applyLayout()
        view.computeStyle()
        Swag.assert(view.themeColors().view_Bk.argb == backgrounds[themeIndex])
        Swag.assert(view.documentStyle.lineHeight >= 1.5)
        if themeIndex == 5
        {
            Swag.assert(view.documentStyle.headingAlignment == .Center)
            Swag.assert(view.documentStyle.headingFontStyles[0] == .Regular)
            Swag.assert(view.documentStyle.headingFontStyles[1] == .Regular)
            Swag.assert(view.documentStyle.headingFontStyles[2] == .Italic)
        }

        Testing.assertContentFits(view)
        var image = host.render(view)
        Swag.assert(image.isValid())
        view.destroy()
    }
}
