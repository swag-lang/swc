#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func testAddMonitor(main: *MainWnd, idx: u32)
{
    testAddMonitorAt(main, Math.Rectangle{cast(f32, idx) * 320, 0, 320, 240})
}

// The capture arrow offers modes and settings before opening any capture overlay.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    main.monitors.clear()
    testAddMonitor(main, 0)
    testAddMonitor(main, 1)

    var inspected: bool
    host.app.sigFrame += func|host = &host, inspected = &inspected|(_)
    {
        if inspected[] do
            return
        let menu = unwrap host.capturedPopupMenu()
        Swag.require(menu.items.count == 9)
        Swag.require(menu.items[0]!.id == ActionCapture.Area)
        Swag.require(menu.items[1]!.id == ActionCapture.ActiveWnd)
        Swag.require(menu.items[2]!.id == ActionCapture.FullScreen)
        Swag.require(menu.items[3]!.id == ActionCapture.LastArea)
        Swag.require(menu.items[4]!.id == ActionCapture.screenId(0))
        Swag.require(menu.items[5]!.id == ActionCapture.screenId(1))
        Swag.require(menu.items[7]!.id == ActionCapture.CaptureCursor)
        let delays = menu.items[8]!.popup
        Swag.require(delays.items.count == 5)
        Swag.require(delays.items[0]!.id == ActionCaptureDelay.Delay0)
        Swag.require(delays.items[4]!.id == ActionCaptureDelay.Delay9)
        inspected[] = true
        Swag.require(host.dismissPopupMenu())
    }

    host.click(main.captureChoice.surfaceRect().center())
    Swag.require(inspected)
    Swag.require(not main.captureChoice.hasFocus())
}

// The selection owns both keys and pointer gestures. Releasing the left button fixes the
// rectangle on release; Escape and right click leave without a grab.
#test
{
    var f: HeadlessFixture
    f.setup(320, 240)
    defer f.shutdown()

    g_DesktopX, g_DesktopY = 0
    g_Exit, g_GrabDone      = false
    let wnd = Wnd.create'CaptureRectWnd(&f.gui.root, {0, 0, 320, 240})
    wnd.main        = f.main
    wnd.focusPolicy = .Click
    wnd.setFocus()
    Swag.require(wnd.hasFocus())

    var evt = Gui.MouseEvent{kind: .Pressed, button: .Left, surfacePos: {80, 100}}
    wnd.sendEvent(&evt)
    evt.kind       = .Move
    evt.surfacePos = {180, 90}
    wnd.sendEvent(&evt)
    Swag.require(wnd.startGrab and not g_Exit)

    evt.kind       = .Released
    evt.surfacePos = {200, 20}
    wnd.sendEvent(&evt)
    Swag.require(g_Exit and g_GrabDone)
    Swag.require(getGrabRect() == {80, 20, 120, 80})

    g_Exit, g_GrabDone = false
    wnd.startGrab      = false
    wnd.tryStartGrab   = false
    evt.kind           = .Pressed
    evt.button         = .Right
    wnd.sendEvent(&evt)
    Swag.require(g_Exit and not g_GrabDone)

    g_Exit, g_GrabDone = false
    var key = Gui.KeyEvent{kind: .Pressed, key: .Escape, modifiers: .Control}
    wnd.sendEvent(&key)
    Swag.require(not g_Exit)
    key.modifiers = .None
    wnd.sendEvent(&key)
    Swag.require(g_Exit and not g_GrabDone)
}

// Capture command states cover every toolbar/menu entry, including monitor
// entries, without starting the interactive capture overlay.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.main.monitors.clear()
    testAddMonitor(f.main, 0)
    testAddMonitor(f.main, 1)
    testAddMonitor(f.main, 2)
    testAddMonitor(f.main, 3)

    var evt = Gui.Testing.commandState(ActionCapture.DoIt)
    Swag.require(Gui.Testing.actionUpdate'ActionCapture(f.main, ActionCapture.DoIt, &evt))
    Swag.require(not evt.name.isEmpty())

    evt = Gui.Testing.commandState(ActionCapture.Area)
    Swag.require(Gui.Testing.actionUpdate'ActionCapture(f.main, ActionCapture.Area, &evt))
    Swag.require(not evt.name.isEmpty())

    evt = Gui.Testing.commandState(ActionCapture.LastArea)
    Swag.require(Gui.Testing.actionUpdate'ActionCapture(f.main, ActionCapture.LastArea, &evt))
    Swag.require(not evt.name.isEmpty())

    evt = Gui.Testing.commandState(ActionCapture.FullScreen)
    Swag.require(Gui.Testing.actionUpdate'ActionCapture(f.main, ActionCapture.FullScreen, &evt))
    Swag.require(not evt.name.isEmpty())

    evt = Gui.Testing.commandState(ActionCapture.ActiveWnd)
    Swag.require(Gui.Testing.actionUpdate'ActionCapture(f.main, ActionCapture.ActiveWnd, &evt))
    Swag.require(not evt.name.isEmpty())

    // One command per connected monitor, minted on demand: the sixth is reachable
    // exactly like the first, and each carries a distinct id and an enabled state.
    for idx in f.main.monitors.count
    {
        let id = ActionCapture.screenId(idx)

        // A minted id must still carry the owning scope: `acceptOwnCmdIds` routes a
        // command to its action by that prefix alone.
        Swag.require(Utf8.startsWith(id, "ActionCapture."))
        Swag.require(ActionCapture.screenIndex(id) == idx)
        evt = Gui.Testing.commandState(id)
        Swag.require(Gui.Testing.actionUpdate'ActionCapture(f.main, id, &evt))
        Swag.require(not evt.name.isEmpty())
        Swag.require(not evt.disabled)
    }

    // A command whose monitor is gone stays answerable and reports itself disabled.
    let goneId = ActionCapture.screenId(f.main.monitors.count)
    evt = Gui.Testing.commandState(goneId)
    Swag.require(Gui.Testing.actionUpdate'ActionCapture(f.main, goneId, &evt))
    Swag.require(not evt.name.isEmpty())
    Swag.require(evt.disabled)
}
