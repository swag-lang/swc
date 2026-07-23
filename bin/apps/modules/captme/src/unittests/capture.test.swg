#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func testAddMonitor(main: *MainWnd, idx: u32)
{
    let x = cast(f32) idx * 320
    let rect = Math.Rectangle{x, 0, 320, 240}
    main.monitors.add({rect: rect, work: rect, scale: 1, rectReal: rect, workReal: rect})
}

// Capture command states cover every toolbar/menu entry, including monitor
// entries, without starting the interactive capture overlay.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    f.main.monitors.clear()
    testAddMonitor(f.main, 0)
    testAddMonitor(f.main, 1)
    testAddMonitor(f.main, 2)
    testAddMonitor(f.main, 3)

    var evt = Testing.commandState(ActionCapture.DoIt)
    @assert(Testing.actionUpdate'ActionCapture(f.main, ActionCapture.DoIt, &evt))
    @assert(!evt.name.isEmpty())

    evt = Testing.commandState(ActionCapture.Area)
    @assert(Testing.actionUpdate'ActionCapture(f.main, ActionCapture.Area, &evt))
    @assert(!evt.name.isEmpty())

    evt = Testing.commandState(ActionCapture.LastArea)
    @assert(Testing.actionUpdate'ActionCapture(f.main, ActionCapture.LastArea, &evt))
    @assert(!evt.name.isEmpty())

    evt = Testing.commandState(ActionCapture.FullScreen)
    @assert(Testing.actionUpdate'ActionCapture(f.main, ActionCapture.FullScreen, &evt))
    @assert(!evt.name.isEmpty())

    evt = Testing.commandState(ActionCapture.ActiveWnd)
    @assert(Testing.actionUpdate'ActionCapture(f.main, ActionCapture.ActiveWnd, &evt))
    @assert(!evt.name.isEmpty())

    evt = Testing.commandState(ActionCapture.Screen0)
    @assert(Testing.actionUpdate'ActionCapture(f.main, ActionCapture.Screen0, &evt))
    @assert(!evt.name.isEmpty())

    evt = Testing.commandState(ActionCapture.Screen1)
    @assert(Testing.actionUpdate'ActionCapture(f.main, ActionCapture.Screen1, &evt))
    @assert(!evt.name.isEmpty())

    evt = Testing.commandState(ActionCapture.Screen2)
    @assert(Testing.actionUpdate'ActionCapture(f.main, ActionCapture.Screen2, &evt))
    @assert(!evt.name.isEmpty())

    evt = Testing.commandState(ActionCapture.Screen3)
    @assert(Testing.actionUpdate'ActionCapture(f.main, ActionCapture.Screen3, &evt))
    @assert(!evt.name.isEmpty())

    f.shutdown()
}

// Full-screen OS capture is tested without creating a Captme library file:
// sendToEditor=false keeps the result in the real clipboard only. The grab covers
// the whole virtual desktop, so the check stops at clipboard presence: decoding a
// desktop-sized PNG back would dominate the whole suite for no extra coverage.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)

    f.main.captureOptions.hideEditorBefore = false
    f.main.captureOptions.captureCursor    = false
    f.main.captureOptions.sendToClipboard  = true
    f.main.captureOptions.sendToEditor     = false
    f.main.captureOptions.inPlaceEdit      = false
    f.main.captureOptions.delay            = 0

    f.main.sendCommandEvent(ActionCapture.FullScreen)

    @assert(Clipboard.hasImage())

    f.shutdown()
}

// Last-area capture reuses cached grab bounds, so it exercises the OS capture
// path without opening the interactive area selector.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)

    f.main.captureOptions.hideEditorBefore = false
    f.main.captureOptions.captureCursor    = false
    f.main.captureOptions.sendToClipboard  = true
    f.main.captureOptions.sendToEditor     = false
    f.main.captureOptions.inPlaceEdit      = false
    f.main.captureOptions.delay            = 0

    g_StartGrabX = 0
    g_StartGrabY = 0
    g_EndGrabX   = 16
    g_EndGrabY   = 12

    @assert(Testing.actionExecute'ActionCapture(f.main, ActionCapture.LastArea))

    let img = Clipboard.getImage()
    @assert(img.isValid())
    @assert(img.width == 16)
    @assert(img.height == 12)

    f.shutdown()
}

// Monitor capture is non-interactive: a small fake monitor keeps the real screen
// grab and the clipboard round-trip cheap while exercising the exact same path as
// a real monitor (a full-monitor grab plus PNG round-trip costs seconds on a 4K
// display).
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)

    f.main.captureOptions.hideEditorBefore = false
    f.main.captureOptions.captureCursor    = false
    f.main.captureOptions.sendToClipboard  = true
    f.main.captureOptions.sendToEditor     = false
    f.main.captureOptions.inPlaceEdit      = false
    f.main.captureOptions.delay            = 0
    f.main.monitors.clear()
    testAddMonitor(f.main, 0)

    @assert(Testing.actionExecute'ActionCapture(f.main, ActionCapture.Screen0))

    let img = Clipboard.getImage()
    @assert(img.isValid())
    @assert(img.width == 320)
    @assert(img.height == 240)

    f.shutdown()
}
