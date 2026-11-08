#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Select one of two marks with a native lasso, delete it, then undo from the keyboard.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    discard journey.newCapture(220, 160)
    let main    = journey.main
    let capture = unwrap main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Shape, .Shape, {20, 20}, {60, 60})
    journey.drawForm(ActionToolMode.Shape, .Shape, {120, 95}, {170, 140})
    main.sendCommandEvent(ActionSelection.DeSelectAll)
    Swag.require(capture.selection.isEmpty())

    var input = Testing.DesktopInput.create(journey.app, journey.surface)
    input.shortcut(.V, .None)
    journey.waitFor("native Selection shortcut", func|main|()->bool => main.editMode == .Selection)
    let view = main.editWnd.editView
    input.drag(&view.wnd, journey.surfacePoint({90, 80}), journey.surfacePoint({5, 5}))
    Swag.require(capture.selection.count == 1 and capture.selection[0] == 0)

    input.shortcut(.Delete, .None)
    journey.waitFor("native Delete removes selected mark", func|capture|()->bool => capture.forms.count == 1)
    input.shortcut(.Z, .Control)
    journey.waitFor("native undo restores selected mark", func|capture|()->bool => capture.forms.count == 2)
}
