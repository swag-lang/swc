#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// A transformed picture can be undone and redone before switching pages; the persisted file and
// the native editor must agree after the library reloads it.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer journey.shutdown()

    var path = journey.newCapture()
    journey.main.sendCommandEvent(ActionImage.RotateImageRight)
    let main = journey.main
    journey.waitFor("rotated picture", func|main|()->bool
    {
        let capture = main.editWnd.getCapture()
        return capture and capture.width == 64 and capture.height == 96
    })
    journey.main.sendCommandEvent(ActionUndo.DoUndo)
    journey.waitFor("undo rotation", func|main|()->bool
    {
        let capture = main.editWnd.getCapture()
        return capture and capture.width == 96 and capture.height == 64
    })
    journey.main.sendCommandEvent(ActionUndo.DoRedo)
    journey.waitFor("redo rotation", func|main|()->bool
    {
        let capture = main.editWnd.getCapture()
        return capture and capture.width == 64 and capture.height == 96
    })
    journey.main.saveCapture(unwrap journey.main.editWnd.getCapture())

    journey.openLibrary(1)
    journey.main.libWnd.view.openItem(journey.main.libWnd.view.items[0])
    journey.waitFor("reopen transformed capture", func|main, &path|()->bool
    {
        let capture = main.editWnd.getCapture()
        return not main.libraryMode and capture and capture.file == path and capture.width == 64 and capture.height == 96
    })
}
