#global internal

using Core, Gui

// Visible strings of the PDF viewer.
struct PdfStrings
{
    ui_Previous: string = "Previous page"     // Tooltip of the previous-page button.
    ui_Next:     string = "Next page"         // Tooltip of the next-page button.
    ui_Fit:      string = "Fit"               // Label of the fit-to-window button.
    ui_Actual:   string = "100%"              // Label of the actual-size button.
    ui_Page:     string = "page"              // One document page.
    ui_Pages:    string = "pages"             // Several document pages.
}

private const FrenchStringsName = "lang/fr/filescope.pdf.tweak"
private const FrenchStrings = #include("../../../datas/lang/fr/filescope.pdf.tweak")

private var g_PdfStrings: PdfStrings

func pdfStrings()->const *PdfStrings => &g_PdfStrings

func registerPdfStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'PdfStrings(&g_PdfStrings, "filescope.pdf")
}

#run
{
    expect Gui.validateStrings'PdfStrings(cast(string) FrenchStrings)
}
