#global internal
#global namespace Viewers.PdfDocument

using Core, Gui

// Visible strings of the PDF viewer.
struct Texts
{
    ui_Previous:               string = "Previous Page"                                                          // Tooltip of the previous-page button.
    ui_Next:                   string = "Next Page"                                                              // Tooltip of the next-page button.
    ui_Fit:                    string = "Fit Page"                                                               // Zoom menu action that fits a whole page.
    ui_FitWidth:               string = "Fit Width"                                                              // Zoom menu action that fits the page width.
    ui_CopyText:               string = "Copy Selected Text"                                                     // Lens command copying the text selected on the pages.
    ui_SelectPage:             string = "Select the Page's Text"                                                 // Lens command selecting the whole text of the page in view.
    ui_ZoomMenu:               string = "Zoom…"                                                                  // Tooltip of the zoom value menu.
    ui_GoToPage:               string = "Go to Page"                                                             // Title and tooltip of direct page navigation.
    ui_PageRange:              string = "Page number from 1 to %."                                               // Direct page navigation prompt.
    ui_PageRangeLabels:        string = "Page number from 1 to %, or a page label such as %."                    // The same, for a document that labels its pages.
    ui_Back:                   string = "Back in Document"                                                       // Lens action that returns to the place the last jump left.
    ui_Forward:                string = "Forward in Document"                                                    // Lens action that undoes the last return.
    ui_Continuous:             string = "Continuous"                                                             // Layout action that scrolls every page in one column.
    ui_SinglePage:             string = "Single Page"                                                            // Layout action that shows one page at a time.
    ui_OnePage:                string = "1 page"                                                                 // Length of a one-page document.
    ui_Pages:                  string = "% pages"                                                                // Length of a longer document.
    err_NoPage:                string = "PDF document contains no page"                                          // Diagnostic of a document with nothing to show.
    ui_NoTextLayer:            string = "The pages are pictures with no text layer, so their words cannot be searched"     // Why a search of a scanned document finds nothing.
    ui_SomeNoText:             string = "% of % pages are pictures with no text layer and were not searched"     // Why a search of a partly scanned document may miss words.
    ui_OneNoText:              string = "1 of % pages is a picture with no text layer and was not searched"      // The same, when one page is a picture.
    ui_Unreadable:             string = "The text of % pages could not be read"                                  // Pages whose text failed to decode, added to the explanation.
    ui_OneUnreadable:          string = "The text of 1 page could not be read"                                   // The same, for one page.
    ui_TextLayerAll:           string = "on every page"                                                          // Text layer reading of a document whose every page carries text.
    ui_TextLayerNone:          string = "none, the pages are pictures"                                           // Text layer reading of a scanned document.
    ui_TextLayerSome:          string = "missing on % of % pages"                                                // Text layer reading of a partly scanned document.
    ui_TextLayerUnreadable:    string = "% pages unreadable"                                                     // Pages whose text failed to decode, after the text layer reading.
    ui_TextLayerOneUnreadable: string = "1 page unreadable"                                                      // The same, for one page.
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
