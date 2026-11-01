#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing, Viewers

// A manuscript can interleave HTML spreads and Markdown figures, with local SVG resources.
func assertMarkdownImages(themeIndex: u32, dpiScale: f32, golden: string)
{
    var host: Testing.HeadlessHost
    host.setup(960, 680, dpiScale)

    let fileName = scopeTestDataPath("markdown.images.md")
    var result   = openTestViewer(MarkdownText.viewerPlugin(), &host.root, fileName)
    Swag.assert(result.view != null and result.failureReason.isEmpty())
    let view = assume cast(*Markdown.View, result.view)
    MarkdownText.applyViewerStyle(view, themeIndex, 1)
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
    assertScopeImageGolden(&image, golden)
}

// Whitey's bold-italic face can lack arrows even though the family itself is installed.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 200)
    let view = Markdown.View.createText(&host.root, "> ***530 → 780 → 470 → 580 → 600 → 500 → 420 → 560 → 650 → 520***")
    view.resize(960, 200)
    MarkdownText.applyViewerStyle(view, 5, 1)
    view.applyLayout()
    Testing.assertContentFits(view)
    var image = host.render(view)
    assertScopeImageGolden(&image, "viewer.markdown.whitey.arrows")
}

// Full-screen reading reaches every edge; transient controls never resize the document.
#[Swag.TestTag("golden")]
#test
{
    let previous = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previous
    MarkdownText.g_ViewerSettings = {themeIndex: 1}
    var host: Testing.HeadlessHost
    host.setup(1280, 720, 1.5)
    shipFrame(&host)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let fileName = scopeTestDataPath("markdown.images.md")
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    let padding  = window.documentHost.padding
    let viewport = host.surface.position
    window.setFullScreen(true)

    // Keep the virtual monitor fixed; the desktop monitor belongs to the machine running the test.
    host.surface.showNormalAt(viewport)
    window.applyLayout()
    for 64 where assume cast(*Markdown.View, window.currentView).isLoading() do
        host.fireTimers()
    Swag.assert(window.documentHost.padding == Math.Vector4{})
    Swag.assert(window.documentPanel.backgroundStyle == .View)
    Swag.assert(window.currentView!.surfaceRect().width == window.clientRect().width)
    let bounds = window.currentView.surfaceRect()
    window.notePointer({10, 1})
    Swag.assert(window.currentView.surfaceRect() == bounds)
    window.notePointer({10, 719})
    Swag.assert(window.currentView.surfaceRect() == bounds)
    window.concealViewerBar()
    host.settleAnimations(window)
    var image = host.render(window)
    Swag.assert(image.width == cast(u32, viewport.width) and image.height == cast(u32, viewport.height))
    Swag.assert(image.pixelColor(0, 0).argb == 0xFFFFFFFF)
    assertScopeImageGolden(&image, "viewer.markdown.fullscreen")
    window.setFullScreen(false)
    Swag.assert(window.documentHost.padding == padding and window.documentPanel.backgroundStyle == .View)
}

// Zoom gestures share the menu's bounded scale and the next document keeps the preference.
#[Swag.TestTag("golden")]
#test
{
    let previous = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previous
    MarkdownText.g_ViewerSettings = {}
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var result = openTestViewer(MarkdownText.viewerPlugin(), &host.root, markdownFixturePath())
    let view   = assume cast(*Markdown.View, result.view)
    let zoom   = assume cast(*MarkdownText.ZoomButton, result.info!.children[0])
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
    assertScopeImageGolden(&image, "viewer.markdown.zoom")
    var second     = openTestViewer(MarkdownText.viewerPlugin(), &host.root, markdownFixturePath())
    let secondZoom = assume cast(*MarkdownText.ZoomButton, second.info!.children[0])
    Swag.assert(secondZoom.zoomPercent == 150)
    Swag.assert(assume cast(*Markdown.View, second.view).documentStyle.bodyFontSize == 24)
}

