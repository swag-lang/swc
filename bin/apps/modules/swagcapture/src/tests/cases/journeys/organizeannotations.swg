#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Organize three marks through the selection, grouping, alignment, order, and history commands.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main

    var path = journey.newCapture(320, 240)
    let capture = unwrap main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Shape, .Shape, {15, 20}, {55, 60})
    journey.drawForm(ActionToolMode.Shape, .Shape, {100, 70}, {140, 110})
    journey.drawForm(ActionToolMode.Shape, .Shape, {200, 140}, {240, 180})

    main.sendCommandEvent(ActionToolMode.Selection)
    Swag.require(main.editMode == .Selection)
    main.sendCommandEvent(ActionSelection.SelectAll)
    Swag.require(capture.selection.count == 3)
    main.sendCommandEvent(ActionGroup.Group)
    Swag.require(capture.forms[0].groups.count == 1)
    Swag.require(capture.forms[0].groups[0] == capture.forms[2].groups[0])
    main.sendCommandEvent(ActionGroup.Ungroup)
    Swag.require(capture.forms[0].groups.isEmpty())

    main.sendCommandEvent(ActionAlign.AlignLeft)
    Swag.require(capture.forms[0].x == capture.forms[1].x and capture.forms[1].x == capture.forms[2].x)
    main.sendCommandEvent(ActionAlign.AlignTop)
    Swag.require(capture.forms[0].y == capture.forms[1].y and capture.forms[1].y == capture.forms[2].y)

    main.sendCommandEvent(ActionSelection.DeSelectAll)
    Swag.require(capture.selection.isEmpty())
    main.sendCommandEvent(ActionSelection.InvertSelection)
    Swag.require(capture.selection.count == 3)
    main.sendCommandEvent(ActionSelection.SelectSameAll)
    Swag.require(capture.selection.count == 3)
    main.sendCommandEvent(ActionCopyPaste.Duplicate)
    Swag.require(capture.forms.count == 6)
    main.sendCommandEvent(ActionSelection.DeleteSelection)
    Swag.require(capture.forms.count == 3)
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.forms.count == 6)
    main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(capture.forms.count == 3)

    main.saveCapture(capture)
    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("reopen organized marks", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 3
    })
}
