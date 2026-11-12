#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Copy a library capture through its command while the editor keeps its own selection.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer Clipboard.clear()
    let main = journey.main
    let file = journey.newCapture(117, 73)
    journey.openLibrary(1)
    main.libWnd.view.setFocusItem(0)
    Clipboard.clear()

    main.sendCommandEvent(ActionFile.CopyImage)
    journey.waitFor("library image copied", func||()->bool => Clipboard.hasImage())
    let image = Clipboard.getImage()
    Swag.require(image.isValid() and image.width == 117 and image.height == 73)
    Swag.require(main.libraryMode and main.editWnd.getCapture()!.file == file)
}
