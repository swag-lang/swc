#global internal
#global namespace Viewers.Html

using Core, Gui

// Visible strings of the HTML viewer.
//
// The format and the encoding are named by their standard spelling, so the summary below is the
// only sentence this viewer writes.
struct Texts
{
    ui_ZoomMenu: string = "Document zoom options"     // Tooltip of the zoom value menu.
    ui_Details:  string = "HTML"     // Summary the host shows beside the file size.
}

private const FrenchStringsName = "lang/fr/scope.html.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.html.tweak")

private var g_Texts: Texts

// Returns the visible strings of the HTML viewer in the active language.
func texts()->const *Texts => &g_Texts

// Registers this viewer's string table with the application.
//
// The embedded translation is published before the table is registered, so the viewer follows
// the language of the application around it. Calling this again is a no-op.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.html")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
