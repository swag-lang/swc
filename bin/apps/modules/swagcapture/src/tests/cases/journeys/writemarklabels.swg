#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Write and restyle labels in the canvas, then keep their text through undo and reopening.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main

    var path = journey.newCapture(360, 220)
    let capture = unwrap main.editWnd.getCapture()
    let view = main.editWnd.editView

    journey.drawForm(ActionToolMode.Text, .Text, {20, 25}, {150, 75})
    let text = assume cast(*FormText, capture.forms[0])
    main.sendCommandEvent(ActionEdit.Bold)
    main.sendCommandEvent(ActionEdit.Italic)
    Swag.require(text.fontStyle == .BoldItalic)
    main.sendCommandEvent(ActionEdit.EditText)
    Swag.require(view.isEditingText())
    view.textLines[0].setText("Review")
    Swag.require(view.textLineKey(view.textLines[0], .Return, .Control))
    Swag.require(text.text == "Review")
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(text.text != "Review")
    main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(text.text == "Review")

    journey.drawForm(ActionToolMode.Callout, .Callout, {180, 25}, {330, 85})
    let callout = assume cast(*FormCallout, capture.forms[1])
    main.sendCommandEvent(ActionEdit.EditText)
    Swag.require(view.isEditingText())
    view.textLines[0].setText("Look here")
    Swag.require(view.textLineKey(view.textLines[0], .Return, .Control))
    Swag.require(callout.text == "Look here")

    journey.drawForm(ActionToolMode.Step, .Step, {80, 155}, {80, 155})
    let step = assume cast(*FormStep, capture.forms[2])
    main.sendCommandEvent(ActionToolMode.Selection)
    main.sendCommandEvent(ActionSelection.SelectAll)
    Swag.require(capture.selection.back() == 2)
    main.sendCommandEvent(ActionEdit.EditText)
    Swag.require(view.isEditingText())
    view.textLines[0].setText("7")
    Swag.require(view.textLineKey(view.textLines[0], .Return, .None))
    Swag.require(step.index == 7)
    main.sendCommandEvent(ActionEdit.ResetSteps)
    Swag.require(capture.nextStepIndex == 1)

    main.saveCapture(capture)
    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("reopen written labels", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        if main.libraryMode or not opened or opened.file != path or opened.forms.count != 3 do
            return false
        let written = assume cast(*FormText, opened.forms[0])
        let noted = assume cast(*FormCallout, opened.forms[1])
        let numbered = assume cast(*FormStep, opened.forms[2])
        return written.text == "Review" and written.fontStyle == .BoldItalic and
               noted.text == "Look here" and numbered.index == 7
    })
}
