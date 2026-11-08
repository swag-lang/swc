#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Draw a selection rectangle around one mark, remove it, and restore it from history.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer journey.shutdown()

    var path = journey.newCapture(220, 160)
    let capture = unwrap journey.main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Shape, .Shape, {20, 20}, {60, 60})
    journey.drawForm(ActionToolMode.Shape, .Shape, {120, 95}, {170, 140})
    journey.main.sendCommandEvent(ActionToolMode.Selection)
    journey.main.sendCommandEvent(ActionSelection.DeSelectAll)
    journey.dragSelection({5, 5}, {90, 80})
    Swag.require(capture.selection.count == 1 and capture.selection[0] == 0)
    journey.main.sendCommandEvent(ActionSelection.DeleteSelection)
    Swag.require(capture.forms.count == 1)
    journey.main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.forms.count == 2)

    journey.main.saveCapture(capture)
    journey.openLibrary(1)
    journey.main.libWnd.view.openItem(journey.main.libWnd.view.items[0])
    let main = journey.main
    journey.waitFor("reopen restored marks", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 2
    })
}
