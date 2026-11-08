#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Turn the picture, restore its original pixels, and burn selected or all marks into it.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main

    var path = journey.newCapture(180, 120)
    let capture = unwrap main.editWnd.getCapture()
    let original = capture.backImg.pixelColor(10, 20).argb
    main.sendCommandEvent(ActionImage.FlipImage)
    Swag.require(capture.backImg.pixelColor(10, 20).argb != original)
    main.sendCommandEvent(ActionImage.MirrorImage)
    main.sendCommandEvent(ActionImage.RotateImageLeft)
    Swag.require(capture.width == 120 and capture.height == 180)
    main.sendCommandEvent(ActionImage.RotateImageRight)
    Swag.require(capture.width == 180 and capture.height == 120)
    main.sendCommandEvent(ActionImage.RestoreOrg)
    Swag.require(capture.backImg.pixelColor(10, 20).argb == original)

    journey.drawForm(ActionToolMode.Shape, .Shape, {20, 20}, {85, 65})
    main.sendCommandEvent(ActionFlatten.Flatten)
    Swag.require(capture.forms.isEmpty())
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.forms.count == 1)
    main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(capture.forms.isEmpty())

    journey.drawForm(ActionToolMode.Arrow, .Arrow, {15, 95}, {95, 105})
    journey.drawForm(ActionToolMode.Shape, .Shape, {110, 30}, {160, 80})
    main.sendCommandEvent(ActionFlatten.FlattenAll)
    Swag.require(capture.forms.isEmpty())
    main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.forms.count == 2)
    main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(capture.forms.isEmpty())

    main.saveCapture(capture)
    journey.openLibrary(1)
    main.libWnd.view.openItem(main.libWnd.view.items[0])
    journey.waitFor("reopen flattened picture", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.isEmpty() and
               opened.width == 180 and opened.height == 120
    })
}
