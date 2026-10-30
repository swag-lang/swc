#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// The fixed afternoon the home writes its times against, so the pictures do not age.
const HomeNow = 17'u64 * Time.TicksPerHour + 50 * Time.TicksPerMinute + 739_000'u64 * Time.TicksPerDay

func homeFixture(name: string)->String => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas", name)

// Builds a window whose history holds six fixtures opened over the last days, on the theme of
// `light`, with the application mark the home shows.
func homeWindow(host: *Testing.HeadlessHost, light: bool)->*ViewerWindow
{
    host.setup(960, 640)
    shipFrame(host)
    host.app.setAppIcon(expect Image.decode(".png", AppIcon))
    if light do
        host.theme.setLight()
    else do
        host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.resize(960, 640)

    const Names: [6] string = ["sample.cpp", "comprehensive.md", "title.png", "viewer.pdf", "pacman_beginning.wav", "ffmpeg-h264-two-aac.mkv"]
    let hours: [6] u64 = [0, 1, 6, 30, 32, 100]
    for name, i in Names
    {
        window.recent.add(homeFixture(name))
        window.recentOpened.add(HomeNow - hours[i] * Time.TicksPerHour - 8 * Time.TicksPerMinute)
    }

    window.home.now = HomeNow
    window.showEmpty(appStrings().ui_DropTitle)

    window.applyLayout()
    return window
}

// The home lists the last six files, quietly: the faint glyph of the kind, the name, the time; the
// row under the pointer names its folder and offers its removal, and "Clear…" comes with the
// pointer. One picture per theme, at rest and in use.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        let window = homeWindow(&host, light)
        Swag.assert(window.home.isLocallyVisible() and window.home.rows.count == 6)
        Swag.assert(ViewerHome.openedText(window.home.rows[0].opened, HomeNow) == "17:42")
        Swag.assert(ViewerHome.openedText(window.home.rows[3].opened, HomeNow) == appStrings().home_Yesterday)
        host.settleAnimations(window, 4)

        var rest = host.render(window)
        Pixel.Testing.assertImageGolden(&rest, light ? "home.paper" : "home.ink")

        host.moveMouse(window.home.localToSurface(window.home.rowRect(1).center()))
        Swag.assert(window.home.hovered == 1 and window.home.pointerIn)
        window.home.invalidate()
        var hover = host.render(window)
        Swag.assert(window.home.hovered == 1 and window.home.pointerIn)
        Pixel.Testing.assertImageGolden(&hover, light ? "home.hover.paper" : "home.hover.ink")
    }
}

// A row opens its file; its cross and Delete take it out of the history, and the clears take
// the files that are gone or the ones opened more than a month ago.
#test
{
    var host: Testing.HeadlessHost
    let window = homeWindow(&host, false)

    let second = String.from(window.home.rows[1].file)
    window.home.removeRow(1)
    Swag.assert(window.recent.count == 5 and
                window.recentOpened.count == 5 and
                not window.recent.contains(second))
    Swag.assert(window.home.rows.count == 5)

    window.home.setFocus()
    window.home.chosen = 0
    host.keyPress(.Delete)
    Swag.assert(window.recent.count == 4 and window.home.rows.count == 4)

    window.recent.add(homeFixture("gone-for-good.txt"))
    window.recentOpened.add(HomeNow)
    Swag.assert(window.missingRecentCount() == 1)
    window.removeMissingRecent()
    Swag.assert(window.recent.count == 4 and window.missingRecentCount() == 0)

    // The fixtures were opened in the year 2025 of the fixed clock; the real one is later.
    Swag.assert(window.olderRecentCount() == 4)
    window.removeOlderRecent()
    Swag.assert(window.recent.isEmpty() and window.recentOpened.isEmpty() and window.home.rows.isEmpty())
}

// Opening a missing home row offers to forget that exact history entry and leaves the home
// invitation in place whether the reader keeps or removes it.
#test
{
    var host: Testing.HeadlessHost
    let window = homeWindow(&host, false)
    window.home.removeRow(5)

    let missing = homeFixture("gone-for-good.txt")
    window.recent.add(missing)
    window.recentOpened.add(HomeNow)
    window.home.refresh()
    Swag.assert(not File.exists(missing))

    host.clickModalButtonWhenShown(Dialog.BtnNo)
    window.queueFile(missing.toString(), offerForgetMissing: true)
    Swag.assert(window.home.isLocallyVisible() and window.home.message.isEmpty())
    completeViewerWindowClassification(&host, window)
    Swag.assert(host.autoHandled and window.home.isLocallyVisible())
    Swag.assert(window.home.message.isEmpty() and window.recent.contains(missing))

    host.clickModalButtonWhenShown(Dialog.BtnYes)
    window.queueFile(missing.toString(), offerForgetMissing: true)
    Swag.assert(window.home.isLocallyVisible() and window.home.message.isEmpty())
    completeViewerWindowClassification(&host, window)
    Swag.assert(host.autoHandled and window.home.isLocallyVisible())
    Swag.assert(window.home.message.isEmpty() and not window.recent.contains(missing))
}

// A recent row stays visible while classification runs, then gives way to the file when it opens.
#test
{
    var host: Testing.HeadlessHost
    let window = homeWindow(&host, false)
    let file   = String.from(window.home.rows[0].file)

    window.queueFile(file.toString(), offerForgetMissing: true)
    Swag.assert(window.home.isLocallyVisible())
    completeViewerWindowClassification(&host, window)
    Swag.assert(not window.home.isLocallyVisible() and not window.currentFile.isEmpty())
}
