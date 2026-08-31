#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing

private func markdownFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/comprehensive.md")
}

private func markdownWhiteyFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/whitey.md")
}

// File-open failures cross the viewer boundary instead of becoming viewer-specific content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("missing_scope_markdown_%.md", Guid64.random()).toString())
    var result   = openTestViewer(markdownViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root)
    Swag.assert(result.view == null and result.commands == null)
    Swag.assert(!result.failureReason.isEmpty())
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("scope_markdown_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source = expect File.readAllText(markdownFixturePath())
    for 160 do
        source += "A README paragraph remains available for progressive wheel navigation.\n\n"
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let infoBar = Wnd.create'Wnd(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle = .Bottom

    var result = openTestViewer(markdownViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root, infoParent: infoBar)
    let wnd    = result.view
    Swag.assert(wnd != null)
    Swag.assert(result.commands != null)
    Swag.assert(result.revealMatch != null and result.searchBounds != null and result.clearSearch != null)
    Swag.assert(result.isLoading != null and result.isLoading!(wnd!))
    Swag.assert(Utf8.contains(result.details.toString(), "Markdown"))
    let commands = result.commands
    commands!.applyLayout()

    // Pointer use of either document command must return focus to the Markdown canvas after the
    // popup closes, leaving navigation keys attached to the document.
    let widthCombo = cast(*ComboBox) commands!.children[0]
    let themeCombo = cast(*ComboBox) commands!.children[1]
    Swag.assert((cast(*Markdown.View) wnd!).hasFocus())
    var comboPoint = widthCombo.surfaceRect().center()
    widthCombo.surface!.surfaceToScreen(&comboPoint)
    host.mouseDown(comboPoint)
    Swag.assert(widthCombo.hasFocus() and !widthCombo.hasVisibleFocus())
    host.keyPress(Input.Key.Escape)
    Swag.assert((cast(*Markdown.View) wnd!).hasFocus())
    host.mouseUp(comboPoint)

    comboPoint = themeCombo.surfaceRect().center()
    themeCombo.surface!.surfaceToScreen(&comboPoint)
    host.mouseDown(comboPoint)
    Swag.assert(themeCombo.hasFocus() and !themeCombo.hasVisibleFocus())
    host.keyPress(Input.Key.Escape)
    Swag.assert((cast(*Markdown.View) wnd!).hasFocus())
    host.mouseUp(comboPoint)

    // The application spinner follows scheduled work, not lazy source left on disk.
    for 64 where result.isLoading!(wnd!) do
        host.fireTimers()
    Swag.assert(!result.isLoading!(wnd!))
    Swag.assert((cast(*Markdown.View) wnd!).hasUnloadedSource())
}

// Reveals a marker beyond the initial resident window of a multi-megabyte Markdown document while
// leaving the remaining source on disk.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("scope_large_markdown_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let fixture       = expect File.readAllText(markdownFixturePath())
    let query         = "distant markdown verification marker"
    let fixtureOffset = Utf8.indexOf(fixture.toString(), query)
    Swag.assert(fixtureOffset != Swag.U64.Max)
    var source: String
    for 32_000 do
        source += "## Streamed section\n\nA paragraph remains outside the resident window.\n\n"
    let offset = source.length + fixtureOffset
    source += fixture
    for 8_000 do
        source += "A trailing paragraph keeps the document large.\n\n"
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(960, 680)
    view.applyLayout()
    Swag.assert(view.revealFileOffset(offset, query))

    var found:  bool
    var bounds: Math.Rectangle
    for 4_000 where view.hasUnloadedSource() and !found
    {
        host.fireTimers()
        found = view.searchMatchRect(&bounds)
    }

    Swag.assert(found and !bounds.isEmpty())
    Swag.assert(view.hasUnloadedSource())
    Swag.assert(view.loadedDocumentHeight() > view.documentStyle.topInset)
    let revealedBounds = bounds
    for 64 do
        host.fireTimers()
    Swag.assert(view.searchMatchRect(&bounds))
    Swag.assert(Math.abs(bounds.y - revealedBounds.y) < 1)
    view.clearSearchHighlight()
    Swag.assert(!view.searchMatchRect(&bounds))
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
    let view   = Markdown.View.createText(&host.root, source.toString(), style)
    applyMarkdownViewerStyle(view, 0, 1)
    view.resize(960, 680)
    view.applyLayout()

    Swag.assert(!view.isLoading())
    Swag.assert(view.loadedDocumentHeight() > style.topInset)
    Swag.assert(view.documentStyle.maxContentWidth == style.maxContentWidth)
    Testing.assertContentFits(view)
    host.settleAnimations(view, 8)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "viewer.markdown.document")
    Swag.assert(view.findText("Notes provide useful context"))
    Swag.assert(view.findText("Alignment"))
    Swag.assert(view.findText("fibonacci"))
    Swag.assert(view.findText("begin{bmatrix}"))
    Swag.assert(view.findText("Footnotes remain readable"))
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

    for themeIndex in backgrounds.count
    {
        let view = Markdown.View.createText(&host.root, source.toString())
        view.resize(960, 680)
        applyMarkdownViewerStyle(view, themeIndex, 1)
        view.applyLayout()
        view.computeStyle()
        Swag.assert(view.themeColors().view_Bk.argb == backgrounds[themeIndex])
        Swag.assert(view.documentStyle.lineHeight >= 1.5)
        if themeIndex == 5 do
            Swag.assert(view.documentStyle.headingAlignment == .Center)
        Testing.assertContentFits(view)
        var image = host.render(view)
        Swag.assert(image.isValid())
        view.destroy()
    }
}

// Whitey keeps soft-wrapped list items together, hangs wrapped lines beneath their wording, and
// draws list and task markers without depending on optional font glyphs.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 900)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let source = expect File.readAllText(markdownWhiteyFixturePath())
    let view   = Markdown.View.createText(&host.root, source.toString())
    view.resize(960, 900)
    applyMarkdownViewerStyle(view, 5, 1)
    view.applyLayout()
    Testing.assertContentFits(view)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "viewer.markdown.whitey")
}
