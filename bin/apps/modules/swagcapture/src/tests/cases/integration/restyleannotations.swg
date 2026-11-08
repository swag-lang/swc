#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Change a mark through the inspector, reset its angle, and restore the tool's style presets.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer journey.shutdown()

    var path = journey.newCapture(180, 140)
    let capture = unwrap journey.main.editWnd.getCapture()
    journey.drawForm(ActionToolMode.Shape, .Shape, {25, 25}, {100, 90})
    let shape = assume cast(*FormShape, capture.forms[0])
    journey.main.propWnd.pushTypedValue(cast #bit (u32, 45'f32), BaseForm, #nameof(BaseForm.rotate), true, true)
    Swag.require(shape.rotate == 45)
    journey.main.sendCommandEvent(ActionEdit.ResetRotation)
    Swag.require(shape.rotate == 0)
    journey.main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(shape.rotate == 45)
    journey.main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(shape.rotate == 0)

    journey.main.propWnd.pushTypedValue(cast(u32, Argb.Blue), BaseForm, #nameof(BaseForm.backColor), true, true)
    Swag.require(shape.backColor.argb == cast(u32, Argb.Blue))
    let styles = &journey.main.quickWnd.qsShape
    let defaultCount = styles.forms.count
    let extra = Memory.new'FormShape()
    extra.IForm.setup(capture)
    styles.forms.add(extra)
    journey.confirmCommand(ActionQuickStyle.Reset, Dialog.BtnYes)
    Swag.require(styles.forms.count == defaultCount)

    journey.main.saveCapture(capture)
    journey.openLibrary(1)
    journey.main.libWnd.view.openItem(journey.main.libWnd.view.items[0])
    let main = journey.main
    journey.waitFor("reopen styled mark", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        if main.libraryMode or not opened or opened.file != path or opened.forms.count != 1 do
            return false
        return opened.forms[0].rotate == 0 and opened.forms[0].backColor.argb == cast(u32, Argb.Blue)
    })
}
