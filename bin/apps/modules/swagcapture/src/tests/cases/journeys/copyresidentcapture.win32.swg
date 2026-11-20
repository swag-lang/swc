#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// The explicit tray command keeps the session resident across captures from the tray and a shortcut.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main    = journey.main
    let surface = journey.surface
    main.showHub()
    let hub = unwrap main.residentPanel
    Swag.require(main.workspace == .Hub and not surface.hasTrayIcon())
    hub.choose(ActionGlobal.Minimize)
    journey.waitFor("explicit resident mode", func|main|()->bool => main.workspace == .Resident)
    Swag.require(surface.isHidden and surface.hasTrayIcon() and main.residentPanel == null)

    main.captureOptions.pictureDestination = .InPlace
    journey.finishInPlacePicture(unwrap ResidentPanel.open(main, .AtPointer))
    Swag.require(main.workspace == .Resident and surface.hasTrayIcon() and main.residentPanel == null)

    journey.finishInPlacePicture(null)
    Swag.require(main.workspace == .Resident and surface.hasTrayIcon() and main.residentPanel == null)

    journey.finishInPlacePicture(unwrap ResidentPanel.open(main, .AtPointer), cancel: true)
    Swag.require(main.workspace == .Resident and surface.hasTrayIcon() and main.residentPanel == null)
}
