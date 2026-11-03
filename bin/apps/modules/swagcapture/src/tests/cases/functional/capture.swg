#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func testAddMonitor(main: *MainWnd, idx: u32)
{
    testAddMonitorAt(main, Math.Rectangle{cast(f32, idx) * 320, 0, 320, 240})
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