// The information band reports the complete source, independently of progressive layout,
// and re-translates the totals without counting again.
#[Swag.TestTag("golden")]
#test
{
    let previous = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previous
    MarkdownText.g_ViewerSettings = {}

    // The golden shows the file name, so it is fixed rather than unique.
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp), "markdown-statistics.md")
    discard expect File.writeAllText(fileName, "Alpha beta\r\nthree\u00a0four\n")
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
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
    let button = assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])
    if button.statisticsLoad.isPending() do
        completeViewerBackgroundLoad(&host, &button.statisticsLoad)
    Swag.assert(Utf8.startsWith(window.readingLine.details.text(), "Markdown · UTF-8 · 2 lines · 4 words · 23 characters · "))
    window.applyLayout()
    host.settleAnimations(window, 6)
    var image = host.render(window)
    assertScopeImageGolden(&image, "viewer.markdown.information")

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    window.applyLayout()
    Swag.assert(Utf8.startsWith(window.readingLine.details.text(), "Markdown · UTF-8 · 2 lignes · 4 mots · 23 caractères · "))
}

#[Swag.TestTag("golden")]
#test { assertMarkdownImages(1, 1, "viewer.markdown.images") }

#[Swag.TestTag("golden")]
#test { assertMarkdownImages(5, 1, "viewer.markdown.images.whitey") }

#[Swag.TestTag("golden")]
#test { assertMarkdownImages(1, 1.5, "viewer.markdown.images.hidpi") }

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    let source = expect File.readAllText(markdownFixturePath())
    let style  = MarkdownText.viewerStyle(0, 1)
    let view   = Markdown.View.createText(&host.root, source, style)
    MarkdownText.applyViewerStyle(view, 0, 1)
    view.resize(960, 680)
    view.applyLayout()

    Swag.assert(not view.isLoading())
    Swag.assert(view.loadedDocumentHeight() > style.topInset)
    Swag.assert(view.documentStyle.maxContentWidth == style.maxContentWidth)
    Testing.assertContentFits(view)
    host.settleAnimations(view, 8)
    var image = host.render(view)
    assertScopeImageGolden(&image, "viewer.markdown.document")
    Swag.assert(view.findText("Notes provide useful context"))
    Swag.assert(view.findText("Alignment"))
    Swag.assert(view.findText("fibonacci"))
    Swag.assert(view.findText("begin{bmatrix}"))
    Swag.assert(view.findText("Footnotes remain readable"))
}

// Whitey keeps soft-wrapped list items together, hangs wrapped lines beneath their wording, and
// draws list and task markers without depending on optional font glyphs.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 900)

    let source = expect File.readAllText(markdownWhiteyFixturePath())
    let view   = Markdown.View.createText(&host.root, source)
    view.resize(960, 900)
    MarkdownText.applyViewerStyle(view, 5, 1)
    view.applyLayout()
    Testing.assertContentFits(view)
    var image = host.render(view)
    assertScopeImageGolden(&image, "viewer.markdown.whitey")
}

// Whitey's justified fluid measure keeps an ordinary blank visible after styled text and between
// unstyled words at a fractional device scale.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(1160, 260, dpiScale: 1.5)

    let source = "L'unité que cet étalon porte a été prise au pays lui-même. Le mètre est le **dix-millionième** d'un **quart de méridien**, l'arc du pôle à l'équateur. On l'a mesuré sur le terrain du nord au sud, de Dunkerque à Barcelone **par Paris**, le long de cette ligne que le premier chant avait chiffrée sous *Devin* et que la flèche de Roncevaux avait ensuite abandonnée comme axe. Le bec du coq ouvrait un quart dès le premier matin, sans qu'on pût savoir lequel, et la géodésie, la science qui mesure la Terre, n'en connaît qu'un. Congédié comme direction, le méridien de Paris revient comme étalon. Il ne tient plus la carte, il tient l'unité avec quoi on la mesure."
    let view   = Markdown.View.createText(&host.root, source)
    view.resize(1160, 260)
    MarkdownText.applyViewerStyle(view, 5, 3)
    view.applyLayout()
    var image = host.render(view)
    assertScopeImageGolden(&image, "viewer.markdown.whitey.justified")
}
