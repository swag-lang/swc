#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

#test
{
    let executable         = Env.executablePath()
    let direct: [1] string = [executable]
    @assert(viewerStartupFile(direct).isEmpty())

    let withFile: [2] string = [executable, executable]
    @assert(viewerStartupFile(withFile) == executable)
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_text_stream_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for 2_000 do
        source += "A source line that stays readable while the rest remains on disk.\n"
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 200, 36})
    let view     = BasicTextView.create(&host.root, commands, fileName)
    view.resize(800, 520)
    view.applyLayout()

    let loaded = view.editor.text()
    @assert(@countof(loaded) <= 16 * 1024)
    @assert(view.stream.isOpen())
    @assert(expect view.stream.position() < view.fileSize)

    var image = host.render(view)
    view.updateEstimatedHeight()
    let loadedHeight = view.editor.loadedDocumentHeight()
    @assert(image.isValid() and loadedHeight > 0)
    @assert(view.editor.scrollableClientRect().height > loadedHeight)

    view.editor.setScrollPosition({0, loadedHeight * 2})
    let position = view.editor.scrollPosition()
    @assert(position.y > loadedHeight)
    view.loadNextChunk()
    @assert(view.editor.scrollPosition() == position)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.app.theme.setSwagDark()
    host.app.notifyThemeChanged()

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.applyLayout()

    @assert(window.commandBar.position.height == ViewerBarHeight)
    @assert(window.infoBar.position.height == ViewerInfoHeight)
    @assert(window.infoBar.backgroundStyle != window.commandBar.backgroundStyle)
    @assert(window.infoTypeLabel.name.raw == "NO FILE")
    @assert(window.emptyLabel.name.raw == appStrings().ui_DropTitle or @countof(window.emptyLabel.name.raw) > @countof(appStrings().ui_DropTitle))
    @assert(!window.previousButton.isEnabled())
    @assert(!window.nextButton.isEnabled())
    @assert(window.currentView == null)
    @assert(window.currentCommands == null)
    @assert(window.plugins.first == null)
    @assert(!window.viewerCombo.isLocallyVisible())
    Testing.assertContentFits(window)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.currentView     = Wnd.create'Wnd(window)
    window.currentCommands = Wnd.create'Wnd(window.commandBar)
    window.currentFile     = "sample.cpp"
    window.previousButton.enable(true)
    window.nextButton.enable(true)

    window.showEmpty(appStrings().ui_Unsupported)
    @assert(window.currentView == null)
    @assert(window.currentCommands == null)
    @assert(window.currentFile.isEmpty())
    @assert(!window.previousButton.isEnabled() and !window.nextButton.isEnabled())
    @assert(window.titleLabel.name.raw == "sFileScope")
}

// Pins the shipped empty surface: one accent line, one compact command row, and no eager
// format-specific controls before a file has selected a plugin.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    window.applyLayout()
    host.settleAnimations(window, 4)

    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "sfilescope.surface")
}
