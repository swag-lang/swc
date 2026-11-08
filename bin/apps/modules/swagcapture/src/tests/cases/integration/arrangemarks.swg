#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Align and reorder separate marks, with undo preserving the original layout each time.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer journey.shutdown()

    var path = journey.newCapture(320, 240)
    let capture = unwrap journey.main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Shape, .Shape, {20, 20}, {60, 55})
    journey.drawForm(ActionToolMode.Shape, .Shape, {110, 75}, {165, 120})
    journey.drawForm(ActionToolMode.Shape, .Shape, {215, 150}, {285, 210})
    let middle = capture.forms[1]
    let last = capture.forms[2]
    let x = middle.x
    let y = middle.y

    journey.main.sendCommandEvent(ActionToolMode.Selection)
    Swag.require(capture.selection.count == 1 and capture.selection[0] == 2)
    journey.main.sendCommandEvent(ActionAlign.SendToBack)
    Swag.require(capture.forms[0] == last)
    journey.main.sendCommandEvent(ActionAlign.MoveForward)
    Swag.require(capture.forms[1] == last)
    journey.main.sendCommandEvent(ActionAlign.SendToFront)
    Swag.require(capture.forms.back() == last)
    journey.main.sendCommandEvent(ActionAlign.MoveBackward)
    Swag.require(capture.forms[1] == last)

    journey.main.sendCommandEvent(ActionSelection.SelectAll)
    for command in [ActionAlign.AlignLeft, ActionAlign.AlignCenter, ActionAlign.AlignRight]
    {
        journey.main.sendCommandEvent(command)
        Swag.require(middle.x != x)
        journey.main.sendCommandEvent(ActionUndo.DoUndo)
        Swag.require(middle.x == x)
    }
    for command in [ActionAlign.AlignTop, ActionAlign.AlignMiddle, ActionAlign.AlignBottom]
    {
        journey.main.sendCommandEvent(command)
        Swag.require(middle.y != y)
        journey.main.sendCommandEvent(ActionUndo.DoUndo)
        Swag.require(middle.y == y)
    }

    journey.main.sendCommandEvent(ActionSelection.Snap)
    Swag.require(journey.main.snap)
    journey.main.sendCommandEvent(ActionSelection.Snap)
    Swag.require(not journey.main.snap)
    journey.main.sendCommandEvent(ActionSelection.Freeze)
    Swag.require(journey.main.freezeSel)
    journey.main.sendCommandEvent(ActionSelection.Freeze)
    Swag.require(not journey.main.freezeSel)

    journey.main.saveCapture(capture)
    journey.openLibrary(1)
    journey.main.libWnd.view.openItem(journey.main.libWnd.view.items[0])
    let main = journey.main
    journey.waitFor("reopen arranged marks", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 3
    })
}
