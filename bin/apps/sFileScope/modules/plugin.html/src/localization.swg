#global public

using Core, Gui

// Visible strings of the HTML viewer.
//
// The format and the encoding are named by their standard spelling, so the summary below is the
// only sentence this viewer writes.
struct HtmlStrings
{
    ui_Details: string = "HTML · UTF-8 · streamed"     // Summary the host shows beside the file size.
}

private const FrenchStringsName = "lang/fr/filescope.html.tweak"
private const FrenchStrings = #include("../datas/lang/fr/filescope.html.tweak")

private var g_HtmlStrings: HtmlStrings

// Returns the visible strings of the HTML viewer in the active language.
func htmlStrings()->const *HtmlStrings => &g_HtmlStrings

// Registers this plugin's string table with the host that loaded it.
//
// A plugin enters the process long after the host chose a language, so its translations are
// published into the host's bundle before the table is registered: [[Gui.registerStrings]] then
// finds them and the viewer opens in the language of the window around it. Calling this again
// is a no-op, so the first view of this format pays for it and no other does.
func registerHtmlStrings(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'HtmlStrings(&g_HtmlStrings, "filescope.html")
}

#run
{
    expect Gui.validateStrings'HtmlStrings(cast(string) FrenchStrings)
}
