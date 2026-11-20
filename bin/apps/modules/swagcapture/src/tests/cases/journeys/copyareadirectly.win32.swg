#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui

// Select a rectangle from the startup hub, then copy and quit in one step.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    let app  = journey.app
    journey.surface.hide()
    main.sendCommandEvent(ActionCapture.ToClipboard)
    expect Clipboard.resetFake()

    main.showHub()
    journey.waitFor("startup hub", func|main|()->bool => main.residentPanel != null)
    let hub = unwrap main.residentPanel

    var selected: bool
    defer app.sigFrame.clear()
    app.sigFrame += func|journey = &journey, &selected|(application)
    {
        for surface in application.surfaces
        {
            if surface.view() is CaptureRectWnd as overlay
            {
                journey.selectScreenArea(overlay)
                selected = true
                return
            }
            Swag.require(not (surface.view() is InPlaceEditWnd), "clipboard mode opened the in-place editor")
        }
    }

    hub.choose(ActionCapture.Area)
    let frameLimit = cast(u32, app.timing.frameCount) + 15
    app.maxRunFrame = frameLimit
    Swag.require(app.run() == 0 and app.timing.frameCount < frameLimit, "clipboard mode left the startup app running")
    let area = getGrabRect()
    let img  = Clipboard.getImage()
    Swag.require(selected and img.width == cast(s32, area.width) and img.height == cast(s32, area.height))
    Swag.require(main.getCapture() == null and journey.surface.isHidden and not journey.surface.hasTrayIcon())
}
