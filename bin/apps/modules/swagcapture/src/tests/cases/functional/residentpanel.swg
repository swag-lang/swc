#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// Reports whether `panel` lists the command `id`.
func testPanelOffers(panel: *ResidentPanel, id: WndId)->bool
{
    for item in panel.menu.items where item and not item.separator and not item.label and item.id == id do
        return true
    return false
}

// Startup waits for the recent-file scan before sizing the hub, so its first visible bounds
// already include a recent row whenever the library has a capture.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    main.recentWnd.addRecent("recent.scc", testFramePicture(80, 8))
    Swag.require(not main.recentWnd.loadDone)
    main.sendCommandEvent(ActionGlobal.ShowHub)
    Swag.require(main.openHubAfterRecentLoad and main.residentPanel == null)
    main.recentWnd.loadRecent()
    Swag.require(not main.openHubAfterRecentLoad and main.residentPanel != null)
    let panel = main.residentPanel
    Swag.require(panel.recents != null)
    let bounds = panel.surface!.position
    host.pump()
    Swag.require(main.residentPanel == panel and panel.surface.position == bounds)
    panel.close()
}

// The hub repaints as decoded recent thumbnails arrive, including refreshed known files.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    main.recentWnd.addRecent("first.scc", testFramePicture(40, 8), front: false)
    let panel = testOpenResidentPanel(&host, main, .Hub)
    let surface = unwrap panel.surface
    let recents = unwrap panel.recents
    surface.show()
    host.app.runFrame()
    let width = cast(s32, surface.position.width)
    let height = cast(s32, surface.position.height)
    var first = host.app.renderer.readRenderTarget(&surface.rt, 0, 0, width, height)

    // Each decoded thumbnail must repaint the hub even after the file scan has started.
    main.recentWnd.loadDone = true
    main.recentWnd.addRecent("second.scc", testFramePicture(100, 20), front: false)
    Swag.require(recents.count() == 2)
    host.app.runFrame()
    var second = host.app.renderer.readRenderTarget(&surface.rt, 0, 0, width, height)
    Swag.require(not testSamePixels(&first, &second))

    // Reopening a known file can replace its preview without adding a tile.
    main.recentWnd.addRecent("second.scc", testFramePicture(180, 34), front: false)
    Swag.require(recents.count() == 2)
    host.app.runFrame()
    var updated = host.app.renderer.readRenderTarget(&surface.rt, 0, 0, width, height)
    Swag.require(not testSamePixels(&second, &updated))
    panel.close()
}

// The menu of the notification-area icon carries every capture command, picture and video, with
// the wait before a capture; a single monitor adds no entry of its own.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    var panel = testOpenResidentPanel(&host, main, .Menu)
    Swag.require(main.residentPanel == panel)
    for id in [ActionGlobal.ShowHub, ActionGlobal.ShowEditor, ActionCapture.Area, ActionCapture.LastArea,
               ActionCapture.FullScreen, ActionCapture.ActiveWnd, ActionCapture.RecordVideo,
               ActionCapture.RecordScreen, ActionCapture.RecordActiveWindow, ActionCapture.Record,
               ActionCapture.CaptureCursor, ActionOptions.Options, ActionGlobal.Exit] do
        Swag.require(testPanelOffers(panel, id), id)
    for item in panel.menu.items where item and item.id == ActionCapture.RecordVideo do
        Swag.require(item.rightName.raw == Input.formatKeyShortcut(.CtrlShift, .F10))
    Swag.require(not testPanelOffers(panel, ActionGlobal.Minimize))
    Swag.require(not testPanelOffers(panel, ActionCapture.screenId(0)))
    Swag.require(not testPanelOffers(panel, ActionCapture.recordScreenId(0)))

    // The waits stand in the menu as one row of choices.
    Swag.require(panel.menu.children.count == 1)
    let delays = assume cast(*StackLayoutCtrl, panel.menu.children[0])
    Swag.require(delays.children.count == CaptureDelays.count)

    // With a second monitor, each one can be captured and recorded. Opening a panel takes the
    // previous one off the screen.
    testAddMonitorAt(main, {1440, 0, 1440, 900})
    let previous = panel
    panel = testOpenResidentPanel(&host, main, .Menu)
    Swag.require(main.residentPanel == panel and panel != previous)
    Swag.require(testPanelOffers(panel, ActionCapture.screenId(1)))
    Swag.require(testPanelOffers(panel, ActionCapture.recordScreenId(1)))
    panel.close()
    Swag.require(main.residentPanel == null)
}

// The hub lists what to capture and what to record under their labels, then the last captures
// once there are some, then the pages of the window.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    Swag.require(main.editorOptions.startup == .Hub)

    var panel = testOpenResidentPanel(&host, main, .Hub)
    Swag.require(panel.menu.items[0]!.label)
    for id in [ActionCapture.Area, ActionCapture.FullScreen, ActionCapture.ActiveWnd, ActionCapture.LastArea,
               ActionCapture.RecordVideo, ActionCapture.RecordScreen, ActionCapture.RecordActiveWindow,
               ActionCapture.Record, ActionGlobal.ShowEditor, ActionGlobal.ShowLibrary,
               ActionOptions.Options, ActionGlobal.Minimize, ActionGlobal.Exit] do
        Swag.require(testPanelOffers(panel, id), id)
    for item in panel.menu.items where item and item.id == ActionCapture.RecordVideo do
        Swag.require(item.rightName.raw == Input.formatKeyShortcut(.CtrlShift, .F10))
    for item in panel.menu.items where item and item.id == ActionGlobal.Minimize do
        Swag.require(item.rightName.raw == Input.formatKeyShortcut(.None, .Escape))
    Swag.require(not testPanelOffers(panel, ActionGlobal.ShowHub))
    Swag.require(panel.recents == null)

    // The row shows the first captures of the recent strip, inside its own bounds.
    for index in HubRecents.MaxShown + 2 do
        main.recentWnd.addRecent(Format.toString("recent%.scc", index), testFramePicture(cast(u8, 40 * index), 8))
    panel = testOpenResidentPanel(&host, main, .Hub)
    let recents = unwrap panel.recents
    Swag.require(recents.count() == HubRecents.MaxShown)
    let last = recents.tileRect(HubRecents.MaxShown - 1)
    Swag.require(last.x > recents.tileRect(0).right() and last.right() <= recents.clientRect().right())
    Swag.require(last.y >= 0 and last.bottom() <= recents.clientRect().bottom())
    panel.close()
}

