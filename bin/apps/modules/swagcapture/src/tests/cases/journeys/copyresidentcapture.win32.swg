#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Copy a picture from a resident session and optionally open the hub again.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main    = journey.main
    let surface = journey.surface
    surface.setTrayIcon(expect Image.decode(".png", AppIcon), ProductName)
    surface.hide()
    main.captureOptions.pictureDestination = .InPlace
    main.editorOptions.showResidentNotice = false
    main.editorOptions.residentNotices    = 0
    defer main.residentNotice?.close()
    defer main.residentPanel?.close()

    main.openStartupHub()
    journey.waitFor("startup hub", func|main|()->bool => main.residentPanel != null)
    let startupHub = main.residentPanel
    (unwrap startupHub).choose(ActionGlobal.Minimize)
    journey.app.runFrame()
    Swag.require(main.residentPanel == null and main.residentNotice == null)
    main.editorOptions.showResidentNotice = true

    Swag.require(not main.captureOptions.returnToHubAfterCopy)
    journey.finishInPlacePicture(unwrap ResidentPanel.open(main, .Centered))
    Swag.require(main.residentPanel == null)
    let notice = unwrap main.residentNotice
    Swag.require(not notice.surface!.isHidden)
    notice.close()

    main.captureOptions.returnToHubAfterCopy = true
    journey.finishInPlacePicture(unwrap ResidentPanel.open(main, .Centered))
    journey.waitFor("hub reopened after copy", func|main|()->bool => main.residentPanel != null)
    let currentHub = main.residentPanel
    let hub = unwrap currentHub
    Swag.require(hub.placement == .Centered and not hub.surface!.isHidden)
    Swag.require(main.residentNotice == null)
    hub.close()

    journey.finishInPlacePicture(null)
    journey.app.runFrame()
    Swag.require(main.residentPanel == null, "a capture started while resident must stay resident")
    main.residentNotice?.close()

    journey.finishInPlacePicture(unwrap ResidentPanel.open(main, .Centered), cancel: true)
    journey.app.runFrame()
    Swag.require(main.residentPanel == null, "canceling must leave the hub closed")
}
