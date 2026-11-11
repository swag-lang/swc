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
               ActionCapture.RecordFullScreen, ActionCapture.RecordActiveWindow, ActionCapture.Record,
               ActionCapture.CaptureCursor, ActionOptions.Options, ActionGlobal.Exit] do
        Swag.require(testPanelOffers(panel, id), id)
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
               ActionCapture.RecordVideo, ActionCapture.RecordFullScreen, ActionCapture.RecordActiveWindow,
               ActionCapture.Record, ActionGlobal.ShowEditor, ActionGlobal.ShowLibrary,
               ActionOptions.Options, ActionGlobal.Exit] do
        Swag.require(testPanelOffers(panel, id), id)
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
