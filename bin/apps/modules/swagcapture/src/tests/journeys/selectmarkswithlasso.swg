#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Draw a selection rectangle around one mark, remove it, and restore it from history.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main

    var path = journey.newCapture(220, 160)
    let capture = unwrap main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Shape, .Shape, {20, 20}, {60, 60})
    journey.drawForm(ActionToolMode.Shape, .Shape, {120, 95}, {170, 140})
    main.sendCommandEvent(ActionToolMode.Selection)
    main.sendCommandEvent(ActionSelection.DeSelectAll)
    journey.dragSelection({5, 5}, {90, 80})
    Swag.require(capture.selection.count == 1 and capture.selection[0] == 0)
    main.sendCommandEvent(ActionSelection.DeleteSelection)
    Swag.require(capture.forms.count == 1)
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.forms.count == 2)

    main.saveCapture(capture)
    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("reopen restored marks", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 2
    })
}
