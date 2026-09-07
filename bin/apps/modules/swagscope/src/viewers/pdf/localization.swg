#global internal

using Core, Gui

// Visible strings of the PDF viewer.
struct PdfStrings
{
    ui_Previous:   string = "Previous page"                // Tooltip of the previous-page button.
    ui_Next:       string = "Next page"                    // Tooltip of the next-page button.
    ui_ZoomOut:    string = "Zoom out"                     // Tooltip of the zoom-out button.
    ui_ZoomIn:     string = "Zoom in"                      // Tooltip of the zoom-in button.
    ui_Fit:        string = "Fit page"                     // Zoom menu action that fits a whole page.
    ui_FitWidth:   string = "Fit width"                    // Zoom menu action that fits the page width.
    ui_Actual:     string = "Actual size"                  // Tooltip of the actual-size button.
    ui_ZoomMenu:   string = "Zoom options"                 // Tooltip of the zoom value menu.
    ui_GoToPage:   string = "Go to page"                   // Title and tooltip of direct page navigation.
    ui_PageRange:  string = "Page number from 1 to %."     // Direct page navigation prompt.
    ui_Continuous: string = "Continuous"                   // Layout action that scrolls every page in one column.
    ui_SinglePage: string = "Single page"                  // Layout action that shows one page at a time.
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
