#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Copy from the in-place tools and quit the launch window without adding a notification icon.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main    = journey.main
    let app     = journey.app
    let surface = journey.surface
    main.captureOptions.pictureDestination = .InPlace
    main.showHub()
    let hub = unwrap main.residentPanel
    Swag.require(hub.surface!.flags.has(.SmallCaption))
    Swag.require(main.workspace == .Hub and not surface.hasTrayIcon())

    journey.finishInPlacePicture(hub, cancel: true)
    let restored = main.residentPanel
    Swag.require(main.workspace == .Hub and main.workspaceSurface().flags.has(.SmallCaption) and not surface.hasTrayIcon())

    journey.finishInPlacePicture(restored)
    let frameLimit = cast(u32, app.timing.frameCount) + 10
    app.maxRunFrame = frameLimit
    Swag.require(app.run() == 0 and app.timing.frameCount < frameLimit, "copying from the capture window must quit")
    Swag.require(not surface.hasTrayIcon() and main.residentPanel == null)
}
