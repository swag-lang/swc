#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Full-screen OS capture is tested without creating a Swag Capture library file:
// sendToEditor=false keeps the result in the real clipboard only. The grab covers
// the whole virtual desktop, so the check stops at clipboard presence: decoding a
// desktop-sized PNG back would dominate the whole suite for no extra coverage.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    f.main.captureOptions.hideEditorBefore = false
    f.main.captureOptions.captureCursor    = false
    f.main.captureOptions.sendToClipboard  = true
    f.main.captureOptions.sendToEditor     = false
    f.main.captureOptions.inPlaceEdit      = false
    f.main.captureOptions.delay            = 0

    f.main.sendCommandEvent(ActionCapture.FullScreen)

    Swag.assert(Clipboard.hasImage())
}

// Last-area capture reuses cached grab bounds, so it exercises the OS capture
// path without opening the interactive area selector.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
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

    let actionExecuted = Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.LastArea)
    Swag.assert(actionExecuted)

    let image = Clipboard.getImage()
    Swag.assert(image.isValid())
    Swag.assert(image.width == 16)
    Swag.assert(image.height == 12)
}

// Monitor capture is non-interactive: a small fake monitor keeps the real screen
// grab and the clipboard round-trip cheap while exercising the exact same path as
// a real monitor (a full-monitor grab plus PNG round-trip costs seconds on a 4K
// display).
#[Swag.TestTag("integration.host.windows")]
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    f.main.captureOptions.hideEditorBefore = false
    f.main.captureOptions.captureCursor    = false
    f.main.captureOptions.sendToClipboard  = true
    f.main.captureOptions.sendToEditor     = false
    f.main.captureOptions.inPlaceEdit      = false
    f.main.captureOptions.delay            = 0

    // Five monitors, and the fifth is the one captured: the per-monitor commands used to
    // stop at four, so a monitor past that could not be captured on its own. The first
    // four stay tiny and the fifth is the only one with a distinctive size, so the grab
    // rectangle proves which monitor was read. All sit at the desktop origin to keep the
    // real screen grab inside any display.
    f.main.monitors.clear()
    for 4 do
        testAddMonitorAt(f.main, {0, 0, 8, 8})
    testAddMonitorAt(f.main, {0, 0, 320, 240})

    let actionExecuted = Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.screenId(4))
    Swag.assert(actionExecuted)

    let image = Clipboard.getImage()
    Swag.assert(image.isValid())
    Swag.assert(image.width == 320)
    Swag.assert(image.height == 240)
}
