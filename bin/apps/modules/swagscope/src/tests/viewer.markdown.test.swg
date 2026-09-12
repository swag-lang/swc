#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing

// A missing optional family must fall back without installing or loading an application asset.
#test
{
    let absent = markdownSystemFaces(["Swag Scope unavailable font family 794501"])
    for face in absent do
        Swag.assert(face == null)
    let absentAgain = markdownSystemFaces(["Swag Scope unavailable font family 794501"])
    Swag.assert(absent == absentAgain)

    #static if #os == Swag.TargetOs.Windows
    {
        let installed = FontFamily.enumerateSystemFonts()
        if not installed.isEmpty()
        {
            let name     = installed[0].name.toString()
            let direct   = markdownSystemFaces([name])
            let fallback = markdownSystemFaces(["Swag Scope unavailable font family 794501", name])
            Swag.assert(direct == fallback)
        }
    }
}

// Full-screen reading reaches every edge; transient controls never resize the document.
#[Swag.TestTag("golden")]
#test
{
    let previous = g_MarkdownViewerSettings
    defer g_MarkdownViewerSettings = previous
    g_MarkdownViewerSettings = {themeIndex: 1}
    var host: Testing.HeadlessHost
    host.setup(1280, 720, 1.5)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/markdown.images.md")
    window.openFile(fileName.toString(), remember: false)
    completeQueuedViewerFile(&host, window)
    let padding = window.documentHost.padding
    window.setFullScreen(true)
    window.resize(1280, 720)
    window.applyLayout()
    for 64 where (cast(*Markdown.View) window.currentView!).isLoading() do
        host.fireTimers()
    Swag.assert(window.documentHost.padding == Math.Vector4{})
    Swag.assert(window.documentPanel.backgroundStyle == .View)
    Swag.assert(window.currentView!.surfaceRect().width == window.clientRect().width)
    let bounds = window.currentView!.surfaceRect()
    window.updateFullScreenChrome({10, 1})
    Swag.assert(window.currentView!.surfaceRect() == bounds)
    window.updateFullScreenChrome({10, 719})
    Swag.assert(window.currentView!.surfaceRect() == bounds)
    window.updateFullScreenChrome({640, 360})
    host.settleAnimations(window)
    var image = host.render(window)
    Swag.assert(image.pixelColor(0, 0).argb == 0xFFFFFFFF)
    Pixel.Testing.assertImageGolden(&image, "viewer.markdown.fullscreen")
    window.setFullScreen(false)
    Swag.assert(window.documentHost.padding == padding and window.documentPanel.backgroundStyle == .Panel)
}

// Zoom gestures share the menu's bounded scale and the next document keeps the preference.
#[Swag.TestTag("golden")]
#test
{
    let previous = g_MarkdownViewerSettings
    defer g_MarkdownViewerSettings = previous
    g_MarkdownViewerSettings = {}
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)
    var result = openTestViewer(markdownViewerPlugin(), &host.root, markdownFixturePath().toString())
    let view   = cast(*Markdown.View) result.view!
    let zoom   = cast(*MarkdownZoomButton) result.info!.children[0]
    view.resize(960, 680)
    view.applyLayout()
    for 64 where view.isLoading() do
        host.fireTimers()
    host.focus(view)
    host.keyPress(.OemPlus, .Control)
    Swag.assert(zoom.zoomPercent == 125 and view.documentStyle.bodyFontSize == 20)
    host.keyPress(.Subtract, .Control)
    Swag.assert(zoom.zoomPercent == 100)
    host.mouseWheel({480, 300}, 120, .Control)
    Swag.assert(zoom.zoomPercent == 125)
    host.mouseWheel({480, 300}, -120, .Control)
    Swag.assert(zoom.zoomPercent == 100)
    zoom.applyZoom(0)
    host.keyPress(.OemMinus, .Control)
    Swag.assert(zoom.zoomPercent == 50)
    zoom.applyZoom(400)
    host.keyPress(.Add, .Control)
    Swag.assert(zoom.zoomPercent == 300)
    host.keyPress(.D0, .Control)
    Swag.assert(zoom.zoomPercent == 100)
    zoom.applyZoom(150)
    Testing.assertContentFits(view)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "viewer.markdown.zoom")
    var second     = openTestViewer(markdownViewerPlugin(), &host.root, markdownFixturePath().toString())
    let secondZoom = cast(*MarkdownZoomButton) second.info!.children[0]
    Swag.assert(secondZoom.zoomPercent == 150)
    Swag.assert((cast(*Markdown.View) second.view!).documentStyle.bodyFontSize == 24)
}

