#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// Startup and the pointer menu share their complete command list, settings and recent captures.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }
    defer discard catch host.app.setLanguage(Gui.ReferenceLanguage)

    testAddMonitorAt(main, {1440, 0, 1440, 900})
    main.recentWnd.addRecent("recent.scc", testFramePicture(80, 8))
    for language in Gui.languages()
    {
        expect host.app.setLanguage(language.tag)
        let centered = testOpenResidentPanel(&host, main, .Centered)
        let pointer = testOpenResidentPanel(&host, main, .AtPointer)
        Swag.require(centered.listSize == pointer.listSize)
        Swag.require(centered.menu.items.count == pointer.menu.items.count)
        Swag.require(centered.recents != null and pointer.recents != null)
        for item, index in centered.menu.items
        {
            let other = unwrap pointer.menu.items[index]
            Swag.require(item!.id == other.id and item.name.text == other.name.text)
            Swag.require(item.checked == other.checked and item.disabled == other.disabled)
        }
        Testing.assertContentFits(centered)
        Testing.assertContentFits(pointer)

        let work = Env.monitorForPoint({}).physicalWorkArea
        let centeredBounds = centered.surface!.position
        Swag.require(Math.abs(centeredBounds.horzCenter() - work.horzCenter()) <= 1)
        Swag.require(Math.abs(centeredBounds.vertCenter() - work.vertCenter()) <= 1)

        let anchor = Math.Point{work.right() - 8, work.bottom() - 8}
        pointer.place(anchor)
        let pointerBounds = pointer.surface!.position
        Swag.require(pointer.anchor == anchor)
        Swag.require(pointerBounds.x >= work.x and pointerBounds.right() <= work.right())
        Swag.require(pointerBounds.y >= work.y and pointerBounds.bottom() <= work.bottom())
        Swag.require(pointerBounds.right() >= anchor.x and pointerBounds.bottom() >= anchor.y)
        centered.close()
        pointer.close()
    }
}

// A late recent capture grows the pointer home at its original anchor without moving monitors.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }
    let panel = testOpenResidentPanel(&host, main, .AtPointer)
    let work = Env.monitorForPoint({}).physicalWorkArea
    let anchor = Math.Point{work.right() - 8, work.bottom() - 8}
    panel.place(anchor)
    Swag.require(panel.recents == null)
    main.recentWnd.addRecent("recent.scc", testFramePicture(80, 8))
    var tick: TimerEvent
    panel.IWnd.onTimerEvent(&tick)
    Swag.require(panel.recents != null and panel.anchor == anchor)
    let bounds = panel.surface!.position
    Swag.require(bounds.right() >= anchor.x and bounds.bottom() >= anchor.y)
    panel.close()
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
    let panel = testOpenResidentPanel(&host, main, .Centered)
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

// The resident home carries every capture command, picture and video, with
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

    var panel = testOpenResidentPanel(&host, main, .AtPointer)
    Swag.require(main.residentPanel == panel)
    for id in [ActionGlobal.ShowLibrary, ActionGlobal.ShowEditor, ActionCapture.Area, ActionCapture.LastArea,
               ActionCapture.FullScreen, ActionCapture.ActiveWnd, ActionCapture.RecordVideo,
               ActionCapture.RecordScreen, ActionCapture.RecordActiveWindow, ActionCapture.Record,
               ActionCapture.CaptureCursor, ActionOptions.Options, ActionGlobal.Exit] do
        Swag.require(testPanelOffers(panel, id), id)
    for item in panel.menu.items where item and item.id == ActionCapture.RecordVideo do
        Swag.require(item.rightName.text == Input.formatKeyShortcut(.CtrlShift, .F10))
    Swag.require(testPanelOffers(panel, ActionGlobal.Minimize))
    Swag.require(not testPanelOffers(panel, ActionGlobal.ShowHub))
    Swag.require(not testPanelOffers(panel, ActionCapture.screenId(0)))
    Swag.require(not testPanelOffers(panel, ActionCapture.recordScreenId(0)))

    // The waits stand in the menu as one row of choices.
    Swag.require(panel.menu.children.count == 1)
    let delays = assume cast(*StackLayoutCtrl, panel.menu.children[0])
    Swag.require(delays.children.count == CaptureDelays.count)
    var delayHeading = false
    for item in panel.menu.items
    {
        if item!.label and item.name.text == appStrings().act_DelayBefore do
            delayHeading = true
        if item.id == null and not item.separator and not item.label and not item.disabled do
            Swag.require(delayHeading)
    }

    // With a second monitor, each one can be captured and recorded. Opening a panel takes the
    // previous one off the screen.
    testAddMonitorAt(main, {1440, 0, 1440, 900})
    let previous = panel
    panel = testOpenResidentPanel(&host, main, .AtPointer)
    Swag.require(main.residentPanel == panel and panel != previous)
    Swag.require(testPanelOffers(panel, ActionCapture.screenId(1)))
    Swag.require(testPanelOffers(panel, ActionCapture.recordScreenId(1)))
    panel.close()
    Swag.require(main.residentPanel == null)
}

