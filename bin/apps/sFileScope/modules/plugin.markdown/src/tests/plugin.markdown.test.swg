using Core, Pixel, Gui, Gui.Testing

private func markdownFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/comprehensive.md")
}

// File-open failures cross the plugin boundary instead of becoming plugin-specific content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("missing_sfilescope_markdown_%.md", Guid64.random()).toString())
    let request  = ViewerRequest{ViewerPluginApiVersion, &host.root, &host.root, fileName.toString()}
    var result: ViewerResult
    @assert(sFileScopePluginCreate(&request, &result))
    @assert(result.view == null and result.commands == null)
    @assert(!result.failureReason.isEmpty())
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_markdown_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let source = expect File.readAllText(markdownFixturePath())
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let request = ViewerRequest{ViewerPluginApiVersion, &host.root, &host.root, fileName.toString()}
    var result: ViewerResult
    @assert(sFileScopePluginCreate(&request, &result))
    let wnd = result.view
    @assert(wnd != null)
    @assert(result.commands != null)
    @assert(result.revealMatch != null)
    @assert(result.isLoading != null and result.isLoading!(wnd!))
    @assert(Utf8.contains(result.details.toString(), "Markdown"))
    let commands = result.commands
    commands!.applyLayout()

    // Pointer use of either document command must return focus to the Markdown canvas after the
    // popup closes, leaving navigation keys attached to the document.
    let widthCombo = cast(*ComboBox) commands!.children[0]
    let themeCombo = cast(*ComboBox) commands!.children[1]
    @assert((cast(*MarkdownView) wnd!).hasFocus())
    var comboPoint = widthCombo.surfaceRect().center()
    widthCombo.surface!.surfaceToScreen(&comboPoint)
    host.mouseDown(comboPoint)
    @assert(widthCombo.hasFocus() and !widthCombo.hasVisibleFocus())
    host.keyPress(Input.Key.Escape)
    @assert((cast(*MarkdownView) wnd!).hasFocus())
    host.mouseUp(comboPoint)

    comboPoint = themeCombo.surfaceRect().center()
    themeCombo.surface!.surfaceToScreen(&comboPoint)
    host.mouseDown(comboPoint)
    @assert(themeCombo.hasFocus() and !themeCombo.hasVisibleFocus())
    host.keyPress(Input.Key.Escape)
    @assert((cast(*MarkdownView) wnd!).hasFocus())
    host.mouseUp(comboPoint)
}

// Reveals a marker beyond the initial resident window of a multi-megabyte Markdown document while
// leaving the remaining source on disk.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_large_markdown_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let fixture       = expect File.readAllText(markdownFixturePath())
    let query         = "distant markdown verification marker"
    let fixtureOffset = Utf8.indexOf(fixture.toString(), query)
    @assert(fixtureOffset != Swag.U64.Max)
    var source: String
    for 32_000 do
        source += "## Streamed section\n\nA paragraph remains outside the resident window.\n\n"
    let offset = source.length + fixtureOffset
    source += fixture
    for 8_000 do
        source += "A trailing paragraph keeps the document large.\n\n"
    @assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let view = MarkdownView.createFile(&host.root, fileName)
    view.resize(960, 680)
    view.applyLayout()
    @assert(view.revealFileOffset(offset, query))

    var found: bool
    for 4_000 where view.isLoading() and !found
    {
        host.fireTimers()
        found = view.findText(query)
    }

    @assert(found)
    @assert(view.isLoading())
    @assert(view.loadedDocumentHeight() > view.documentStyle.topInset)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let source = expect File.readAllText(markdownFixturePath())
    let style  = markdownViewerStyle(0, 1)
    let view   = MarkdownView.createText(&host.root, source.toString(), style)
    applyMarkdownViewerStyle(view, 0, 1)
    view.resize(960, 680)
    view.applyLayout()

    @assert(!view.isLoading())
    @assert(view.loadedDocumentHeight() > style.topInset)
    @assert(view.documentStyle.maxContentWidth == style.maxContentWidth)
    Testing.assertContentFits(view)
    host.settleAnimations(view, 8)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "plugin.markdown.document")
    @assert(view.findText("Notes provide useful context"))
    @assert(view.findText("Alignment"))
    @assert(view.findText("fibonacci"))
    @assert(view.findText("begin{bmatrix}"))
    @assert(view.findText("Footnotes remain readable"))
}

// Exercises the application-bound appearance and every shipped document profile headlessly,
// including page color, typography, reading measure, and Whitey's centered headings.
#test
{
    let source               = expect File.readAllText(markdownFixturePath())
    let backgrounds: [6] u32 = [0xFF15151A, 0xFFFFFFFF, 0xFFF3F2EE, 0xFF363B40, 0xFFFFFFFF, 0xFFFEFEFE]
    var host:        Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    for themeIndex in @countof(backgrounds)
    {
        let view = MarkdownView.createText(&host.root, source.toString())
        view.resize(960, 680)
        applyMarkdownViewerStyle(view, themeIndex, 1)
        view.applyLayout()
        view.computeStyle()
        @assert(view.themeColors().view_Bk.argb == backgrounds[themeIndex])
        @assert(view.documentStyle.lineHeight >= 1.5)
        if themeIndex == 5 do
            @assert(view.documentStyle.headingAlignment == .Center)
        Testing.assertContentFits(view)
        var image = host.render(view)
        @assert(image.isValid())
        view.destroy()
    }
}
