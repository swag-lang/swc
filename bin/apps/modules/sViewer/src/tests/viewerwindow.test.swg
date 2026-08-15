#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

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
    @assert(window.emptyLabel.name.raw == appStrings().ui_DropTitle or @countof(window.emptyLabel.name.raw) > @countof(appStrings().ui_DropTitle))
    @assert(!window.previousButton.isEnabled())
    @assert(!window.nextButton.isEnabled())
    @assert(window.currentView == null)
    @assert(window.currentCommands == null)
    @assert(window.plugins.first == null)
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
    @assert(window.titleLabel.name.raw == "sViewer")
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
    Pixel.Testing.assertImageGolden(&image, "sviewer.surface")
}
