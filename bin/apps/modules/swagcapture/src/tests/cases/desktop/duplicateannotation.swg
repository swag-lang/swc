#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Draw through the desktop pointer, then select and duplicate the mark with real keys.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    discard journey.newCapture(300, 210)
    let main    = journey.main
    let capture = unwrap main.editWnd.getCapture()
    var input   = Testing.DesktopInput.create(journey.app, journey.surface)

    input.shortcut(.R, .None)
    journey.waitFor("native Shape shortcut", func|main|()->bool => main.editMode == .Shape)
    input.drag(&main.editWnd.editView.wnd, journey.surfacePoint({25, 25}), journey.surfacePoint({110, 80}))
    journey.waitFor("native mark drawn", func|capture|()->bool => capture.forms.count == 1)

    input.shortcut(.A, .Control)
    journey.waitFor("native selection", func|capture|()->bool => capture.selection.count == 1)
    input.shortcut(.D, .Control)
    journey.waitFor("native duplicate", func|capture|()->bool => capture.forms.count == 2)
    Swag.require(capture.selection.count == 1)

    input.shortcut(.Delete, .None)
    journey.waitFor("native deletion of duplicate", func|capture|()->bool => capture.forms.count == 1)
    input.shortcut(.Z, .Control)
    journey.waitFor("native undo of deletion", func|capture|()->bool => capture.forms.count == 2)
}
