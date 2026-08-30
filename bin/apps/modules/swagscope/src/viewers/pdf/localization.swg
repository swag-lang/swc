#global internal

using Core, Gui

// Visible strings of the PDF viewer.
struct PdfStrings
{
    ui_Previous: string = "Previous page"     // Tooltip of the previous-page button.
    ui_Next:     string = "Next page"         // Tooltip of the next-page button.
    ui_ZoomOut:  string = "Zoom out"          // Tooltip of the zoom-out button.
    ui_ZoomIn:   string = "Zoom in"           // Tooltip of the zoom-in button.
    ui_Fit:      string = "Fit page"          // Tooltip of the fit-to-window button.
    ui_Actual:   string = "Actual size"       // Tooltip of the actual-size button.
    ui_Page:     string = "page"              // One document page.
    ui_Pages:    string = "pages"             // Several document pages.
}

private const FrenchStringsName = "lang/fr/scope.pdf.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.pdf.tweak")

private var g_PdfStrings: PdfStrings

func pdfStrings()->const *PdfStrings => &g_PdfStrings

func registerPdfStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'PdfStrings(&g_PdfStrings, "scope.pdf")
}

#run
{
    expect Gui.validateStrings'PdfStrings(cast(string) FrenchStrings)
}