// The information band reports the complete source, independently of progressive layout,
// and re-translates the totals without counting again.
#[Swag.TestTag("golden")]
#test
{
    let previous = g_MarkdownViewerSettings
    defer g_MarkdownViewerSettings = previous
    g_MarkdownViewerSettings = {}
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "markdown-statistics.md")
    discard expect File.writeAllBytes(fileName.toString(), cast(const [..] u8) "Alpha beta\r\nthree\u00a0four\n")
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
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
    window.openFile(fileName.toString(), remember: false)
    completeQueuedViewerFile(&host, window)
    let button = cast(*MarkdownZoomButton) window.currentInfo!.children[0]
    if button.statisticsLoad.started do
        button.statisticsLoad.task.wait()
    if button.statisticsTimer do
        host.fireTimer(button.statisticsTimer)
    Swag.assert(window.infoStatsLabel.text() == "Markdown · UTF-8 · 2 lines · 4 words")
    window.applyLayout()
    Swag.assert(window.infoStatsLabel.position.width >= Math.ceil(window.infoStatsLabel.itf.measureContent({}).x))
    host.settleAnimations(window, 6)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "viewer.markdown.information")

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    window.applyLayout()
    Swag.assert(window.infoStatsLabel.text() == "Markdown · UTF-8 · 2 lignes · 4 mots")
    Swag.assert(window.infoStatsLabel.position.width >= Math.ceil(window.infoStatsLabel.itf.measureContent({}).x))
}

// A manuscript can interleave HTML spreads and Markdown figures, with local SVG resources.
func assertMarkdownImages(themeIndex: u32, dpiScale: f32, golden: string)
{
    var host: Testing.HeadlessHost
    host.setup(960, 680, dpiScale)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/markdown.images.md")
    var result   = openTestViewer(markdownViewerPlugin(), &host.root, fileName.toString())
    Swag.assert(result.view != null and result.failureReason.isEmpty())
    let view = cast(*Markdown.View) result.view
    applyMarkdownViewerStyle(view, themeIndex, 1)
    view.resize(960, 680)
    view.applyLayout()
    for 64 where view.hasUnloadedSource() do
        host.fireTimers()
    Swag.assert(not view.hasUnloadedSource())
    Swag.assert(view.findText("Before after."))
    Swag.assert(view.findText("FIG. 5 — The center."))
    Swag.assert(not view.findText("*FIG.") and not view.findText("**The center"))
    Swag.assert(not view.findText("Opening spread") and not view.findText("</div>"))
    view.clearSearchHighlight()
    Testing.assertContentFits(view)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, golden)
}

#[Swag.TestTag("golden")]
#test { assertMarkdownImages(1, 1, "viewer.markdown.images") }

#[Swag.TestTag("golden")]
#test { assertMarkdownImages(5, 1, "viewer.markdown.images.whitey") }

#[Swag.TestTag("golden")]
#test { assertMarkdownImages(1, 1.5, "viewer.markdown.images.hidpi") }

private func markdownFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/comprehensive.md")
}

private func markdownWhiteyFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/whitey.md")
}

