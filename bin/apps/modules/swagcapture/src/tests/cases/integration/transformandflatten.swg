#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Turn the picture, restore its original pixels, and burn selected or all marks into it.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer journey.shutdown()

    var path = journey.newCapture(180, 120)
    let capture = unwrap journey.main.editWnd.getCapture()
    let original = capture.backImg.pixelColor(10, 20).argb
    journey.main.sendCommandEvent(ActionImage.FlipImage)
    Swag.require(capture.backImg.pixelColor(10, 20).argb != original)
    journey.main.sendCommandEvent(ActionImage.MirrorImage)
    journey.main.sendCommandEvent(ActionImage.RotateImageLeft)
    Swag.require(capture.width == 120 and capture.height == 180)
    journey.main.sendCommandEvent(ActionImage.RotateImageRight)
    Swag.require(capture.width == 180 and capture.height == 120)
    journey.main.sendCommandEvent(ActionImage.RestoreOrg)
    Swag.require(capture.backImg.pixelColor(10, 20).argb == original)

    journey.drawForm(ActionToolMode.Shape, .Shape, {20, 20}, {85, 65})
    journey.main.sendCommandEvent(ActionFlatten.Flatten)
    Swag.require(capture.forms.isEmpty())
    journey.main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.forms.count == 1)
    journey.main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(capture.forms.isEmpty())

    journey.drawForm(ActionToolMode.Arrow, .Arrow, {15, 95}, {95, 105})
    journey.drawForm(ActionToolMode.Shape, .Shape, {110, 30}, {160, 80})
    journey.main.sendCommandEvent(ActionFlatten.FlattenAll)
    Swag.require(capture.forms.isEmpty())
    journey.main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.forms.count == 2)
    journey.main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(capture.forms.isEmpty())

    journey.main.saveCapture(capture)
    journey.openLibrary(1)
    journey.main.libWnd.view.openItem(journey.main.libWnd.view.items[0])
    let main = journey.main
    journey.waitFor("reopen flattened picture", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and opened.forms.isEmpty() and
               opened.width == 180 and opened.height == 120
    })
}
