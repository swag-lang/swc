#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// A startup capture can reopen the hub, or copy and quit with the option off.
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
    main.captureOptions.pictureDestination = .InPlace
    main.editorOptions.showResidentNotice = true
    defer main.residentNotice?.close()
    defer main.residentPanel?.close()

    var exitRequested: bool
    main.hookOnEvent = func|&exitRequested|(_, evt)->bool
    {
        if evt is CommandEvent as cmd where cmd.id == ActionGlobal.Exit do
            exitRequested = true
        return false
    }

    main.captureOptions.returnToHubAfterCopy = true
    main.openStartupHub()
    journey.waitFor("startup hub", func|main|()->bool => main.residentPanel != null)
    let startupHub = main.residentPanel
    journey.finishInPlacePicture(unwrap startupHub)
    journey.waitFor("startup hub reopened after copy", func|main|()->bool => main.residentPanel != null)
    Swag.require(not exitRequested and main.residentNotice == null)

    main.captureOptions.returnToHubAfterCopy = false
    let reopenedHub = main.residentPanel
    journey.finishInPlacePicture(unwrap reopenedHub)
    let frameLimit = cast(u32, app.timing.frameCount) + 10
    app.maxRunFrame = frameLimit
    Swag.require(app.run() == 0 and app.timing.frameCount < frameLimit, "copying from the startup hub must quit the app")
    Swag.require(exitRequested)
    Swag.require(main.residentNotice == null and main.residentPanel == null)
}
