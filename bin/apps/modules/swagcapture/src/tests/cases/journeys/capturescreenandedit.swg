#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Select a real screen area, annotate its picture, then reopen the saved document from the library.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    journey.captureScreenPicture()
    let main = journey.main
    let capture = unwrap main.editWnd.getCapture()
    var path = String.from(capture.file)
    Swag.require(capture.sourceKind == .Screen and capture.media == .Picture)
    Swag.require(capture.width >= 8 and capture.height >= 8)
    journey.drawForm(ActionToolMode.Arrow, .Arrow, {5, 5}, {45, 30})
    capture.changed = true
    main.saveCapture(capture)

    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("screen picture reopened", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and
               opened.sourceKind == .Screen and opened.forms.count == 1
    })
}
