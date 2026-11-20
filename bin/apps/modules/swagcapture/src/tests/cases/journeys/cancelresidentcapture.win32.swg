#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Cancel area selection and restore the capture window where the user left it.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main    = journey.main
    let app     = journey.app
    let surface = journey.surface
    main.showHub()
    let original = main.residentPanel
    let hub = unwrap original
    let hubSurface = unwrap hub.surface
    let oldBounds = hubSurface.position
    hubSurface.setPosition({oldBounds.x + 12, oldBounds.y + 8, oldBounds.width, oldBounds.height})
    let moved = hubSurface.position
    defer main.residentPanel?.close()

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

    hub.choose(ActionCapture.Area)
    app.runFrame()

    Swag.require(canceled, "the area selector did not receive Escape")
    let current = main.residentPanel
    let restored = unwrap current
    Swag.require(main.workspace == .Hub and surface.isHidden and not surface.hasTrayIcon())
    Swag.require(restored.surface!.position == moved)
}
