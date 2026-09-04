#global internal

using Core, Gui

// Visible strings of the InDesign document viewer.
struct IndesignStrings
{
    ui_Name:                 string = "InDesign"                                                         // Name of this viewer in the viewer selector.
    ui_Details:              string = "InDesign · page % of % · saved preview % × %"                     // Short visual-preview summary in the information band.
    ui_MarkupDetails:        string = "InDesign Markup page % of %: % text frames, % missing images"     // Summary for a page composed from IDML objects.
    ui_LoadingDetails:       string = "InDesign page % of %: loading saved preview"                      // Summary while the selected preview decodes.
    ui_Page:                 string = "Page % / %"                                                       // Current saved-preview position in the compact command group.
    ui_PageMenuEntry:        string = "Page %"                                                           // One saved-preview entry in the page selector.
    ui_ZoomMenu:             string = "Choose zoom"                                                      // Tooltip for the zoom selector.
    ui_Actual:               string = "Actual size"                                                      // Zoom menu action that maps one image pixel to one screen pixel.
    ui_Fit:                  string = "Fit page"                                                         // Zoom menu action that fits the whole saved preview.
    ui_FitWidth:             string = "Fit width"                                                        // Zoom menu action that fits an IDML page width to its viewport.
    ui_PreviousPage:         string = "Previous saved preview"                                           // Tooltip for the preceding saved-preview action.
    ui_NextPage:             string = "Next saved preview"                                               // Tooltip for the following saved-preview action.
    ui_ChoosePage:           string = "Choose saved preview"                                             // Tooltip for the saved-preview selector.
    ui_PreviousDocumentPage: string = "Previous page"                                                    // Tooltip for preceding composed IDML page.
    ui_NextDocumentPage:     string = "Next page"                                                        // Tooltip for following composed IDML page.
    ui_ChooseDocumentPage:   string = "Choose page"                                                      // Tooltip for composed IDML page selector.
    ui_PageEntry:            string = "Page % · % × %"                                                   // One saved-preview entry in the page selector.
    ui_GoToPage:             string = "Go to page"                                                       // Title and action for direct page navigation.
    ui_PageRange:            string = "Page number from 1 to %."                                         // Direct page-navigation prompt.
    err_Header:              string = "the file does not contain a valid InDesign document header"       // Error for a malformed or truncated header.
    err_Preview:             string = "the document does not contain a readable saved page preview"      // Error when no visual page preview can be decoded.
}

private const FrenchStringsName = "lang/fr/scope.indesign.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.indesign.tweak")

private var g_IndesignStrings: IndesignStrings

func indesignStrings()->const *IndesignStrings => &g_IndesignStrings

func registerIndesignStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'IndesignStrings(&g_IndesignStrings, "scope.indesign")
}

#run
{
    expect Gui.validateStrings'IndesignStrings(cast(string) FrenchStrings)
}
