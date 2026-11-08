#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Delete one selected mark from the desktop keyboard, then undo its removal.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    discard journey.newCapture(220, 160)
    let capture = unwrap main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Shape, .Shape, {20, 20}, {60, 60})
    journey.drawForm(ActionToolMode.Shape, .Shape, {120, 95}, {170, 140})
    main.sendCommandEvent(ActionToolMode.Selection)
    main.sendCommandEvent(ActionSelection.DeSelectAll)

    journey.dragSelection({5, 5}, {90, 80})
    Swag.require(capture.selection.count == 1)
    Swag.require(capture.selection[0] == 0)

    var input = Gui.Testing.DesktopInput.create(journey.app, journey.surface)
    input.shortcut(.Delete, .None)
    journey.waitFor("desktop Delete removes the mark", func|capture|()->bool => capture.forms.count == 1)

    input.shortcut(.Z, .Control)
    journey.waitFor("desktop undo restores the mark", func|capture|()->bool => capture.forms.count == 2)
}