// Theme and line width are viewer preferences, not properties of one Markdown file.
#test
{
    let previous = g_MarkdownViewerSettings
    defer g_MarkdownViewerSettings = previous
    g_MarkdownViewerSettings = {themeIndex: 3, widthIndex: 2}

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    var first      = openTestViewer(markdownViewerPlugin(), &host.root, markdownFixturePath().toString(), commandParent: &host.root)
    let firstWidth = cast(*ComboBox) first.commands!.children[0]
    let firstTheme = cast(*ComboBox) first.commands!.children[1]
    let firstZoom  = cast(*MarkdownZoomButton) first.info!.children[0]
    assertViewerInfoButton(firstZoom)
    Swag.assert(first.info!.preferredSize.x == ViewerZoomSlotWidth)
    Swag.assert(firstWidth.selectedIndex == 2 and firstTheme.selectedIndex == 3)
    firstWidth.setSelectedIndex(0)
    firstTheme.setSelectedIndex(5)
    Swag.assert(g_MarkdownViewerSettings.widthIndex == 0 and g_MarkdownViewerSettings.themeIndex == 5)

    var second      = openTestViewer(markdownViewerPlugin(), &host.root, markdownWhiteyFixturePath().toString(), commandParent: &host.root)
    let secondWidth = cast(*ComboBox) second.commands!.children[0]
    let secondTheme = cast(*ComboBox) second.commands!.children[1]
    Swag.assert(secondWidth.selectedIndex == 0 and secondTheme.selectedIndex == 5)

    let oldWidth = String.from(firstWidth.items[0]!.name.raw)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(firstWidth.items[0]!.name.raw == markdownStrings().ui_Narrow and firstWidth.items[0]!.name.raw != oldWidth)
    Swag.assert(secondWidth.items[0]!.name.raw == firstWidth.items[0]!.name.raw)
    Swag.assert(firstTheme.items[0]!.name.raw == markdownStrings().ui_ThemeApp)
    Swag.assert(firstWidth.toolTip == markdownStrings().ui_TipWidth and firstTheme.toolTip == markdownStrings().ui_TipTheme)
    Swag.assert(firstZoom.toolTip == markdownStrings().ui_ZoomMenu)
    Swag.assert(firstWidth.selectedIndex == 0 and firstTheme.selectedIndex == 5)
    Swag.assert(g_MarkdownViewerSettings.widthIndex == 0 and g_MarkdownViewerSettings.themeIndex == 5)
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.assert(firstWidth.items[0]!.name.raw == oldWidth)
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
    Swag.assert(not result.failureReason.isEmpty())
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("scope_markdown_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source = expect File.readAllText(markdownFixturePath())
    for 160 do
        source += "A README paragraph remains available for progressive wheel navigation.\n\n"
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.storage(), source.length))

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
    Swag.assert(result.isLoading != null and result.isLoading(wnd))
    Swag.assert(Utf8.contains(result.details.toString(), "Markdown"))
    let commands = result.commands
    commands.applyLayout()

    // Pointer use of either document command must return focus to the Markdown canvas after the
    // popup closes, leaving navigation keys attached to the document.
    let widthCombo = cast(*ComboBox) commands.children[0]
    let themeCombo = cast(*ComboBox) commands.children[1]
    Swag.assert((cast(*Markdown.View) wnd).hasFocus())
    var comboPoint = widthCombo.surfaceRect().center()
    widthCombo.surface!.surfaceToScreen(&comboPoint)
    host.mouseDown(comboPoint)
    Swag.assert(widthCombo.hasFocus() and not widthCombo.hasVisibleFocus())
    host.keyPress(Input.Key.Escape)
    Swag.assert((cast(*Markdown.View) wnd).hasFocus())
    host.mouseUp(comboPoint)

    comboPoint = themeCombo.surfaceRect().center()
    themeCombo.surface!.surfaceToScreen(&comboPoint)
    host.mouseDown(comboPoint)
    Swag.assert(themeCombo.hasFocus() and not themeCombo.hasVisibleFocus())
    host.keyPress(Input.Key.Escape)
    Swag.assert((cast(*Markdown.View) wnd).hasFocus())
    host.mouseUp(comboPoint)

    // The application spinner follows scheduled work, not lazy source left on disk.
    for 64 where result.isLoading(wnd) do
        host.fireTimers()
    Swag.assert(not result.isLoading(wnd))
    Swag.assert((cast(*Markdown.View) wnd).hasUnloadedSource())
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
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.storage(), source.length))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(960, 680)
    view.applyLayout()
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

#[Swag.TestTag("golden")]
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

    Swag.assert(not view.isLoading())
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
    let source = expect File.readAllText(markdownFixturePath())
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
#[Swag.TestTag("golden")]
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
