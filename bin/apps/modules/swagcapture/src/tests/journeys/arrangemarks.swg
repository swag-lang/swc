#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Align and reorder separate marks, with undo preserving the original layout each time.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main

    var path = journey.newCapture(320, 240)
    let capture = unwrap main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Shape, .Shape, {20, 20}, {60, 55})
    journey.drawForm(ActionToolMode.Shape, .Shape, {110, 75}, {165, 120})
    journey.drawForm(ActionToolMode.Shape, .Shape, {215, 150}, {285, 210})
    let middle = capture.forms[1]
    let last = capture.forms[2]
    let x = middle.x
    let y = middle.y

    main.sendCommandEvent(ActionToolMode.Selection)
    Swag.require(capture.selection.count == 1 and capture.selection[0] == 2)
    main.sendCommandEvent(ActionAlign.SendToBack)
    Swag.require(capture.forms[0] == last)
    main.sendCommandEvent(ActionAlign.MoveForward)
    Swag.require(capture.forms[1] == last)
    main.sendCommandEvent(ActionAlign.SendToFront)
    Swag.require(capture.forms.back() == last)
    main.sendCommandEvent(ActionAlign.MoveBackward)
    Swag.require(capture.forms[1] == last)

    main.sendCommandEvent(ActionSelection.SelectAll)
    for command in [ActionAlign.AlignLeft, ActionAlign.AlignCenter, ActionAlign.AlignRight]
    {
        main.sendCommandEvent(command)
        Swag.require(middle.x != x)
        main.sendCommandEvent(ActionUndo.DoUndo)
        Swag.require(middle.x == x)
    }
    for command in [ActionAlign.AlignTop, ActionAlign.AlignMiddle, ActionAlign.AlignBottom]
    {
        main.sendCommandEvent(command)
        Swag.require(middle.y != y)
        main.sendCommandEvent(ActionUndo.DoUndo)
        Swag.require(middle.y == y)
    }

    main.sendCommandEvent(ActionSelection.Snap)
    Swag.require(main.snap)
    main.sendCommandEvent(ActionSelection.Snap)
    Swag.require(not main.snap)
    main.sendCommandEvent(ActionSelection.Freeze)
    Swag.require(main.freezeSel)
    main.sendCommandEvent(ActionSelection.Freeze)
    Swag.require(not main.freezeSel)

    main.saveCapture(capture)
    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("reopen arranged marks", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 3
    })
}
