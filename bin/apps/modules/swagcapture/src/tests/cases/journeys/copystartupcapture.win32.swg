#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Cancel and copy from the in-place tools, returning to the capture window both times.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main    = journey.main
    let surface = journey.surface
    main.captureOptions.pictureDestination = .InPlace
    main.showHub()
    let hub = unwrap main.residentPanel
    Swag.require(hub.surface!.flags.has(.SmallCaption))
    Swag.require(main.workspace == .Hub and not surface.hasTrayIcon())

    journey.finishInPlacePicture(hub, cancel: true)
    let restored = main.residentPanel
    Swag.require(main.workspace == .Hub and
                 main.workspaceSurface().flags.has(.SmallCaption) and
                 not surface.hasTrayIcon())
    Swag.require(not main.clipboardPreview.isValid())

    journey.finishInPlacePicture(restored)
    let copied      = Clipboard.getImage()
    let hubWithCopy = main.residentPanel
    Swag.require(main.workspace == .Hub and not surface.hasTrayIcon() and main.residentNotice == null)
    Swag.require(hubWithCopy.childById(ResidentPanel.ClipboardPreviewId) != null)
    let preview = main.clipboardPreview
    Swag.require(copied.isValid() and preview.isValid())
    Swag.require(Math.abs(preview.aspectRatio() - copied.aspectRatio()) < 0.05)

    journey.finishInPlacePicture(hubWithCopy, cancel: true)
    Swag.require(main.residentPanel.childById(ResidentPanel.ClipboardPreviewId) != null)
    Swag.require(main.clipboardPreview.width == preview.width and main.clipboardPreview.height == preview.height)
}
