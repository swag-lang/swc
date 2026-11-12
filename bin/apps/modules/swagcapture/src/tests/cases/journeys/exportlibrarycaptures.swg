#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Select two captures, choose a folder, and let their exports finish in request order.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let first = journey.newCapture(81, 57)
    let second = journey.newCapture(91, 61)
    journey.openLibrary(2)
    let library = journey.main.libWnd
    library.view.selModel.select(0)
    library.view.selModel.select(1)

    var accepted: bool
    let app = journey.app
    defer app.sigFrame.clear()
    app.sigFrame += func|app, &accepted|(_)
    {
        if accepted do
            return
        for surface in app.surfaces
        {
            if surface.view() is FileDlg as dialog where dialog.browser.hasValidSelection()
            {
                accepted = dialog.closeWithResult(Dialog.BtnOk)
                return
            }
        }
    }

    library.exportSelected()
    Swag.require(accepted)
    var firstImage = Path.combine(journey.root, Format.toString("%.png", Path.fileNameWithoutExtension(first) orelse "capture"))
    var secondImage = Path.combine(journey.root, Format.toString("%.png", Path.fileNameWithoutExtension(second) orelse "capture"))
    journey.waitFor("library captures exported", func|library, &firstImage, &secondImage|()->bool =>
                    not library.exporting and File.exists(firstImage) and File.exists(secondImage))

    let firstExport = expect Image.load(firstImage)
    let secondExport = expect Image.load(secondImage)
    Swag.require(firstExport.width == 81 and firstExport.height == 57)
    Swag.require(secondExport.width == 91 and secondExport.height == 61)
    Swag.require(journey.main.toast.message == appStrings().msg_ExportedCaptures)
}
