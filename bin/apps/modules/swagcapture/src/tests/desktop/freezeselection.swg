#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Freeze selected forms with the desktop keyboard, then leave the lasting mode by its visible control.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    discard journey.newCapture(220, 160)
    let capture = unwrap main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Shape, .Shape, {20, 20}, {80, 65})
    main.sendCommandEvent(ActionSelection.SelectAll)
    Swag.require(capture.selection.count == 1)

    var input = Gui.Testing.DesktopInput.create(journey.app, journey.surface)
    input.shortcut(.L, .Control)
    journey.waitFor("desktop keyboard freezes selection", func|main|()->bool =>
        main.freezeSel and main.taskStrip.frozenPanel.isLocallyVisible())
    Swag.require(capture.selection.isEmpty() and capture.forms[0].freeze)

    input.click(&main.taskStrip.frozenButton.wnd)
    journey.waitFor("desktop pointer releases selection", func|main|()->bool =>
        not main.freezeSel and not main.taskStrip.frozenPanel.isLocallyVisible())
}
