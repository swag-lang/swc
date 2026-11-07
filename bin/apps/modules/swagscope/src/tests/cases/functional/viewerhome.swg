#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// The fixed afternoon the home writes its times against, so the pictures do not age.
internal const HomeNow = 17'u64 * Time.TicksPerHour + 50 * Time.TicksPerMinute + 739_000'u64 * Time.TicksPerDay

func homeFixture(name: string)->String => Path.combine(testSourceRoot(#curlocation), "datas", name)

// Builds a window whose history holds six fixtures opened over the last days and two explored
// folders, on the theme of `light`, with the application mark the home shows.
internal func homeWindow(host: *Testing.HeadlessHost, light: bool, height = 640)->*ViewerWindow
{
    host.setup(960, height)
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
    window.resize(960, height)

    const Names: [6] string = ["comprehensive.md", "sample.cpp", "title.png", "viewer.pdf", "pacman_beginning.wav", "ffmpeg-h264-two-aac.mkv"]
    let hours: [6] u64 = [0, 1, 6, 30, 32, 100]
    for name, i in Names
    {
        window.recent.add(homeFixture(name))
        window.recentOpened.add(HomeNow - hours[i] * Time.TicksPerHour - 8 * Time.TicksPerMinute)
    }

    let datas = Path.directoryName(homeFixture(Names[0])) orelse ""
    window.systemPlaces.clear()
    window.rememberExplored(Path.combine(datas, "viewer.archive.zip"))
    window.rememberExplored(datas)
    window.home.now = HomeNow
    window.showEmpty(appStrings().ui_DropTitle)

    window.applyLayout()
    completeHomePreviews(host, window.home)
    return window
}

// Lets every picture the home asked for arrive, so a capture does not depend on worker speed.
internal func completeHomePreviews(host: *Testing.HeadlessHost, home: *ViewerHome)
{
    for 64 where not home.previewsSettled()
    {
        home.preview.task.wait()
        host.pump()
    }

    Swag.require(home.previewsSettled())
}

// Clear opens after a completed click, supports cancelling the gesture, and keeps its trigger
// visible while the menu owns the pointer. Cancelling the confirmation preserves the history.
#test
{
    var host: Testing.HeadlessHost
    let window = homeWindow(&host, false)
    let button = window.home.clearButton
    Swag.require(button.isLocallyVisible() and button.arrowPosition == .RightDownward)
    var clear = button.surfaceRect().center()
    host.surface.surfaceToScreen(&clear)

    var sawMenu: bool
    host.app.sigFrame += func|host = &host, home = window.home, sawMenu = &sawMenu|(_)
    {
        let menu = host.capturedPopupMenu()
        if not menu do
            return
        sawMenu[] = true
        Swag.require(home.clearButton.isLocallyVisible())
        var point = menu.surfaceRect().center()
        host.surface.surfaceToScreen(&point)
        host.moveMouse(point)
        Swag.require(not home.pointerIn and home.clearButton.isLocallyVisible())
    }

    host.clickPopupMenuItemWhenShown("scope.home.clear.all")
    host.thenClickModalButton(Dialog.BtnNo)
    host.mouseDown(clear)
    Swag.require(button.mouseCapture() == button)
    Swag.require(host.capturedPopupMenu() == null)
    host.mouseUp(clear)
    Swag.require(sawMenu and host.autoHandled and window.recent.count == 6)
    Swag.require(button.isLocallyVisible() and button.mouseCapture() == null)

    // Releasing outside the command cancels this click.
    host.mouseDown(clear)
    host.moveMouse({0, 0})
    host.mouseUp({0, 0})
    Swag.require(button.mouseCapture() == null and host.capturedPopupMenu() == null)
    Swag.require(window.recent.count == 6)

    host.clickPopupMenuItemWhenShown("scope.home.clear.all")
    host.thenClickModalButton(Dialog.BtnYes)
    button.setFocus()
    host.keyPress(.Return)
    Swag.require(host.autoHandled and window.recent.isEmpty() and window.home.rows.isEmpty())
    Swag.require(not button.isLocallyVisible())
    Swag.require(window.home.openButton.isLocallyVisible() and window.home.exploreButton.isLocallyVisible())
}

// A row opens its file; its remove button and Delete ask before taking it out of the history.
#test
{
    var host: Testing.HeadlessHost
    let window = homeWindow(&host, false)

    let button = window.home.removeButton
    Swag.require(not button.isLocallyVisible())
    let picture = window.home.pictureRect(1)
    let size = host.theme.metrics.control_InspectorHeight
    let buttonRect = Math.Rectangle{picture.right() - size - 4, picture.y + 4, size, size}
    Swag.require(window.home.removeRect(1) == buttonRect and window.home.rowRect(1).contains(buttonRect.center()))
    let point = buttonRect.center()
    let screenPoint = window.home.localToSurface(point)
    host.moveMouse(screenPoint)
    Swag.require(window.home.hovered == 1 and button.isLocallyVisible())
    Swag.require(button.position == buttonRect)
    let clickPoint = window.home.localToSurface(button.position.center())
    Swag.require(host.mouseTargetAt(clickPoint) == button)
    host.moveMouse(clickPoint)
    Swag.require(window.home.pointerIn and window.home.hovered == 1 and button.isLocallyVisible())

    let second = String.from(window.home.rows[1].file)
    host.clickModalButtonWhenShown(Dialog.BtnNo)
    host.click(clickPoint)
    Swag.require(window.recent.count == 6 and window.recent.contains(second))

    host.clickModalButtonWhenShown(Dialog.BtnYes)
    host.click(clickPoint)
    Swag.require(window.recent.count == 5 and
                 window.recentOpened.count == 5 and
                 not window.recent.contains(second))
    Swag.require(window.home.rows.count == 5)

    window.home.setFocus()
    window.home.chosen = 0
    host.clickModalButtonWhenShown(Dialog.BtnNo)
    host.keyPress(.Delete)
    Swag.require(window.recent.count == 5 and window.home.rows.count == 5)

    window.recent.add(homeFixture("gone-for-good.txt"))
    window.recentOpened.add(HomeNow)
    Swag.require(window.missingRecentCount() == 1)
    window.removeMissingRecent()
    Swag.require(window.recent.count == 5 and window.missingRecentCount() == 0)

    // The fixtures were opened in the year 2025 of the fixed clock; the real one is later.
    Swag.require(window.olderRecentCount() == 5)
    window.removeOlderRecent()
    Swag.require(window.recent.isEmpty() and window.recentOpened.isEmpty() and window.home.rows.isEmpty())
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
    Swag.require(not File.exists(missing))

    host.clickModalButtonWhenShown(Dialog.BtnNo)
    window.queueFile(missing.toString(), offerForgetMissing: true)
    Swag.require(window.home.isLocallyVisible() and window.home.message.isEmpty())
    completeViewerWindowClassification(&host, window)
    Swag.require(host.autoHandled and window.home.isLocallyVisible())
    Swag.require(window.home.message.isEmpty() and window.recent.contains(missing))

    host.clickModalButtonWhenShown(Dialog.BtnYes)
    window.queueFile(missing.toString(), offerForgetMissing: true)
    Swag.require(window.home.isLocallyVisible() and window.home.message.isEmpty())
    completeViewerWindowClassification(&host, window)
    Swag.require(host.autoHandled and window.home.isLocallyVisible())
    Swag.require(window.home.message.isEmpty() and not window.recent.contains(missing))
}

// A short window lets the folders give way before the tiles, and a taller one gives them back.
#test
{
    var host: Testing.HeadlessHost
    let home  = homeWindow(&host, false).home
    let place = home.layout()
    Swag.require(home.places.count == 2 and not place.showPlaces and not home.placeShown(0))
    Swag.require(home.rowRect(5).bottom() <= home.clientRect().bottom() - ViewerHome.BottomReserve)

    var tallHost: Testing.HeadlessHost
    let tall      = homeWindow(&tallHost, false, height: 760).home
    let tallPlace = tall.layout()
    Swag.require(tallPlace.showPlaces and tall.placeShown(1))
    Swag.require(tall.placeRect(0).x + ViewerHome.PlaceInset == tallPlace.column.x)
    Swag.require(tall.placeRect(1).bottom() <= tall.clientRect().bottom() - ViewerHome.BottomReserve)
}

// A recent row stays visible while classification runs, then gives way to the file when it opens.
#test
{
    var host: Testing.HeadlessHost
    let window = homeWindow(&host, false)
    let file   = String.from(window.home.rows[0].file)

    window.queueFile(file.toString(), offerForgetMissing: true)
    Swag.require(window.home.isLocallyVisible())
    completeViewerWindowClassification(&host, window)
    Swag.require(not window.home.isLocallyVisible() and not window.currentFile.isEmpty())
}
