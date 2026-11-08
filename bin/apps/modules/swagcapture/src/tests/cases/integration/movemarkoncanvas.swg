#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Drag a visible mark on the canvas and use history to review the move before saving.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer journey.shutdown()

    var path = journey.newCapture(220, 160)
    let capture = unwrap journey.main.editWnd.getCapture()
    journey.main.quickWnd.applyPreset(journey.main.quickWnd.qsShape.forms[4])
    journey.drawForm(ActionToolMode.Shape, .Shape, {25, 25}, {85, 70})
    let shape = assume cast(*FormShape, capture.forms[0])
    let x = shape.x
    let y = shape.y

    journey.dragImage({55, 45}, {95, 75})
    Swag.require(shape.x == x + 40 and shape.y == y + 30)
    journey.main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(shape.x == x and shape.y == y)
    journey.main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(shape.x == x + 40 and shape.y == y + 30)

    journey.main.sendCommandEvent(ActionSelection.SelectAll)
    journey.waitFor("move painted", func|shape, x, y|()->bool => shape.x == x + 40 and shape.y == y + 30)
    let sizeX = shape.w
    let sizeY = shape.h
    testPrimeGizmo(shape, journey.main.editWnd.editView.zoom)
    let bound = shape.IForm.boundRect()
    journey.dragImage({bound.right(), bound.bottom()}, {bound.right() + 25, bound.bottom() + 20})
    Swag.require(shape.w == sizeX + 25 and shape.h == sizeY + 20)
    journey.main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(shape.w == sizeX and shape.h == sizeY)
    journey.main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(shape.w == sizeX + 25 and shape.h == sizeY + 20)

    journey.main.saveCapture(capture)
    journey.openLibrary(1)
    journey.main.libWnd.view.openItem(journey.main.libWnd.view.items[0])
    let main = journey.main
    journey.waitFor("reopen moved mark", func|main, &path, x, y, sizeX, sizeY|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 1 and
               opened.forms[0].x == x + 40 and opened.forms[0].y == y + 30 and
               opened.forms[0].w == sizeX + 25 and opened.forms[0].h == sizeY + 20
    })
}
