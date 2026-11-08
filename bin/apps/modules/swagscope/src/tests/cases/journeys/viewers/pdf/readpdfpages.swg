#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Turn PDF pages, change zoom, and reload without losing the page being read.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = Path.combine(journey.root, "report.pdf")
    var document = Pdf.Document.create()
    var first = Pdf.Page.create(320, 220)
    first.addText("First page", 32, 28, 24, Color.fromArgb(Argb.Black))
    document.addPage(#move first)
    var second = Pdf.Page.create(320, 220)
    second.addText("Second page", 32, 28, 24, Color.fromArgb(Argb.Black))
    document.addPage(#move second)
    expect document.save(file)

    let window = journey.window
    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "pdf")
    let panel = assume cast(*PdfDocument.Panel, window.currentView)
    Swag.require(panel.pdfView.pageCount() == 2 and panel.pdfView.pageIndex == 0)

    panel.nextButton.sigPressed.call(panel.nextButton)
    journey.waitFor("second PDF page", func|panel|()->bool => panel.pdfView.pageIndex == 1)
    panel.pdfView.zoomToFitWidth()
    Swag.require(panel.pdfView.zoomMode == .FitWidth)

    window.sendCommandEvent(ViewerCommands.Reload)
    journey.waitFor("PDF reading place restored", func|window|()->bool
    {
        if window.reloading or window.choiceLoad.started or window.currentView == null do
            return false
        let restored = assume cast(*PdfDocument.Panel, window.currentView)
        return restored.pdfView.pageIndex == 1 and restored.pdfView.zoomMode == .FitWidth
    })
}
