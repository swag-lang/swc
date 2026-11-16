#global internal
#global namespace Viewers.Html

using Core, Gui

// Visible strings of the HTML viewer.
//
// The summary is the format's standard name alone; the encoding and what decided it are readings
// of the information sheet.
struct Texts
{
    ui_ZoomMenu:         string = "Zoom…"                       // Tooltip of the zoom value menu.
    ui_Details:          string = "HTML"                        // Summary the host shows beside the file size.
    ui_EncodingMarked:   string = "byte-order mark"             // After the encoding name: a byte-order mark opening the file decided it.
    ui_EncodingDeclared: string = "declared by the page"        // After the encoding name: a charset label in the page decided it.
    ui_EncodingDetected: string = "detected from the bytes"     // After the encoding name: no mark or label, the bytes decided it.
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
