#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Place each image-tool variant on a picture and keep the chosen effect through reopening.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer journey.shutdown()

    var path = journey.newCapture(420, 260)
    let capture = unwrap journey.main.editWnd.getCapture()
    let positions = [Math.Point{10, 15}, Math.Point{95, 15}, Math.Point{180, 15},
                     Math.Point{265, 15}, Math.Point{350, 15}]
    let kinds = [FormImageKind.Image, FormImageKind.Zoom, FormImageKind.Blur,
                 FormImageKind.Pixelate, FormImageKind.Capture]
    for kind, i in kinds
    {
        journey.main.sendCommandEvent(ActionSelection.DeSelectAll)
        journey.main.sendCommandEvent(ActionToolMode.Img)
        journey.main.quickWnd.applyPreset(journey.main.quickWnd.qsImage.forms[i])
        journey.drawForm(ActionToolMode.Img, .Image, positions[i], positions[i] + Math.Point{60, 70})
        let form = assume cast(*FormImage, capture.forms.back())
        Swag.require(form.kind == kind)
    }

    journey.main.saveCapture(capture)
    journey.openLibrary(1)
    journey.main.libWnd.view.openItem(journey.main.libWnd.view.items[0])
    let main = journey.main
    journey.waitFor("reopen image effects", func|main, &path, kinds|()->bool
    {
        let opened = main.editWnd.getCapture()
        if main.libraryMode or not opened or opened.file != path or opened.forms.count != 5 do
            return false
        for kind, i in kinds
        {
            let effect = assume cast(*FormImage, opened.forms[i])
            if effect.kind != kind do
                return false
        }
        return true
    })
}
