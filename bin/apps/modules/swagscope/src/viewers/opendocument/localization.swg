#global internal

using Core, Gui

// Visible strings of the OpenDocument viewer.
struct OpenDocumentStrings
{
    ui_Name:         string = "OpenDocument"
    ui_ZoomMenu:     string = "Document zoom options"
    ui_Details:      string = "OpenDocument · %"
    ui_Text:         string = "text document"
    ui_Spreadsheet:  string = "spreadsheet"
    ui_Presentation: string = "presentation"
    ui_Sheet:        string = "Sheet %"
    ui_TipSheet:     string = "Select spreadsheet sheet"
    ui_Drawing:      string = "drawing"
    ui_Slide:        string = "Slide %"
    ui_TipSlide:     string = "Select presentation slide"
    ui_Page:         string = "Page %"
    ui_TipPage:      string = "Select drawing page"
    ui_DetailsPage:  string = "OpenDocument drawing · %"
    ui_DetailsSlide: string = "OpenDocument · presentation · %"
    ui_DetailsSheet: string = "OpenDocument Â· spreadsheet Â· %"
    ui_Column:       string = "Column %"
    err_MimeType:    string = "the archive does not identify an OpenDocument format"
    err_Content:     string = "the OpenDocument archive has no content.xml entry"
    err_TooLarge:    string = "the OpenDocument viewer accepts document XML up to 32 MiB"
    err_Encoding:    string = "the OpenDocument XML is not UTF-8"
    err_Xml:         string = "the OpenDocument XML has an unclosed XML tag"
    err_Body:        string = "the OpenDocument XML has no office document body"
    err_Sheet:       string = "the spreadsheet has no table"
    err_Slide:       string = "the presentation has no slide"
    err_Page:        string = "the drawing has no page"
    err_Columns:     string = "the spreadsheet has more than 256 columns"
    err_Rows:        string = "the spreadsheet has more than 100,000 rows"
    err_Cells:       string = "the spreadsheet has more than 1,000,000 cells"
}

private const FrenchStringsName = "lang/fr/scope.opendocument.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.opendocument.tweak")

private var g_OpenDocumentStrings: OpenDocumentStrings

// Returns the visible strings of the OpenDocument viewer in the active language.
func openDocumentStrings()->const *OpenDocumentStrings => &g_OpenDocumentStrings

// Registers this viewer's strings before the registry names its plugin.
func registerOpenDocumentStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'OpenDocumentStrings(&g_OpenDocumentStrings, "scope.opendocument")
}

#run
{
    expect Gui.validateStrings'OpenDocumentStrings(cast(string) FrenchStrings)
}
