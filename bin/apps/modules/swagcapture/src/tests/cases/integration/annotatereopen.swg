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
    let main = journey.main

    var path    = journey.newCapture()
    let capture = unwrap main.editWnd.getCapture()
    capture.title = "Reviewed capture"
    journey.drawForm(ActionToolMode.Shape, .Shape, {8, 10}, {38, 30})
    capture.changed = true
    main.saveCapture(capture)

    journey.openLibrary(1)
    Swag.require(main.libWnd.view.items.count == 1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("reopen annotated capture", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 1
    })
    Swag.require(main.editWnd.getCapture()!.title == "Reviewed capture")
}
