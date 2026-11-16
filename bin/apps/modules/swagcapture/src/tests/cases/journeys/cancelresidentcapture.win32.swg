#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Start from the hub, keep its type and shortcuts on one screen, then cancel to resident mode.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    let app = journey.app
    let surface = journey.surface
    surface.setTrayIcon(expect Image.decode(".png", AppIcon), ProductName)
    surface.hide()
    main.editorOptions.showResidentNotice = true
    main.editorOptions.residentNotices = 0
    defer main.residentNotice?.close()

    var canceled: bool
    defer app.sigFrame.clear()
    app.sigFrame += func|main, canceled = &canceled|(_)
    {
        if canceled[] do
            return
        for candidate in g_App.surfaces
        {
            if candidate.view() is CaptureRectWnd as overlay
            {
                var tab = KeyEvent{kind: .Pressed, key: .Tab}
                overlay.sendEvent(&tab)
                Swag.require(g_CaptureMedia == .Picture)

                let hints = unwrap overlay.hints
                for monitor in main.monitors
                {
                    hints.placeAt(monitor.physicalBounds.center())
                    overlay.applyLayout()
                    let rect  = hints.line.surfaceRect()
                    var first = rect.topLeft()
                    var last  = rect.bottomRight()
                    candidate.surfaceToScreen(&first)
                    candidate.surfaceToScreen(&last)
                    let work = monitor.physicalWorkArea
                    Swag.require(first.x >= work.x and first.y >= work.y)
                    Swag.require(last.x <= work.right() and last.y <= work.bottom())
                }

                var escape = KeyEvent{kind: .Pressed, key: .Escape, modifiers: .None}
                overlay.sendEvent(&escape)
                canceled[] = true
                return
            }
        }
    }

    let hub = unwrap ResidentPanel.open(main, .Centered)
    hub.choose(ActionCapture.Area)
    app.runFrame()

    Swag.require(canceled, "the area selector did not receive Escape")
    Swag.require(surface.isHidden and main.residentPanel == null,
                 "the canceled capture did not return to resident mode")
    let notice = unwrap main.residentNotice
    Swag.require(not notice.surface!.isHidden,
                 "canceling a capture from the hub must show the resident notice")
}
