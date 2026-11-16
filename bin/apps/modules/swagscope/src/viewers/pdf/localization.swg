#global internal
#global namespace Viewers.PdfDocument

using Core, Gui

// Visible strings of the PDF viewer.
struct Texts
{
    ui_Previous:    string = "Previous Page"                             // Tooltip of the previous-page button.
    ui_Next:        string = "Next Page"                                 // Tooltip of the next-page button.
    ui_ZoomOut:     string = "Zoom Out"                                  // Tooltip of the zoom-out button.
    ui_ZoomIn:      string = "Zoom In"                                   // Tooltip of the zoom-in button.
    ui_Fit:         string = "Fit Page"                                  // Zoom menu action that fits a whole page.
    ui_FitWidth:    string = "Fit Width"                                 // Zoom menu action that fits the page width.
    ui_Actual:      string = "Actual Size"                               // Tooltip of the actual-size button.
    ui_ZoomMenu:    string = "Zoom…"                                     // Tooltip of the zoom value menu.
    ui_GoToPage:    string = "Go to Page"                                // Title and tooltip of direct page navigation.
    ui_PageRange:   string = "Page number from 1 to %."                  // Direct page navigation prompt.
    ui_Back:        string = "Back in Document"                          // Lens action that returns to the place the last jump left.
    ui_Forward:     string = "Forward in Document"                       // Lens action that undoes the last return.
    ui_Continuous:  string = "Continuous"                                // Layout action that scrolls every page in one column.
    ui_SinglePage:  string = "Single Page"                               // Layout action that shows one page at a time.
    ui_OnePage:     string = "1 page"                                    // Length of a one-page document.
    ui_Pages:       string = "% pages"                                   // Length of a longer document.
    err_NoPage:     string = "PDF document contains no page"             // Diagnostic of a document with nothing to show.
    ui_NoTextLayer: string = "The pages are pictures with no text layer, so their words cannot be searched"     // Why a search of a scanned document finds nothing.
    ui_SomeNoText:  string = "% of % pages are pictures with no text layer and were not searched"     // Why a search of a partly scanned document may miss words.
    ui_Unreadable:  string = "The text of % pages could not be read"     // Pages whose text failed to decode, added to the explanation.
}

private const FrenchStringsName = "lang/fr/scope.pdf.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.pdf.tweak")

private var g_Texts: Texts

func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.pdf")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
