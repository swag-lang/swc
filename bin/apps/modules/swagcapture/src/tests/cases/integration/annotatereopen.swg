#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Capture, annotate, save and return from the library. The reopened document must retain the
// edited form after the native window has presented each screen.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer journey.shutdown()

    var path    = journey.newCapture()
    let capture = unwrap journey.main.editWnd.getCapture()
    capture.title = "Reviewed capture"
    journey.drawForm(ActionToolMode.Shape, .Shape, {8, 10}, {38, 30})
    capture.changed = true
    journey.main.saveCapture(capture)

    journey.openLibrary(1)
    Swag.require(journey.main.libWnd.view.items.count == 1)
    journey.main.libWnd.view.openItem(journey.main.libWnd.view.items[0])
    let main = journey.main
    journey.waitFor("reopen annotated capture", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 1
    })
    Swag.require(journey.main.editWnd.getCapture()!.title == "Reviewed capture")
}
