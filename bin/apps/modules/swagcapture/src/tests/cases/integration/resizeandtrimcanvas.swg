#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Resize a picture in its sheet, enlarge image and canvas, then trim the unused border.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    defer journey.shutdown()

    var path = journey.newCapture(100, 80)
    let capture = unwrap journey.main.editWnd.getCapture()
    g_ResizeMode = 1
    journey.changeImageSize(ActionImage.ResizeImage, 120, 90)
    Swag.require(capture.backImg.width == 120 and capture.backImg.height == 90)
    Swag.require(capture.width == 120 and capture.height == 90)

    journey.changeImageSize(ActionImage.ExpandImage, 140, 100)
    Swag.require(capture.backImg.width == 140 and capture.backImg.height == 100)
    Swag.require(capture.width == 120 and capture.height == 90)

    journey.changeImageSize(ActionImage.ExpandCapture, 160, 110)
    Swag.require(capture.width == 160 and capture.height == 110)
    journey.main.sendCommandEvent(ActionImage.TrimCapture)
    Swag.require(capture.width == 140 and capture.height == 100)
    journey.main.sendCommandEvent(ActionUndo.DoUndo)
    Swag.require(capture.width == 160 and capture.height == 110)
    journey.main.sendCommandEvent(ActionUndo.DoRedo)
    Swag.require(capture.width == 140 and capture.height == 100)

    journey.main.saveCapture(capture)
    journey.openLibrary(1)
    journey.main.libWnd.view.openItem(journey.main.libWnd.view.items[0])
    let main = journey.main
    journey.waitFor("reopen trimmed canvas", func|main, &path|()->bool
    {
        let opened = main.editWnd.getCapture()
        return not main.libraryMode and opened and opened.file == path and
               opened.width == 140 and opened.height == 100
    })
}