// The hub and tray menu navigate by keyboard, including the hosted recent row.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    for index in 3 do
        main.recentWnd.addRecent(Format.toString("recent%.scc", index), testFramePicture(cast(u8, 40 * index), 8))
    let panel = testOpenResidentPanel(&host, main, .Hub)
    let recents = unwrap panel.recents

    var down = KeyEvent{kind: .Pressed, key: .Down}
    for item in panel.menu.items
    {
        if item!.id == null and not item.disabled and not item.separator and not item.label
        {
            panel.sendEvent(&down)
            break
        }
        if not item.disabled and not item.separator and not item.label do
            panel.sendEvent(&down)
    }

    var right = KeyEvent{kind: .Pressed, key: .Right}
    panel.sendEvent(&right)
    Swag.require(right.accepted and recents.keyboardIndex == 0)
    panel.sendEvent(&right)
    Swag.require(recents.keyboardIndex == 1)
    var left = KeyEvent{kind: .Pressed, key: .Left}
    panel.sendEvent(&left)
    Swag.require(recents.keyboardIndex == 0)

    var home = KeyEvent{kind: .Pressed, key: .Home}
    panel.sendEvent(&home)
    Swag.require(recents.keyboardIndex == Swag.U64.Max)
    panel.close()

    let menuPanel = testOpenResidentPanel(&host, main, .Menu)
    menuPanel.sendEvent(&home)
    var enter = KeyEvent{kind: .Pressed, key: .Return}
    menuPanel.sendEvent(&enter)
    Swag.require(enter.accepted and main.residentPanel == null)
}

// While a recording runs the panel offers to stop or abandon it, not to start another capture.
#test
{
    var host: Testing.HeadlessHost
    let main     = testSetupSurfaceMain(&host)
    let recorder = Memory.new'Recorder()
    defer
    {
        g_Recorder = null
        Memory.delete(recorder)
        host.shutdown()
        g_Main = null
    }

    recorder.main = main
    g_Recorder    = recorder
    for kind in [ResidentPanelKind.Hub, ResidentPanelKind.Menu]
    {
        let panel = testOpenResidentPanel(&host, main, kind)
        Swag.require(testPanelOffers(panel, ActionCapture.RecordVideo))
        Swag.require(testPanelOffers(panel, ActionCapture.CancelRecording))
        Swag.require(testPanelOffers(panel, ActionGlobal.ShowEditor))
        Swag.require(not testPanelOffers(panel, ActionCapture.Area))
        Swag.require(not testPanelOffers(panel, ActionCapture.Record))
        Swag.require(panel.recents == null)
        panel.close()
    }
}

// A choice takes the panel off the screen, then runs on the main window: the editor comes back
// from behind the icon.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    let surface = unwrap main.surface
    main.editorOptions.showResidentNotice = false
    surface.hide()
    Swag.require(surface.isHidden)

    var panel = testOpenResidentPanel(&host, main, .Hub)
    panel.choose(ActionGlobal.ShowEditor)
    host.pump()
    Swag.require(main.residentPanel == null)
    Swag.require(not surface.isHidden)

    // Leaving without a choice changes nothing.
    surface.hide()
    panel = testOpenResidentPanel(&host, main, .Menu)
    panel.choose(null)
    host.pump()
    Swag.require(main.residentPanel == null and surface.isHidden)
}

// Escape from the last visible hub opens a nonmodal reminder beside the icon. Its checkbox
// disables later reminders, even when an older saved notice count has reached zero.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    let surface = unwrap main.surface
    main.editorOptions.residentNotices = 0
    main.editorOptions.showResidentNotice = true
    surface.hide()
    let panel = testOpenResidentPanel(&host, main, .Hub)
    var escape = KeyEvent{kind: .Pressed, key: .Escape}
    panel.sendEvent(&escape)
    Swag.require(escape.accepted and main.residentPanel == null)
    host.pump()
    let notice = unwrap main.residentNotice
    Swag.require(host.app.surfaces.count == 2)
    Swag.require(notice.surface != surface)
    let card = notice.children[0]
    let cardBounds = card.surfaceRect()
    let choice = unwrap notice.optionCheck
    let choiceBounds = choice.surfaceRect()
    Swag.require(choiceBounds.x >= cardBounds.x and choiceBounds.right() <= cardBounds.right() and
                 choiceBounds.y >= cardBounds.y and choiceBounds.bottom() <= cardBounds.bottom())
    Swag.require(not choice.isChecked())
    choice.toggle()
    Swag.require(not main.editorOptions.showResidentNotice)
    notice.close()
    host.pump()
    Swag.require(host.app.surfaces.count == 1)
    Swag.require(not main.noticeResident())
}
