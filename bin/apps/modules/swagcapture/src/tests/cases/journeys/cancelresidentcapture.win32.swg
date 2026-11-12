#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Start an area capture from the resident hub, cancel its selector, and see the resident notice.
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
    app.sigFrame += func|canceled = &canceled|(_)
    {
        if canceled[] do
            return
        for candidate in g_App.surfaces
        {
            if candidate.view() is CaptureRectWnd as overlay
            {
                var escape = KeyEvent{kind: .Pressed, key: .Escape, modifiers: .None}
                overlay.sendEvent(&escape)
                canceled[] = true
                return
            }
        }
    }

    let hub = unwrap ResidentPanel.open(main, .Hub)
    hub.choose(ActionCapture.Area)
    app.runFrame()

    Swag.require(canceled, "the area selector did not receive Escape")
    Swag.require(surface.isHidden and main.residentPanel == null,
                 "the canceled capture did not return to resident mode")
    let notice = unwrap main.residentNotice
    Swag.require(not notice.surface!.isHidden,
                 "canceling a capture from the hub must show the resident notice")
}
