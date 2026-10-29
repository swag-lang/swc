#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing, Viewers

// Reading grounds, chrome and outline stay coherent across document and application appearances.
func assertMarkdownSilence(light: bool, appearance: u32, golden: string)
{
    let previous = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previous
    MarkdownText.g_ViewerSettings = {themeIndex: appearance}
    let fileName = Testing.tempFilePath("scope-silence-", ".md")
    discard expect File.writeAllText(fileName, "# Reading quietly\n\nA document keeps **emphasis**, `inline code` and [links](https://example.org) in the same reading line.\n\n## A second section\n\nThe outline stays beside the work.\n")
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(1280, 800)
    shipFrame(&host)
    host.app.setAppIcon(expect Image.decode(".png", AppIcon))
    if light do
        host.theme.setLight()
    host.notify(.ThemeChanged)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    let zoom = assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])
    if zoom.outline!.load.isPending() do
        completeViewerBackgroundLoad(&host, &zoom.outline.load)
    zoom.reportStatistics()
    host.surface.setTitle("Reading quietly.md")
    window.applyLayout()
    host.settleAnimations(window)

    let view = assume cast(*Markdown.View, window.currentView)
    Swag.assert(window.documentHost.padding.y == 0)
    Swag.assert(view.padding.y == window.stripInset())
    Swag.assert(zoom.outline.loaded and zoom.outline.headings.count == 2)
    Swag.assert(not window.readingLine.isLocallyVisible() and not window.viewerBar.isLocallyVisible())
    var image  = host.render(&host.surfaceWnd)
    let ground = view.themeColors().view_Bk
    Swag.assert(image.pixelColor(10, 10) == ground)
    Swag.assert(image.pixelColor(10, 100) == ground)
    Pixel.Testing.assertImageGolden(&image, golden)

    let viewport = host.surface.position
    window.setFullScreen(true)
    host.surface.showNormalAt(viewport)
    window.applyLayout()
    Swag.assert(view.padding.y == 0 and window.stripInset() == 0)
    window.setFullScreen(false)
    Swag.assert(view.padding.y == window.stripInset())
    Swag.assert(host.surface.position == viewport)
    if appearance != 0 do
        Swag.assert(host.surfaceWnd.themeColors().wnd_Bk == ground)
}

#[Swag.TestTag("golden")]
#test { assertMarkdownSilence(false, 0, "viewer.markdown.silence.encre") }

#[Swag.TestTag("golden")]
#test { assertMarkdownSilence(true, 0, "viewer.markdown.silence.paper") }

#[Swag.TestTag("golden")]
#test { assertMarkdownSilence(false, 5, "viewer.markdown.silence.whitey") }

// A long margin is independently scrollable and follows keyboard navigation to its last heading.
#test
{
    let previous = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previous
    MarkdownText.g_ViewerSettings = {}
    let fileName = Testing.tempFilePath("scope-margin-", ".md")
    var source: String
    for index in 40 do
        source += Format.toString("## Section %\n\nA paragraph in the reading column.\n\n", index)
    discard expect File.writeAllText(fileName, source)
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(1600, 600)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    let zoom = assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])
    if zoom.outline!.load.isPending() do
        completeViewerBackgroundLoad(&host, &zoom.outline.load)
    window.applyLayout()
    let margin = unwrap zoom.readingMargin
    Swag.assert(margin.isVisible() and margin.entries.count == 40)
    Swag.assert(margin.surfaceRect().bottom() <= window.currentView!.surfaceRect().bottom())
    Swag.assert(margin.scroll.scrollSize.y > margin.scroll.clientRect().height)
    host.mouseWheel(margin.surfaceRect().center(), -120)
    Swag.assert(margin.scroll.scrollTarget().y > 0)
    host.focus(margin)
    host.keyPress(.End)
    for 128 where zoom.view.isLoading() do
        host.fireTimers()
    margin.follow()
    Swag.assert(zoom.view.readingOffset() == zoom.outline.headings[39].sourceOffset)
    Swag.assert(margin.list.active == 39)
    Swag.assert(margin.scroll.scrollPosition().y > 0)

    window.resize(640, 420)
    window.applyLayout()
    Swag.assert(not margin.isLocallyVisible())
    zoom.outline.toggle.setChecked(true)
    zoom.outline.toggle.sigCheckedChanged.call(zoom.outline.toggle)
    Swag.assert(zoom.outline.filterBox.hasFocus())
}