// The hub keeps capture delay choices available without dismissing the next capture command.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    defer discard catch host.app.setLanguage(Gui.ReferenceLanguage)
    for language in Gui.languages()
    {
        expect host.app.setLanguage(language.tag)
        main.captureOptions.delay = 7
        let panel   = testOpenResidentPanel(&host, main, .Centered)
        let surface = unwrap panel.surface
        surface.show()
        let choices = assume cast(*StackLayoutCtrl, panel.menu.children[0])
        Swag.require(choices.children.count == CaptureDelays.count)
        Swag.require(testPanelOffers(panel, ActionCapture.Area))
        Testing.assertContentFits(panel)

        for choice, index in CaptureDelays
        {
            let button = assume cast(*IconButton, choices.children[index])
            let bounds = button.surfaceRect()
            Swag.require(bounds.x >= 0 and bounds.right() <= surface.position.width / surface.dpiScale)
            host.clickWnd(button)
            host.pump()
            Swag.require(main.captureOptions.delay == choice.seconds)
            Swag.require(main.residentPanel == panel and not panel.menu.isModalEnded())
            for child, other in choices.children do
                Swag.require((assume cast(*IconButton, child)).isChecked == (other == index))
        }

        panel.close()
    }
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

    var panel = testOpenResidentPanel(&host, main, .Centered)
    Swag.require(panel.menu.items[0]!.label)
    for id in [ActionCapture.Area, ActionCapture.FullScreen, ActionCapture.ActiveWnd, ActionCapture.LastArea,
               ActionCapture.RecordVideo, ActionCapture.RecordScreen, ActionCapture.RecordActiveWindow,
               ActionCapture.Record, ActionGlobal.ShowEditor, ActionGlobal.ShowLibrary,
               ActionOptions.Options, ActionGlobal.Minimize, ActionGlobal.Exit] do
        Swag.require(testPanelOffers(panel, id), id)
    for item in panel.menu.items where item and item.id == ActionCapture.RecordVideo do
        Swag.require(item.rightName.text == Input.formatKeyShortcut(.CtrlShift, .F10))
    for item in panel.menu.items where item and item.id == ActionGlobal.Minimize do
        Swag.require(item.rightName.text == Input.formatKeyShortcut(.None, .Escape))
    Swag.require(not testPanelOffers(panel, ActionGlobal.ShowHub))
    Swag.require(panel.recents == null)

    // The row shows the first captures of the recent strip, inside its own bounds.
    for index in HubRecents.MaxShown + 2 do
        main.recentWnd.addRecent(Format.toString("recent%.scc", index), testFramePicture(cast(u8, 40 * index), 8))
    panel = testOpenResidentPanel(&host, main, .Centered)
    let recents = unwrap panel.recents
    Swag.require(recents.count() == HubRecents.MaxShown)
    let last = recents.tileRect(HubRecents.MaxShown - 1)
    Swag.require(last.x > recents.tileRect(0).right() and last.right() <= recents.clientRect().right())
    Swag.require(last.y >= 0 and last.bottom() <= recents.clientRect().bottom())
    panel.close()
}

// Both placements of the home navigate by keyboard, including the hosted recent row.
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
    let panel = testOpenResidentPanel(&host, main, .Centered)
    let recents = unwrap panel.recents

    var down        = KeyEvent{kind: .Pressed, key: .Down}
    var recentGroup = false
    for item in panel.menu.items
    {
        if item!.label and item.name.text == appStrings().lens_Recent do
            recentGroup = true
        if not item.disabled and not item.separator and not item.label
        {
            panel.sendEvent(&down)
            if recentGroup do
                break
        }
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

    let menuPanel = testOpenResidentPanel(&host, main, .AtPointer)
    menuPanel.sendEvent(&home)
    var escape = KeyEvent{kind: .Pressed, key: .Escape}
    menuPanel.sendEvent(&escape)
    Swag.require(escape.accepted and main.residentPanel == null)
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
    for placement in [ResidentPanelPlacement.Centered, ResidentPanelPlacement.AtPointer]
    {
        let panel = testOpenResidentPanel(&host, main, placement)
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

    var panel = testOpenResidentPanel(&host, main, .Centered)
    panel.choose(ActionGlobal.ShowEditor)
    host.pump()
    Swag.require(main.residentPanel == null)
    Swag.require(not surface.isHidden)

    // Leaving without a choice changes nothing.
    surface.hide()
    panel = testOpenResidentPanel(&host, main, .AtPointer)
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
    let panel = testOpenResidentPanel(&host, main, .Centered)
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
