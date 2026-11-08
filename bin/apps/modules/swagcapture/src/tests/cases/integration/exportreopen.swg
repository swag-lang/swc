#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// A PNG exported from an edited capture points back to its document. Opening that PNG through
// the production external-image handler returns to the same document and preserves annotations.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer journey.shutdown()

    var path = journey.newCapture()
    let capture = unwrap journey.main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Arrow, .Arrow, {5, 5}, {45, 30})
    capture.changed = true
    journey.main.saveCapture(capture)

    var exported = Path.combine(journey.root, "review.png")
    journey.main.doSaveAsImage(exported)
    journey.waitFor("PNG exported", func|&exported|()->bool => File.exists(exported))
    let image = expect Image.load(exported)
    Swag.require(image.width == 96 and image.height == 64)
    Swag.require(not image.metadata.isEmpty())

    journey.openLibrary(2)
    journey.main.loadExternalImage(exported)
    let main = journey.main
    journey.waitFor("export returns to source", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 1
    })
}
