#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Select pixels on a picture, fill and clear them, repair them, then lift them as an image.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main

    var path = journey.newCapture(120, 100)
    let capture = unwrap main.editWnd.getCapture()
    main.quickWnd.applyPreset(main.quickWnd.qsPixSel.forms[0])
    journey.drawForm(ActionToolMode.PixSel, .PixSel, {20, 20}, {60, 60})
    Swag.require(capture.forms[0].subKind == .PixSel)

    let original = capture.backImg.pixelColor(40, 40).argb
    main.pixSelFillCol = Argb.Red
    main.sendCommandEvent(ActionPixSel.Fill)
    let filled = capture.backImg.pixelColor(40, 40).argb
    Swag.require(filled != original)
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.backImg.pixelColor(40, 40).argb == original)
    main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(capture.backImg.pixelColor(40, 40).argb == filled)

    main.sendCommandEvent(ActionPixSel.Clear)
    Swag.require(capture.backImg.pixelColor(40, 40).argb == 0)
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.backImg.pixelColor(40, 40).argb == filled)
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.backImg.pixelColor(40, 40).argb == original)

    main.sendCommandEvent(ActionSelection.SelectAll)
    main.sendCommandEvent(ActionPixSel.SmartFill)
    let repaired = capture.backImg.pixelColor(40, 40).argb
    Swag.require(repaired != original)
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.backImg.pixelColor(40, 40).argb == original)

    main.sendCommandEvent(ActionSelection.SelectAll)
    main.sendCommandEvent(ActionPixSel.SmartMove)
    Swag.require(capture.forms.count == 1 and Swag.kindOf(capture.forms[0]) == FormImage)
    let lifted = assume cast(*FormImage, capture.forms[0])
    Swag.require(lifted.image.isValid())

    main.saveCapture(capture)
    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("reopen lifted pixels", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.count == 1 and
               Swag.kindOf(opened.forms[0]) == FormImage
    })
}
