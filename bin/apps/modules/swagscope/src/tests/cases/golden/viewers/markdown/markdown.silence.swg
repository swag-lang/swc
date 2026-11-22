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
    host.setup(1280, 560)
    shipFrame(&host)
    host.app.setAppIcon(expect Image.decode(".png", AppIcon))
    if light do
        host.theme.setLight()
    host.notify(.ThemeChanged)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    if appearance != 0 do
        window.applyTheme(cast(u32, AppearanceTheme.Document))
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    let zoom = assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])
    Swag.require(not zoom.outline!.load.started)
    host.surface.setTitle("Reading quietly.md")
    window.applyLayout()
    host.settleAnimations(window)

    let view = assume cast(*Markdown.View, window.currentView)
    Swag.require(window.documentHost.padding.y == 0)
    Swag.require(view.padding.y == window.stripInset())
    Swag.require(window.readingLine.isLocallyVisible() and not window.viewerBar.isLocallyVisible())
    var image  = host.render(&host.surfaceWnd)
    let ground = view.themeColors().view_Bk
    Swag.require(image.pixelColor(10, 10) == ground)
    Swag.require(image.pixelColor(10, 100) == ground)
    assertScopeImageGolden(&image, golden)

    let viewport = host.surface.position
    window.setFullScreen(true)
    host.surface.showNormalAt(viewport)
    window.applyLayout()
    Swag.require(view.padding.y == 0 and window.stripInset() == 0)
    window.setFullScreen(false)
    Swag.require(view.padding.y == window.stripInset())
    Swag.require(host.surface.position == viewport)
    if appearance != 0
    {
        Swag.require(host.surfaceWnd.themeColors().wnd_Bk == ground)
        zoom.outline.toggle.setChecked(true)
        zoom.outline.toggle.sigCheckedChanged.call(zoom.outline.toggle)
        completeViewerBackgroundLoad(&host, &zoom.outline.load)
        Swag.require(zoom.outline.loaded and zoom.outline.headings.count == 2)
        window.applyLayout()
        host.settleAnimations(window)
        let appColors = window.themeColors()
        Swag.require(zoom.outline.list.themeColors().listItem_Text == appColors.label_Text)
        Swag.require(zoom.outline.filterBox.themeColors().edit_Text == appColors.label_Text)
        Swag.require(zoom.outline.filterBox.themeColors().edit_FocusBk == appColors.edit_FocusBk)
        host.surface.setTitle("Reading quietly.md")
        var outlineImage  = host.render(&host.surfaceWnd)
        let outlineGolden = Format.toString("%.outline", golden)
        assertScopeImageGolden(&outlineImage, outlineGolden.toString())
    }
}

func assertMarkdownPlanAppearance(light: bool, readerTheme: u32, title, source, golden: string)
{
    let previous = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previous
    MarkdownText.g_ViewerSettings = {themeIndex: readerTheme}

    let fileName = Testing.tempFilePath("scope-plan-appearance-", ".md")
    discard expect File.writeAllText(fileName, source)
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(1280, 720)
    shipFrame(&host)
    host.app.setAppIcon(expect Image.decode(".png", AppIcon))
    if light do
        host.theme.setLight()
    host.notify(.ThemeChanged)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.applyTheme(cast(u32, light ? AppearanceTheme.Light : AppearanceTheme.Dark))
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)

    let view    = assume cast(*Markdown.View, window.currentView)
    let zoom    = assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])
    let outline = unwrap zoom.outline
    outline.toggle.setChecked(true)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    completeViewerBackgroundLoad(&host, &outline.load)
    window.applyLayout()
    host.settleAnimations(window)

    let appColors = window.themeColors()
    Swag.require(view.themeColors().view_Bk != appColors.view_Bk)
    Swag.require(outline.themeColors().view_Bk == appColors.view_Bk)
    Swag.require(outline.list.themeColors().listItem_Text == appColors.label_Text)
    Swag.require(outline.filterBox.themeColors().edit_Text == appColors.label_Text)
    host.surface.setTitle(title)

    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, golden)
}

#[Swag.TestTag("golden")]
#test { assertMarkdownSilence(false, 0, "viewer.markdown.silence.encre") }

#[Swag.TestTag("golden")]
#test { assertMarkdownSilence(true, 0, "viewer.markdown.silence.paper") }

#[Swag.TestTag("golden")]
#test { assertMarkdownSilence(false, 5, "viewer.markdown.silence.whitey") }

#[Swag.TestTag("golden")]
#test
{
    assertMarkdownPlanAppearance(false,
                                 1,
                                 "GitHub.md",
                                 "# The northern route\n\nThe reader keeps a light page in a dark workspace.\n\n## Departure\n\nA calm outline beside the text.\n\n## Arrival\n\nThe application palette stays in charge of its controls.\n",
                                 "viewer.markdown.plan.github.encre")
}

#[Swag.TestTag("golden")]
#test
{
    assertMarkdownPlanAppearance(true,
                                 3,
                                 "Night.md",
                                 "# Carnet des saisons\n\nLa page garde son apparence sombre.\n\n## Automne\n\nLes notes restent lisibles.\n\n### Première marche\n\nLe panneau suit la palette claire de l'application.\n",
                                 "viewer.markdown.plan.night.paper")
}
