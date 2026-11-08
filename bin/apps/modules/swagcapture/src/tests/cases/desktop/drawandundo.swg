#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Draw a shape with the desktop pointer, then undo and redo with the desktop keyboard.
// This crosses native input delivery, hit testing, focus, shortcut routing and editing.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    discard journey.newCapture(400, 300)
    let capture = unwrap main.editWnd.getCapture()

    var input = Gui.Testing.DesktopInput.create(journey.app, journey.surface)
    var shapeButton: *IconButton?
    for button in main.dock.tools where button.id == ActionToolMode.Shape
    {
        shapeButton = button
        break
    }
    Swag.require(shapeButton != null, "the Shape tool is absent from the dock")
    Swag.require(not main.libraryMode, "the new capture did not open the editor")
    Swag.require(not shapeButton.wndFlags.has(.Disabled), "the Shape tool is disabled")
    Swag.require(not shapeButton.wndFlags.has(.Hidden), "the Shape tool is hidden")
    input.click(&shapeButton.wnd)
    journey.waitFor("desktop pointer selects Shape", func|main|()->bool => main.editMode == .Shape)

    let canvas = &main.editWnd.editView.wnd
    input.drag(canvas, journey.surfacePoint({25, 25}), journey.surfacePoint({120, 85}))
    journey.waitFor("desktop pointer draws a shape", func|capture|()->bool => capture.forms.count == 1)
    Swag.require(Swag.kindOf(capture.forms[0]) == FormShape)

    input.shortcut(.Z, .Control)
    journey.waitFor("desktop keyboard undoes the shape", func|capture|()->bool => capture.forms.isEmpty())

    input.shortcut(.Y, .Control)
    journey.waitFor("desktop keyboard redoes the shape", func|capture|()->bool => capture.forms.count == 1)
}
