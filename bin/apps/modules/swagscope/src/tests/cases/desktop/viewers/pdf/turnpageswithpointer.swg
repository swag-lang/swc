#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Open a two-page PDF and turn it using the native pointer on the visible controls.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = Path.combine(journey.root, "two-pages.pdf")
    var document = Pdf.Document.create()
    for title in ["First page", "Second page"]
    {
        var page = Pdf.Page.create(320, 220)
        page.addText(title, 32, 28, 24, Color.fromArgb(Argb.Black))
        document.addPage(#move page)
    }
    expect document.save(file)

    let window = journey.window
    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "pdf")
    let panel = assume cast(*PdfDocument.Panel, window.currentView)
    Swag.require(panel.pdfView.pageCount() == 2 and panel.pdfView.pageIndex == 0)

    var input = Testing.DesktopInput.create(&journey.app, journey.surface)
    input.click(&panel.nextButton.wnd)
    journey.waitFor("native next-page click", func|panel|()->bool => panel.pdfView.pageIndex == 1 and
                                                            panel.previousButton.isEnabled() and
                                                            not panel.nextButton.isEnabled())
    input.click(&panel.previousButton.wnd)
    journey.waitFor("native previous-page click", func|panel|()->bool => panel.pdfView.pageIndex == 0 and
                                                                panel.nextButton.isEnabled() and
                                                                not panel.previousButton.isEnabled())
}
