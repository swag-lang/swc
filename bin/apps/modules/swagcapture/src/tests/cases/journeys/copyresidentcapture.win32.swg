#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Copy an area capture started from the resident hub, then check that the hidden app is explained.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main    = journey.main
    let app     = journey.app
    let surface = journey.surface
    surface.setTrayIcon(expect Image.decode(".png", AppIcon), ProductName)
    surface.hide()
    main.captureOptions.inPlaceEdit       = true
    main.editorOptions.showResidentNotice = true
    main.editorOptions.residentNotices    = 0
    defer main.residentNotice?.close()

    var copied: bool
    defer app.sigFrame.clear()
    app.sigFrame += func|journey = &journey, copied = &copied|(_)
    {
        if copied[] do
            return
        for candidate in g_App.surfaces
        {
            if candidate.view() is CaptureRectWnd as overlay
            {
                journey.selectScreenArea(overlay)
                return
            }

            if candidate.view() is InPlaceEditWnd as editor
            {
                var enter = KeyEvent{kind: .Pressed, key: .Return, modifiers: .None}
                editor.sendEvent(&enter)
                copied[] = enter.accepted
                return
            }
        }
    }

    let hub = unwrap ResidentPanel.open(main, .Centered)
    hub.choose(ActionCapture.Area)
    app.runFrame()

    Swag.require(copied, "the in-place editor did not copy the selected area")
    Swag.require(surface.isHidden and main.residentPanel == null,
                 "copying the area unexpectedly restored the main window")
    let notice        = unwrap main.residentNotice
    let noticeSurface = unwrap notice.surface
    Swag.require(noticeSurface.isHidden == false,
                 "copying an area capture from the hub must show the resident notice")
}
