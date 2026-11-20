#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// The same full-screen command follows each image destination chosen before the grab.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main    = journey.main
    let surface = journey.surface
    surface.hide()
    main.captureOptions.returnToHubAfterCopy = true
    defer main.residentPanel?.close()

    expect Clipboard.resetFake()
    let clipboardHub = unwrap ResidentPanel.open(main, .Centered)
    main.sendCommandEvent(ActionCapture.ToClipboard)
    clipboardHub.choose(ActionCapture.FullScreen)
    journey.waitFor("screen copied and hub reopened", func|main|()->bool => Clipboard.hasImage() and main.residentPanel != null)
    let desktop = Clipboard.getImage()
    Swag.require(desktop.width == g_ScreenWidth and desktop.height == g_ScreenHeight)
    Swag.require(surface.isHidden and main.getCapture() == null)

    main.sendCommandEvent(ActionCapture.ToInPlace)
    let annotationHub = main.residentPanel
    journey.finishInPlacePicture(unwrap annotationHub, command: ActionCapture.FullScreen)
    journey.waitFor("hub reopened after copying the annotation", func|main|()->bool => main.residentPanel != null)
    let annotated = Clipboard.getImage()
    Swag.require(annotated.width == desktop.width and annotated.height == desktop.height)

    expect Clipboard.resetFake()
    main.sendCommandEvent(ActionCapture.ToEditor)
    let editorHub = main.residentPanel
    (unwrap editorHub).choose(ActionCapture.FullScreen)
    journey.waitFor("full screen in the editor", func|main, surface|()->bool => not surface.isHidden and main.getCapture() != null)
    let capture = unwrap main.getCapture()
    Swag.require(capture.width == desktop.width and capture.height == desktop.height)
    Swag.require(not Clipboard.hasImage() and main.residentPanel == null)
}
